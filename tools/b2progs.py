#!/usr/bin/env python3
"""b2progs.py -- B2's programs and their modules (the first one each program's main module), for
the build tools (buildb2.sh, mkself2.sh, mkvolume2.py, b2self.py ...).

  b2progs.py            prints PROG=MOD,MOD,... a line each (the programs built so far)
  b2progs.py modules    prints every module, once
"""
import os, sys

PROGS = [('B2', ['B2', 'B2UTIL']),                                       # the driver
         ('B2LEX', ['B2LEX', 'B2KW', 'B2UTIL']),                         # pass 1: tokens
         ('B2CONST', ['B2CONST', 'B2IO', 'B2UTIL']),                     # 1b: names, CONSTs, counts
         ('B2SYN', ['B2SYN', 'B2IO', 'B2UTIL']),                         # 2: the statements' syntax
         ('B2DECL', ['B2DECL', 'B2SYMT', 'B2IO', 'B2UTIL']),             # 3: declarations
         ('B2NAME', ['B2NAME', 'B2SYMT', 'B2IO', 'B2UTIL']),             # 4: names
         ('B2EXPR', ['B2EXPR', 'B2EXGEN', 'B2IO', 'B2UTIL']),            # 5: expressions
         ('B2CTL', ['B2CTL', 'B2IO', 'B2UTIL']),                         # 6: control structures
         ('B2STMT', ['B2STMT', 'B2IO', 'B2UTIL']),                       # 7: the other statements
         ('B2ASM', ['B2ASM', 'B2IO', 'B2UTIL']),                         # 8: the object file
         ('B2LIST', ['B2LIST', 'B2UTIL']),                               # the listing
         ('B2LINK', ['B2LINK', 'B2UTIL']),                               # the linker
         ('B2ERR', ['B2ERR', 'B2KW', 'B2UTIL']),                         # a compile's errors
         ('B2DEBUG', ['B2DEBUG']),                                       # a run-time error's line
         ('B2DUMP', ['B2DUMP', 'B2IO', 'B2KW', 'B2UTIL'])]               # a pass's file as text (-K)
_here = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'b2')
PROGS = [(p, m) for p, m in PROGS if all(os.path.exists(os.path.join(_here, x.lower() + '.bas')) for x in m)]
MODS = []
for _p, _m in PROGS:
    MODS += [m for m in _m if m not in MODS]

if __name__ == '__main__':
    if sys.argv[1:] == ['modules']:
        print(' '.join(MODS))
    else:
        for p, m in PROGS:
            print('%s=%s' % (p, ','.join(m)))
