#!/usr/bin/env python3
"""voltest.py -- build/BASIC.BLK on the P-System (unit #5): BC runs
@BASIC:ALL, which rebuilds the compiler from BASIC:/SRC (BUILD -> BASIC:BC2.CODE,
BCLEX2 ... BCERR2, each the same as BC.CODE ... BCERR.CODE but for segment 1's
name) and the library in BASIC:/LIB
(LIBS -> BASLIB2.OBJ, the same as BASLIB.OBJ), and compiles every demo and
test in their sub-volumes, and then PI again with a listing (-S: DEMO/PI.LST,
the host's listing but for the source's name); then the demos STATS and PI and
the test PROCS run from there (X(ecute BASIC:/DEMO/STATS).  Then, in the
shell, @BASIC:INSTALL puts the rebuilt compiler in the old one's place (BC2.CODE
becomes BC.CODE ...), and that one compiles and links DEMO/HELLO, which runs.
The volume's directories are checked on the host afterwards.

  voltest.py [--pascal]     (--pascal: BIGGY boots SYSTEM.PASCAL, not SYSTEM.C)
"""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol, mkvolume
from bcprogs import PROGS


def main(a):
    ps = psys.PSystem()
    shutil.copy(os.path.join(ROOT, 'build', 'BASIC.BLK'), ps.src)
    # (a key at the boot's question: SYSTEM.PASCAL)
    script = 'WAIT "instead of SYSTEM.C"\nTYPE " "\n' if '--pascal' in a else ''
    script += ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:BC\\r"\n'
              'WAIT "Compile what file?"\nTYPE "-Q @BASIC:ALL -S BASIC:/DEMO/PI\\r"\n'
              'WAIT "Compile what file?"\nTYPE "\\r"\nWAIT "Command:"\n'
              'TYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:/DEMO/STATS\\r"\nWAIT "Command:"\n'
              'TYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:/DEMO/PI\\r"\nWAIT "Command:"\n'
              'TYPE "X"\nWAIT "Execute what file?"\nTYPE "BASIC:/TEST/PROCS\\r"\nWAIT "Command:"\n'
              'TYPE "S"\nWAIT "> "\nTYPE "@BASIC:INSTALL\\r"\nWAIT "BCERR.CODE"\nWAIT "> "\n'
              'TYPE "bc -q basic:/demo/hello\\r"\nWAIT "exit status"\nWAIT "> "\n'
              'TYPE "basic:/demo/hello\\r"\nWAIT "exit status"\nWAIT "> "\nTYPE "bye\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 3000)
    tr = tr.replace('\n\n', '\n')
    print(tr[tr.find('BASIC:BC'):])
    print(info.strip().split('\n')[-1])
    v = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_SOURCE.BLK'))
    lib = open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read()
    bad = 0
    # (after @BASIC:INSTALL: PROG.CODE is the PROG2.CODE BUILD made, and that is gone)
    for p, m in PROGS:
        bc = open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read()
        try:
            bc2 = bytearray(v.read(p + '.CODE')[0])
            same = bc2[72:80] != bc[72:80] and not v.find(p + '2.CODE')
            bc2[72:80] = bc[72:80]          # segment 1's name: BC2 ...
            same = same and bytes(bc2) == bc
        except BaseException:
            same = False
        print('%s.CODE: %s' % (p, 'the %s2.CODE BUILD made, the same as the host\'s' % p if same else 'DIFFERENT'))
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
    # the listing: the host's (BC on Linux) but for the source's name
    work = tempfile.mkdtemp(prefix='bcvl_')
    shutil.copy(os.path.join(ROOT, 'demos', 'pi.bas'), work)
    shutil.copy(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), work)
    subprocess.run([os.path.join(ROOT, 'build', 'bc'), '-Q', '-S', '-C', 'PI'], cwd=work, capture_output=True)
    host = open(os.path.join(work, 'PI.LST'), encoding='latin1').read()
    shutil.rmtree(work, True)
    try:
        got = v.sub('DEMO').read('PI.LST')[0].rstrip(b'\0').decode('latin1').replace('\r', '\n').replace('BASIC:/DEMO/PI.BAS', 'PI.BAS')
    except BaseException:
        got = ''
    same = got == host
    print('DEMO/PI.LST: %s' % ('the host\'s listing' if same else 'DIFFERENT'))
    bad += not same
    i = tr.find('@BASIC:INSTALL')
    same = i >= 0 and tr.count('(replaced)', i) == len(PROGS) and 'Hello' in tr[tr.find('basic:/demo/hello', i + 30):]
    print('@BASIC:INSTALL: %s' % ('the %d moved; BC then made HELLO, which ran' % len(PROGS) if same else 'FAILED'))
    bad += not same
    for name, exp in [('STATS', 'std. dev. 4.73840690527945'),
                      ('PI', '  24   100663296  3.141592653589792  3.141592653589794  15 15'),
                      ('PROCS', open(os.path.join(ROOT, 'tests', 'procs.expect')).read())]:
        same = exp in tr
        print('%s: %s' % (name, 'ran as expected' if same else 'WRONG OUTPUT'))
        bad += not same
    return bad


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
