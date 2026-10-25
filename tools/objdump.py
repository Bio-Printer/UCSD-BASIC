#!/usr/bin/env python3
"""objdump.py -- show a BC object file (NAME.OBJ, BASLIB.OBJ): its modules,
procedures (disassembled), relocations, COMMON variables and statics.

  objdump.py FILE.OBJ [-q]      (-q: no disassembly)
"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pdis

RTYPES = {1: 'CALL', 3: 'GSTAT', 4: 'GNAME'}


class R:
    def __init__(self, data):
        self.d, self.p = data, 0

    def b(self):
        if self.p >= len(self.d):
            return 0
        v = self.d[self.p]
        self.p += 1
        return v

    def w(self):
        lo = self.b()
        return lo | (self.b() << 8)

    def s(self):
        n = self.b()
        v = self.d[self.p:self.p + n].decode('latin1')
        self.p += n
        return v


def dump(path, quiet=False):
    r = R(open(path, 'rb').read())
    while True:
        c = r.b()
        if c == 0:
            break
        if c == ord('B'):
            assert r.d[r.p:r.p + 3] == b'COB', 'not a BC object file'
            r.p += 3
            continue
        c = chr(c)
        if c == 'M':
            print('MODULE', r.s())
        elif c == 'P':
            fl, nm, sg = r.b(), r.s(), r.s()
            parmsz, rw, clen, jtab = r.w(), r.b(), r.w(), r.w()
            code = r.d[r.p:r.p + clen]
            r.p += clen
            nrel = r.w()
            rels = [(r.w(), r.b(), r.s()) for _ in range(nrel)]
            print('\n  PROC %s%s seg %r parmsz %d rw %d len %d jtab %d' %
                  (nm, ' (body)' if fl == 1 else ' (private)' if fl == 2 else '', sg, parmsz, rw, clen, jtab))
            ent = (jtab - 2 - struct.unpack_from('<H', code, jtab - 2)[0]) & 0xFFFF
            ext = (jtab - 4 - struct.unpack_from('<H', code, jtab - 4)[0]) & 0xFFFF
            print('    datasz %d  entry %04X exit %04X' % (struct.unpack_from('<H', code, jtab - 8)[0], ent, ext))
            relat = {}
            for pos, ty, t in rels:
                relat.setdefault(pos, []).append('%s %s' % (RTYPES.get(ty, ty), t))
            if not quiet:
                for a, txt in pdis.disasm(code, ent, jtab - 8, jtab, []):
                    note = relat.get(a, []) + relat.get(a + 1, [])
                    print('    %04X  %-28s %s' % (a, txt, '; ' + ', '.join(note) if note else ''))
            else:
                for pos, ty, t in rels:
                    print('    rel %04X %s %s' % (pos, RTYPES.get(ty, ty), t))
        elif c == 'D':
            strong, nm, words = r.b(), r.s(), r.w()
            print('  COMMON %s %d words' % (nm, words))
        elif c == 'G':
            print('  statics %d words' % r.w())
        elif c == 'E':
            print('END')
        else:
            print('bad record %r at %d' % (c, r.p - 1))
            break


if __name__ == '__main__':
    dump(sys.argv[1], '-q' in sys.argv)
