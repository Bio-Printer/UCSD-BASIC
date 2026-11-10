#!/usr/bin/env python3
"""voltest2.py -- build/BASIC2.BLK on the P-System (unit #5), as voltest.py BASIC.BLK: from the
UCSD-C shell, with UCSD-C's TOOLS: (MAKE) on #11, make -f basic2:makefile runs the makefiles of
BASIC2:/SRC (B2 rebuilt: BASIC2:B22.CODE, B2LEX2 ... B2DEBUG2, each the same as B2.CODE ...
B2DEBUG.CODE but for segment 1's name, its map in BASIC2:/MAP), BASIC2:/LIB (BASLIB2.OBJ, the
same as BASLIB.OBJ), BASIC2:/DEMO and BASIC2:/TEST (every demo and test compiled); then again:
everything up to date.  B2 -S compiles PI again with a listing (DEMO/PI.LST, the host's but for
the source's name); the demos STATS and PI and the test PROCS run.  Then make -f basic2:makefile
install puts the rebuilt compiler in the old one's place (B22.CODE becomes B2.CODE ...,
MAP/B22.MAP MAP/B2.MAP), and that one compiles and links DEMO/HELLO, which runs; then B2 -K -MAP
compiles TEST/RTERR (its NAME.W0 ... W7 in BASIC2:/MAP/W0 ... W7, NAME.MAP in BASIC2:/MAP, each
naming BASIC2:/TEST/RTERR.BAS), RTERR runs (B2DEBUG says its line from that map) and B2DUMP
RTERR.W5 finds the file in BASIC2:/MAP/W5 and writes RTERR.D5 beside the source, in BASIC2:/TEST,
and B2DUMP -MAP RTERR.W4 writes RTERR.D4 into BASIC2:/MAP/D4.  The volume's directories are
checked on the host afterwards.

  voltest2.py [--pascal]     (--pascal: BIGGY boots SYSTEM.PASCAL, not SYSTEM.C)
"""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol, mkvolume, mkvolume2
from b2progs import PROGS


def main(a):
    ps = psys.PSystem()
    shutil.copy(os.path.join(ROOT, 'build', 'BASIC2.BLK'), ps.src)
    # (a key at the boot's question: SYSTEM.PASCAL)
    script = 'WAIT "instead of SYSTEM.C"\nTYPE " "\n' if '--pascal' in a else ''
    script += ('WAIT "Command:"\nTYPE "S"\nWAIT "> "\n'
               'TYPE "make -f basic2:makefile\\r"\nWAIT "> MAKE -f BASIC2:/TEST/MAKEFILE"\nWAIT "TEST/SUFFIX"\nWAIT "> "\n'
               'TYPE "make -f basic2:makefile\\r"\nWAIT "> MAKE -f BASIC2:/TEST/MAKEFILE"\nWAIT "> "\n'
               'TYPE "b2 -q -s basic2:/demo/pi\\r"\nWAIT "exit status"\nWAIT "> "\n'
               'TYPE "basic2:/demo/stats\\r"\nWAIT "exit status"\nWAIT "> "\n'
               'TYPE "basic2:/demo/pi\\r"\nWAIT "exit status"\nWAIT "> "\n'
               'TYPE "basic2:/test/procs\\r"\nWAIT "exit status"\nWAIT "> "\n'
               'TYPE "make -f basic2:makefile install\\r"\nWAIT "B2DEBUG.MAP"\nWAIT "> "\n'
              'TYPE "b2 -q basic2:/demo/hello\\r"\nWAIT "exit status"\nWAIT "> "\n'
              'TYPE "basic2:/demo/hello\\r"\nWAIT "exit status"\nWAIT "> "\n'
              'TYPE "b2 -q -k -map basic2:/test/rterr\\r"\nWAIT "exit status"\nWAIT "> "\n'
              'TYPE "basic2:/test/rterr\\r"\nWAIT "exit status"\nWAIT "> "\n'
              'TYPE "b2dump rterr.w5\\r"\nWAIT "exit status"\nWAIT "> "\n'
              'TYPE "b2dump -map rterr.w4\\r"\nWAIT "exit status"\nWAIT "> "\nTYPE "bye\\r"\nWAIT "Command:"\n')
    os.environ['VERIFY_UNIT11'] = psys.tools_blk()
    ok, tr, info = ps.run_script(script, 6000)
    tr = tr.replace('\n\n', '\n')
    print(tr[tr.find('make -f basic2:makefile'):][-6000:])
    print(info.strip().split('\n')[-1])
    v = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_SOURCE.BLK'))
    lib = open(os.path.join(ROOT, 'build', 'BASLIB2.OBJ'), 'rb').read()
    bad = 0
    # (after make install: PROG.CODE is the PROG2.CODE BUILD made, and that is gone)
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
    # (and each one's map in MAP/: the volume's but for the program's name, PROG2)
    mp = v.sub('MAP')
    for p, m in PROGS:
        host = mkvolume2.volume_map(p)
        try:
            got = mp.read(p + '.MAP')[0].rstrip(b'\0').replace(b'BASIC2:' + p.encode() + b'2.CODE', b'BASIC2:' + p.encode() + b'.CODE')
            got = got.replace(b'S# 1 ' + p.encode() + b'2,', b'S# 1 ' + p.encode() + b',')
            same = got == host and not mp.find(p + '2.MAP') and not v.find(p + '.MAP')
        except BaseException:
            same = False
        print('%s.MAP: %s' % (p, 'the %s2.MAP BUILD made, the host\'s' % p if same else 'DIFFERENT'))
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
            'TEST': sorted(set(re.findall(r'\$\(D\)(\w+)\.CODE', ucsdvol.ucsd_to_text(v.sub('TEST').read('MAKEFILE.TEXT')[0]))))}
    for d, names in want.items():
        sv = v.sub(d)
        missing = [n for n in names if not sv.find(n + '.CODE')]
        ents = sorted(sv.entries)
        overlap = any(a[1] > b[0] for a, b in zip(ents, ents[1:])) or (ents and ents[-1][1] > sv.eov)
        print('%s: %d code files%s%s' % (d, len(names) - len(missing), ', missing ' + ' '.join(missing) if missing else '',
                                         ', FILES OVERLAP' if overlap else ''))
        bad += bool(missing) + bool(overlap)
    # the listing: the host's (B2 on Linux) but for the source's name
    work = tempfile.mkdtemp(prefix='bcvl_')
    shutil.copy(os.path.join(ROOT, 'demos', 'pi.bas'), work)
    shutil.copy(os.path.join(ROOT, 'build', 'BASLIB2.OBJ'), os.path.join(work, 'BASLIB.OBJ'))
    subprocess.run([os.path.join(ROOT, 'build', 'b2', 'b2'), '-Q', '-S', '-C', 'PI'], cwd=work, capture_output=True)
    host = open(os.path.join(work, 'PI.LST'), encoding='latin1').read()
    shutil.rmtree(work, True)
    try:
        got = v.sub('DEMO').read('PI.LST')[0].rstrip(b'\0').decode('latin1').replace('\r', '\n').replace('BASIC2:/DEMO/PI.BAS', 'PI.BAS')
    except BaseException:
        got = ''
    same = got == host
    print('DEMO/PI.LST: %s' % ('the host\'s listing' if same else 'DIFFERENT'))
    bad += not same
    j = tr.find('make -f basic2:makefile', tr.find('make -f basic2:makefile') + 10)
    second = tr[j:tr.find('b2 -q -s', j)]
    same = j >= 0 and "'BASIC2:/LIB/BASLIB2.OBJ' is up to date" in second and second.count("Nothing to be done for 'all'") == 3 \
        and '> B2' not in second
    print('make again: %s' % ('every makefile up to date' if same else 'NOT UP TO DATE'))
    bad += not same
    i = tr.find('make -f basic2:makefile install')
    same = i >= 0 and tr.count('(replaced)', i) == 2 * len(PROGS) and 'Hello' in tr[tr.find('basic2:/demo/hello', i + 30):]
    print('make install: %s' % ('the %d and their maps moved; B2 then made HELLO, which ran' % len(PROGS) if same else 'FAILED'))
    bad += not same
    # -K and -MAP: RTERR's files in BASIC2:/MAP, none in TEST/; their source BASIC2:/TEST/RTERR.BAS
    src = b'BASIC2:/TEST/RTERR.BAS'
    try:
        w = [mp.sub('W%d' % i).read('RTERR.W%d' % i)[0] for i in (0, 1, 2, 4, 5, 6, 7)]
        hs = [x[34:34 + 2 * ((x[32] + 1) // 2)][:x[32]] for x in w]
        mtext = mp.read('RTERR.MAP')[0]
        dump = v.sub('TEST').read('RTERR.D5')[0]           # beside the source
        dump4 = mp.sub('D4').read('RTERR.D4')[0]           # -MAP
        same = all(h == src for h in hs) and b'  MODULE RTERR from ' + src + b' (object BASIC2:/TEST/RTERR.OBJ)' in mtext
        same = same and mtext.startswith(b'BASIC2:/TEST/RTERR.CODE: ') and b'; the source: ' + src in dump
        same = same and b'; the source: ' + src in dump4 and not mp.sub('D5').find('RTERR.D5')
        same = same and not any(n.startswith('RTERR.W') or n == 'RTERR.MAP' or n == 'RTERR.D4' for n in [e[3] for e in v.sub('TEST').entries])
    except BaseException:
        same = False
    print('-K -MAP: %s' % ('RTERR.W0 ... W7 in MAP/W0 ... W7, RTERR.MAP in MAP/, each naming its source; '
                           'B2DUMP RTERR.W5 into TEST/ (the source\'s), -MAP RTERR.W4 into MAP/D4' if same else 'WRONG'))
    bad += not same
    i = tr.find('basic2:/test/rterr\n')
    same = i >= 0 and 'RTERR.BAS line 8, in FILL' in tr[i:] and 'x(a) = a' in tr[i:]
    print('RTERR: %s' % ('B2DEBUG said its line from MAP/RTERR.MAP' if same else 'WRONG OUTPUT'))
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
