#!/usr/bin/env python3
"""bas2c.py -- translate the BASIC compiler's sources into C (the bootstrap).

  bas2c.py -o out.c MAIN.bas OTHER.bas ...

The modules are translated into one C file that, with tools/hostrt.h,
builds the compiler on Linux.  The first module is the main program (its
body runs last, after the other modules' bodies, as the P-System linker
does it).

Only the part of the language the compiler itself is written in is
handled: INTEGER, BYTE, DOUBLE and STRING variables and arrays, SUB and
FUNCTION (BYVAL, BYREF, array parameters), COMMON SHARED, DIM SHARED,
CONST, block and one-line IF, SELECT CASE, FOR, DO, WHILE, EXIT,
CONTINUE, GOTO, the string and file statements and functions the
compiler uses.  Semantics follow the compiler: 16-bit integers that wrap,
comparisons -1 / 0, left-to-right evaluation (C's unspecified order is
made explicit with temporaries where it could matter).
"""
import os, re, sys

KEYWORDS = """PRINT INPUT LET IF THEN ELSE ELSEIF END FOR TO STEP NEXT WHILE WEND DO LOOP UNTIL EXIT
GOTO GOSUB RETURN ON SUB FUNCTION CALL DIM REDIM SHARED COMMON AS INTEGER SINGLE DOUBLE
STRING BYTE CONST DECLARE DEFINT DEFSNG DEFDBL DEFSTR SELECT CASE IS OPEN CLOSE OUTPUT
APPEND BINARY RANDOM LINE GET PUT KILL STOP SYSTEM AND OR XOR NOT MOD BYREF BYVAL STATIC
SEGMENT PRIVATE SWAP ERASE DATA READ RESTORE CONTINUE RANDOMIZE OPTION EXPLICIT REAL CLS
LOCATE WRITE PRESERVE ERROR RESUME SEEK USING""".split()
KW = set(KEYWORDS)

T_INT, T_SNG, T_DBL, T_STR, T_BYTE = 'I', 'F', 'D', 'S', 'B'
CTYPE = {T_INT: 'bint', T_BYTE: 'bint', T_SNG: 'float', T_DBL: 'double', T_STR: 'bstr'}
ELEMC = {T_INT: 'bint', T_BYTE: 'uint8_t', T_SNG: 'float', T_DBL: 'double', T_STR: 'bstr'}
ZERO = {T_INT: '0', T_BYTE: '0', T_SNG: '0', T_DBL: '0', T_STR: '{0}'}
SUFFIX = {'%': T_INT, '!': T_SNG, '#': T_DBL, '$': T_STR}
TYPECHAR = {T_INT: '%', T_SNG: '!', T_DBL: '#', T_STR: '$', T_BYTE: '&'}


class Err(Exception):
    pass


class Tok:
    __slots__ = ('k', 'v', 'line', 'file')

    def __init__(self, k, v, line, file):
        self.k, self.v, self.line, self.file = k, v, line, file

    def __repr__(self):
        return '%s:%r' % (self.k, self.v)


# ---------------------------------------------------------------- lexer

def comment_at(l):
    p, st, n = 0, True, len(l)
    while p < n:
        c = l[p]
        if c == '"':
            q = l.find('"', p + 1)
            if q < 0:
                return n
            p, st = q + 1, False
        elif c == "'":
            return p
        elif c == ':':
            st, p = True, p + 1
        elif c in ' \t' or (st and c.isdigit()):
            p += 1
        elif st and l[p:p + 3].upper() == 'REM' and not (l[p + 3:p + 4].isalnum() or l[p + 3:p + 4] == '_'):
            return p
        else:
            st, p = False, p + 1
    return n


def lex_file(path, out, depth=0):
    d = os.path.dirname(path)
    lines = open(path, encoding='latin1').read().split('\n')
    i = 0
    while i < len(lines):
        l = lines[i].rstrip('\r')
        ln = i + 1
        i += 1
        while l.rstrip().endswith(' _') and i < len(lines):
            l = l.rstrip()[:-1] + lines[i].strip()
            i += 1
        t = l[:comment_at(l)].strip()
        if not t:
            continue
        if t.upper().startswith('#INCLUDE'):
            m = re.search(r'"([^"]*)"', t)
            name = m.group(1)
            for cand in (name, name.lower() + '.bas', name + '.bas', name.lower()):
                p = os.path.join(d, cand)
                if os.path.exists(p):
                    lex_file(p, out, depth + 1)
                    break
            else:
                raise Err('%s:%d: no include file %s' % (path, ln, name))
            continue
        lex_line(t, path, ln, out)
    return out


def lex_line(t, path, ln, out):
    p, n = 0, len(t)
    first = 1

    def add(k, v=None):
        out.append(Tok(k, v, ln, path))
    add('NL')
    while p < n:
        c = t[p]
        if c in ' \t':
            p += 1
            continue
        if first == 1 and c.isdigit():
            s = p
            while p < n and t[p].isdigit():
                p += 1
            add('LABEL', str(int(t[s:p])))
            continue
        if c.isalpha() or c == '_':
            s = p
            while p < n and (t[p].isalnum() or t[p] == '_'):
                p += 1
            w = t[s:p].upper()
            if w in KW and not (p < n and t[p] in '%!$'):
                add('KW', w)
                first = 2 if w in ('THEN', 'ELSE') else 0
                continue
            if p < n and t[p] in '%!#$':
                w += t[p]
                p += 1
            if first == 1 and p < n and t[p] == ':' and w[-1] not in '%!#$':
                p += 1
                add('LABEL', w)
                continue
            add('ID', w)
            first = 0
            continue
        if c.isdigit() or (c == '.' and p + 1 < n and t[p + 1].isdigit()):
            m = re.match(r'(\d*\.?\d*)([EeDd][+-]?\d+)?([%!#]?)', t[p:])
            txt = m.group(0)
            p += len(txt)
            body, ex, suf = m.group(1), m.group(2) or '', m.group(3)
            isreal = '.' in body or ex or suf in '!#' and suf
            if not isreal and suf in ('', '%') and int(body) <= 32768:
                v = int(body)
                add('INT', -32768 if v == 32768 else v)
            else:
                ty = T_DBL if (suf == '#' or ex[:1] in 'Dd' and ex) else T_SNG
                add('REAL', (body + ex.upper().replace('D', 'E'), ty))
            first = 0
            continue
        if c == '"':
            q = t.find('"', p + 1)
            if q < 0:
                q = n
            add('STR', t[p + 1:q])
            p = q + 1
            first = 0
            continue
        if c == '&' and p + 1 < n and t[p + 1] in 'HhOoBb':
            base = {'H': 16, 'O': 8, 'B': 2}[t[p + 1].upper()]
            p += 2
            s = p
            while p < n and t[p].upper() in '0123456789ABCDEF'[:base]:
                p += 1
            v = int(t[s:p], base) & 0xFFFF
            if v > 32767:
                v -= 65536
            add('INT', v)
            first = 0
            continue
        two = t[p:p + 2]
        if two in ('<>', '<=', '>=', '=<', '=>', '><'):
            add('OP', {'=<': '<=', '=>': '>=', '><': '<>'}.get(two, two))
            p += 2
            first = 0
            continue
        if c in '=<>+-*/\\^(),;#&:':
            add('OP', c)
            p += 1
            first = 1 if c == ':' else 0
            continue
        if c == '?':
            add('KW', 'PRINT')
            p += 1
            continue
        raise Err('%s:%d: unexpected character %r' % (path, ln, c))


# ---------------------------------------------------------------- symbols

def mangle(name):
    s = name.replace('$', '_S').replace('%', '_I').replace('!', '_F').replace('#', '_D').replace('&', '_B')
    s = s.replace("'", '_q_')
    return s


class Proc:
    def __init__(self, name, kind, ret, params, private, mod):
        self.name, self.kind, self.ret, self.params, self.private, self.mod = name, kind, ret, params, private, mod
        # params: list of (name, type, byref, isarray, asflag)

    def cname(self):
        if self.private:
            return 'p%d_%s' % (self.mod.idx, mangle(self.name))
        return 'p_' + mangle(self.name)


class Var:
    def __init__(self, key, ty, isarr, cls, cname, asflag=False):
        self.key, self.ty, self.isarr, self.cls, self.cname, self.asflag = key, ty, isarr, cls, cname, asflag
        # cls: common static local param ref


class Module:
    def __init__(self, idx, path):
        self.idx, self.path = idx, path
        self.name = os.path.splitext(os.path.basename(path))[0].upper()
        self.toks = lex_file(path, [])
        self.statics = {}        # key -> Var (module level)
        self.consts = {}         # key -> (type, ctext)
        self.deftype = [T_SNG] * 26


# ---------------------------------------------------------------- translator

class Trans:
    def __init__(self, mods):
        self.stmtcall = False
        self.mods = mods
        self.commons = {}
        self.procs = {}
        self.out = []

    # ---- tokens
    def setup(self, mod):
        self.mod = mod
        self.toks = mod.toks
        self.p = 0

    @property
    def t(self):
        return self.toks[self.p] if self.p < len(self.toks) else Tok('EOF', None, 0, '')

    def at(self, k, v=None):
        t = self.t
        return t.k == k and (v is None or t.v == v)

    def kw(self, v):
        return self.at('KW', v)

    def op(self, v):
        return self.at('OP', v)

    def next(self):
        t = self.t
        self.p += 1
        return t

    def err(self, msg):
        t = self.t
        raise Err('%s:%d: %s (at %r)' % (t.file, t.line, msg, t))

    def expect_kw(self, v):
        if not self.kw(v):
            self.err(v + ' expected')
        self.next()

    def expect_op(self, v):
        if not self.op(v):
            self.err(v + ' expected')
        self.next()

    def at_end(self):
        t = self.t
        return t.k in ('NL', 'EOF') or (t.k == 'OP' and t.v == ':') or (t.k == 'KW' and t.v == 'ELSE')

    def skip_stmt(self):
        while not (self.t.k in ('NL', 'EOF') or self.op(':')):
            self.next()

    # ---- types
    def nametype(self, n):
        if n[-1] in SUFFIX:
            return SUFFIX[n[-1]]
        c = ord(n.lstrip('_')[:1] or '_') - 65
        return self.mod.deftype[c] if 0 <= c < 26 else T_SNG

    def parse_type(self):
        t = self.next()
        m = {'INTEGER': T_INT, 'SINGLE': T_SNG, 'REAL': T_SNG, 'DOUBLE': T_DBL, 'STRING': T_STR, 'BYTE': T_BYTE}
        if t.k != 'KW' or t.v not in m:
            self.err('a type expected')
        return m[t.v]

    def decl_type(self, n, isproc=False):
        """(key, type, asflag) of a declared name"""
        if self.kw('AS'):
            self.next()
            return n, self.parse_type(), True
        if n[-1] in SUFFIX:
            return n, SUFFIX[n[-1]], False
        ty = self.nametype(n)
        if isproc:
            return n, ty, True
        return n + TYPECHAR[ty], ty, False

    def def_letters(self, ty):
        while True:
            a = self.next().v
            b = a
            if self.op('-'):
                self.next()
                b = self.next().v
            for c in range(ord(a[0]) - 65, ord(b[0]) - 64):
                self.mod.deftype[c] = ty
            if not self.op(','):
                break
            self.next()

    DEFKW = {'DEFINT': T_INT, 'DEFSNG': T_SNG, 'DEFDBL': T_DBL, 'DEFSTR': T_STR}

    # ---- pass A: declarations
    def params(self):
        ps = []
        if not self.op('('):
            return ps
        self.next()
        if self.op(')'):
            self.next()
            return ps
        while True:
            byref = False
            if self.kw('BYREF'):
                byref = True
                self.next()
            elif self.kw('BYVAL'):
                self.next()
            n = self.next().v
            isarr = False
            if self.op('('):
                self.next()
                self.expect_op(')')
                isarr = True
            key, ty, asf = self.decl_type(n)
            ps.append((key, ty, byref, isarr, asf))
            if not self.op(','):
                break
            self.next()
        self.expect_op(')')
        return ps

    def proc_header(self, private):
        kind = self.next().v
        n = self.next().v
        ps = self.params()
        ret = None
        if kind == 'FUNCTION':
            key, ret, asf = self.decl_type(n, True)
            n = key
        if self.kw('STATIC'):
            self.next()
        return Proc(n, kind, ret, ps, private, self.mod)

    def link_name(self, n, kind, ret):
        base = n[:-1] if n[-1] in SUFFIX else n
        return base if kind == 'SUB' else base + TYPECHAR[ret]

    def find_proc(self, n):
        if n in self.procs:
            return self.procs[n]
        if n[-1] in SUFFIX:
            p = self.procs.get(n[:-1])
            if p and p.ret == SUFFIX[n[-1]]:
                return p
        return None

    def add_proc(self, pr):
        # by its name as written in the definition (FindProc's rules)
        old = self.procs.get(pr.name)
        if old is None:
            self.procs[pr.name] = pr

    def pass_a(self, mod):
        self.setup(mod)
        mod.deftype = [T_SNG] * 26
        mod.bodies = []
        while self.t.k != 'EOF':
            t = self.t
            if t.k in ('NL', 'LABEL') or self.op(':'):
                self.next()
                continue
            private = False
            if self.kw('PRIVATE'):
                self.next()
                private = True
            if self.kw('SUB') or self.kw('FUNCTION'):
                start = self.p
                pr = self.proc_header(private)
                pr.start = start
                self.add_proc(pr)
                self.skip_body()
                pr.defined = True
                continue
            if self.kw('DECLARE'):
                self.next()
                pr = self.proc_header(private)
                self.add_proc(pr)
                continue
            if t.k == 'KW' and t.v in self.DEFKW:
                self.next()
                self.def_letters(self.DEFKW[t.v])
                continue
            if self.kw('COMMON'):
                self.next()
                if self.kw('SHARED'):
                    self.next()
                self.decl_vars('common')
                continue
            if self.kw('DIM'):
                self.next()
                if self.kw('SHARED'):
                    self.next()
                    self.decl_vars('static')
                    continue
            self.skip_stmt()

    def skip_body(self):
        while True:
            self.skip_stmt()
            if self.t.k == 'EOF':
                return
            self.next()
            while self.t.k in ('LABEL', 'NL'):
                self.next()
            if self.kw('END'):
                self.next()
                if self.kw('SUB') or self.kw('FUNCTION'):
                    self.next()
                    return

    def decl_vars(self, cls):
        while True:
            n = self.next().v
            isarr = False
            if self.op('('):
                isarr = True
                depth = 0
                self.next()
                while True:
                    t = self.next()
                    if t.k in ('EOF', 'NL'):
                        self.err(') expected')
                    if t.k == 'OP' and t.v == '(':
                        depth += 1
                    elif t.k == 'OP' and t.v == ')':
                        if depth == 0:
                            break
                        depth -= 1
            key, ty, asf = self.decl_type(n)
            if cls == 'common':
                cn = 'g_' + mangle(key) + ('_a' if isarr else '')
                self.commons[key] = Var(key, ty, isarr, 'common', cn, asf)
            else:
                cn = 'm%d_%s%s' % (self.mod.idx, mangle(key), '_a' if isarr else '')
                v = Var(key, ty, isarr, 'static', cn, asf)
                v.shared = True
                self.mod.statics[key] = v
            if not self.op(','):
                break
            self.next()

    # ---- variables in scope
    def visible_lookup(self, key):
        if self.inproc and key in self.locals:
            return self.locals[key]
        if key in self.consts_local:
            return self.consts_local[key]
        v = self.mod.statics.get(key)
        if v is not None and (not self.inproc or getattr(v, 'shared', False)):
            return v
        if key in self.mod.consts:
            return self.mod.consts[key]
        if key in self.commons:
            return self.commons[key]
        return None

    def find_var(self, n):
        if n[-1] not in SUFFIX:
            v = self.visible_lookup(n)
            if v is not None:
                return v
            return self.visible_lookup(n + TYPECHAR[self.nametype(n)])
        v = self.visible_lookup(n)
        if v is not None:
            return v
        v = self.visible_lookup(n[:-1])
        if v is not None and getattr(v, 'asflag', False) and v.ty == SUFFIX[n[-1]]:
            return v
        return None

    def new_var(self, key, ty, isarr, asf=False):
        if self.inproc:
            v = Var(key, ty, isarr, 'local', 'l_' + mangle(key) + ('_a' if isarr else ''), asf)
            self.locals[key] = v
            self.localdecls.append(v)
        else:
            v = Var(key, ty, isarr, 'static', 'm%d_%s%s' % (self.mod.idx, mangle(key), '_a' if isarr else ''), asf)
            v.shared = False
            self.mod.statics[key] = v
        return v

    def lookup_var(self, n, create=True):
        v = self.find_var(n)
        if v is None and create:
            if n[-1] in SUFFIX:
                v = self.new_var(n, SUFFIX[n[-1]], False)
            else:
                ty = self.nametype(n)
                v = self.new_var(n + TYPECHAR[ty], ty, False)
        return v

    def temp(self, ty):
        self.ntemp += 1
        name = '_t%d' % self.ntemp
        self.temps.append((name, ty))
        return name

    # ---- expressions: (code, type, impure)
    def expr(self):
        a = self.p_or()
        while self.kw('XOR'):
            self.next()
            b = self.p_or()
            a = self.logic('^', a, b)
        return a

    def p_or(self):
        a = self.p_and()
        while self.kw('OR') or self.at('ID', 'ORELSE'):
            o = self.next().v
            b = self.p_and()
            a = self.logic('|' if o == 'OR' else '||', a, b)
        return a

    def p_and(self):
        a = self.p_not()
        while self.kw('AND') or self.at('ID', 'ANDALSO'):
            o = self.next().v
            b = self.p_not()
            a = self.logic('&' if o == 'AND' else '&&', a, b)
        return a

    def p_not(self):
        if self.kw('NOT'):
            self.next()
            a = self.toint(self.p_not())
            return ('((bint)~%s)' % a[0], T_INT, a[2])
        return self.p_cmp()

    def p_cmp(self):
        a = self.p_concat()
        while self.t.k == 'OP' and self.t.v in ('=', '<>', '<', '>', '<=', '>='):
            o = self.next().v
            b = self.p_concat()
            a = self.compare(o, a, b)
        return a

    def p_concat(self):
        a = self.p_add()
        while self.op('&'):
            self.next()
            b = self.p_add()
            a = self.arith('+', a, b)
        return a

    def p_add(self):
        a = self.p_mod()
        while self.op('+') or self.op('-'):
            o = self.next().v
            b = self.p_mod()
            a = self.arith(o, a, b)
        return a

    def p_mod(self):
        a = self.p_idiv()
        while self.kw('MOD'):
            self.next()
            b = self.p_idiv()
            a = self.arith('MOD', a, b)
        return a

    def p_idiv(self):
        a = self.p_mul()
        while self.op('\\'):
            self.next()
            b = self.p_mul()
            a = self.arith('\\', a, b)
        return a

    def p_mul(self):
        a = self.p_neg()
        while self.op('*') or self.op('/'):
            o = self.next().v
            b = self.p_neg()
            a = self.arith(o, a, b)
        return a

    def p_neg(self):
        if self.op('-'):
            self.next()
            a = self.p_neg()
            if a[1] == T_STR:
                self.err('type mismatch')
            if a[1] == T_INT:
                return ('((bint)-%s)' % a[0], T_INT, a[2])
            return ('(-%s)' % a[0], a[1], a[2])
        if self.op('+'):
            self.next()
        return self.p_pow()

    def p_pow(self):
        a = self.primary()
        while self.op('^'):
            self.next()
            b = self.p_neg() if self.op('-') else self.primary()
            a = ('pow(%s, %s)' % (self.conv(a, T_DBL)[0], self.conv(b, T_DBL)[0]), T_DBL, a[2] or b[2])
        return a

    def seq2(self, a, b, ta, tb):
        """a and b as C operands evaluated left to right"""
        if (a[2] or b[2]) and not (self.isconst(a) or self.isconst(b)):
            x = self.temp(ta)
            y = self.temp(tb)
            return '(%s = %s, %s = %s, ' % (x, a[0], y, b[0]), x, y
        return '(', a[0], b[0]

    @staticmethod
    def isconst(e):
        return re.match(r'^\(\(bint\)-?\d+\)$', e[0]) is not None or e[0].startswith('BS(')

    def conv(self, e, ty):
        c, t, imp = e
        if ty == T_BYTE:
            ty = T_INT
        if t == T_BYTE:
            t = T_INT
        if t == ty:
            return (c, t, imp)
        if t == T_STR or ty == T_STR:
            self.err('type mismatch')
        if ty == T_INT:
            return ('b_cint(%s)' % c, T_INT, imp)
        return ('((%s)%s)' % (CTYPE[ty], c), ty, imp)

    def toint(self, e):
        return self.conv(e, T_INT)

    def maxtype(self, a, b):
        ta = T_INT if a[1] == T_BYTE else a[1]
        tb = T_INT if b[1] == T_BYTE else b[1]
        if ta == T_STR or tb == T_STR:
            if ta != tb:
                self.err('type mismatch')
            return T_STR
        order = [T_INT, T_SNG, T_DBL]
        return order[max(order.index(ta), order.index(tb))]

    def arith(self, o, a, b):
        t = self.maxtype(a, b)
        imp = a[2] or b[2]
        if t == T_STR:
            pre, x, y = self.seq2(a, b, T_STR, T_STR)
            return ('%sbs_cat(%s, %s))' % (pre, x, y), T_STR, imp)
        if o == '/' and t == T_INT:
            t = T_DBL
        if o in ('\\', 'MOD'):
            t = T_INT
        a = self.conv(a, t)
        b = self.conv(b, t)
        pre, x, y = self.seq2(a, b, t, t)
        if t == T_INT:
            if o == '\\':
                return ('%sb_idiv(%s, %s))' % (pre, x, y), T_INT, imp)
            if o == 'MOD':
                return ('%sb_imod(%s, %s))' % (pre, x, y), T_INT, imp)
            return ('%s(bint)(%s %s %s))' % (pre, x, o, y), T_INT, imp)
        return ('%s(%s %s %s))' % (pre, x, o, y), t, imp)

    def compare(self, o, a, b):
        t = self.maxtype(a, b)
        co = {'=': '==', '<>': '!='}.get(o, o)
        imp = a[2] or b[2]
        if t == T_STR:
            pre, x, y = self.seq2(a, b, T_STR, T_STR)
            return ('%s(bint)-(bs_cmp(%s, %s) %s 0))' % (pre, x, y, co), T_INT, imp)
        a = self.conv(a, t)
        b = self.conv(b, t)
        pre, x, y = self.seq2(a, b, t, t)
        return ('%s(bint)-(%s %s %s))' % (pre, x, co, y), T_INT, imp)

    def logic(self, o, a, b):
        a = self.toint(a)
        b = self.toint(b)
        imp = a[2] or b[2]
        if o in ('&&', '||'):
            return ('((bint)-((%s != 0) %s (%s != 0)))' % (a[0], o, b[0]), T_INT, imp)
        pre, x, y = self.seq2(a, b, T_INT, T_INT)
        return ('%s(bint)(%s %s %s))' % (pre, x, o, y), T_INT, imp)

    def cond(self, e):
        if e[1] == T_STR:
            self.err('a string as a condition')
        return '(%s != 0)' % e[0]

    def cstr(self, s):
        out = []
        for ch in s:
            o = ord(ch)
            if ch in '"\\':
                out.append('\\' + ch)
            elif 32 <= o < 127:
                out.append(ch)
            else:
                out.append('\\%03o' % o)
        return '"' + ''.join(out) + '"'

    def args(self):
        """( a, b, ... ) -> list of expressions"""
        r = []
        if not self.op('('):
            return r
        self.next()
        if self.op(')'):
            self.next()
            return r
        while True:
            r.append(self.expr())
            if not self.op(','):
                break
            self.next()
        self.expect_op(')')
        return r

    def callseq(self, fn, parts):
        """fn(parts...) with parts (code, ctype, impure) evaluated in order"""
        n_imp = sum(1 for p in parts if p[2])
        if len(parts) >= 2 and n_imp >= 1:
            pre = []
            names = []
            for c, ct, imp in parts:
                if imp or n_imp >= 1:
                    tn = self.temp(ct)
                    pre.append('%s = %s' % (tn, c))
                    names.append(tn)
                else:
                    names.append(c)
            return '(%s, %s(%s))' % (', '.join(pre), fn, ', '.join(names)), True
        return '%s(%s)' % (fn, ', '.join(p[0] for p in parts)), n_imp > 0

    BUILTIN = {
        'LEN': ('bs_len', [T_STR], T_INT), 'CHR$': ('bs_chr', [T_INT], T_STR),
        'LEFT$': ('bs_left', [T_STR, T_INT], T_STR), 'RIGHT$': ('bs_right', [T_STR, T_INT], T_STR),
        'UCASE$': ('bs_ucase', [T_STR], T_STR), 'LCASE$': ('bs_lcase', [T_STR], T_STR),
        'LTRIM$': ('bs_ltrim', [T_STR], T_STR), 'RTRIM$': ('bs_rtrim', [T_STR], T_STR),
        'TRIM$': ('bs_trim', [T_STR], T_STR), 'SPACE$': ('bs_space', [T_INT], T_STR),
        'HEX$': ('bs_hex', [T_INT], T_STR), 'VAL': ('bs_val', [T_STR], T_DBL),
        'MKD$': ('bs_mkd', [T_DBL], T_STR), 'CVD': ('bs_cvd', [T_STR], T_DBL),
        'MKI$': ('bs_mki', [T_INT], T_STR), 'CVI': ('bs_cvi', [T_STR], T_INT),
        'EOF': ('b_eof', [T_INT], T_INT),
    }

    def builtin(self, n):
        if n in self.BUILTIN:
            fn, ats, rt = self.BUILTIN[n]
            a = self.args()
            if len(a) != len(ats):
                self.err(n + ': arguments')
            parts = [self.conv(x, t)[:1] + (CTYPE[t], x[2]) for x, t in zip(a, ats)]
            c, imp = self.callseq(fn, parts)
            return (c, rt, imp or n == 'EOF')
        if n == 'ASC':
            a = self.args()
            if len(a) == 1:
                a.append(('((bint)1)', T_INT, False))
            parts = [self.conv(a[0], T_STR)[:1] + ('bstr', a[0][2]), self.toint(a[1])[:1] + ('bint', a[1][2])]
            c, imp = self.callseq('bs_asc', parts)
            return (c, T_INT, imp)
        if n == 'MID$':
            a = self.args()
            if len(a) == 2:
                a.append(('((bint)255)', T_INT, False))
            parts = [self.conv(a[0], T_STR)[:1] + ('bstr', a[0][2])] + [self.toint(x)[:1] + ('bint', x[2]) for x in a[1:]]
            c, imp = self.callseq('bs_mid', parts)
            return (c, T_STR, imp)
        if n == 'INSTR':
            a = self.args()
            if len(a) == 2:
                a.insert(0, ('((bint)1)', T_INT, False))
            parts = [self.toint(a[0])[:1] + ('bint', a[0][2]), self.conv(a[1], T_STR)[:1] + ('bstr', a[1][2]),
                     self.conv(a[2], T_STR)[:1] + ('bstr', a[2][2])]
            c, imp = self.callseq('bs_instr', parts)
            return (c, T_INT, imp)
        if n == 'STRING$':
            a = self.args()
            b = a[1]
            if b[1] == T_STR:
                b = ('bs_asc(%s, 1)' % b[0], T_INT, b[2])
            parts = [self.toint(a[0])[:1] + ('bint', a[0][2]), self.toint(b)[:1] + ('bint', b[2])]
            c, imp = self.callseq('bs_string', parts)
            return (c, T_STR, imp)
        if n == 'STR$':
            a = self.args()
            if a[0][1] in (T_INT, T_BYTE):
                return ('bs_stri(%s)' % a[0][0], T_STR, a[0][2])
            self.err('STR$ of a real')
        if n == 'CINT':
            a = self.args()
            return self.toint(a[0])
        if n == 'CDBL':
            a = self.args()
            return self.conv(a[0], T_DBL)
        if n == 'ABS':
            a = self.args()
            if a[0][1] == T_INT:
                return ('((bint)abs(%s))' % a[0][0], T_INT, a[0][2])
            return ('fabs(%s)' % a[0][0], a[0][1], a[0][2])
        if n == 'COMMAND$':
            return ('b_command()', T_STR, False)
        if n == 'ERR':
            return ('b_errno()', T_INT, True)
        if n == 'UBOUND':
            self.expect_op('(')
            v = self.find_var(self.next().v)
            if self.op('('):
                self.next()
                self.expect_op(')')
            k = '1'
            if self.op(','):
                self.next()
                k = self.toint(self.expr())[0]
            self.expect_op(')')
            return ('ar_ub(%s, %s)' % (self.arrptr(v), k), T_INT, False)
        if n == 'LBOUND':
            self.args()
            return ('((bint)0)', T_INT, False)
        return None

    def arrptr(self, v):
        if v.cls == 'ref':
            return v.cname
        return '&' + v.cname

    def elem(self, v, idx):
        parts = [self.toint(x)[:1] + ('bint', x[2]) for x in idx]
        c, imp = self.callseq('ax', [(self.arrptr(v), 'barr*', False), (str(len(idx)), 'int', False)] + parts)
        return ('(*(%s*)%s)' % (ELEMC[v.ty], c), v.ty, imp)

    def varref(self, v):
        if v.cls == 'ref':
            return '(*%s)' % v.cname
        return v.cname

    def call(self, pr, args_toks_paren=True):
        """the call of procedure pr: its arguments are next"""
        parts = []
        stmtcall = self.stmtcall
        self.stmtcall = False
        k = 0
        paren = False
        if args_toks_paren and self.op('('):
            # name (a, b) -- or name (a) * 2, b: the ( starts an argument
            d, q = 0, self.p
            while True:
                tk = self.toks[q]
                if tk.k == 'OP' and tk.v == '(':
                    d += 1
                elif tk.k == 'OP' and tk.v == ')':
                    d -= 1
                    if d == 0:
                        break
                elif tk.k in ('NL', 'EOF'):
                    break
                q += 1
            nt = self.toks[q + 1] if q + 1 < len(self.toks) else Tok('EOF', None, 0, '')
            if nt.k in ('NL', 'EOF') or (nt.k == 'OP' and nt.v == ':') or (nt.k == 'KW' and nt.v == 'ELSE') \
                    or not stmtcall:
                self.next()
                paren = True
        if (paren and self.op(')')) or (not paren and (self.at_end() or not args_toks_paren)):
            pass
        else:
            while True:
                if k >= len(pr.params):
                    self.err('too many arguments to ' + pr.name)
                pn, pt, byref, isarr, asf = pr.params[k]
                k += 1
                if isarr:
                    v = self.find_var(self.next().v)
                    if v is None or not v.isarr:
                        self.err('an array argument expected')
                    if self.op('('):
                        self.next()
                        self.expect_op(')')
                    parts.append((self.arrptr(v), 'barr*', False))
                elif byref:
                    save = self.p
                    lv = self.lvalue_try()
                    if lv is not None and lv[1] == pt and (self.at_end() or self.op(',') or self.op(')')):
                        parts.append(('&' + lv[0], CTYPE[pt] + '*', lv[2]))
                    else:
                        self.p = save
                        e = self.conv(self.expr(), pt)
                        parts.append(('&(%s){%s}' % (CTYPE[pt], e[0]), CTYPE[pt] + '*', e[2]))
                else:
                    e = self.conv(self.expr(), pt)
                    parts.append((e[0], CTYPE[pt], e[2]))
                if not self.op(','):
                    break
                self.next()
        if paren:
            self.expect_op(')')
        if k != len(pr.params):
            self.err('%s: %d arguments expected' % (pr.name, len(pr.params)))
        c, imp = self.callseq(pr.cname(), parts)
        return (c, pr.ret, True)

    def primary(self):
        t = self.t
        if t.k == 'INT':
            self.next()
            return ('((bint)%d)' % t.v, T_INT, False)
        if t.k == 'REAL':
            self.next()
            txt, ty = t.v
            return ('(%s)' % (txt if ('.' in txt or 'E' in txt) else txt + '.0'), T_DBL, False)
        if t.k == 'STR':
            self.next()
            return ('BS(%s)' % self.cstr(t.v), T_STR, False)
        if self.op('('):
            self.next()
            e = self.expr()
            self.expect_op(')')
            return ('(%s)' % e[0], e[1], e[2])
        if t.k == 'ID':
            n = t.v
            self.next()
            v = self.find_var(n)
            if v is not None:
                if isinstance(v, tuple):
                    return v
                if v.isarr:
                    return self.elem(v, self.args())
                return (self.varref(v), v.ty, False)
            pr = self.find_proc(n)
            if pr is not None:
                return self.call(pr, False) if not self.op('(') else self.call(pr)
            b = self.builtin(n)
            if b is not None:
                return b
            v = self.lookup_var(n)
            return (self.varref(v), v.ty, False)
        self.err('an expression expected')

    def lvalue_try(self):
        """a variable or element: (ccode, type, impure) or None (tokens consumed)"""
        if self.t.k != 'ID':
            return None
        n = self.next().v
        v = self.find_var(n)
        if v is not None and isinstance(v, tuple):
            return None
        if v is not None and v.isarr:
            if not self.op('('):
                return None
            return self.elem(v, self.args())
        if v is None:
            if self.find_proc(n) or self.op('('):
                return None
            v = self.lookup_var(n)
        return (self.varref(v), v.ty, False)

    def lvalue(self):
        lv = self.lvalue_try()
        if lv is None:
            self.err('a variable expected')
        return lv

    def assign_code(self, lv, e):
        if lv[1] == T_BYTE and not lv[0].startswith('(*(uint8_t'):
            e = self.toint(e)
            return '%s = (bint)(%s & 255);' % (lv[0], e[0])
        e = self.conv(e, lv[1])
        if lv[2] and e[2]:
            # the element's address first (BASIC: target, then value)
            t = self.temp(ELEMC[lv[1]] + '*')
            return '%s = &%s; *%s = %s;' % (t, lv[0], t, e[0])
        return '%s = %s;' % (lv[0], e[0])

    # ---- statements
    def emit(self, s):
        self.body.append('    ' * self.indent + s)

    def newlab(self):
        self.nlab += 1
        return self.nlab

    def block(self):
        """statements to a terminator: returns it ('ELSE', 'END IF', ...)"""
        while True:
            t = self.t
            if t.k == 'EOF':
                return 'EOF'
            if t.k == 'NL' or self.op(':'):
                self.next()
                continue
            if t.k == 'LABEL':
                self.next()
                self.emit('L_%s: ;' % mangle(t.v))
                continue
            if t.k == 'KW' and t.v in ('ELSE', 'ELSEIF', 'NEXT', 'LOOP', 'WEND', 'CASE'):
                self.next()
                return t.v
            if self.kw('END'):
                self.next()
                if self.t.k == 'KW' and self.t.v in ('IF', 'SUB', 'FUNCTION', 'SELECT'):
                    return 'END ' + self.next().v
                self.emit('b_halt(0);')
                continue
            if t.k == 'KW' and t.v in ('SUB', 'FUNCTION', 'PRIVATE') and not self.inproc:
                self.skip_body()
                continue
            self.stmt()
            if not self.at_end():
                self.err('end of statement expected')
            if self.pendnext:
                return 'NEXT'

    def line_stmts(self):
        while True:
            if self.t.k in ('NL', 'EOF') or self.kw('ELSE'):
                return
            if self.op(':'):
                self.next()
                continue
            self.stmt()
            if not self.op(':'):
                return

    def stmt(self):
        t = self.t
        if t.k == 'ID':
            return self.ident_stmt()
        if t.k != 'KW':
            self.err('a statement expected')
        k = t.v
        f = getattr(self, 's_' + k, None)
        if f is None:
            self.err('statement %s not handled by bas2c' % k)
        f()

    def s_LET(self):
        self.next()
        self.ident_stmt()

    def ident_stmt(self):
        n = self.t.v
        if n == 'MID$':
            self.next()
            self.expect_op('(')
            lv = self.lvalue()
            self.expect_op(',')
            st = self.toint(self.expr())[0]
            ln = '255'
            if self.op(','):
                self.next()
                ln = self.toint(self.expr())[0]
            self.expect_op(')')
            self.expect_op('=')
            v = self.conv(self.expr(), T_STR)[0]
            self.emit('bs_midset(&%s, %s, %s, %s);' % (lv[0], st, ln, v))
            return
        if self.inproc and self.curproc.kind == 'FUNCTION' and self.find_proc(n) is self.curproc \
                and self.toks[self.p + 1].k == 'OP' and self.toks[self.p + 1].v == '=':
            self.next()
            self.next()
            e = self.conv(self.expr(), self.curproc.ret)
            self.emit('_r = %s;' % e[0])
            return
        v = self.find_var(n)
        if v is None:
            pr = self.find_proc(n)
            if pr is not None:
                self.next()
                self.stmtcall = True
                c = self.call(pr)
                self.stmtcall = False
                self.emit('%s;' % c[0])
                return
        lv = self.lvalue()
        self.expect_op('=')
        e = self.expr()
        self.emit(self.assign_code(lv, e))

    def s_CALL(self):
        self.next()
        pr = self.find_proc(self.next().v)
        c = self.call(pr)
        self.emit('%s;' % c[0])

    def s_IF(self):
        self.next()
        c = self.cond(self.expr())
        self.expect_kw('THEN')
        if self.t.k in ('NL', 'EOF'):
            self.emit('if %s {' % c)
            self.indent += 1
            r = self.block()
            while True:
                if r == 'ELSEIF':
                    c = self.cond(self.expr())
                    self.expect_kw('THEN')
                    self.indent -= 1
                    self.emit('} else if %s {' % c)
                    self.indent += 1
                    r = self.block()
                elif r == 'ELSE':
                    self.indent -= 1
                    self.emit('} else {')
                    self.indent += 1
                    r = self.block()
                else:
                    break
            if r != 'END IF':
                self.err('END IF expected')
            self.indent -= 1
            self.emit('}')
            return
        self.emit('if %s {' % c)
        self.indent += 1
        if self.t.k == 'INT':
            self.emit('goto L_%d;' % self.next().v)
        else:
            self.line_stmts()
        self.indent -= 1
        if self.kw('ELSE'):
            self.next()
            self.emit('} else {')
            self.indent += 1
            if self.t.k == 'INT':
                self.emit('goto L_%d;' % self.next().v)
            else:
                self.line_stmts()
            self.indent -= 1
        self.emit('}')

    def s_FOR(self):
        self.next()
        n = self.next().v
        v = self.lookup_var(n)
        vr = self.varref(v)
        ty = T_INT if v.ty == T_BYTE else v.ty
        self.expect_op('=')
        e1 = self.conv(self.expr(), ty)
        self.expect_kw('TO')
        e2 = self.conv(self.expr(), ty)
        step = ('((bint)1)', T_INT, False)
        if self.kw('STEP'):
            self.next()
            step = self.expr()
        step = self.conv(step, ty)
        lab = self.newlab()
        lim = self.temp(ty)
        self.emit('%s = %s;' % (vr, e1[0]))
        self.emit('%s = %s;' % (lim, e2[0]))
        m = re.match(r'^\(\(bint\)(-?)\d+\)$', step[0]) or re.match(r'^\((-?)[\d.]+\)$', step[0])
        if m:
            sv = step[0]
            test = ('%s > %s' if m.group(1) == '' else '%s < %s') % (vr, lim)
        else:
            sv = self.temp(ty)
            self.emit('%s = %s;' % (sv, step[0]))
            test = '(%s >= 0 ? %s > %s : %s < %s)' % (sv, vr, lim, vr, lim)
        self.emit('for (;;) {')
        self.indent += 1
        self.emit('if (%s) break;' % test)
        self.loops.append(('FOR', lab))
        r = self.block()
        if r != 'NEXT':
            self.err('NEXT expected')
        self.pendnext = False
        if self.t.k == 'ID':
            self.next()
            if self.op(','):
                self.next()
                self.pendnext = True
        self.loops.pop()
        self.emit('_c%d: ;' % lab)
        if ty == T_INT:
            self.emit('%s = (bint)(%s + %s);' % (vr, vr, sv))
        else:
            self.emit('%s = %s + %s;' % (vr, vr, sv))
        self.indent -= 1
        self.emit('}')
        self.emit('_x%d: ;' % lab)

    def s_DO(self):
        self.next()
        lab = self.newlab()
        self.emit('for (;;) {')
        self.indent += 1
        if self.kw('WHILE') or self.kw('UNTIL'):
            k = self.next().v
            c = self.cond(self.expr())
            self.emit(('if (!%s) break;' if k == 'WHILE' else 'if (%s) break;') % c)
        self.loops.append(('DO', lab))
        r = self.block()
        if r != 'LOOP':
            self.err('LOOP expected')
        self.loops.pop()
        self.emit('_c%d: ;' % lab)
        if self.kw('WHILE') or self.kw('UNTIL'):
            k = self.next().v
            c = self.cond(self.expr())
            self.emit(('if (!%s) break;' if k == 'WHILE' else 'if (%s) break;') % c)
        self.indent -= 1
        self.emit('}')
        self.emit('_x%d: ;' % lab)

    def s_WHILE(self):
        self.next()
        lab = self.newlab()
        c = self.cond(self.expr())
        self.emit('for (;;) {')
        self.indent += 1
        self.emit('if (!%s) break;' % c)
        self.loops.append(('WHILE', lab))
        r = self.block()
        if r != 'WEND':
            self.err('WEND expected')
        self.loops.pop()
        self.emit('_c%d: ;' % lab)
        self.indent -= 1
        self.emit('}')
        self.emit('_x%d: ;' % lab)

    def s_SELECT(self):
        self.next()
        self.expect_kw('CASE')
        e = self.expr()
        ty = T_INT if e[1] == T_BYTE else e[1]
        sel = self.temp(ty)
        self.emit('%s = %s;' % (sel, e[0]))
        lab = self.newlab()
        self.loops.append(('SELECT', lab))
        r = self.block()
        first = True
        selv = (sel, ty, False)
        while r == 'CASE':
            if self.kw('ELSE'):
                self.next()
                self.emit('else {' if not first else '{')
            else:
                conds = []
                while True:
                    if self.kw('IS'):
                        self.next()
                        o = self.next().v
                        conds.append(self.compare(o, selv, self.expr())[0])
                    else:
                        v1 = self.expr()
                        if self.kw('TO'):
                            self.next()
                            v2 = self.expr()
                            conds.append('(%s && %s)' % (self.compare('>=', selv, v1)[0], self.compare('<=', selv, v2)[0]))
                        else:
                            conds.append(self.compare('=', selv, v1)[0])
                    if not self.op(','):
                        break
                    self.next()
                c = ' || '.join('(%s != 0)' % x for x in conds)
                self.emit(('if (%s) {' if first else 'else if (%s) {') % c)
            first = False
            self.indent += 1
            r = self.block()
            self.indent -= 1
            self.emit('}')
        if r != 'END SELECT':
            self.err('END SELECT expected')
        self.loops.pop()
        self.emit('_x%d: ;' % lab)

    def s_EXIT(self):
        self.next()
        k = self.next().v
        if k in ('SUB', 'FUNCTION'):
            self.emit('goto _exit;')
            return
        for kind, lab in reversed(self.loops):
            if kind == k:
                self.emit('goto _x%d;' % lab)
                return
        self.err('EXIT ' + k + ' outside')

    def s_CONTINUE(self):
        self.next()
        k = self.next().v
        for kind, lab in reversed(self.loops):
            if kind == k:
                self.emit('goto _c%d;' % lab)
                return
        self.err('CONTINUE ' + k + ' outside')

    def s_GOTO(self):
        self.next()
        t = self.next()
        self.emit('goto L_%s;' % mangle(str(t.v)))

    def s_RETURN(self):
        self.next()
        if self.at_end():
            self.emit('goto _exit;')
            return
        e = self.conv(self.expr(), self.curproc.ret)
        self.emit('_r = %s; goto _exit;' % e[0])

    def s_ON(self):
        self.next()
        self.expect_kw('ERROR')
        if self.kw('RESUME'):
            self.next()
            self.expect_kw('NEXT')
            self.emit('b_onerr(1);')
        else:
            self.expect_kw('GOTO')
            self.next()
            self.emit('b_onerr(0);')

    def chan(self):
        if self.op('#'):
            self.next()
        return self.toint(self.expr())[0]

    def s_PRINT(self):
        self.next()
        ch = '0'
        if self.op('#'):
            self.next()
            ch = self.toint(self.expr())[0]
            self.next()
        nl = True
        while not self.at_end():
            if self.op(';'):
                self.next()
                nl = False
            elif self.op(','):
                self.next()
                self.emit('p_comma(%s);' % ch)
                nl = False
            else:
                e = self.expr()
                if e[1] == T_STR:
                    self.emit('p_str(%s, %s);' % (ch, e[0]))
                elif e[1] in (T_INT, T_BYTE):
                    self.emit('p_int(%s, %s);' % (ch, e[0]))
                else:
                    self.emit('p_dbl(%s, %s);' % (ch, e[0]))
                nl = True
        if nl:
            self.emit('p_nl(%s);' % ch)

    def s_LINE(self):
        self.next()
        self.expect_kw('INPUT')
        ch = '0'
        prompt = '0'
        if self.op('#'):
            self.next()
            ch = self.toint(self.expr())[0]
            self.expect_op(',')
        elif self.t.k == 'STR':
            prompt = '&(bstr){BS(%s)}' % self.cstr(self.next().v)
            self.next()
        lv = self.lvalue()
        self.emit('%s = b_linput(%s, %s);' % (lv[0], ch, prompt))

    def s_OPEN(self):
        self.next()
        f = self.conv(self.expr(), T_STR)[0]
        self.expect_kw('FOR')
        mode = {'INPUT': 1, 'OUTPUT': 2, 'APPEND': 3, 'BINARY': 4, 'RANDOM': 5}[self.next().v]
        self.expect_kw('AS')
        ch = self.chan()
        self.emit('b_open(%s, %d, %s, 0);' % (f, mode, ch))

    def s_CLOSE(self):
        self.next()
        if self.at_end():
            self.emit('b_close(0);')
            return
        while True:
            self.emit('b_close(%s);' % self.chan())
            if not self.op(','):
                break
            self.next()

    def s_KILL(self):
        self.next()
        self.emit('b_kill(%s);' % self.conv(self.expr(), T_STR)[0])

    def getput(self, isput):
        self.next()
        ch = self.chan()
        self.expect_op(',')
        if not self.op(','):
            self.err('GET/PUT with a position: not handled by bas2c')
        self.next()
        if isput:
            save = self.p
            lv = self.lvalue_try() if self.t.k == 'ID' else None
            if lv is not None and self.at_end():
                e = lv
            else:
                self.p = save
                e = self.expr()
            if e[1] == T_STR:
                self.emit('b_puts(%s, %s);' % (ch, e[0]))
            elif e[1] == T_BYTE:
                self.emit('{ uint8_t _b = (uint8_t)%s; b_putr(&_b, %s, 1); }' % (e[0], ch))
            else:
                ct = CTYPE[e[1]]
                self.emit('{ %s _v = %s; b_putr(&_v, %s, %d); }' % (ct, e[0], ch, {T_INT: 2, T_SNG: 4, T_DBL: 8}[e[1]]))
            return
        lv = self.lvalue()
        if lv[1] == T_STR:
            self.emit('%s = b_gets(%s, %s.len);' % (lv[0], ch, lv[0]))
        elif lv[1] == T_BYTE:
            self.emit('{ uint8_t _b; b_getr(&_b, %s, 1); %s = _b; }' % (ch, lv[0]))
        else:
            self.emit('b_getr(&%s, %s, %d);' % (lv[0], ch, {T_INT: 2, T_SNG: 4, T_DBL: 8}[lv[1]]))

    def s_GET(self):
        self.getput(False)

    def s_PUT(self):
        self.getput(True)

    def s_SYSTEM(self):
        self.next()
        c = '0' if self.at_end() else self.toint(self.expr())[0]
        self.emit('b_halt(%s);' % c)

    s_STOP = s_SYSTEM

    def s_DIM(self, redim=False):
        self.next()
        shared = False
        if self.kw('SHARED'):
            self.next()
            shared = True
        while True:
            n = self.next().v
            bounds = None
            if self.op('('):
                bounds = self.args()
            key, ty, asf = self.decl_type(n)
            if shared:
                v = self.mod.statics[key]
            elif redim:
                v = self.find_var(n)
                if v is None:
                    v = self.new_var(key, ty, True, asf)
            elif not self.inproc and key in self.mod.statics:
                v = self.mod.statics[key]
            elif not self.inproc and key in self.commons and self.commons[key].isarr:
                v = self.commons[key]
            else:
                if self.inproc and key in self.locals:
                    self.err(n + ' declared twice')
                v = self.new_var(key, ty, bounds is not None, asf)
            if bounds:
                es = 'sizeof(%s)' % ELEMC[v.ty]
                bs = ', '.join(self.toint(b)[0] for b in bounds)
                self.emit('ar_dim(%s, %s, %d, %d, %s);' % (self.arrptr(v), es, v.ty == T_STR, len(bounds), bs))
            if not self.op(','):
                break
            self.next()

    def s_REDIM(self):
        self.s_DIM(True)

    def s_ERASE(self):
        self.next()
        while True:
            v = self.find_var(self.next().v)
            self.emit('ar_free(%s);' % self.arrptr(v))
            if not self.op(','):
                break
            self.next()

    def s_CONST(self):
        self.next()
        while True:
            n = self.next().v
            self.expect_op('=')
            e = self.expr()
            ty = e[1]
            if n[-1] in SUFFIX:
                e = self.conv(e, SUFFIX[n[-1]])
                ty = SUFFIX[n[-1]]
            entry = ('(%s)' % e[0], ty, False)
            if self.inproc:
                self.consts_local[n] = entry
            else:
                self.mod.consts[n] = entry
            if not self.op(','):
                break
            self.next()

    def s_SWAP(self):
        self.next()
        a = self.lvalue()
        self.expect_op(',')
        b = self.lvalue()
        t = self.temp(a[1])
        self.emit('%s = %s; %s = %s; %s = %s;' % (t, a[0], a[0], b[0], b[0], t))

    def skip(self):
        self.skip_stmt()

    s_DECLARE = s_COMMON = s_OPTION = s_SEGMENT = lambda self: self.skip_stmt()

    def s_DEFINT(self):
        k = self.next().v
        self.def_letters(self.DEFKW[k])

    s_DEFSNG = s_DEFDBL = s_DEFSTR = s_DEFINT

    # ---- procedures
    def start_func(self):
        self.body = []
        self.indent = 1
        self.locals = {}
        self.localdecls = []
        self.consts_local = {}
        self.temps = []
        self.ntemp = 0
        self.nlab = 0
        self.loops = []
        self.pendnext = False

    def finish_func(self, header, rettype):
        o = self.out
        o.append(header + ' {')
        if rettype:
            o.append('    %s _r = %s;' % (CTYPE[rettype], ZERO[rettype]))
        for v in self.localdecls:
            if v.cls == 'local':
                if v.isarr:
                    o.append('    barr %s = {0};' % v.cname)
                else:
                    o.append('    %s %s = %s;' % (CTYPE[v.ty], v.cname, ZERO[v.ty]))
        for name, ty in self.temps:
            if ty in CTYPE:
                o.append('    %s %s;' % (CTYPE[ty], name))
            else:
                o.append('    %s %s;' % (ty, name))
        o.extend(self.body)
        o.append('_exit: ;')
        for v in self.localdecls:
            if v.cls == 'local' and v.isarr:
                o.append('    ar_free(&%s);' % v.cname)
        o.append('    return%s;' % (' _r' if rettype else ''))
        o.append('}')
        o.append('')

    def proc_sig(self, pr):
        ps = []
        for pn, pt, byref, isarr, asf in pr.params:
            pc = 'l_' + mangle(pn) + ('_a' if isarr else '')
            if isarr:
                ps.append('barr *' + pc)
            elif byref:
                ps.append('%s *%s' % (CTYPE[pt], pc))
            else:
                ps.append('%s %s' % (CTYPE[pt], pc))
        ret = CTYPE[pr.ret] if pr.ret else 'void'
        return 'static %s %s(%s)' % (ret, pr.cname(), ', '.join(ps) or 'void')

    def gen_proc(self, pr):
        self.start_func()
        self.inproc = True
        self.curproc = pr
        for pn, pt, byref, isarr, asf in pr.params:
            pc = 'l_' + mangle(pn) + ('_a' if isarr else '')
            v = Var(pn, pt, isarr, 'ref' if (byref or isarr) else 'param', pc, asf)
            self.locals[pn] = v
        r = self.block()
        if r not in ('END SUB', 'END FUNCTION'):
            self.err('END SUB / END FUNCTION expected')
        self.finish_func(self.proc_sig(pr), pr.ret)

    def translate(self):
        o = self.out
        o.append('#include "hostrt.h"')
        o.append('')
        # pass A over every module
        for m in self.mods:
            self.pass_a(m)
        for key, v in self.commons.items():
            if v.isarr:
                o.append('static barr %s;' % v.cname)
            else:
                o.append('static %s %s;' % (CTYPE[v.ty], v.cname))
        for m in self.mods:
            for key, v in m.statics.items():
                o.append('static barr %s;' % v.cname if v.isarr else 'static %s %s;' % (CTYPE[v.ty], v.cname))
        seen = set()
        for pr in self.procs.values():
            if pr.cname() not in seen:
                seen.add(pr.cname())
                o.append(self.proc_sig(pr) + ';')
        o.append('')
        # the bodies first (module-level statics and constants come from them)
        bodyouts = []
        for m in self.mods:
            self.setup(m)
            m.deftype = [T_SNG] * 26
            self.inproc = False
            self.curproc = None
            self.start_func()
            r = self.block()
            if r != 'EOF':
                self.err(r + ' without its block')
            self.finish_func('static void body%d(void)' % m.idx, None)
        # the module statics found in the bodies
        decl = []
        for m in self.mods:
            for key, v in m.statics.items():
                d = 'static barr %s;' % v.cname if v.isarr else 'static %s %s;' % (CTYPE[v.ty], v.cname)
                if d not in o:
                    decl.append(d)
        idx = o.index('')
        o[idx:idx] = decl
        # then the procedures
        for m in self.mods:
            self.setup(m)
            m.deftype = [T_SNG] * 26
            while self.t.k != 'EOF':
                t = self.t
                if t.k == 'KW' and t.v in self.DEFKW:
                    self.next()
                    self.def_letters(self.DEFKW[t.v])
                    continue
                if self.kw('DECLARE'):
                    self.skip_stmt()
                    continue
                if self.kw('PRIVATE'):
                    self.next()
                if self.kw('SUB') or self.kw('FUNCTION'):
                    hdr = self.proc_header(False)
                    pr = self.find_proc(hdr.name)
                    self.gen_proc(pr)
                    continue
                self.next()
        o.append('int main(int argc, char **argv)')
        o.append('{')
        o.append('    brt_init(argc, argv);')
        for m in self.mods[1:]:
            o.append('    body%d();' % m.idx)
        o.append('    body%d();' % self.mods[0].idx)
        o.append('    b_halt(0);')
        o.append('    return 0;')
        o.append('}')
        return '\n'.join(o) + '\n'


def main(argv):
    out = None
    files = []
    i = 0
    while i < len(argv):
        if argv[i] == '-o':
            out = argv[i + 1]
            i += 2
        else:
            files.append(argv[i])
            i += 1
    try:
        mods = [Module(k + 1, f) for k, f in enumerate(files)]
        c = Trans(mods).translate()
    except Err as e:
        import traceback; traceback.print_exc()
        return 1
    open(out, 'w').write(c)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
