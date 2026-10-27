#!/usr/bin/env python3
"""importtest.py -- the emulator's Import File and Export File with a BASIC source (emulator
2.10): demos/pi.bas as a Windows file (CR LF; more than 1K, so a lost first 1K shows) is
imported into #5 before the boot (run_verify's VERIFY_IMPORT: Options > Import File) and must
become a text file, header and all: BC compiles and links #5:PI and PI runs.  When the script
has ended #5:PI.BAS is exported (VERIFY_EXPORT: Options > Export File) and must be the Windows
file again.  build/psys/run_verify must be built from the emulator's sources (tools/setup.sh
builds it again when they are newer).
"""
import os, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import psys, ucsdvol
from bcprogs import PROGS

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


if __name__ == '__main__':
    sys.exit(main())
