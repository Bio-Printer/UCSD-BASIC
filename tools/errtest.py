#!/usr/bin/env python3
"""errtest.py -- BC's compile errors (BCERR says them): each tests/errors/NAME.bas,
full of mistakes, compiled with -Q -C must give tests/errors/NAME.expect, the
messages and the "N error(s)" line -- by the host build (build/bc) and by BC on
the P-System (the names there have #5: before them, taken off).

  errtest.py [--host]      (--host: the host build only)
"""
import glob, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import psys
from bcprogs import PROGS

DIR = os.path.join(ROOT, 'tests', 'errors')


def names():
    return sorted(os.path.basename(f)[:-4].upper() for f in glob.glob(os.path.join(DIR, '*.bas')))


def expect(n):
    return open(os.path.join(DIR, n.lower() + '.expect')).read()


def host():
    work = tempfile.mkdtemp(prefix='bcerr_')
    bad = 0
    try:
        for f in glob.glob(os.path.join(DIR, '*.bas')):
            shutil.copy(f, work)
        shutil.copy(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), work)
        for n in names():
            r = subprocess.run([os.path.join(ROOT, 'build', 'bc'), '-Q', '-C', n], cwd=work, capture_output=True, text=True)
            left = [f for f in os.listdir(work) if f.startswith('BCTEMP') or f.endswith('.OBJ') and f != 'BASLIB.OBJ']
            good = r.stdout == expect(n) and r.returncode == 1 and not left
            print('host %s: %s' % (n, 'as expected' if good else 'DIFFERENT (status %d, left %s)\n%s' % (r.returncode, left, r.stdout)))
            bad += not good
    finally:
        shutil.rmtree(work, True)
    return bad


def psystem():
    ps = psys.PSystem()
    for p, m in PROGS:
        ps.put(p + '.CODE', open(os.path.join(ROOT, 'build', p + '.CODE'), 'rb').read())
    ps.put('BASLIB.OBJ', open(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), 'rb').read())
    for n in names():
        ps.put(n + '.BAS', open(os.path.join(DIR, n.lower() + '.bas')).read())
    script = 'WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:BC\\r"\n'
    for n in names():
        script += 'WAIT "Compile what file?"\nTYPE "-Q -C #5:%s\\r"\n' % n
    script += 'WAIT "Compile what file?"\nTYPE "\\r"\nWAIT "Command:"\n'
    ok, tr, info = ps.run_script(script, 1200)
    tr = tr.replace('\r\n', '\n').replace('\r', '\n').replace('\n\n', '\n').replace('#5:', '')
    bad = 0
    for n in names():
        i = tr.find('-Q -C %s\n' % n)
        j = tr.find('Compile what file?', i)
        got = tr[i + len('-Q -C %s\n' % n):j] if i >= 0 else ''
        good = got == expect(n)
        print('P-System %s: %s' % (n, 'as expected' if good else 'DIFFERENT\n' + got))
        bad += not good
    if not ok:
        print(info.strip().split('\n')[-1])
        bad += 1
    return bad


def main(a):
    bad = host()
    if '--host' not in a:
        bad += psystem()
    print('error test: %s' % ('FAILED' if bad else 'PASSED'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
