#!/usr/bin/env node
'use strict';
/**
 * Servidor de partidas ONLINE da Operação Eclipse (matchmaking + salas + relay).
 * - Zero dependências (só módulos nativos do Node 18+): HTTP + WebSocket (RFC 6455) implementado aqui.
 * - NÃO simula o jogo: o jogador "host" da sala roda a partida (listen-server) e este servidor só
 *   organiza filas/salas e repassa mensagens entre os jogadores. Bots completam as vagas no host.
 * - Hospede onde houver processo Node de longa duração com WebSocket (Render, Railway, Fly.io, VPS...).
 *   A Vercel (funções serverless) NÃO serve para este servidor.
 *
 * Variáveis de ambiente: PORT (8080), MM_WAIT_MS (15000), MAX_ROOMS (200), MAX_CLIENTS (2000), ALLOWED_ORIGINS (lista separada por vírgula)
 */
const http = require('http');
const crypto = require('crypto');

const PROTOCOL = 1;
const MAX_PLAYERS = 16;
const MAX_PAYLOAD = 256 * 1024;
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const DIFFS = ['mixed', 'beginner', 'intermediate', 'advanced'];

function createServer(opts = {}) {
  const MM_WAIT_MS = opts.mmWaitMs ?? parseInt(process.env.MM_WAIT_MS || '15000', 10);
  const MAX_ROOMS = opts.maxRooms ?? parseInt(process.env.MAX_ROOMS || '200', 10);
  const MAX_CLIENTS = opts.maxClients ?? parseInt(process.env.MAX_CLIENTS || '2000', 10);
  const ORIGINS = (opts.origins ?? process.env.ALLOWED_ORIGINS ?? '').split(',').map(s => s.trim()).filter(Boolean);
  const clients = new Map();
  const rooms = new Map();
  let nextId = 1;

  // ------------------------------------------------------------ WebSocket mínimo (servidor)
  class Conn {
    constructor(socket) {
      this.socket = socket; this.buf = Buffer.alloc(0); this.frag = null; this.closed = false;
      this.onmessage = null; this.onclose = null; this.lastSeen = Date.now();
      socket.setNoDelay(true);
      socket.on('data', d => this._data(d));
      socket.on('close', () => this._closed());
      socket.on('error', () => this._closed());
    }
    _closed() { if (!this.closed) { this.closed = true; this.onclose && this.onclose(); } }
    _data(chunk) {
      this.lastSeen = Date.now();
      this.buf = Buffer.concat([this.buf, chunk]);
      if (this.buf.length > MAX_PAYLOAD * 2) return this.terminate();
      for (;;) { const f = this._parse(); if (!f || this.closed) break; this._frame(f); }
    }
    _parse() {
      const b = this.buf; if (b.length < 2) return null;
      const fin = !!(b[0] & 0x80), op = b[0] & 0x0f, masked = !!(b[1] & 0x80);
      let len = b[1] & 0x7f, off = 2;
      if (len === 126) { if (b.length < 4) return null; len = b.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (b.length < 10) return null; if (b.readUInt32BE(2) !== 0) { this.close(1009); return null; } len = b.readUInt32BE(6); off = 10; }
      if (!masked) { this.close(1002); return null; }
      if (len > MAX_PAYLOAD) { this.close(1009); return null; }
      if (b.length < off + 4 + len) return null;
      const mask = b.subarray(off, off + 4);
      const payload = Buffer.from(b.subarray(off + 4, off + 4 + len));
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
      this.buf = b.subarray(off + 4 + len);
      return { fin, op, payload };
    }
    _frame({ fin, op, payload }) {
      if (op === 0x8) { this.close(1000); return; }
      if (op === 0x9) { this._write(0xA, payload); return; }
      if (op === 0xA) return;
      if (op === 0x2) { this.close(1003); return; }
      if (op === 0x1) this.frag = [payload];
      else if (op === 0x0 && this.frag) this.frag.push(payload);
      else { this.close(1002); return; }
      if (fin) {
        const text = Buffer.concat(this.frag).toString('utf8'); this.frag = null;
        this.onmessage && this.onmessage(text);
      }
    }
    _write(op, payload) {
      if (this.closed || !this.socket.writable) return;
      const n = payload.length; let head;
      if (n < 126) head = Buffer.from([0x80 | op, n]);
      else if (n < 65536) { head = Buffer.alloc(4); head[0] = 0x80 | op; head[1] = 126; head.writeUInt16BE(n, 2); }
      else { head = Buffer.alloc(10); head[0] = 0x80 | op; head[1] = 127; head.writeUInt32BE(0, 2); head.writeUInt32BE(n, 6); }
      if (this.socket.writableLength > 2 * 1024 * 1024) return this.terminate();   // cliente lento
      this.socket.write(Buffer.concat([head, payload]));
    }
    send(obj) { this._write(0x1, Buffer.from(typeof obj === 'string' ? obj : JSON.stringify(obj))); }
    ping() { this._write(0x9, Buffer.alloc(0)); }
    close(code = 1000) { if (this.closed) return; const p = Buffer.alloc(2); p.writeUInt16BE(code); this._write(0x8, p); this.socket.end(); setTimeout(() => this.terminate(), 500).unref(); }
    terminate() { try { this.socket.destroy(); } catch (e) { /* ignore */ } this._closed(); }
  }

  // ------------------------------------------------------------ utilidades
  const cleanName = s => String(s ?? '').replace(/[\u0000-\u001f\u007f<>]/g, '').trim().slice(0, 16) || 'Jogador';
  function cleanApp(a) {
    const out = {};
    if (a && typeof a === 'object' && !Array.isArray(a)) {
      for (const k of Object.keys(a).slice(0, 24)) {
        const v = Number(a[k]);
        if (/^[a-z_]{1,16}$/.test(k) && Number.isFinite(v)) out[k] = Math.max(0, Math.min(63, Math.trunc(v)));
      }
    }
    return out;
  }
  function genCode() {
    for (let t = 0; t < 50; t++) {
      let c = ''; for (let i = 0; i < 5; i++) c += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
      if (!rooms.has(c)) return c;
    }
    return null;
  }
  const send = (cl, obj) => cl && cl.conn && cl.conn.send(obj);
  const roomClients = room => room.players.map(id => clients.get(id)).filter(Boolean);
  const cleanCfg = (c, old) => {
    c = (c && typeof c === 'object') ? c : {};
    return {
      capacity: Math.max(2, Math.min(MAX_PLAYERS, Math.trunc(Number(c.capacity ?? old.capacity)) || old.capacity)),
      fill_bots: typeof c.fill_bots === 'boolean' ? c.fill_bots : old.fill_bots,
      difficulty: DIFFS.includes(c.difficulty) ? c.difficulty : old.difficulty,
    };
  };

  function roomInfo(room) {
    return {
      t: 'room', code: room.code, type: room.type, host: room.host, cfg: room.cfg, state: room.state,
      players: roomClients(room).map(c => ({ id: c.id, name: c.name })),
    };
  }
  function broadcastRoom(room) { for (const c of roomClients(room)) send(c, roomInfo(room)); }
  function broadcastQueue(room) {
    const left = Math.max(0, Math.ceil((room.deadline - Date.now()) / 1000));
    for (const c of roomClients(room)) send(c, { t: 'queue', players: room.players.length, capacity: MAX_PLAYERS, seconds_left: left, code: room.code });
  }

  function removeRoom(room) {
    if (room.timer) clearTimeout(room.timer);
    for (const id of room.players) { const c = clients.get(id); if (c && c.room === room.code) c.room = null; }
    rooms.delete(room.code);
  }

  function startRoom(room) {
    if (room.state !== 'waiting') return;
    const humans = roomClients(room);
    const capacity = room.type === 'public' ? MAX_PLAYERS : room.cfg.capacity;
    const fill = room.type === 'public' ? true : room.cfg.fill_bots;
    const bots = fill ? Math.max(0, capacity - humans.length) : 0;
    if (humans.length + bots < 2 && room.type !== 'public') return null;
    if (room.timer) { clearTimeout(room.timer); room.timer = null; }
    room.state = 'playing';
    const msg = {
      t: 'start', seed: crypto.randomInt(1, 2147483647), host: room.host, room: room.code, bots,
      difficulty: room.type === 'public' ? 'mixed' : room.cfg.difficulty, capacity: humans.length + bots,
      humans: humans.map(c => ({ id: c.id, name: c.name, app: c.app })),
    };
    for (const c of humans) send(c, { ...msg, you: c.id });
    return true;
  }

  function leaveRoom(cl, notify = true) {
    const room = cl.room && rooms.get(cl.room);
    cl.room = null;
    if (!room) return;
    room.players = room.players.filter(id => id !== cl.id);
    if (room.state === 'playing') {
      if (cl.id === room.host) { for (const c of roomClients(room)) send(c, { t: 'host_left' }); removeRoom(room); }
      else { const h = clients.get(room.host); send(h, { t: 'peer_left', id: cl.id }); if (room.players.length === 0) removeRoom(room); }
    } else {
      if (room.players.length === 0) { removeRoom(room); }
      else {
        if (cl.id === room.host) room.host = room.players[0];
        room.type === 'public' ? broadcastQueue(room) : broadcastRoom(room);
      }
    }
    if (notify) send(cl, { t: 'left' });
  }

  function quickMatch(cl) {
    if (cl.room) leaveRoom(cl, false);
    let room = null;
    for (const r of rooms.values()) if (r.type === 'public' && r.state === 'waiting' && r.players.length < MAX_PLAYERS && r.deadline - Date.now() > 800) { room = r; break; }
    if (!room) {
      if (rooms.size >= MAX_ROOMS) return send(cl, { t: 'error', code: 'busy', msg: 'Servidor cheio. Tente novamente em instantes.' });
      const code = genCode(); if (!code) return send(cl, { t: 'error', code: 'busy', msg: 'Sem códigos livres.' });
      room = { code, type: 'public', host: cl.id, players: [], cfg: { capacity: MAX_PLAYERS, fill_bots: true, difficulty: 'mixed' }, state: 'waiting', deadline: Date.now() + MM_WAIT_MS, timer: null };
      room.timer = setTimeout(() => startRoom(room), MM_WAIT_MS);
      rooms.set(code, room);
    }
    room.players.push(cl.id); cl.room = room.code;
    broadcastQueue(room);
    if (room.players.length >= MAX_PLAYERS) startRoom(room);
  }

  // ------------------------------------------------------------ mensagens dos clientes
  const buckets = new WeakMap();
  function allow(cl) {
    const now = Date.now(); let b = buckets.get(cl);
    if (!b) { b = { tokens: 300, t: now }; buckets.set(cl, b); }
    b.tokens = Math.min(300, b.tokens + (now - b.t) * 0.4); b.t = now;   // 400 msg/s sustentado, rajada de 300
    if (b.tokens < 1) return false; b.tokens -= 1; return true;
  }

  function onMessage(cl, text) {
    if (!allow(cl)) { cl.strikes = (cl.strikes || 0) + 1; if (cl.strikes > 200) cl.conn.close(1008); return; }
    let m; try { m = JSON.parse(text); } catch (e) { return send(cl, { t: 'error', code: 'json', msg: 'Mensagem inválida.' }); }
    if (!m || typeof m !== 'object' || typeof m.t !== 'string') return;
    if (m.t === 'relay') return relay(cl, m);
    if (m.t === 'hello') {
      cl.name = cleanName(m.name); cl.app = cleanApp(m.app); cl.hello = true;
      return send(cl, { t: 'welcome', id: cl.id, version: PROTOCOL, mm_wait: MM_WAIT_MS, players_online: clients.size });
    }
    if (!cl.hello) return send(cl, { t: 'error', code: 'hello', msg: 'Envie "hello" primeiro.' });
    const room = cl.room ? rooms.get(cl.room) : null;
    switch (m.t) {
      case 'ping': return send(cl, { t: 'pong', ts: m.ts ?? 0 });
      case 'quick': if (room && room.state === 'playing') return; return quickMatch(cl);
      case 'cancel': case 'leave': return leaveRoom(cl);
      case 'create': {
        if (room && room.state === 'playing') return;
        if (cl.room) leaveRoom(cl, false);
        if (rooms.size >= MAX_ROOMS) return send(cl, { t: 'error', code: 'busy', msg: 'Servidor cheio.' });
        const code = genCode(); if (!code) return send(cl, { t: 'error', code: 'busy', msg: 'Sem códigos livres.' });
        const r = { code, type: 'custom', host: cl.id, players: [cl.id], cfg: cleanCfg(m.cfg, { capacity: 8, fill_bots: true, difficulty: 'mixed' }), state: 'waiting', deadline: 0, timer: null };
        rooms.set(code, r); cl.room = code; return broadcastRoom(r);
      }
      case 'join': {
        const code = String(m.code ?? '').toUpperCase().trim();
        const r = rooms.get(code);
        if (!r || r.type !== 'custom') return send(cl, { t: 'error', code: 'no_room', msg: 'Sala não encontrada.' });
        if (r.state !== 'waiting') return send(cl, { t: 'error', code: 'started', msg: 'A partida dessa sala já começou.' });
        if (r.players.length >= r.cfg.capacity) return send(cl, { t: 'error', code: 'full', msg: 'Sala cheia.' });
        if (cl.room) leaveRoom(cl, false);
        r.players.push(cl.id); cl.room = code; return broadcastRoom(r);
      }
      case 'cfg': {
        if (!room || room.type !== 'custom' || room.host !== cl.id || room.state !== 'waiting') return;
        room.cfg = cleanCfg(m.cfg, room.cfg);
        if (room.cfg.capacity < room.players.length) room.cfg.capacity = Math.max(2, room.players.length);
        return broadcastRoom(room);
      }
      case 'start': {
        if (!room || room.type !== 'custom' || room.host !== cl.id || room.state !== 'waiting') return send(cl, { t: 'error', code: 'denied', msg: 'Só o dono da sala pode iniciar.' });
        if (!startRoom(room)) return send(cl, { t: 'error', code: 'min', msg: 'São necessários ao menos 2 participantes (ative os bots ou convide amigos).' });
        return;
      }
    }
  }

  function relay(cl, m) {
    const room = cl.room ? rooms.get(cl.room) : null;
    if (!room || room.state !== 'playing' || typeof m.d !== 'object' || m.d === null) return;
    const out = JSON.stringify({ t: 'relay', from: cl.id, d: m.d });
    if (m.to === 'host') { if (cl.id !== room.host) { const h = clients.get(room.host); h && h.conn.send(out); } }
    else if (m.to === 'all') { if (cl.id === room.host) for (const id of room.players) if (id !== cl.id) { const c = clients.get(id); c && c.conn.send(out); } }
    else if (typeof m.to === 'number' && cl.id === room.host && room.players.includes(m.to)) { const c = clients.get(m.to); c && c.conn.send(out); }
  }

  // ------------------------------------------------------------ HTTP / upgrade
  const server = http.createServer((req, res) => {
    if (req.url === '/health' || req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
      return res.end(JSON.stringify({ ok: true, game: 'operacao-eclipse', protocol: PROTOCOL, clients: clients.size, rooms: rooms.size }));
    }
    res.writeHead(404); res.end('not found');
  });
  server.on('upgrade', (req, socket) => {
    const key = req.headers['sec-websocket-key'];
    const origin = req.headers.origin;
    if (!key || req.headers.upgrade?.toLowerCase() !== 'websocket' || clients.size >= MAX_CLIENTS || (ORIGINS.length && origin && !ORIGINS.includes(origin))) {
      socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return socket.destroy();
    }
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
      'Sec-WebSocket-Accept: ' + crypto.createHash('sha1').update(key + GUID).digest('base64') + '\r\n\r\n');
    const cl = { id: nextId++, conn: null, name: 'Jogador', app: {}, room: null, hello: false };
    cl.conn = new Conn(socket); clients.set(cl.id, cl);
    cl.conn.onmessage = text => onMessage(cl, text);
    cl.conn.onclose = () => { leaveRoom(cl, false); clients.delete(cl.id); };
  });

  const tick = setInterval(() => {
    const now = Date.now();
    for (const room of rooms.values()) if (room.type === 'public' && room.state === 'waiting') broadcastQueue(room);
    for (const cl of clients.values()) { if (now - cl.conn.lastSeen > 60000) cl.conn.terminate(); else cl.conn.ping(); }
  }, 1000);
  tick.unref();

  return {
    server, clients, rooms,
    listen: (port, cb) => server.listen(port, cb),
    close: () => { clearInterval(tick); for (const r of rooms.values()) if (r.timer) clearTimeout(r.timer); for (const c of clients.values()) c.conn.terminate(); server.close(); },
  };
}

module.exports = { createServer };
if (require.main === module) {
  const s = createServer();
  const port = parseInt(process.env.PORT || '8080', 10);
  s.listen(port, () => console.log(`[operacao-eclipse] servidor de partidas ouvindo na porta ${port}`));
  process.on('SIGTERM', () => { s.close(); process.exit(0); });
}
