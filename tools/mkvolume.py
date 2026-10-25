#!/usr/bin/env python3
"""mkvolume.py -- build/BASIC.BLK: the volume BASIC: (4000 blocks)

    BC.CODE          the compiler          BASLIB.OBJ   the run-time library
    BC*.TEXT         the compiler's sources RT*.TEXT    the library's sources
    BUILD.TEXT       @BASIC:BUILD rebuilds the compiler: BASIC:BC2.CODE
    LIBS.TEXT        @BASIC:LIBS rebuilds the library: BASIC:BASLIB2.OBJ
    README.TEXT LANGUAGE.TEXT DESIGN.TEXT   the documentation
    the example programs (the tests: ARITH.TEXT ...), CATALOG.TEXT the list

The compiler and library are the host build's (tools/mkself.sh,
tools/mklib.sh), which BC on the P-System rebuilds byte for byte.
"""
import glob, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ucsdvol

MODS = ['BC', 'BCLEX', 'BCDECL', 'BCGEN', 'BCEXPR', 'BCEMIT', 'BCLIST', 'BCLINK']
LIBS = ['RTCORE', 'RTFILE', 'RTSTR', 'RTNUM', 'RTARR', 'RTINPUT', 'RTDATA']


def text(path):
    return open(path, encoding='latin1').read()


def main(out=os.path.join(ROOT, 'build', 'BASIC.BLK')):
    if os.path.exists(out):
        os.remove(out)
    ucsdvol.main(['new', out, 'BASIC', '4000'])
    v = ucsdvol.Volume(out)
    files = []

    def put(name, data, kind=None):
        if isinstance(data, str):
            v.write(name, ucsdvol.text_to_ucsd(data), 3)
        else:
            v.write(name, data, kind or (2 if name.endswith('.CODE') else 5))
        files.append(name)

    put('BC.CODE', open(os.path.join(ROOT, 'build', 'BC.CODE'), 'rb').read())
    put('BASLIB.OBJ', open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read())
    put('README.TEXT', text(os.path.join(ROOT, 'README.md')))
    put('LANGUAGE.TEXT', text(os.path.join(ROOT, 'docs', 'LANGUAGE.md')))
    put('DESIGN.TEXT', text(os.path.join(ROOT, 'docs', 'DESIGN.md')))
    put('BUILD.TEXT', ''.join('-C BASIC:%s\n' % m for m in MODS) +
        '-L BASIC:BC2=' + ','.join('BASIC:' + m for m in MODS) + '\n')
    put('LIBS.TEXT', ''.join('-C BASIC:%s\n' % m for m in LIBS) +
        '-J BASIC:BASLIB2=' + ','.join('BASIC:' + m for m in LIBS) + '\n')
    for f in sorted(glob.glob(os.path.join(ROOT, 'bc', '*.bas')) + glob.glob(os.path.join(ROOT, 'lib', '*.bas'))):
        put(os.path.basename(f)[:-4].upper() + '.TEXT', text(f))
    for f in sorted(glob.glob(os.path.join(ROOT, 'tests', '*.bas'))):
        put(os.path.basename(f)[:-4].upper() + '.TEXT', text(f))
    listing = ['BASIC: -- the BC BASIC compiler for the UCSD P-System', '']
    for n in files + ['CATALOG.TEXT']:
        listing.append(n)
    put('CATALOG.TEXT', '\n'.join(listing) + '\n')
    v.save()
    print('%s: %d files' % (out, len(files)))


if __name__ == '__main__':
    main(*sys.argv[1:])
