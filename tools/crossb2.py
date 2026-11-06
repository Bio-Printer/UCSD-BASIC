#!/usr/bin/env python3
"""crossb2.py -- B2 compiles BC, and that BC builds BC: B2's code checked on a large program.

BC's sources (bc/) are compiled and linked by the host B2 with B2's library (build/BASLIB2.OBJ):
build/cross/BC.CODE ... BCDEBUG.CODE.  On the P-System, that BC (X(ecute #5:BC) compiles BC's
sources and BC's library and links BC's programs, as selfcompile.py does; each code file and
BASLIB.OBJ must be byte for byte what the host BC made (build/BC.CODE ..., build/BASLIB.OBJ:
tools/mkself.sh, tools/mklib.sh).

  crossb2.py [-v]
"""
import glob, os, shutil, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol
from bcprogs import PROGS, MODS
LIBS = ['RTCORE', 'RTFILE', 'RTSTR', 'RTNUM', 'RTARR', 'RTINPUT', 'RTDATA', 'RTSUBV', 'RTCHAIN', 'RTWHERE', 'RTUSING']


def build_cross():
    d = os.path.join(ROOT, 'build', 'cross')
    shutil.rmtree(d, True)
    os.makedirs(d)
    for f in glob.glob(os.path.join(ROOT, 'bc', '*.bas')):
        shutil.copy(f, d)
    shutil.copy(os.path.join(ROOT, 'build', 'BASLIB2.OBJ'), os.path.join(d, 'BASLIB.OBJ'))
    b2 = os.path.join(ROOT, 'build', 'b2', 'b2')
    for m in MODS:
        subprocess.run([b2, '-Q', '-C', m], cwd=d, check=True)
    for p, m in PROGS:
        subprocess.run([b2, '-Q', '-L', '%s=%s' % (p, ','.join(m))], cwd=d, check=True)
    return d


def main(a):
    d = build_cross()
    ps = psys.PSystem(blocks=4000)
    for p, m in PROGS:
        ps.put(p + '.CODE', open(os.path.join(d, p + '.CODE'), 'rb').read())
    ps.put('BASLIB.OBJ', open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read())
    for f in glob.glob(os.path.join(ROOT, 'bc', '*.bas')) + glob.glob(os.path.join(ROOT, 'lib', '*.bas')):
        ps.put(os.path.basename(f)[:-4].upper() + '.BAS', open(f).read())
    batch = ''.join('-C #5:%s\n' % m for m in MODS)
    batch += ''.join('-L #9:%s=%s\n' % (p, ','.join('#5:' + x for x in m)) for p, m in PROGS)
    batch += ''.join('-C #5:%s\n' % m for m in LIBS) + '-J #9:BASLIB=' + ','.join('#5:' + m for m in LIBS) + '\n'
    ps.put('BUILD.TEXT', batch)
    script = ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:BC\\r"\n'
              'WAIT "Compile what file?"\nTYPE "@#5:BUILD\\r"\nWAIT "Compile what file?"\n'
              'TYPE "\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 3000)
    if '-v' in a:
        print(tr)
    print(info.strip().split('\n')[-1])
    out = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_COMPASM.BLK'))
    bad = 0
    lib = open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read()
    try:
        newlib = out.read('BASLIB.OBJ')[0]
    except Exception:
        newlib = b''
    same = newlib.rstrip(b'\0') == lib.rstrip(b'\0')
    print('crossb2: BASLIB.OBJ %s' % ('IDENTICAL' if same else 'DIFFERENT'))
    bad += not same
    for p, m in PROGS:
        host = open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read()
        try:
            new = out.read(p + '.CODE')[0]
        except BaseException:
            new = b''
        same = new == host
        print('crossb2: %s.CODE %s' % (p, 'IDENTICAL (%d bytes)' % len(new) if same else 'DIFFERENT'))
        bad += not same
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
