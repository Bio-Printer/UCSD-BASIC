#!/usr/bin/env python3
"""brun.py -- run a code file on the P-System (the emulator, P-Code mode).

  brun.py NAME.CODE [FILE ...] [--keys TEXT]

The code file (and the other files) are put on WORK: (unit #5); the
program is started with X(ecute and the console transcript printed, from
the program's start to the Command: prompt after it.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psys


def run(code, files=(), keys='', timeout=120):
    ps = psys.PSystem()
    name = os.path.basename(code).upper()
    ps.put(name, open(code, 'rb').read())
    for f in files:
        n = os.path.basename(f).upper()
        if n.endswith('.BAS'):
            n = n[:-4] + '.TEXT'
        data = open(f, 'rb').read()
        ps.put(n, data.decode('latin1') if n.endswith('.TEXT') else data)
    base = name[:-5]
    script = 'WAIT "Command:"\nTYPE "X"\nWAIT "Execute what file?"\nTYPE "#5:%s\\r"\n' % base
    for k in keys.split('\n') if keys else []:
        script += 'WAIT "?"\nTYPE "%s\\r"\n' % psys.esc(k)
    script += 'WAIT "Command:"\n'
    ok, tr, info = ps.run_script(script, timeout)
    i = tr.find('#5:%s' % base)
    out = tr[i + len(base) + 3:] if i >= 0 else tr
    j = out.rfind('Command:')
    if j >= 0:
        out = out[:j]
    # the transcript shows each CR as two new lines
    out = out.replace('\r\n', '\n').replace('\r', '\n').replace('\n\n', '\n')
    if out.startswith('\n'):
        out = out[1:]
    return ok, out, info, ps


if __name__ == '__main__':
    a = sys.argv[1:]
    keys = ''
    if '--keys' in a:
        i = a.index('--keys')
        keys = a[i + 1]
        del a[i:i + 2]
    ok, out, info, ps = run(a[0], a[1:], keys)
    sys.stdout.write(out)
    if not ok:
        print('--- not completed:', info[-500:])
