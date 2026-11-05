#!/usr/bin/env python3
"""b2dump.py -- an intermediate file of B2 (the token file, NAME.W2 ... NAME.W7, -K keeps them) as
text: each BASIC line as a comment, then what it has become in that pass.

  b2dump.py FILE [--raw]

The record kinds are read from b2/b2com.bas, b2rec.bas and b2ops.bas (docs/B2DESIGN.md section 3).
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))


def consts():
    c = {}
    for l in (x for f in ('b2com', 'b2rec', 'b2ops') for x in open(os.path.join(HERE, '..', 'b2', f + '.bas'), encoding='latin1')):
        l = l.split("'")[0]
        if l.strip().upper().startswith('CONST'):
            for m in re.finditer(r'([A-Z0-9_]+)\s*=\s*(&H[0-9A-F]+|-?\d+)', l[5:]):
                v = m.group(2)
                c[m.group(1)] = int(v[2:], 16) if v.startswith('&H') else int(v)
    return c


C = consts()
KW = {v: k[1:] for k, v in C.items() if k.startswith('K') and 1 <= v < 100 and k != 'KWHERE'}
OPS = {'TEQ': '=', 'TNE': '<>', 'TLT': '<', 'TGT': '>', 'TLE': '<=', 'TGE': '>=', 'TPLUS': '+',
       'TMINUS': '-', 'TMUL': '*', 'TDIV': '/', 'TIDIV': '\\', 'TPOW': '^', 'TLPAR': '(',
       'TRPAR': ')', 'TCOMMA': ',', 'TSEMI': ';', 'THASH': '#', 'TAMP': '&', 'TCOLON': ':',
       'TBAR': '|', 'TANDALSO': 'ANDALSO', 'TORELSE': 'ORELSE'}
OPN = {C[k]: v for k, v in OPS.items()}
SK = {v: k[1:] for k, v in C.items() if k.startswith('S') and 100 <= v < 120 and k not in ('SFRUNTIME', 'SFGOSUB')}
TY = {0: 'void', 1: 'INT', 2: 'SNG', 3: 'DBL', 4: 'STR', 5: 'BYTE'}
XM = {0: 'any', 1: 'INT', 2: 'SNG', 3: 'DBL', 4: 'STR', 5: 'BYTE', 10: 'cond', 11: 'notcond',
      12: 'as-target', 13: 'call', 14: 'select', 15: 'channel', 16: 'put', 17: 'raw'}
LVM = {1: 'assign', 2: 'pre/store', 3: 'get', 4: 'address'}
CLS = {1: 'local', 2: 'static', 3: 'common', 4: 'param', 5: 'byref'}
OPC = {v: k[1:] for k, v in C.items() if k.startswith('O') and 0x80 <= v <= 0xFF and not k.startswith('OPT')}


class R:
    def __init__(self, b):
        self.b, self.p = b, 0

    def B(self):
        v = self.b[self.p]
        self.p += 1
        return v

    def W(self):
        v = struct.unpack_from('<h', self.b, self.p)[0]
        self.p += 2
        return v

    def S(self):
        n = self.B()
        s = self.b[self.p:self.p + n].decode('latin1')
        self.p += n
        return s


def dump(path, raw=False):
    b = open(path, 'rb').read()
    r = R(b)
    head = [r.W() for _ in range(16)]
    out = ['; %s  (pass %d)  header %s' % (os.path.basename(path), head[15], head)]
    line = []
    ind = 0

    def flush():
        if line:
            out.append('    ' * ind + ' '.join(line))
            line.clear()

    while r.p < len(b):
        k = r.B()
        if k == 0 or k == C['TEOF']:
            flush()
            out.append('; end')
            break
        if k < 100:
            line.append(KW.get(k, 'K%d' % k))
        elif k < 128:
            line.append(OPN.get(k, 'op%d' % k))
        elif k == C['TIDENT']:
            line.append(r.S())
        elif k == C['TINT']:
            line.append(str(r.W()))
        elif k in (C['TSNG'], C['TDBL']):
            line.append(r.S() + ('#' if k == C['TSNG'] else '!'))
        elif k == C['TSTR']:
            line.append('"%s"' % r.S())
        elif k == C['TLINE']:
            flush()
            n = r.W()
            out.append("'%5d  %s" % (n, r.S()))
        elif k == C['TLABEL']:
            line.append('label:' + r.S())
        elif k == C['RLREF']:
            line.append('to:' + r.S())
        elif k == C['TFILE']:
            flush()
            out.append('; file ' + r.S())
        elif k == C['TSKIP']:
            line.append('(skipped)')
        elif k == C['RSTMT']:
            flush()
            s = r.B()
            line.append('[%s]' % (KW.get(s) if s < 100 else SK.get(s, 'S%d' % s)))
        elif k == C['RX']:
            line.append('{%s:' % XM.get(r.B(), '?'))
        elif k == C['RXE']:
            line.append('}')
        elif k == C['RLV']:
            line.append('<%s:' % LVM.get(r.B(), '?'))
        elif k == C['RLVE']:
            line.append('>')
        elif k == C['RMARK']:
            line.append({1: 'TAB', 2: 'SPC', 3: '#', 4: '(last)', 5: '(more)'}.get(r.B(), '?'))
        elif k == C['RSEL']:
            line.append('SEL')
        elif k == C['RVAR']:
            kind, ty, cl, off, nd, nm, ln = r.B(), r.B(), r.B(), r.W(), r.B(), r.S(), r.W()
            line.append('%s%s[%s %s %d%s%s]' % (nm, '()' if kind == 2 else '', TY.get(ty), CLS.get(cl, cl), off,
                                               ' %dD' % nd if kind == 2 else '', ' LENGTH %d' % ln if ln else ''))
        elif k == C['RPROC']:
            ty, kind, nm, np = r.B(), r.B(), r.S(), r.B()
            ps = [(r.B(), r.B(), r.W()) for _ in range(np)]
            txt = r.S()
            line.append('%s=call %s(%s)%s' % (txt, nm, ','.join(TY[t] + ('&' if f & 1 else '') + ('()' if f & 2 else '') + ('*%d' % l if l else '')
                                                                for t, f, l in ps), ':' + TY[ty] if kind == 5 else ''))
        elif k == C['RBUILT']:
            i = r.B()
            line.append('%s=built%d' % (r.S(), i))
        elif k == C['RLAB']:
            line.append('L%d' % r.W())
        elif k == C['RXC']:
            ty, fl, v = r.B(), r.B(), r.W()
            line.append('{code %s%s%s%s:' % (TY.get(ty), ' =%d' % v if fl & 2 else '', ' real' if fl & 4 else '',
                                              ' neg' if fl & 8 else '') + (' address' if fl & 16 else ''))
        elif k == C['RXCE']:
            line.append('}' + (' (temps)' if r.B() & 1 else ''))
        elif k == C['RLVC']:
            ty, fl, kd = r.B(), r.B(), r.W()
            line.append('<target %s%s:' % (TY.get(ty), ' kind %d' % kd if kd else ''))
        elif k == C['RLVL']:
            line.append('| load:')
        elif k == C['RLVS']:
            line.append('| store:')
        elif k == C['RLVCE']:
            line.append('>' + (' (temps)' if r.B() & 1 else ''))
        elif k == C['CBYTES']:
            n = r.B()
            bs = r.b[r.p:r.p + n]
            r.p += n
            line.append(disasm(bs) if raw else ' '.join('%02X' % x for x in bs))
        elif k == C['CJUMP']:
            op, l = r.B(), r.W()
            line.append('%s L%s' % (OPC.get(op, '%02X' % op), 'false' if l == -1 else l))
        elif k == C['CCASE']:
            line.append('case L%d' % r.W())
        elif k == C['CLABEL']:
            flush()
            out.append('    ' * ind + 'L%d:' % r.W())
        elif k == C['CALIAS']:
            a, m = r.W(), r.W()
            line.append('L%d=L%d' % (a, m))
        elif k == C['CREL']:
            t, nm = r.B(), r.S()
            line.append('(%s %s)' % ({1: 'call', 3: 'static', 4: 'common'}.get(t, t), nm))
        elif k == C['CALIGN']:
            line.append('align')
        elif k == C['CTEMP']:
            line.append('(temporaries back)')
        elif k == C['CGOSUB']:
            line.append('(gosub return L%d)' % r.W())
        elif k == C['CFREE']:
            t, o = r.B(), r.W()
            line.append('(free %s %d)' % ('string' if t == 1 else 'array', o))
        elif k == C['CBEGIN']:
            flush()
            f = [r.W() for _ in range(10)]
            nm, sg = r.S(), r.S()
            out.append('PROC %s%s  params %d words, result %d (at %d, %s), mark %d, frame %d, labels %d%s'
                       % (nm, ' (segment %s)' % sg if sg else '', f[1], f[2], f[3], TY.get(f[4]), f[5], f[6], f[7],
                          ', zeroed' if f[8] else ''))
            ind = 1
        elif k == C['CEND']:
            flush()
            r.W(); r.S(); r.S()
            out.append('END PROC')
            ind = 0
        elif k == C['COBJB']:
            line.append('obj %d' % r.B())
        elif k == C['COBJW']:
            line.append('objw %d' % r.W())
        elif k == C['COBJS']:
            line.append('objs %s' % r.S())
        else:
            flush()
            out.append('; ? record %d at %d' % (k, r.p - 1))
            break
    flush()
    return '\n'.join(out)


def disasm(bs):
    # a light one: opcodes by name, short constants and loads as such
    out, i = [], 0
    while i < len(bs):
        b = bs[i]
        i += 1
        if b < 0x80:
            out.append('LDCI%d' % b)
        elif 0xD8 <= b <= 0xE7:
            out.append('LDL%d' % (b - 0xD7))
        else:
            out.append(OPC.get(b, '%02X' % b))
    return ' '.join(out)


if __name__ == '__main__':
    print(dump(sys.argv[1], '--raw' in sys.argv))
