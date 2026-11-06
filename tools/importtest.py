#!/usr/bin/env python3
"""importtest.py -- the emulator's Import File and Export File with a BASIC source (emulator
2.10): demos/pi.bas as a Windows file (CR LF; more than 1K, so a lost first 1K shows) is
imported into #5 before the boot (run_verify's VERIFY_IMPORT: Options > Import File) and must
become a text file, header and all: BC compiles and links #5:PI and PI runs.  When the script
has ended #5:PI.BAS is exported (VERIFY_EXPORT: Options > Export File) and must be the Windows
file again.  Then (emulator 2.11) several files into a nested sub-volume, WORK:/A/B, one of them
twice: the second replaces the first (no question), its blocks taken by the next file (the first
free area that holds it); a file named as a sub-volume is refused; the shell TYPEs the new one.
Then (2.12) Export All of that volume: a folder WORK with A/B/ in it, the text files as PC text.
build/psys/run_verify must be built from the emulator's sources (tools/setup.sh builds it again
when they are newer).
"""
import os, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import psys, ucsdvol
from bcprogs import PROGS
from mkvolume import Dir

LAST = '  15      196608  3.141592653456104  3.141592653857171  10 10'


def main():
    host = tempfile.mkdtemp(prefix='bcimp_')
    src = os.path.join(host, 'PI.BAS')
    text = open(os.path.join(ROOT, 'demos', 'pi.bas')).read().replace('\n', '\r\n')
    open(src, 'wb').write(text.encode('latin1'))
    back = os.path.join(host, 'PI-BACK.BAS')
    ps = psys.PSystem()
    for p, m in PROGS:
        ps.put(p + '.CODE', open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read())
    ps.put('BASLIB.OBJ', open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read())
    os.environ['VERIFY_IMPORT'] = '5:' + src
    os.environ['VERIFY_EXPORT'] = '5:PI.BAS:' + back
    script = ('WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:BC\\r"\n'
              'WAIT "Compile what file?"\nTYPE "-Q #5:PI\\r"\nWAIT "Compile what file?"\nTYPE "\\r"\n'
              'WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:PI\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 900)
    v = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_SOURCE.BLK'))
    e = v.find('PI.BAS')
    kind = e[2] & 15 if e else None
    checks = [('imported as a text file (kind 3)', kind == 3),
              ('BC compiled and linked it, PI ran', ok and LAST in tr and 'error' not in tr.lower()),
              ('exported back as the Windows file', os.path.exists(back) and open(back, 'rb').read() == text.encode('latin1'))]
    for n, good in checks:
        print('%-5s %s' % ('ok' if good else 'FAIL', n))
    bad = [n for n, good in checks if not good]
    if bad:
        print(tr[-1500:])
        print(info.strip().split('\n')[-3:])
    print('import test: %s' % ('FAILED' if bad else 'PASSED'))
    return 1 if bad else 0


def several():
    h = tempfile.mkdtemp(prefix='bcimp2_')
    os.makedirs(h + '/v1')
    os.makedirs(h + '/v2')
    open(h + '/v1/HELLO.TEXT', 'wb').write(b'first version\r\n' * 200)
    open(h + '/v2/HELLO.TEXT', 'wb').write(b'second version\r\n')
    open(h + '/v1/BIG.DAT', 'wb').write(bytes(range(256)) * 20)
    open(h + '/v1/SMALL.DAT', 'wb').write(b'x' * 100)
    open(h + '/v1/B', 'wb').write(b'not a sub-volume')
    top = Dir('WORK', 3000)
    a = top.sub('A')
    a.total = 600
    b = a.sub('B')
    b.total = 200
    b.text('OLD.TEXT', 'old\n')
    ps = psys.PSystem()
    open(ps.src, 'wb').write(top.image())
    os.environ['VERIFY_IMPORT'] = ';'.join(['5/A/B:' + h + '/v1/HELLO.TEXT', '5/A/B:' + h + '/v1/BIG.DAT',
                                            '5/A/B:' + h + '/v2/HELLO.TEXT', '5/A/B:' + h + '/v1/SMALL.DAT',
                                            '5/A:' + h + '/v1/B'])
    os.environ['VERIFY_EXPORT'] = '5/A/B:HELLO.TEXT:' + h + '/back.txt'
    script = ('WAIT "Command:"\nTYPE "S"\nWAIT "> "\nTYPE "type work:/a/b/hello.text\\r"\nWAIT "> "\n'
              'TYPE "bye\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 300)
    v = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_SOURCE.BLK'))
    ents = [(e[0], e[1], e[3]) for e in v.sub('A').sub('B').entries]
    checks = [('several into WORK:/A/B, HELLO.TEXT replaced, SMALL.DAT in its old place',
               ents == [(6, 10, 'OLD.TEXT'), (10, 14, 'HELLO.TEXT'), (14, 15, 'SMALL.DAT'), (20, 30, 'BIG.DAT')]),
              ('the sub-volume B not replaced', [e[3] for e in v.sub('A').entries] == ['B']),
              ('the shell reads the new HELLO.TEXT', 'second version' in tr and 'first version' not in tr),
              ('exported back', open(h + '/back.txt', 'rb').read() == b'second version\r\n')]
    # Export All of WORK: a folder WORK holding A/ holding B/, the text files as PC text
    os.makedirs(os.path.join(h, 'out'))
    tree = os.path.join(h, 'out', 'WORK')
    os.environ['VERIFY_EXPORT_TREE'] = '5:' + tree
    os.environ.pop('VERIFY_IMPORT')
    os.environ.pop('VERIFY_EXPORT')
    open(ps.src, 'wb').write(open(os.path.join(ps.out, 'VERIFY_SOURCE.BLK'), 'rb').read())
    ps.run_script('WAIT "Command:"\n', 120)
    os.environ.pop('VERIFY_EXPORT_TREE')
    b = os.path.join(tree, 'A', 'B')
    files = sorted(os.path.relpath(os.path.join(d, f), tree) for d, _, fs in os.walk(tree) for f in fs)
    checks.append(('Export All: WORK/A/B/ with its four files, HELLO.TEXT and OLD.TEXT as PC text',
                   files == sorted(['A/B/OLD.TEXT', 'A/B/HELLO.TEXT', 'A/B/SMALL.DAT', 'A/B/BIG.DAT'])
                   and open(os.path.join(b, 'HELLO.TEXT'), 'rb').read() == b'second version\r\n'
                   and open(os.path.join(b, 'OLD.TEXT'), 'rb').read() == b'old\r\n'
                   and open(os.path.join(b, 'BIG.DAT'), 'rb').read() == bytes(range(256)) * 20))
    for n, good in checks:
        print('%-5s %s' % ('ok' if good else 'FAIL', n))
    if not all(g for n, g in checks):
        print(ents, files, tr[-800:])
    return 0 if all(g for n, g in checks) else 1


if __name__ == '__main__':
    r = main()
    for k in ('VERIFY_IMPORT', 'VERIFY_EXPORT'):
        os.environ.pop(k, None)
    r2 = several()
    print('several files: %s' % ('FAILED' if r2 else 'PASSED'))
    sys.exit(r or r2)
