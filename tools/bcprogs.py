#!/usr/bin/env python3
"""bcprogs.py -- the programs of the compiler and their modules (the first one each program's main
module), for the build tools (buildhost.sh, mkself.sh, mkvolume.py, selfcompile.py, voltest.py).

  bcprogs.py            prints PROG=MOD,MOD,... a line each
  bcprogs.py modules    prints every module, once
"""
import sys

PROGS = [('BC', ['BC', 'BCUTIL']),                                       # the driver
         ('BCLEX', ['BCLEX', 'BCKW', 'BCUTIL']),                         # pass 1
         ('BCGEN', ['BCGEN', 'BCSTMT', 'BCDECL', 'BCEXPR', 'BCEXGEN', 'BCEMIT', 'BCTOK', 'BCUTIL']),   # passes 2, 3
         ('BCASM', ['BCASM', 'BCUTIL']),                                 # pass 4: the object file
         ('BCLIST', ['BCLIST', 'BCUTIL']),                               # the listing
         ('BCLINK', ['BCLINK', 'BCUTIL']),                               # the linker
         ('BCERR', ['BCERR', 'BCKW', 'BCUTIL']),                         # a compile's errors
         ('BCDEBUG', ['BCDEBUG'])]                                       # a run-time error's line
MODS = []
for _p, _m in PROGS:
    MODS += [m for m in _m if m not in MODS]

if __name__ == '__main__':
    if sys.argv[1:] == ['modules']:
        print(' '.join(MODS))
    else:
        for p, m in PROGS:
            print('%s=%s' % (p, ','.join(m)))
