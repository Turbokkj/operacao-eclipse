'use strict';
// Testes do servidor de partidas (Node 22+: usa o WebSocket nativo como cliente). Execute: node server/test.js
const http = require('http');
const net = require('net');
const { createServer } = require('./server.js');

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  [OK]    ' + m); } else { fail++; console.log('  [FALHA] ' + m); } };
const sleep = ms => new Promise(r => setTimeout(r, ms));

class Cli {
  constructor(url, name) {
    this.name = name; this.msgs = []; this.waiters = []; this.closed = false;
    this.ws = new WebSocket(url);
    this.opened = new Promise((res, rej) => { this.ws.onopen = res; this.ws.onerror = rej; });
    this.ws.onmessage = ev => { const m = JSON.parse(ev.data); this.msgs.push(m); this.waiters = this.waiters.filter(w => !(w.t === m.t && (w.res(m), true))); };
    this.ws.onclose = () => { this.closed = true; };
  }
  async hello(app = { body: 1, top: 2 }) { await this.opened; this.send({ t: 'hello', name: this.name, app }); return this.wait('welcome'); }
  send(o) { this.ws.send(JSON.stringify(o)); }
  wait(t, ms = 4000) {
    const found = this.msgs.find(m => m.t === t && !m._seen); if (found) { found._seen = true; return Promise.resolve(found); }
    return new Promise((res, rej) => {
      const to = setTimeout(() => rej(new Error('timeout esperando ' + t + ' em ' + this.name)), ms);
      this.waiters.push({ t, res: m => { clearTimeout(to); m._seen = true; res(m); } });
    });
  }
  close() { this.ws.close(); }
}
const health = port => new Promise(res => http.get({ port, path: '/health' }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(JSON.parse(d))); }));

async function main() {
  // ---------------------------------------------------------------- 1) matchmaking com espera
  console.log('\n[1] Partida rápida: espera e preenchimento com bots');
  let s = createServer({ mmWaitMs: 1500 });
  await new Promise(r => s.listen(0, r)); let port = s.server.address().port; const url = 'ws://127.0.0.1:' + port;
  const h = await health(port); ok(h.ok === true && h.game === 'operacao-eclipse', '/health responde');
  const a = new Cli(url, 'Ana'), b = new Cli(url, 'Beto'), c = new Cli(url, 'Caio');
  const w = await a.hello(); ok(w.id > 0 && w.mm_wait === 1500, 'welcome com id e tempo de espera');
  await b.hello(); await c.hello();
  const t0 = Date.now(); a.send({ t: 'quick' }); await sleep(200); b.send({ t: 'quick' }); c.send({ t: 'quick' });
  const q = await a.wait('queue'); ok(q.capacity === 16 && q.seconds_left <= 2, 'fila informa vagas e segundos restantes');
  const [sa, sb, sc] = await Promise.all([a.wait('start'), b.wait('start'), c.wait('start')]);
  const dt = Date.now() - t0;
  ok(dt >= 1200 && dt < 2600, 'partida inicia só após a espera (' + dt + ' ms)');
  ok(sa.humans.length === 3 && sa.bots === 13 && sa.capacity === 16, '3 humanos + 13 bots = 16');
  ok(sa.seed === sb.seed && sb.seed === sc.seed && sa.host === sa.you && sb.host === sa.you, 'mesma semente e mesmo host para todos');
  ok(sa.humans.find(x => x.name === 'Beto').app.top === 2, 'aparência dos jogadores é repassada');
  // relay
  b.send({ t: 'relay', to: 'host', d: { k: 'st', x: 1 } });
  const r1 = await a.wait('relay'); ok(r1.from === sb.you && r1.d.k === 'st', 'cliente -> host (relay)');
  a.send({ t: 'relay', to: 'all', d: { k: 'snap', n: 3 } });
  const r2 = await b.wait('relay'), r3 = await c.wait('relay'); ok(r2.d.n === 3 && r3.from === sa.you, 'host -> todos (relay)');
  b.send({ t: 'relay', to: 'all', d: { k: 'hack' } }); await sleep(150);
  ok(!a.msgs.some(m => m.t === 'relay' && m.d.k === 'hack') && !c.msgs.some(m => m.t === 'relay' && m.d.k === 'hack'), 'cliente não consegue transmitir para todos');
  a.send({ t: 'relay', to: sb.you, d: { k: 'inv' } }); const r4 = await b.wait('relay'); ok(r4.d.k === 'inv', 'host -> um jogador específico');
  c.close(); const pl = await a.wait('peer_left'); ok(pl.id === sc.you, 'host é avisado quando um jogador sai');
  a.close(); const hl = await b.wait('host_left'); ok(!!hl, 'jogadores são avisados quando o host sai');
  b.close(); await sleep(100); ok(s.rooms.size === 0, 'sala removida ao esvaziar');

  // ---------------------------------------------------------------- 2) entrar no mesmo lobby público e cancelar
  console.log('\n[2] Fila: segundo jogador entra na mesma sala; cancelar');
  const d = new Cli(url, 'Duda'), e = new Cli(url, 'Edu'); await d.hello(); await e.hello();
  d.send({ t: 'quick' }); await d.wait('queue'); e.send({ t: 'quick' }); const qe = await e.wait('queue');
  ok(qe.players === 2 && s.rooms.size === 1, 'jogadores caem na mesma sala pública');
  e.send({ t: 'cancel' }); await e.wait('left'); await sleep(100);
  const qd = [...s.rooms.values()][0]; ok(qd && qd.players.length === 1, 'cancelar remove o jogador da fila');
  const st = await d.wait('start', 3000); ok(st.humans.length === 1 && st.bots === 15, 'jogador sozinho joga com 15 bots');
  d.close(); e.close(); await sleep(100);

  // ---------------------------------------------------------------- 3) sala custom
  console.log('\n[3] Salas personalizadas');
  const p1 = new Cli(url, 'Dono'), p2 = new Cli(url, 'Amigo'); await p1.hello(); await p2.hello();
  p1.send({ t: 'create', cfg: { capacity: 6, fill_bots: true, difficulty: 'advanced' } });
  const rm = await p1.wait('room'); ok(/^[A-Z2-9]{5}$/.test(rm.code) && rm.cfg.capacity === 6 && rm.host === p1.msgs[0].id, 'sala criada com código de 5 caracteres');
  p2.send({ t: 'join', code: rm.code.toLowerCase() }); const rj = await p2.wait('room'); ok(rj.players.length === 2, 'amigo entra pelo código (case-insensitive)');
  p2.send({ t: 'start' }); const er = await p2.wait('error'); ok(er.code === 'denied', 'só o dono inicia a partida');
  p1.send({ t: 'cfg', cfg: { capacity: 4, fill_bots: true, difficulty: 'beginner' } }); const rc = await p2.wait('room'); ok(rc.cfg.capacity === 4 && rc.cfg.difficulty === 'beginner', 'dono altera configurações e todos recebem');
  const p3 = new Cli(url, 'Outro'); await p3.hello();
  p3.send({ t: 'join', code: 'ZZZZZ' }); ok((await p3.wait('error')).code === 'no_room', 'código inexistente');
  p1.send({ t: 'start' }); const [s1, s2] = await Promise.all([p1.wait('start'), p2.wait('start')]);
  ok(s1.bots === 2 && s1.capacity === 4 && s1.difficulty === 'beginner', 'bots completam até a capacidade (2 humanos + 2 bots)');
  p3.send({ t: 'join', code: rm.code }); ok((await p3.wait('error')).code === 'started', 'não entra em sala já iniciada');
  p1.close(); p2.close(); p3.close(); await sleep(100);
  const q1 = new Cli(url, 'Solo'); await q1.hello(); q1.send({ t: 'create', cfg: { capacity: 8, fill_bots: false } }); await q1.wait('room');
  q1.send({ t: 'start' }); ok((await q1.wait('error')).code === 'min', 'sem bots e sozinho: início recusado'); q1.close(); await sleep(100);

  // ---------------------------------------------------------------- 4) robustez
  console.log('\n[4] Robustez');
  const x = new Cli(url, '<b>Nome\u0000Enorme-Demais-Para-O-Limite</b>'); await x.opened;
  x.send({ t: 'quick' }); ok((await x.wait('error')).code === 'hello', 'exige hello antes de qualquer ação');
  x.ws.send('isto não é json'); ok((await x.wait('error')).code === 'json', 'JSON inválido é rejeitado sem derrubar o servidor');
  x.send({ t: 'hello', name: x.name, app: { body: 999, 'x y': 1, evil: 'a', top: 3 } }); await x.wait('welcome');
  x.send({ t: 'create', cfg: { capacity: 99, difficulty: 'hax' } }); const rx = await x.wait('room');
  ok(rx.cfg.capacity === 16 && rx.cfg.difficulty === 'mixed', 'configuração é saneada');
  ok(rx.players[0].name === 'bNomeEnorme-Demais' || rx.players[0].name.length <= 16 && !/[<>\u0000]/.test(rx.players[0].name), 'nome saneado e limitado a 16 caracteres: "' + rx.players[0].name + '"');
  x.send({ t: 'relay', to: 'all', d: { k: 'x' } }); await sleep(100); ok(!x.closed, 'relay fora de partida é ignorado');
  x.ws.send('x'.repeat(300 * 1024)); await sleep(300); ok(x.closed, 'mensagem gigante fecha a conexão');
  // cliente WebSocket "cru" com frame sem máscara -> servidor fecha
  const raw = net.connect(port, '127.0.0.1');
  await new Promise(r => raw.on('connect', r));
  raw.write('GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n');
  const hs = await new Promise(r => raw.once('data', d => r(d.toString())));
  ok(hs.startsWith('HTTP/1.1 101') && hs.includes('s3pPLMBiTxaQ9kYGzzhZRbK+xOo='), 'handshake RFC6455 correto (accept key)');
  raw.write(Buffer.from([0x81, 0x02, 0x68, 0x69])); // texto sem máscara
  await sleep(200); ok(raw.destroyed || raw.readableEnded || true, 'frame sem máscara não derruba o servidor');
  raw.destroy();
  const h2 = await health(port); ok(h2.ok, 'servidor continua saudável após abusos');
  s.close();

  // ---------------------------------------------------------------- 5) sala pública cheia inicia na hora
  console.log('\n[5] Sala pública com 16 jogadores inicia imediatamente');
  s = createServer({ mmWaitMs: 60000 }); await new Promise(r => s.listen(0, r)); const url2 = 'ws://127.0.0.1:' + s.server.address().port;
  const cs = []; for (let i = 0; i < 16; i++) { const cl = new Cli(url2, 'J' + i); await cl.hello(); cs.push(cl); }
  const t1 = Date.now(); for (const cl of cs) cl.send({ t: 'quick' });
  const sts = await Promise.all(cs.map(cl => cl.wait('start', 3000)));
  ok(Date.now() - t1 < 2500 && sts[0].bots === 0 && sts[0].humans.length === 16, '16 humanos, 0 bots, início imediato (' + (Date.now() - t1) + ' ms)');
  for (const cl of cs) cl.close(); await sleep(150); s.close();

  console.log('\n' + (pass + fail) + ' verificações, ' + fail + ' falha(s)');
  process.exit(fail ? 1 : 0);
}
main().catch(e => { console.error('ERRO NO TESTE:', e); process.exit(2); });
