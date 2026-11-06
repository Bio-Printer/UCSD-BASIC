#!/usr/bin/env python3
"""b2self.py -- B2 compiles itself on the P-System.

The host-built code files of B2's programs (build/B2.CODE ... B2DEBUG.CODE: tools/mkself2.sh)
and B2's library build/BASLIB2.OBJ (tools/mklib2.sh) are put on WORK: (#5) with B2's sources
and a batch file, the library's sources on #9; on the P-System, X(ecute #5:B2, then @#5:BUILD
compiles every module and links the programs onto #9, and the library's modules there into
#9:BASLIB.OBJ -- each must be byte for byte the host's.  (WORK: and #9: hold 77 files each,
the most a UCSD directory has: the two are filled so.)

  b2self.py [-v]            (-v: the whole console transcript)
  PSYS_MODE=z80 VERIFY_HARVARD=0 b2self.py    the same in Z80 mode (the least memory)
"""
import glob, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol
from b2progs import PROGS, MODS
LIBS = ['RTCORE', 'RTFILE', 'RTSTR', 'RTNUM', 'RTARR', 'RTINPUT', 'RTDATA', 'RTSUBV', 'RTCHAIN', 'RTWHERE', 'RTUSING']


def main(a):
    ps = psys.PSystem(blocks=6000)
    host = {}
    for p, m in PROGS:
        host[p] = open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read()
        ps.put(p + '.CODE', host[p])
    lib = open(os.path.join(ROOT, 'build', 'BASLIB2.OBJ'), 'rb').read()
    ps.put('BASLIB.OBJ', lib)
    for f in glob.glob(os.path.join(ROOT, 'b2', '*.bas')):
        ps.put(os.path.basename(f)[:-4].upper() + '.BAS', open(f).read())
    spare = ucsdvol.Volume(ps.spare)
    for f in glob.glob(os.path.join(ROOT, 'lib', '*.bas')):
        spare.write(os.path.basename(f)[:-4].upper() + '.BAS', ucsdvol.text_to_ucsd(open(f).read()), 3)
    spare.save()
    mem = '-M ' if '-m' in a else ''
    batch = ''.join('-C #5:%s\n' % m for m in MODS)
    batch += ''.join('-L #9:%s=%s\n' % (p, ','.join('#5:' + x for x in m)) for p, m in PROGS)
    batch += ''.join('-C #9:%s\n' % m for m in LIBS) + '-J #9:BASLIB=' + ','.join('#9:' + m for m in LIBS) + '\n'
    ps.put('BUILD.TEXT', batch)
    script = ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:B2\\r"\n'
              'WAIT "Compile what file?"\nTYPE "%s@#5:BUILD\\r"\nWAIT "Compile what file?"\n'
              'TYPE "\\r"\nWAIT "Command:"\n' % mem)
    ok, tr, info = ps.run_script(script, 6000)
    tr = tr.replace('\n\n', '\n')
    if '-v' in a:
        print(tr)
    else:
        for l in tr.split('\n'):
            if 'least free' in l or 'error' in l.lower() or 'B2:' in l:
                print(l)
    print(info.strip().split('\n')[-1])
    out = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_COMPASM.BLK'))
    try:
        newlib = out.read('BASLIB.OBJ')[0]
    except Exception:
        newlib = b''
    # (a file on the P-System is whole blocks: the zeros after the end)
    libok = newlib.rstrip(b'\0') == lib.rstrip(b'\0')
    print('b2self: BASLIB.OBJ %s' % ('IDENTICAL' if libok else 'DIFFERENT'))
    bad = not libok
    for p, m in PROGS:
        try:
            new = out.read(p + '.CODE')[0]
        except BaseException:
            print('b2self: %s.CODE MISSING' % p)
            bad = 1
            continue
        if new == host[p]:
            print('b2self: %s.CODE IDENTICAL (%d bytes)' % (p, len(new)))
            continue
        d = [i for i in range(min(len(new), len(host[p]))) if new[i] != host[p][i]]
        print('b2self: %s.CODE DIFFERENT (%d and %d bytes, %d differ, first at %s)' % (p, len(new), len(host[p]), len(d), d[:1]))
        open(os.path.join(ROOT, 'build', p + '-psys.CODE'), 'wb').write(new)
        bad = 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
