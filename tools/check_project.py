#!/usr/bin/env python3
"""Verificador ESTÁTICO do projeto Godot (não substitui abrir no editor/rodar os testes do jogo).
Procura erros que costumam virar "Parse Error" no GDScript:
  - indentação mista / colchetes desbalanceados
  - caminhos res:// inexistentes
  - class_name duplicado e autoloads sem script
  - chamadas  Autoload.func(...) / Classe.func_estatica(...) para funções inexistentes ou com nº de argumentos errado
  - Events.sinal.emit/connect para sinais inexistentes (e nº de argumentos do emit)
  - 'var x := <expressão Variant>' (inferência impossível)
  - membros declarados com nomes que já existem em classes base da Godot
  - funções/membros duplicados no mesmo arquivo
Uso: python3 tools/check_project.py   (código de saída 1 se houver ERROS)"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
errors, warnings = [], []


def err(f, ln, msg):
    errors.append("ERRO   %s:%d  %s" % (os.path.relpath(f, ROOT), ln, msg))


def warn(f, ln, msg):
    warnings.append("AVISO  %s:%d  %s" % (os.path.relpath(f, ROOT), ln, msg))


def files(ext):
    out = []
    for d, _, fs in os.walk(ROOT):
        if "/build" in d or "/.git" in d or "/.godot" in d:
            continue
        for f in fs:
            if f.endswith(ext):
                out.append(os.path.join(d, f))
    return sorted(out)


def strip_code(line):
    """Remove strings e comentários de uma linha (aproximado) para análise de colchetes."""
    out, q, i = [], None, 0
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\":
                i += 2
                continue
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c == "#":
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


gd = files(".gd")
src = {}
for f in gd:
    src[f] = open(f, encoding="utf-8").read().split("\n")

# ---------------------------------------------------------------- registro de classes/autoloads
classes = {}   # class_name -> arquivo
for f, lines in src.items():
    for i, l in enumerate(lines):
        m = re.match(r"^class_name\s+(\w+)", l)
        if m:
            if m.group(1) in classes:
                err(f, i + 1, "class_name duplicado: " + m.group(1))
            classes[m.group(1)] = f
autoloads = {}
pg = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
for m in re.finditer(r'^(\w+)="\*res://([^"]+)"', pg, re.M):
    autoloads[m.group(1)] = os.path.join(ROOT, m.group(2))
    if not os.path.exists(autoloads[m.group(1)]):
        err(os.path.join(ROOT, "project.godot"), 1, "autoload sem arquivo: " + m.group(2))


def parse_members(f):
    """Retorna dict: funcs{nome:(min_args,max_args,static)}, signals{nome:nargs}, others(set de var/const/enum)."""
    funcs, sigs, others = {}, {}, set()
    for i, l in enumerate(src[f]):
        m = re.match(r"^(static\s+)?func\s+(\w+)\s*\((.*)\)", l)
        if m:
            params = [p.strip() for p in split_args(m.group(3))] if m.group(3).strip() else []
            req = sum(1 for p in params if "=" not in p)
            name = m.group(2)
            if name in funcs:
                err(f, i + 1, "função duplicada: " + name)
            funcs[name] = (req, len(params), bool(m.group(1)))
            continue
        m = re.match(r"^signal\s+(\w+)\s*(\((.*)\))?", l)
        if m:
            sigs[m.group(1)] = len(split_args(m.group(3))) if m.group(3) and m.group(3).strip() else 0
            continue
        m = re.match(r"^(?:static\s+)?(?:var|const)\s+(\w+)", l)
        if m:
            others.add(m.group(1))
        m = re.match(r"^enum\s+(\w+)", l)
        if m:
            others.add(m.group(1))
    return funcs, sigs, others


def split_args(s):
    out, depth, cur, q = [], 0, "", None
    for c in s:
        if q:
            cur += c
            if c == q:
                q = None
            continue
        if c in "\"'":
            q = c
            cur += c
        elif c in "([{":
            depth += 1
            cur += c
        elif c in ")]}":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur)
    return out


members = {f: parse_members(f) for f in gd}

# ---------------------------------------------------------------- 1) indentação e colchetes
for f, lines in src.items():
    depth = 0
    in_ml = False
    prev_cont = False
    for i, l in enumerate(lines):
        if l.count('"""') % 2 == 1:
            in_ml = not in_ml
            continue
        if in_ml:
            continue
        continuation = depth > 0 or prev_cont
        if not continuation:
            if re.match(r"^\t* +\S", l) and not re.match(r"^ +\S", l):
                err(f, i + 1, "indentação mista (tabs + espaços)")
            elif re.match(r"^ +\S", l):
                err(f, i + 1, "indentação com espaços (deve usar tabs)")
        code = strip_code(l)
        depth += sum(code.count(c) for c in "([{") - sum(code.count(c) for c in ")]}")
        if depth < 0:
            err(f, i + 1, "fecha colchete sem abrir")
            depth = 0
        prev_cont = l.rstrip().endswith("\\")
    if depth != 0:
        err(f, len(lines), "colchetes desbalanceados (saldo %d)" % depth)

# ---------------------------------------------------------------- 2) caminhos res://
for f in gd + files(".tscn") + files(".cfg") + [os.path.join(ROOT, "project.godot")]:
    text = open(f, encoding="utf-8").read()
    for m in re.finditer(r'"(res://[^"\s]+)"', text):
        p = m.group(1)
        if "%" in p or p.endswith("/") or "{" in p:
            continue
        path = os.path.join(ROOT, p[6:])
        if not os.path.exists(path):
            ln = text[: m.start()].count("\n") + 1
            err(f, ln, "caminho inexistente: " + p)

# ---------------------------------------------------------------- 3) chamadas entre scripts
BUILTIN_STATIC = {"new", "get_class", "free", "connect", "emit", "is_connected", "disconnect", "call", "bind", "get", "set",
                  "get_script", "has_method", "to_string", "instantiate", "duplicate", "size", "keys"}
call_re = re.compile(r"(?<![\w.])([A-Z]\w+)\.(\w+)\s*\(")


def call_args(line, start):
    depth, i, q = 0, start, None
    buf = ""
    while i < len(line):
        c = line[i]
        if q:
            buf += c
            if c == q:
                q = None
        elif c in "\"'":
            q = c
            buf += c
        elif c == "(":
            depth += 1
            if depth > 1:
                buf += c
        elif c == ")":
            depth -= 1
            if depth == 0:
                return split_args(buf), True
            buf += c
        else:
            buf += c
        i += 1
    return split_args(buf), False


for f, lines in src.items():
    for i, raw in enumerate(lines):
        line = strip_code(raw) if '"' not in raw else raw
        if raw.strip().startswith("#"):
            continue
        for m in call_re.finditer(raw):
            name, meth = m.group(1), m.group(2)
            target = autoloads.get(name) or classes.get(name)
            if not target or target not in members:
                continue
            funcs, sigs, others = members[target]
            if meth in BUILTIN_STATIC and meth != "get":
                if meth == "new":
                    init = funcs.get("_init")
                    args, ok = call_args(raw, m.end() - 1)
                    if ok and init and not (init[0] <= len(args) <= init[1]) and not (len(args) == 0 and init[0] == 0):
                        err(f, i + 1, "%s.new(): %d args, _init espera %d..%d" % (name, len(args), init[0], init[1]))
                continue
            if meth not in funcs and meth not in sigs and meth not in others:
                err(f, i + 1, "%s.%s não existe" % (name, meth))
                continue
            if meth in funcs:
                mn, mx, is_static = funcs[meth]
                if name in classes and not is_static and name not in autoloads:
                    warn(f, i + 1, "%s.%s não é static (chamada a método de instância via nome da classe)" % (name, meth))
                args, ok = call_args(raw, m.end() - 1)
                if ok:
                    n = len(args)
                    if n < mn or n > mx:
                        err(f, i + 1, "%s.%s(): %d args (esperado %d..%d)" % (name, meth, n, mn, mx))

# ---------------------------------------------------------------- 3b) constantes/propriedades Classe.CONSTANTE
const_re = re.compile(r"(?<![\w.])([A-Z]\w+)\.([A-Z][A-Z0-9_]*)\b(?!\s*\()")
for f, lines in src.items():
    for i, raw in enumerate(lines):
        if raw.strip().startswith("#"):
            continue
        code = re.sub(r'"[^"\n]*"', '""', raw)
        for m in const_re.finditer(code):
            name, const = m.group(1), m.group(2)
            target = autoloads.get(name) or classes.get(name)
            if not target or target not in members:
                continue
            funcs, sigs, others = members[target]
            # enums internos: ENUM.valor é resolvido como membro 'others' (nome do enum); aqui só checa o 1º nível
            if const not in others and const not in funcs and const not in sigs:
                # valores de enum declarados em linha (enum B { A, B })
                body = "\n".join(src[target])
                if re.search(r"\b%s\b" % re.escape(const), body):
                    continue
                err(f, i + 1, "%s.%s não existe" % (name, const))

# ---------------------------------------------------------------- 4) sinais do barramento Events
ev_funcs, ev_sigs, _ = members[autoloads["Events"]]
for f, lines in src.items():
    for i, raw in enumerate(lines):
        for m in re.finditer(r"Events\.(\w+)\.(emit|connect|disconnect|is_connected)\(", raw):
            sg = m.group(1)
            if sg not in ev_sigs:
                err(f, i + 1, "Events.%s não é um sinal declarado" % sg)
            elif m.group(2) == "emit":
                args, ok = call_args(raw, m.end() - 1)
                if ok and len(args) != ev_sigs[sg]:
                    err(f, i + 1, "Events.%s.emit com %d args (declarado %d)" % (sg, len(args), ev_sigs[sg]))

# ---------------------------------------------------------------- 5) := com valor Variant
variant_fn = re.compile(r":=\s*(lerp|clamp|min|max|abs|sign|floor|ceil|round|snapped|wrap|move_toward|remap)\(")
for f, lines in src.items():
    for i, raw in enumerate(lines):
        m = re.search(r"\bvar\s+\w+\s*:=\s*(.*)$", raw)
        if not m:
            continue
        rhs = m.group(1).strip()
        if variant_fn.search(raw):
            err(f, i + 1, "':=' com função que retorna Variant (use lerpf/clampf/...): " + rhs[:60])
        elif re.search(r"\[\"[^\"]+\"\]\s*$", rhs) or re.search(r"\[\d+\]\s*$", rhs):
            warn(f, i + 1, "':=' com indexação (pode ser Variant): " + rhs[:60])
        elif re.search(r"\.get\([^)]*\)\s*$", rhs) and "get_" not in rhs:
            warn(f, i + 1, "':=' com .get() (Variant): " + rhs[:60])
        elif re.search(r"\.(pop_front|pop_back|front|back|pick_random)\(\)\s*$", rhs):
            warn(f, i + 1, "':=' com retorno Variant: " + rhs[:60])

# ---------------------------------------------------------------- 6) membros que colidem com classes base
FORBIDDEN = {"name", "position", "rotation", "scale", "velocity", "visible", "size", "text", "transform", "owner", "mesh",
             "layer", "process_mode", "global_position", "basis", "modulate", "material", "scene_file_path", "parent", "script"}
for f, lines in src.items():
    ext = next((re.match(r"^extends\s+(\w+)", l).group(1) for l in lines if re.match(r"^extends\s+(\w+)", l)), "")
    if ext in ("RefCounted", "Object", ""):
        continue
    for i, raw in enumerate(lines):
        m = re.match(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+(\w+)", raw)
        if m and m.group(1) in FORBIDDEN:
            err(f, i + 1, "membro '%s' conflita com propriedade de %s" % (m.group(1), ext))

# ---------------------------------------------------------------- 7) variável local redeclarada em escopo aninhado
def _tabs(l):
    return len(re.match(r"^(\t*)", l).group(1))


for f, lines in src.items():
    stack = []
    depth = 0
    prev_cont = False
    in_ml = False
    in_func = False
    for n, raw in enumerate(lines, 1):
        if raw.count('"""') % 2 == 1:
            in_ml = not in_ml
            continue
        if in_ml:
            continue
        code = strip_code(raw)
        cont = depth > 0 or prev_cont
        depth += sum(code.count(c) for c in "([{") - sum(code.count(c) for c in ")]}")
        prev_cont = raw.rstrip().endswith("\\")
        if cont or not code.strip():
            continue
        L = _tabs(raw)
        body = code.strip()
        if L == 0:
            stack = []
            m = re.match(r"^(?:static\s+)?func\s+\w+\s*\((.*)\)", body)
            in_func = bool(m)
            if m:
                stack = [(1, set(re.findall(r"(\w+)\s*(?::|,|=|$)", m.group(1))))]
            continue
        if not in_func:
            continue
        while stack and stack[-1][0] > L:
            stack.pop()
        if not stack:
            continue
        m = re.match(r"^var\s+(\w+)", body)
        if m:
            nm = m.group(1)
            if any(nm in sc for _, sc in stack):
                err(f, n, "variável '%s' já declarada em escopo envolvente (erro de parse no GDScript)" % nm)
            else:
                stack[-1][1].add(nm)
        for lm in re.finditer(r"func\s*\(([^)]*)\)\s*(?:->\s*\w+\s*)?:", code):
            for pnm in re.findall(r"(\w+)\s*(?::\s*\w+)?\s*(?:,|$)", lm.group(1)):
                if any(pnm in sc for _, sc in stack):
                    warn(f, n, "parâmetro de lambda '%s' colide com variável local" % pnm)
        if body.endswith(":") and not body.startswith(("func", "class")):
            new = set()
            m = re.match(r"^for\s+(\w+)\s+in\b", body)
            if m:
                if any(m.group(1) in sc for _, sc in stack):
                    err(f, n, "variável de laço '%s' já declarada em escopo envolvente" % m.group(1))
                new.add(m.group(1))
            stack.append((L + 1, new))

# ---------------------------------------------------------------- resultado
print("Arquivos .gd analisados: %d | classes: %d | autoloads: %d" % (len(gd), len(classes), len(autoloads)))
for w in warnings:
    print(w)
for e in errors:
    print(e)
print("\n%d erro(s), %d aviso(s)." % (len(errors), len(warnings)))
sys.exit(1 if errors else 0)
