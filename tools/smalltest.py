#!/usr/bin/env python3
"""smalltest.py -- BC outside the Harvard layout: in the emulator's Z80 mode
and in P-Code mode without the Harvard layout (the code in the data space
too) BC compiles and links DEMO PI (-M: the memory each program has left)
and PI runs.  docs/DESIGN.md section 10 says what makes it fit.

  smalltest.py [-v]      (-v: the whole console transcript)
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import psys
from bcprogs import PROGS

LAST = '  15      196608  3.141592653456104  3.141592653857171  10 10'


def run(mode):
    os.environ['PSYS_MODE'] = mode
    os.environ['VERIFY_HARVARD'] = '0'
    ps = psys.PSystem()
    for p, m in PROGS:
        ps.put(p + '.CODE', open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read())
    ps.put('BASLIB.OBJ', open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read())
    ps.put('PI.BAS', open(os.path.join(ROOT, 'demos', 'pi.bas')).read())
    script = ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:BC\\r"\n'
              'WAIT "Compile what file?"\nTYPE "-M #5:PI\\r"\nWAIT "Compile what file?"\nTYPE "\\r"\n'
              'WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:PI\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 900)
    tr = tr.replace('\n\n', '\n')
    return ok, tr, info


def main(a):
    bad = 0
    for mode, name in [('z80', 'Z80 mode'), ('native', 'P-Code mode, no Harvard layout')]:
        ok, tr, info = run(mode)
        if '-v' in a:
            print(tr)
        least = [l.split('least free memory:')[1].strip() for l in tr.split('\n') if 'least free memory:' in l]
        good = ok and LAST in tr and 'error' not in tr.lower() and 'OFLOW' not in tr
        print('%s: %s (least free: BCGEN %s, BCLINK %s)' % (name, 'PI compiled, linked and ran' if good else 'FAILED',
                                                                least[0] if least else '?', least[1] if len(least) > 1 else '?'))
        if not good and '-v' not in a:
            print(tr[-1500:])
            print(info.strip().split('\n')[-1])
        bad += not good
    print('small test: %s' % ('FAILED' if bad else 'PASSED'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
