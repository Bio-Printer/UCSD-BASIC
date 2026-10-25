#!/usr/bin/env python3
"""brun.py -- run a code file on the P-System (the emulator, P-Code mode).

  brun.py NAME.CODE [FILE ...] [--keys TEXT]

The code file (and the other files) are put on WORK: (unit #5); the
program is started with X(ecute and the console transcript printed, from
the program's start to the Command: prompt after it.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psys, ucsdvol


def read_dirs(path):
    """a test's sub-volumes: lines DIR PATH BLOCKS, TEXT PATH LINE"""
    out = []
    for l in open(path):
        w = l.split(None, 2)
        if w and not w[0].startswith('#'):
            out.append((w[0], w[1].upper(), w[2].rstrip('\n') if len(w) > 2 else ''))
    return out


def make_dirs(v, dirs, pre=''):
    """the sub-volumes and files under pre (A/) of dirs, written into the Volume v"""
    for kind, path, arg in dirs:
        if not path.startswith(pre) or '/' in path[len(pre):]:
            continue
        name = path[len(pre):]
        if kind == 'DIR':
            sub = ucsdvol.Volume.new(name, int(arg))
            make_dirs(sub, dirs, path + '/')
            v.write(name, sub.image(), 5)
        else:
            v.write(name, ucsdvol.text_to_ucsd(arg + '\n'), 3)


def list_dirs(ps, dirs):
    """after the run: each sub-volume's files, NAME BLOCKS KIND, and the text files' lines"""
    v = ucsdvol.Volume(os.path.join(ps.out, 'VERIFY_SOURCE.BLK'))
    out = []

    def walk(v, pre):
        for first, last, kind, name, lastbyte, date in sorted(v.entries, key=lambda e: e[3]):
            if pre + name in [p for k, p, a in dirs if k == 'DIR']:
                out.append('-- %s%s/ %d' % (pre, name, v.eov if False else last - first))
                walk(v.sub(name), pre + name + '/')
            elif pre or name.endswith('.BAS'):
                out.append('-- %s%s %d %d' % (pre, name, last - first, kind & 15))
    walk(v, '')
    return '\n'.join(out) + '\n'


def run(code, files=(), keys='', timeout=120, dirs=None):
    ps = psys.PSystem()
    if dirs:
        v = ucsdvol.Volume(ps.src)
        make_dirs(v, dirs)
        v.save()
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
    if keys:
        # (the runner types only while the program waits for a key)
        script += 'TYPE "%s"\n' % psys.esc(keys.replace('\n', '\r') + '\r')
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
