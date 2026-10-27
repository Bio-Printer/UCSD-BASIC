#!/usr/bin/env python3
"""chaintest.py -- CHAIN from programs Tiny-C's shell started (BIGGY's S): tests/chain.bas and the two
programs it chains to (CHAIN2 with options, CHAIN3 by a string variable) run one after the other, and
the shell comes back after the last one with its exit status (END 3); after a CD into a sub-volume, a
program there chains to another one there by its name alone (the shell's path goes along: COMMAND$
and the files they open are on it).  The host BC compiles them (build/bc, build/BASLIB.OBJ).

  chaintest.py [--pascal]     (--pascal: BIGGY boots SYSTEM.PASCAL, not SYSTEM.C)
"""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault('VERIFY_HARVARD', '1')
import psys, ucsdvol, brun

SV1 = '''DEFINT A-Z
OPEN "HERE.TXT" FOR OUTPUT AS #1
PRINT #1, "a file on the shell's path"
CLOSE #1
CHAIN "SV2 from sv1"
'''
SV2 = '''DEFINT A-Z
PRINT "sv2: ["; COMMAND$; "]"
OPEN "HERE.TXT" FOR INPUT AS #1
LINE INPUT #1, l$
PRINT "sv2 reads: "; l$
END 7
'''


def compile_all(work, names):
    shutil.copy(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), work)
    for n in names:
        r = subprocess.run([os.path.join(ROOT, 'build', 'bc'), '-Q', n], cwd=work, capture_output=True, text=True)
        if r.returncode:
            raise SystemExit('compile %s: %s%s' % (n, r.stdout, r.stderr))


def main(a):
    work = tempfile.mkdtemp(prefix='bcch_')
    for n in ('chain', 'chain2', 'chain3'):
        shutil.copy(os.path.join(ROOT, 'tests', n + '.bas'), work)
    open(os.path.join(work, 'sv1.bas'), 'w').write(SV1)
    open(os.path.join(work, 'sv2.bas'), 'w').write(SV2)
    compile_all(work, ['CHAIN', 'CHAIN2', 'CHAIN3', 'SV1', 'SV2'])
    ps = psys.PSystem()
    v = ucsdvol.Volume(ps.src)
    for n in ('CHAIN', 'CHAIN2', 'CHAIN3'):
        v.write(n + '.CODE', open(os.path.join(work, n + '.CODE'), 'rb').read(), 2)
    v.write('CHAIN.BAS', ucsdvol.text_to_ucsd(open(os.path.join(work, 'chain.bas')).read()), 3)
    sub = ucsdvol.Volume.new('P', 200)
    for n in ('SV1', 'SV2'):
        sub.write(n + '.CODE', open(os.path.join(work, n + '.CODE'), 'rb').read(), 2)
    v.write('P', sub.image(), 5)
    v.save()
    shutil.rmtree(work, True)
    boot = 'WAIT "instead of SYSTEM.C"\nTYPE " "\n' if '--pascal' in a else ''
    script = boot + psys.shell_script('WAIT "Command:"\nTYPE "S"\nWAIT "shell> "\nTYPE "#5:CHAIN\\r"\nWAIT "shell> "\n'
                               'TYPE "cd #5:/P\\r"\nWAIT "shell> "\nTYPE "sv1\\r"\nWAIT "shell> "\n'
                               'TYPE "bye\\r"\nWAIT "Command:"\n')
    ok, tr, info = ps.run_script(script, 600)
    tr = psys.shell_transcript(tr).replace('\r', '\n').replace('\n\n', '\n')
    exp = open(os.path.join(ROOT, 'tests', 'chain.expect')).read()
    img = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_SOURCE.BLK'))
    checks = [('the script completed', ok),
              ('the chain from the shell: the three programs\' output', exp in tr),
              ('the shell back after the last one, with its exit status 3', exp + '[exit status 3]\nshell> ' in tr),
              ('in a sub-volume (CD): CHAIN "SV2 from sv1" by its name, COMMAND$, the file on the path',
               'sv2: [from sv1]\nsv2 reads: a file on the shell\'s path\n[exit status 7]' in tr),
              ('the file written on the shell\'s path (in P)', img.sub('P').find('HERE.TXT') is not None)]
    bad = 0
    for what, good in checks:
        print('%-4s %s' % ('ok' if good else 'BAD', what))
        bad += not good
    if bad:
        print(tr[tr.find('shell> #5:CHAIN'):][:2000])
    print('chain test (%s): %s' % ('SYSTEM.PASCAL' if '--pascal' in a else 'SYSTEM.C', 'FAILED' if bad else 'PASSED'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
