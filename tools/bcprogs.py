#!/usr/bin/env python3
"""bcprogs.py -- the programs of the compiler and their modules (the first one each program's main
module), for the build tools (buildhost.sh, mkself.sh, mkvolume.py, selfcompile.py, voltest.py).

  bcprogs.py            prints PROG=MOD,MOD,... a line each
  bcprogs.py modules    prints every module, once
"""
import sys

PROGS = [('BC', ['BC', 'BCUTIL']),                                       # the driver
         ('BCLEX', ['BCLEX', 'BCKW', 'BCUTIL']),                         # pass 1
         ('BCGEN', ['BCGEN', 'BCDECL', 'BCEXPR', 'BCEMIT', 'BCTOK', 'BCKW', 'BCUTIL']),   # passes 2, 3
         ('BCLIST', ['BCLIST', 'BCUTIL']),                               # the listing
         ('BCLINK', ['BCLINK', 'BCUTIL'])]                               # the linker
MODS = []
for _p, _m in PROGS:
    MODS += [m for m in _m if m not in MODS]

if __name__ == '__main__':
    if sys.argv[1:] == ['modules']:
        print(' '.join(MODS))
    else:
        for p, m in PROGS:
            print('%s=%s' % (p, ','.join(m)))
