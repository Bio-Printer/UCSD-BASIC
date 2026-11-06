#!/usr/bin/env python3
"""mkvolume2.py -- build/BASIC2.BLK: the volume BASIC2:, B2's (as BASIC: is BC's: tools/mkvolume.py)

    B2.CODE            the compiler: its driver; B2LEX.CODE, B2CONST.CODE, B2SYN.CODE ...
                       B2ASM.CODE its passes, B2LIST, B2LINK, B2ERR, B2DEBUG the programs it
                       chains to (each in memory alone), each with its map
    README.TEXT LANGUAGE.TEXT B2DESIGN.TEXT DESIGN.TEXT   the documentation
    ALL.TEXT           @BASIC2:ALL runs the four batch files below
    INSTALL.TEXT       in the shell, after @BASIC2:/SRC/BUILD: @BASIC2:INSTALL puts
                       B22.CODE, B2LEX2.CODE ... in the places of B2.CODE, B2LEX.CODE ...
    FILES.TEXT         every file, the sub-volumes' too
    SRC/               B2's sources (B2*.BAS); BUILD.TEXT: @BASIC2:/SRC/BUILD rebuilds B2
                       as BASIC2:B22.CODE, B2LEX2.CODE ...
    LIB/               the run-time library BASLIB.OBJ (compiled by B2), its sources;
                       LIBS.TEXT: @BASIC2:/LIB/LIBS rebuilds it as BASIC2:/LIB/BASLIB2.OBJ
    DEMO/              the example programs; DEMOS.TEXT compiles them all
    TEST/              the tests; TESTS.TEXT compiles them all, EXPECT/ what each prints

The compiler and library are the host build's (tools/mkself2.sh, tools/mklib2.sh), which
B2 on the P-System rebuilds byte for byte (tools/b2self.py).
"""
import glob, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ucsdvol
from mkvolume import Dir, blocks, text, LIBS, DEMOS, NOTEST
from b2progs import PROGS, MODS

B2 = os.path.join(ROOT, 'build', 'b2', 'b2')
LIB = os.path.join(ROOT, 'build', 'BASLIB2.OBJ')


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


def main(out=os.path.join(ROOT, 'build', 'BASIC2.BLK')):
    top = Dir('BASIC2', 9000)
    for p, m in PROGS:
        top.binary(p + '.CODE', open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read())
    # (each one's map beside it: a run-time error in B2 says its line; the lines end in CR)
    for p, m in PROGS:
        top.binary(p + '.MAP', open(os.path.join(ROOT, 'build', p + '.MAP'), 'rb').read().replace(b'\n', b'\r'))
    top.text('README.TEXT', text(os.path.join(ROOT, 'docs', 'README2.md')))
    top.text('LANGUAGE.TEXT', text(os.path.join(ROOT, 'docs', 'LANGUAGE.md')))
    top.text('B2DESIGN.TEXT', text(os.path.join(ROOT, 'docs', 'B2DESIGN.md')))
    top.text('DESIGN.TEXT', text(os.path.join(ROOT, 'docs', 'DESIGN.md')))
    top.text('ALL.TEXT', "' everything: the compiler, the library, the demos, the tests\n"
             '@BASIC2:/SRC/BUILD\n@BASIC2:/LIB/LIBS\n@BASIC2:/DEMO/DEMOS\n@BASIC2:/TEST/TESTS\n')
    top.text('INSTALL.TEXT', "' the compiler @BASIC2:/SRC/BUILD rebuilt in the place of the old one: in\n"
             "' the shell, @BASIC2:INSTALL.  Each MOVE deletes the old file and renames the\n"
             "' new one; when the new one is not there it says so and leaves the old one.\n" +
             ''.join('MOVE BASIC2:%s2.CODE BASIC2:%s.CODE\nMOVE BASIC2:%s2.MAP BASIC2:%s.MAP\n' % (p, p, p, p) for p, m in PROGS))

    src = top.sub('SRC')
    src.text('BUILD.TEXT', "' B2: its modules, linked into its %d programs BASIC2:B22.CODE,\n" % len(PROGS) +
             "' %s (the first module of each its main one), each with its\n" % ', '.join(p + '2' for p, m in PROGS[1:]) +
             "' map (-MAP, this file's links: a run-time error in B2 says its line)\n-MAP\n" +
             ''.join('-C BASIC2:/SRC/%s\n' % m for m in MODS) +
             ''.join('-L BASIC2:%s2=%s\n' % (p, ','.join('BASIC2:/SRC/' + x for x in m)) for p, m in PROGS))
    for f in sorted(glob.glob(os.path.join(ROOT, 'b2', '*.bas'))):
        src.text(os.path.basename(f)[:-4].upper() + '.BAS', text(f))
    src.extra = sum(blocks(os.path.getsize(os.path.join(ROOT, 'build', 'self2', m + '.OBJ'))) for m in MODS)

    lib = top.sub('LIB')
    baslib = open(LIB, 'rb').read()
    lib.binary('BASLIB.OBJ', baslib)
    lib.text('LIBS.TEXT', "' the run-time library: its modules, joined into BASIC2:/LIB/BASLIB2.OBJ\n" +
             ''.join('-C BASIC2:/LIB/%s\n' % m for m in LIBS) +
             '-J BASIC2:/LIB/BASLIB2=' + ','.join('BASIC2:/LIB/' + m for m in LIBS) + '\n')
    for f in sorted(glob.glob(os.path.join(ROOT, 'lib', '*.bas'))):
        lib.text(os.path.basename(f)[:-4].upper() + '.BAS', text(f))
    lib.extra = blocks(len(baslib)) + sum(blocks(os.path.getsize(os.path.join(ROOT, 'build', 'lib2', m + '.OBJ'))) for m in LIBS)

    demo = top.sub('DEMO')
    cmds, srcs, links = [], {}, []
    for d in DEMOS:
        name, more = (d, []) if isinstance(d, str) else d
        for m in more:
            cmds.append('-C BASIC2:/DEMO/%s' % m)
        if more:
            cmds.append('-C BASIC2:/DEMO/%s' % name)
            cmds.append('-L BASIC2:/DEMO/%s=%s' % (name, ','.join('BASIC2:/DEMO/' + m for m in [name] + more)))
        else:
            cmds.append('BASIC2:/DEMO/%s' % name)
        links.append((name, [name] + more))
        for m in [name] + more:
            srcs[m] = os.path.join(ROOT, 'demos', m.lower() + '.bas')
    demo.text('DEMOS.TEXT', "' the demos: each compiled and linked into DEMO/NAME.CODE\n" + '\n'.join(cmds) + '\n')
    for m in sorted(srcs):
        demo.text(m + '.BAS', text(srcs[m]))
    demo.extra = host_sizes(srcs, links)

    test = top.sub('TEST')
    names = sorted(os.path.basename(f)[:-7].upper() for f in glob.glob(os.path.join(ROOT, 'tests', '*.expect')))
    names = [n for n in names if n not in NOTEST]
    test.text('TESTS.TEXT', "' the tests: each compiled and linked into TEST/NAME.CODE; what it\n"
              "' prints is in TEST/EXPECT/NAME.TEXT\n" + ''.join('BASIC2:/TEST/%s\n' % n for n in names))
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
