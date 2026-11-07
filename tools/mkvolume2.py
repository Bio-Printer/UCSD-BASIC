#!/usr/bin/env python3
"""mkvolume2.py -- build/BASIC2.BLK: the volume BASIC2:, B2's (as BASIC: is BC's: tools/mkvolume.py)

    B2.CODE            the compiler: its driver; B2LEX.CODE, B2CONST.CODE, B2SYN.CODE ...
                       B2ASM.CODE its passes, B2LIST, B2LINK, B2ERR, B2DEBUG the programs it
                       chains to (each in memory alone)
    MAP/               their maps (B2.MAP ...), and what B2 -MAP makes: NAME.MAP (B2DEBUG
                       looks for it there); MAP/W0 ... MAP/W7 what -K makes, NAME.W0 in
                       W0 ... (B2DUMP looks for them there)
    README.TEXT LANGUAGE.TEXT B2DESIGN.TEXT DESIGN.TEXT   the documentation
    MAKEFILE.TEXT      MAKE -f BASIC2:MAKEFILE runs the four makefiles below (Tiny-C's MAKE,
                       on TOOLS:); MAKE -f BASIC2:MAKEFILE INSTALL installs the new B2
    FILES.TEXT         every file, the sub-volumes' too
    SRC/               B2's sources (B2*.BAS); MAKEFILE.TEXT: MAKE -f BASIC2:/SRC/MAKEFILE
                       rebuilds B2 as BASIC2:B22.CODE, B2LEX2.CODE ... (what changed); its
                       INSTALL puts them in the places of B2.CODE ...; after MAKE -B -f
                       BASIC2:/SRC/MAKEFILE FLAGS=-K, its DUMPALL dumps every NAME.Wn into
                       BASIC2:/MAP/Dn
    LIB/               the run-time library BASLIB.OBJ (compiled by B2), its sources;
                       MAKEFILE.TEXT rebuilds it as BASIC2:/LIB/BASLIB2.OBJ
    DEMO/              the example programs; MAKEFILE.TEXT compiles them
    TEST/              the tests; MAKEFILE.TEXT compiles them, EXPECT/ what each prints

The compiler and library are the host build's (tools/mkself2.sh, tools/mklib2.sh), which
B2 on the P-System rebuilds byte for byte (tools/b2self.py).
"""
import glob, os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ucsdvol
from mkvolume import Dir, blocks, text, LIBS, DEMOS, NOTEST
from b2progs import PROGS, MODS

B2 = os.path.join(ROOT, 'build', 'b2', 'b2')
# the sub-volume MAP: B2's maps (about 400 blocks), BUILD's while INSTALL has not moved them,
# what -MAP makes; and in it W0 ... W7 (no W3), each pass's -K files: B2's whole build makes
# 21 a pass, 1040 to 1250 blocks (a sub-volume holds 77 files: MAP alone could not)
MAPBLOCKS = 1400
WBLOCKS = 1500
# MAP/D0 ... D7 (no D3): B2DUMP's dumps of them (BASIC2:/SRC/DUMPALL), 1360 to 1810 blocks a
# pass for B2's build -- the volume near the most a UCSD volume can be (32767 blocks)
DBLOCKS = 1900
WPASSES = (0, 1, 2, 4, 5, 6, 7)
LIB = os.path.join(ROOT, 'build', 'BASLIB2.OBJ')


import basmake


def host_sizes(srcs, links):
    """the blocks of the objects and code files the host B2 makes of srcs (NAME: path) and links"""
    work = tempfile.mkdtemp(prefix='b2vol_')
    try:
        for n, p in srcs.items():
            shutil.copy(p, os.path.join(work, n + '.BAS'))
        shutil.copy(LIB, os.path.join(work, 'BASLIB.OBJ'))
        for n in srcs:
            subprocess.run([B2, '-Q', '-C', n], cwd=work, check=True, capture_output=True)
        for out, mods in links:
            subprocess.run([B2, '-Q', '-L', out + '=' + ','.join(mods)], cwd=work, check=True, capture_output=True)
        return sum(blocks(os.path.getsize(f)) for f in glob.glob(os.path.join(work, '*.OBJ')) + glob.glob(os.path.join(work, '*.CODE'))
                   if not f.endswith('BASLIB.OBJ'))
    finally:
        shutil.rmtree(work, True)


def volume_map(p):
    """build/PROG.MAP (the host's link) as the volume has it in MAP/: its files named as BUILD's
    link on the P-System names them -- BASIC2:PROG.CODE, BASIC2:/SRC/NAME.BAS and .OBJ, the
    library BASIC2:/LIB/BASLIB.OBJ (B2DEBUG reads a source beside the one the map names); the
    lines end in CR"""
    t = open(os.path.join(ROOT, 'build', p + '.MAP')).read()
    t = t.replace(p + '.CODE: its ', 'BASIC2:' + p + '.CODE: its ', 1)
    t = re.sub(r'^  MODULE (\S+) from (\S+) \(object (\S+)\)$',
               lambda m: '  MODULE %s from BASIC2:/SRC/%s (object BASIC2:/SRC/%s)' % m.groups(), t, flags=re.M)
    t = t.replace('\n  LIBRARY BASLIB.OBJ\n', '\n  LIBRARY BASIC2:/LIB/BASLIB.OBJ\n', 1)
    return t.replace('\n', '\r').encode('latin1')


def main(out=os.path.join(ROOT, 'build', 'BASIC2.BLK')):
    top = Dir('BASIC2', 32000)
    for p, m in PROGS:
        top.binary(p + '.CODE', open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read())
    # (each one's map in MAP/: a run-time error in B2 says its line; and what -MAP and -K make)
    maps = top.sub('MAP')
    for p, m in PROGS:
        maps.binary(p + '.MAP', volume_map(p))
    for n in WPASSES:
        maps.sub('W%d' % n).total = WBLOCKS
    for n in WPASSES:
        maps.sub('D%d' % n).total = DBLOCKS
    maps.total = MAPBLOCKS + 7 * WBLOCKS + 7 * DBLOCKS
    top.text('README.TEXT', text(os.path.join(ROOT, 'docs', 'README2.md')))
    top.text('LANGUAGE.TEXT', text(os.path.join(ROOT, 'docs', 'LANGUAGE.md')))
    top.text('B2DESIGN.TEXT', text(os.path.join(ROOT, 'docs', 'B2DESIGN.md')))
    top.text('DESIGN.TEXT', text(os.path.join(ROOT, 'docs', 'DESIGN.md')))
    top.text('MAKEFILE.TEXT', basmake.all_makefile('BASIC2', 'B2'))
    src = top.sub('SRC')
    src.text('MAKEFILE.TEXT', basmake.src_makefile('BASIC2', 'B2', PROGS, MODS, os.path.join(ROOT, 'b2'), 'BASIC2:/MAP/',
                                                   ['BASIC2:B2DUMP -MAP BASIC2:/MAP/W%d/%s.W%d' % (n, m[:10], n)
                                                    for m in MODS for n in WPASSES]))
    for f in sorted(glob.glob(os.path.join(ROOT, 'b2', '*.bas'))):
        src.text(os.path.basename(f)[:-4].upper() + '.BAS', text(f))
    src.extra = sum(blocks(os.path.getsize(os.path.join(ROOT, 'build', 'self2', m + '.OBJ'))) for m in MODS)

    lib = top.sub('LIB')
    baslib = open(LIB, 'rb').read()
    lib.binary('BASLIB.OBJ', baslib)
    lib.text('MAKEFILE.TEXT', basmake.lib_makefile('BASIC2', 'B2', LIBS, os.path.join(ROOT, 'lib')))
    for f in sorted(glob.glob(os.path.join(ROOT, 'lib', '*.bas'))):
        lib.text(os.path.basename(f)[:-4].upper() + '.BAS', text(f))
    lib.extra = blocks(len(baslib)) + sum(blocks(os.path.getsize(os.path.join(ROOT, 'build', 'lib2', m + '.OBJ'))) for m in LIBS)

    demo = top.sub('DEMO')
    srcs, links = {}, []
    for d in DEMOS:
        name, more = (d, []) if isinstance(d, str) else d
        links.append((name, [name] + more))
        for m in [name] + more:
            srcs[m] = os.path.join(ROOT, 'demos', m.lower() + '.bas')
    demo.text('MAKEFILE.TEXT', basmake.progs_makefile('BASIC2', 'B2', 'DEMO', 'the demos', [(n, m[1:]) for n, m in links],
                                                      os.path.join(ROOT, 'demos')))
    for m in sorted(srcs):
        demo.text(m + '.BAS', text(srcs[m]))
    demo.extra = host_sizes(srcs, links)

    test = top.sub('TEST')
    names = sorted(os.path.basename(f)[:-7].upper() for f in glob.glob(os.path.join(ROOT, 'tests', '*.expect')))
    names = [n for n in names if n not in NOTEST]
    test.text('MAKEFILE.TEXT', basmake.progs_makefile('BASIC2', 'B2', 'TEST', 'the tests (what each prints is in\n'
                                                      'BASIC2:/TEST/EXPECT/NAME.TEXT)', [(n, []) for n in names],
                                                      os.path.join(ROOT, 'tests')))
    srcs = {n: os.path.join(ROOT, 'tests', n.lower() + '.bas') for n in names}
    for n in names:
        test.text(n + '.BAS', text(srcs[n]))
    test.extra = host_sizes(srcs, [(n, [n]) for n in names])
    exp = test.sub('EXPECT')
    for n in names:
        e2 = os.path.join(ROOT, 'tests', n.lower() + '.expect2')
        exp.text(n + '.TEXT', text(e2 if os.path.exists(e2) else os.path.join(ROOT, 'tests', n.lower() + '.expect')))

    # FILES.TEXT: made twice, to list itself with its own size
    top.items.append(('FILES.TEXT', b'', 3))
    for _ in range(2):
        top.image()
        listing = '\n'.join(['BASIC2: -- B2, the second BASIC compiler for the UCSD P-System', '',
                             'Every file (A/NAME: NAME in the sub-volume A) and its blocks:', ''] +
                            top.listing()) + '\n'
        top.items[-1] = ('FILES.TEXT', ucsdvol.text_to_ucsd(listing), 3)
    if os.path.exists(out):
        os.remove(out)
    open(out, 'wb').write(top.image())
    print('%s: %d files' % (out, len(top.listing())))
    sys.stdout.write(listing)


if __name__ == '__main__':
    main(*sys.argv[1:])
