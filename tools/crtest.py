#!/usr/bin/env python3
"""crtest.py -- the console's line ends: PRINT a; CHR$(13); goes back to the line's start
(a CR, no LF: the next number overwrites the line), PRINT's end of a line is CR and LF, and
CHR$(10) is a LF alone.  The emulator's transcript writes a CR and a LF each as a new line,
so a line end is two of them and a CR alone one.
"""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import brun

SRC = 'FOR a = 1 TO 3\n    PRINT a; CHR$(13);\nNEXT a\nPRINT "end"\nPRINT "x"; CHR$(10); "y"\nPRINT "z"\n'


def main():
    work = tempfile.mkdtemp(prefix='bccr_')
    try:
        open(os.path.join(work, 'CRTEST.BAS'), 'w').write(SRC)
        shutil.copy(os.path.join(ROOT, 'build', 'BASLIB.OBJ'), work)
        subprocess.run([os.path.join(ROOT, 'build', 'bc'), '-Q', 'CRTEST'], cwd=work, check=True)
        ok, out, info, ps = brun.run(os.path.join(work, 'CRTEST.CODE'))
        raw = open(os.path.join(ps.out, 'transcript.txt'), 'rb').read().decode('latin1')
    finally:
        shutil.rmtree(work, True)
    i = raw.find(' 1 ')
    got = raw[i:raw.find('Command:', i)] if i >= 0 else raw
    want = ' 1 \n 2 \n 3 \nend\n\nx\ny\n\nz\n\n'
    good = ok and got == want
    print('crtest: %s' % ('PASSED' if good else 'FAILED: %r (want %r)' % (got, want)))
    return 0 if good else 1


if __name__ == '__main__':
    sys.exit(main())
