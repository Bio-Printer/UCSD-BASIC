#!/usr/bin/env python3
"""selfcompile.py -- BC compiles itself on the P-System.

The host-built code files of the compiler's five programs (build/BC.CODE,
BCLEX, BCGEN, BCLIST, BCLINK: tools/mkself.sh) and build/BASLIB.OBJ are put
on WORK: (#5) with BC's sources and a batch file; on the P-System,
X(ecute #5:BC, then  @#5:BUILD  compiles every module and links the five
programs onto #9, each of which must be byte for byte the host's.  The Harvard layout (code in its
own I-space: the emulator's default) gives BC the memory it needs.

  selfcompile.py [-v]       (-v: the whole console transcript)
"""
import glob, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol
from bcprogs import PROGS, MODS
LIBS = ['RTCORE', 'RTFILE', 'RTSTR', 'RTNUM', 'RTARR', 'RTINPUT', 'RTDATA', 'RTSUBV', 'RTCHAIN']


def main(a):
    ps = psys.PSystem(blocks=4000)
    host = {}
    for p, m in PROGS:
        host[p] = open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read()
        ps.put(p + '.CODE', host[p])
    ps.put('BASLIB.OBJ', open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read())
    for f in glob.glob(os.path.join(ROOT, 'bc', '*.bas')) + glob.glob(os.path.join(ROOT, 'lib', '*.bas')):
        ps.put(os.path.basename(f)[:-4].upper() + '.BAS', open(f).read())
    batch = ''.join('-C #5:%s\n' % m for m in MODS)
    batch += ''.join('-L #9:%s=%s\n' % (p, ','.join('#5:' + x for x in m)) for p, m in PROGS)
    batch += ''.join('-C #5:%s\n' % m for m in LIBS) + '-J #9:BASLIB=' + ','.join('#5:' + m for m in LIBS) + '\n'
    ps.put('BUILD.TEXT', batch)
    script = ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:BC\\r"\n'
              'WAIT "Compile what file?"\nTYPE "-M @#5:BUILD\\r"\nWAIT "Compile what file?"\n'
              'TYPE "\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 3000)
    tr = tr.replace('\n\n', '\n')
    if '-v' in a:
        print(tr)
    else:
        for l in tr.split('\n'):
            if 'least free' in l or 'error' in l.lower() or 'segment' in l:
                print(l)
    print(info.strip().split('\n')[-1])
    out = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_COMPASM.BLK'))
    lib = open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read()
    try:
        newlib = out.read('BASLIB.OBJ')[0]
    except Exception:
        newlib = b''
    # (a file on the P-System is whole blocks: the zeros after the end)
    libok = newlib.rstrip(b'\0') == lib.rstrip(b'\0')
    print('selfcompile: BASLIB.OBJ %s' % ('IDENTICAL' if libok else 'DIFFERENT'))
    bad = not libok
    for p, m in PROGS:
        try:
            new = out.read(p + '.CODE')[0]
        except BaseException as e:
            print('selfcompile: %s.CODE MISSING' % p)
            bad = 1
            continue
        if new == host[p]:
            print('selfcompile: %s.CODE IDENTICAL (%d bytes)' % (p, len(new)))
            continue
        d = [i for i in range(min(len(new), len(host[p]))) if new[i] != host[p][i]]
        print('selfcompile: %s.CODE DIFFERENT (%d and %d bytes, %d differ, first at %s)' % (p, len(new), len(host[p]), len(d), d[:1]))
        open(os.path.join(ROOT, 'build', p + '-psys.CODE'), 'wb').write(new)
        bad = 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
