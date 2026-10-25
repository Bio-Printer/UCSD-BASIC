#!/usr/bin/env python3
"""selfcompile.py -- BC compiles itself on the P-System.

The host-built build/BC.CODE (tools/mkself.sh) and build/BASLIB.OBJ are put
on WORK: (#5) with BC's sources and a batch file; on the P-System,
X(ecute #5:BC, then  @#5:BUILD  compiles every module and links #9:BC.CODE,
which must be byte for byte build/BC.CODE.  The Harvard layout (code in its
own I-space: the emulator's default) gives BC the memory it needs.

  selfcompile.py [-v]       (-v: the whole console transcript)
"""
import glob, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol

MODS = ['BC', 'BCLEX', 'BCDECL', 'BCGEN', 'BCEXPR', 'BCEMIT', 'BCLIST', 'BCLINK']
LIBS = ['RTCORE', 'RTFILE', 'RTSTR', 'RTNUM', 'RTARR', 'RTINPUT', 'RTDATA', 'RTSUBV']


def main(a):
    ps = psys.PSystem(blocks=4000)
    host = open(os.path.join(ROOT, 'build', 'BC.CODE'), 'rb').read()
    ps.put('BC.CODE', host)
    ps.put('BASLIB.OBJ', open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read())
    for f in glob.glob(os.path.join(ROOT, 'bc', '*.bas')) + glob.glob(os.path.join(ROOT, 'lib', '*.bas')):
        ps.put(os.path.basename(f)[:-4].upper() + '.TEXT', open(f).read())
    batch = ''.join('-C #5:%s\n' % m for m in MODS) + '-L #9:BC=' + ','.join('#5:' + m for m in MODS) + '\n'
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
    try:
        new = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_COMPASM.BLK')).read('BC.CODE')[0]
    except Exception as e:
        print('selfcompile: FAILED (no #9:BC.CODE: %s)' % e)
        return 1
    lib = open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read()
    try:
        newlib = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_COMPASM.BLK')).read('BASLIB.OBJ')[0]
    except Exception:
        newlib = b''
    # (a file on the P-System is whole blocks: the zeros after the end)
    libok = newlib.rstrip(b'\0') == lib.rstrip(b'\0')
    print('selfcompile: BASLIB.OBJ %s' % ('IDENTICAL' if libok else 'DIFFERENT'))
    if new == host:
        print('selfcompile: BC.CODE IDENTICAL (%d bytes)' % len(new))
        return 0 if libok else 1
    d = [i for i in range(min(len(new), len(host))) if new[i] != host[i]]
    print('selfcompile: DIFFERENT (%d and %d bytes, %d differ, first at %s)' % (len(new), len(host), len(d), d[:1]))
    open(os.path.join(ROOT, 'build', 'BC-psys.CODE'), 'wb').write(new)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
