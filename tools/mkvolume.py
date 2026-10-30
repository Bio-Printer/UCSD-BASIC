#!/usr/bin/env python3
"""mkvolume.py -- build/BASIC.BLK: the volume BASIC: (6000 blocks: the BUILD writes the eight new code files on it)

    BC.CODE            the compiler: its driver; BCLEX.CODE, BCGEN.CODE, BCLIST.CODE,
                       BCLINK.CODE, BCERR.CODE and BCDEBUG.CODE the programs it chains to (each in
                       memory alone)
    README.TEXT LANGUAGE.TEXT DESIGN.TEXT   the documentation
    ALL.TEXT           @BASIC:ALL runs the four batch files below
    INSTALL.TEXT       in the shell, after @BASIC:/SRC/BUILD: @BASIC:INSTALL puts
                       BC2.CODE ... BCDEBUG2.CODE in the places of BC.CODE ... BCDEBUG.CODE
    FILES.TEXT         every file, the sub-volumes' too
    SRC/               the compiler's sources (BC*.BAS); BUILD.TEXT:
                       @BASIC:/SRC/BUILD rebuilds the compiler as BASIC:BC2.CODE,
                       BCLEX2.CODE ... BCDEBUG2.CODE
    LIB/               the run-time library BASLIB.OBJ, its sources (RT*.BAS);
                       LIBS.TEXT: @BASIC:/LIB/LIBS rebuilds it as BASIC:/LIB/BASLIB2.OBJ
    DEMO/              example programs; DEMOS.TEXT compiles them all
    TEST/              the compiler's tests; TESTS.TEXT compiles them all,
                       EXPECT/ what each prints

The sub-volumes are data files holding a volume of their own (Tiny-C's
MKDIR), made here with room for what their batch files write (the objects
and code files, measured with the host build: twice that and 40 blocks).
The compiler and library are the host build's (tools/mkself.sh,
tools/mklib.sh), which BC on the P-System rebuilds byte for byte.  The BASIC
sources are NAME.BAS, of the kind text (as the Editor's files are).
"""
import glob, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ucsdvol

from bcprogs import PROGS, MODS
LIBS = ['RTCORE', 'RTFILE', 'RTSTR', 'RTNUM', 'RTARR', 'RTINPUT', 'RTDATA', 'RTSUBV', 'RTCHAIN', 'RTWHERE']
# the demos: NAME, or (NAME, [the modules linked with it])
DEMOS = ['HELLO', 'PRIMES', 'HANOI', 'MANDEL', 'PI', 'GUESS', 'AMAZING', ('STATS', ['STATLIB'])]
# the tests on the volume (not SUBVOL: it needs the sub-volumes runtests makes; not CHAIN:
# its programs are on #5 as runtests puts them)
NOTEST = ['SUBVOL', 'CHAIN']
ROOM = 40


def blocks(n):
    return max(1, (n + 511) // 512)


def text(path):
    return open(path, encoding='latin1').read()


class Dir:
    """a volume being made, or a sub-volume in it: its files, then made with
    room for `extra` more blocks"""
    def __init__(self, name, total=None):
        self.name, self.total, self.items, self.extra = name, total, [], 0

    def text(self, name, s):
        self.items.append((name, ucsdvol.text_to_ucsd(s), 3))

    def binary(self, name, data):
        self.items.append((name, data, 2 if name.endswith('.CODE') else 5))

    def sub(self, name):
        d = Dir(name)
        self.items.append((name, d, 5))
        return d

    def image(self):
        parts = [(n, r.image() if isinstance(r, Dir) else r, k) for n, r, k in self.items]
        need = 6 + sum(blocks(len(r)) for n, r, k in parts)
        v = ucsdvol.Volume.new(self.name, self.total or need + 2 * self.extra + ROOM)
        for n, r, k in parts:
            v.write(n, r, k)
        self.blocks = v.eov
        return v.image()

    def listing(self, pre=''):
        out = []
        for n, r, k in self.items:
            if isinstance(r, Dir):
                out.append('  %-26s %5d  (sub-volume)' % (pre + n + '/', r.blocks))
                out += r.listing(pre + n + '/')
            else:
                out.append('  %-26s %5d' % (pre + n, blocks(len(r))))
        return out


def host_sizes(srcs, links):
    """the blocks of the objects and code files the host BC makes of srcs
    (NAME: path) and links ([(OUT, [NAME ...])])"""
    work = tempfile.mkdtemp(prefix='bcvol_')
    try:
        for n, p in srcs.items():
            shutil.copy(p, os.path.join(work, n + '.BAS'))
        shutil.copy(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), work)
        bc = os.path.join(ROOT, 'build', 'bc')
        for n in srcs:
            subprocess.run([bc, '-Q', '-C', n], cwd=work, check=True, capture_output=True)
        for out, mods in links:
            subprocess.run([bc, '-Q', '-L', out + '=' + ','.join(mods)], cwd=work, check=True, capture_output=True)
        return sum(blocks(os.path.getsize(f)) for f in glob.glob(os.path.join(work, '*.OBJ')) + glob.glob(os.path.join(work, '*.CODE'))
                   if not f.endswith('BASLIB.OBJ'))
    finally:
        shutil.rmtree(work, True)


def main(out=os.path.join(ROOT, 'build', 'BASIC.BLK')):
    top = Dir('BASIC', 6000)
    for p, m in PROGS:
        top.binary(p + '.CODE', open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read())
    top.text('README.TEXT', text(os.path.join(ROOT, 'README.md')))
    top.text('LANGUAGE.TEXT', text(os.path.join(ROOT, 'docs', 'LANGUAGE.md')))
    top.text('DESIGN.TEXT', text(os.path.join(ROOT, 'docs', 'DESIGN.md')))
    top.text('ALL.TEXT', "' everything: the compiler, the library, the demos, the tests\n"
             '@BASIC:/SRC/BUILD\n@BASIC:/LIB/LIBS\n@BASIC:/DEMO/DEMOS\n@BASIC:/TEST/TESTS\n')

    top.text('INSTALL.TEXT', "' the compiler @BASIC:/SRC/BUILD rebuilt in the place of the old one: in the\n"
             "' shell, @BASIC:INSTALL.  Each MOVE deletes the old file and renames the new\n"
             "' one; when the new one is not there it says so and leaves the old one.\n" +
             ''.join('MOVE BASIC:%s2.CODE BASIC:%s.CODE\n' % (p, p) for p, m in PROGS))

    src = top.sub('SRC')
    src.text('BUILD.TEXT', "' the compiler: its modules, linked into its %d programs BASIC:BC2.CODE,\n" % len(PROGS) +
             "' %s (the first module of each its main one)\n" % ', '.join(p + '2' for p, m in PROGS[1:]) +
             ''.join('-C BASIC:/SRC/%s\n' % m for m in MODS) +
             ''.join('-L BASIC:%s2=%s\n' % (p, ','.join('BASIC:/SRC/' + x for x in m)) for p, m in PROGS))
    for f in sorted(glob.glob(os.path.join(ROOT, 'bc', '*.bas'))):
        src.text(os.path.basename(f)[:-4].upper() + '.BAS', text(f))
    src.extra = sum(blocks(os.path.getsize(os.path.join(ROOT, 'build', 'self', m + '.OBJ'))) for m in MODS)

    lib = top.sub('LIB')
    baslib = open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read()
    lib.binary('BASLIB.OBJ', baslib)
    lib.text('LIBS.TEXT', "' the run-time library: its modules, joined into BASIC:/LIB/BASLIB2.OBJ\n" +
             ''.join('-C BASIC:/LIB/%s\n' % m for m in LIBS) +
             '-J BASIC:/LIB/BASLIB2=' + ','.join('BASIC:/LIB/' + m for m in LIBS) + '\n')
    for f in sorted(glob.glob(os.path.join(ROOT, 'lib', '*.bas'))):
        lib.text(os.path.basename(f)[:-4].upper() + '.BAS', text(f))
    lib.extra = blocks(len(baslib)) + sum(blocks(os.path.getsize(os.path.join(ROOT, 'build', 'lib', m + '.OBJ'))) for m in LIBS)

    demo = top.sub('DEMO')
    cmds, srcs, links = [], {}, []
    for d in DEMOS:
        name, more = (d, []) if isinstance(d, str) else d
        for m in more:
            cmds.append('-C BASIC:/DEMO/%s' % m)
        if more:
            cmds.append('-C BASIC:/DEMO/%s' % name)
            cmds.append('-L BASIC:/DEMO/%s=%s' % (name, ','.join('BASIC:/DEMO/' + m for m in [name] + more)))
        else:
            cmds.append('BASIC:/DEMO/%s' % name)
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
              "' prints is in TEST/EXPECT/NAME.TEXT\n" + ''.join('BASIC:/TEST/%s\n' % n for n in names))
    srcs = {n: os.path.join(ROOT, 'tests', n.lower() + '.bas') for n in names}
    for n in names:
        test.text(n + '.BAS', text(srcs[n]))
    test.extra = host_sizes(srcs, [(n, [n]) for n in names])
    exp = test.sub('EXPECT')
    for n in names:
        exp.text(n + '.TEXT', text(os.path.join(ROOT, 'tests', n.lower() + '.expect')))

    # FILES.TEXT: made twice, to list itself with its own size
    top.items.append(('FILES.TEXT', b'', 3))
    for _ in range(2):
        top.image()
        listing = '\n'.join(['BASIC: -- the BC BASIC compiler for the UCSD P-System', '',
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
