#!/usr/bin/env python3
"""runtests.py -- the regression tests: each tests/NAME.bas compiled by the
host BC (build/bc, build/BASLIB.OBJ), run on the P-System, its output
compared with tests/NAME.expect (NAME.keys: what is typed, one line each).

  runtests.py [NAME ...]        (-v: show the differences)
"""
import difflib, glob, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import brun


def compile_host(src, work, extra=()):
    base = os.path.splitext(os.path.basename(src))[0].upper()
    shutil.copy(src, os.path.join(work, base.lower() + '.bas'))
    for e in extra:
        shutil.copy(e, work)
    shutil.copy(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), work)
    r = subprocess.run([os.path.join(ROOT, 'build', 'bc'), '-Q', base], cwd=work, capture_output=True, text=True)
    return base, r


def run_test(name, verbose=False):
    src = os.path.join(ROOT, 'tests', name + '.bas')
    work = tempfile.mkdtemp(prefix='bct_')
    base, r = compile_host(src, work)
    code = os.path.join(work, base + '.CODE')
    if r.returncode != 0 or not os.path.exists(code):
        print('FAIL  %s (compile)\n%s%s' % (name, r.stdout, r.stderr))
        return False
    keys = ''
    kf = os.path.join(ROOT, 'tests', name + '.keys')
    if os.path.exists(kf):
        keys = open(kf).read().rstrip('\n')
    files = [f for f in glob.glob(os.path.join(ROOT, 'tests', name + '.*')) if f.endswith('.dat')]
    ok, out, info, ps = brun.run(code, files, keys)
    exp = open(os.path.join(ROOT, 'tests', name + '.expect')).read()
    if out == exp:
        print('PASS  %s' % name)
        shutil.rmtree(work, True)
        return True
    print('FAIL  %s%s' % (name, '' if ok else ' (run did not complete)'))
    if verbose:
        sys.stdout.writelines(difflib.unified_diff(exp.splitlines(1), out.splitlines(1), 'expected', 'got'))
    return False


def main(a):
    verbose = '-v' in a
    a = [x for x in a if x != '-v']
    names = a or sorted(os.path.splitext(os.path.basename(f))[0] for f in glob.glob(os.path.join(ROOT, 'tests', '*.expect')))
    n = sum(run_test(x, verbose) for x in names)
    print('%d of %d tests passed' % (n, len(names)))
    return 0 if n == len(names) else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
