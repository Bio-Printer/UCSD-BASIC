#!/usr/bin/env python3
"""voltest.py -- build/BASIC.BLK on the P-System (unit #5): BC rebuilds
itself (@BASIC:BUILD -> BC2.CODE, the same as BC.CODE but for segment 1's
name) and the library (@BASIC:LIBS -> BASLIB2.OBJ, the same as BASLIB.OBJ),
then compiles and runs the example BASIC:PROCS.
"""
import os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol


def main():
    ps = psys.PSystem()
    shutil.copy(os.path.join(ROOT, 'build', 'BASIC.BLK'), ps.src)
    script = ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:BC\\r"\n'
              'WAIT "Compile what file?"\nTYPE "-Q @BASIC:BUILD @BASIC:LIBS BASIC:PROCS\\r"\n'
              'WAIT "Compile what file?"\nTYPE "\\r"\nWAIT "Command:"\n'
              'TYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:PROCS\\r"\nWAIT "Command:"\n')
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
    except Exception as e:
        same = False
    print('BC2.CODE: %s' % ('the same as BC.CODE' if same else 'DIFFERENT'))
    bad += not same
    try:
        lib2 = v.read('BASLIB2.OBJ')[0]
        same = lib2.rstrip(b'\0') == lib.rstrip(b'\0')
    except Exception:
        same = False
    print('BASLIB2.OBJ: %s' % ('the same as BASLIB.OBJ' if same else 'DIFFERENT'))
    bad += not same
    exp = open(os.path.join(ROOT, 'tests', 'procs.expect')).read()
    same = exp in tr
    print('PROCS: %s' % ('ran as expected' if same else 'WRONG OUTPUT'))
    bad += not same
    return bad


if __name__ == '__main__':
    sys.exit(main())
