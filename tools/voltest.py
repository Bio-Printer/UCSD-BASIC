#!/usr/bin/env python3
"""voltest.py -- build/BASIC.BLK on the P-System (unit #5): BC runs
@BASIC:ALL, which rebuilds the compiler from BASIC:/SRC (BUILD -> BASIC:BC2.CODE,
the same as BC.CODE but for segment 1's name) and the library in BASIC:/LIB
(LIBS -> BASLIB2.OBJ, the same as BASLIB.OBJ), and compiles every demo and
test in their sub-volumes; then the demos STATS and PI and the test PROCS run
from there (X(ecute BASIC:/DEMO/STATS).  The volume's directories are checked on
the host afterwards.

  voltest.py [--pascal]     (--pascal: BIGGY boots SYSTEM.PASCAL, not SYSTEM.C)
"""
import os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol, mkvolume


def main(a):
    ps = psys.PSystem()
    shutil.copy(os.path.join(ROOT, 'build', 'BASIC.BLK'), ps.src)
    # (a key at the boot's question: SYSTEM.PASCAL)
    script = 'WAIT "instead of SYSTEM.C"\nTYPE " "\n' if '--pascal' in a else ''
    script += ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:BC\\r"\n'
              'WAIT "Compile what file?"\nTYPE "-Q @BASIC:ALL\\r"\n'
              'WAIT "Compile what file?"\nTYPE "\\r"\nWAIT "Command:"\n'
              'TYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:/DEMO/STATS\\r"\nWAIT "Command:"\n'
              'TYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:/DEMO/PI\\r"\nWAIT "Command:"\n'
              'TYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:/TEST/PROCS\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 3000)
    tr = tr.replace('\n\n', '\n')
    print(tr[tr.find('BASIC:BC'):])
    print(info.strip().split('\n')[-1])
    v = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_SOURCE.BLK'))
    bc = open(os.path.join(ROOT, 'build', 'BC.CODE'), 'rb').read()
    lib = open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read()
    bad = 0
    try:
        bc2 = bytearray(v.read('BC2.CODE')[0])
        bc2[72:80] = bc[72:80]          # segment 1's name: BC2
        same = bytes(bc2) == bc
    except BaseException:
        same = False
    print('BC2.CODE: %s' % ('the same as BC.CODE' if same else 'DIFFERENT'))
    bad += not same
    try:
        lib2 = v.sub('LIB').read('BASLIB2.OBJ')[0]
        same = lib2.rstrip(b'\0') == lib.rstrip(b'\0')
    except BaseException:
        same = False
    print('LIB/BASLIB2.OBJ: %s' % ('the same as BASLIB.OBJ' if same else 'DIFFERENT'))
    bad += not same
    # every demo and test has its code file; the directories hold together
    want = {'DEMO': [d if isinstance(d, str) else d[0] for d in mkvolume.DEMOS],
            'TEST': [l.split('/')[-1] for l in ucsdvol.ucsd_to_text(v.sub('TEST').read('TESTS.TEXT')[0]).split('\n')
                     if l.startswith('BASIC:')]}
    for d, names in want.items():
        sv = v.sub(d)
        missing = [n for n in names if not sv.find(n + '.CODE')]
        ents = sorted(sv.entries)
        overlap = any(a[1] > b[0] for a, b in zip(ents, ents[1:])) or (ents and ents[-1][1] > sv.eov)
        print('%s: %d code files%s%s' % (d, len(names) - len(missing), ', missing ' + ' '.join(missing) if missing else '',
                                         ', FILES OVERLAP' if overlap else ''))
        bad += bool(missing) + bool(overlap)
    for name, exp in [('STATS', 'std. dev. 4.73840690527945'),
                      ('PI', '  24   100663296  3.141592653589792  3.141592653589794  15 15'),
                      ('PROCS', open(os.path.join(ROOT, 'tests', 'procs.expect')).read())]:
        same = exp in tr
        print('%s: %s' % (name, 'ran as expected' if same else 'WRONG OUTPUT'))
        bad += not same
    return bad


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
