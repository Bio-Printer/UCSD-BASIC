#!/usr/bin/env python3
"""b2mem.py -- each pass's least free memory compiling modules with B2 on the P-System, in Z80
mode by default (the least memory): quicker than b2self.py's whole rebuild.

  b2mem.py [MODULE ...]     (default: B2's largest modules; -harvard: the Harvard layout)
"""
import glob, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
if '-harvard' not in sys.argv:
    os.environ.setdefault('PSYS_MODE', 'z80')
    os.environ.setdefault('VERIFY_HARVARD', '0')
import psys
from b2progs import PROGS


def main(a):
    mods = [m.upper() for m in a if not m.startswith('-')] or ['B2NAME', 'B2EXPR', 'B2STMT', 'B2SYN']
    ps = psys.PSystem(blocks=4000)
    for p, m in PROGS:
        ps.put(p + '.CODE', open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read())
    ps.put('BASLIB.OBJ', open(os.path.join(ROOT, 'build', 'BASLIB2.OBJ'), 'rb').read())
    for f in glob.glob(os.path.join(ROOT, 'b2', '*.bas')):
        ps.put(os.path.basename(f)[:-4].upper() + '.BAS', open(f).read())
    ps.put('MEM.TEXT', ''.join('-C #5:%s\n' % m for m in mods))
    script = ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:B2\\r"\n'
              'WAIT "Compile what file?"\nTYPE "-M @#5:MEM\\r"\nWAIT "Compile what file?"\n'
              'TYPE "\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 3000)
    bad = 0
    for l in tr.split('\n'):
        if l.startswith('Compiling') or 'least free memory' in l or 'error' in l.lower() or 'OFLOW' in l:
            print(l.rstrip())
            bad += 'error' in l.lower() or 'OFLOW' in l
    print(info.strip().split('\n')[-1])
    return 1 if bad or not ok else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
