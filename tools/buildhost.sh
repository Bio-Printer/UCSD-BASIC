#!/bin/sh
# buildhost.sh -- the host (Linux) build of BC: bas2c.py, then gcc -> build/bc
set -e
cd "$(dirname "$0")/.."
M="bc/bc.bas bc/bclex.bas bc/bcdecl.bas bc/bcgen.bas bc/bcexpr.bas bc/bcemit.bas bc/bclist.bas bc/bclink.bas"
python3 tools/mkdecls.py $M > bc/bcprocs.bas
mkdir -p build
python3 tools/bas2c.py -o build/bc.c $M
gcc -O1 -w -I tools -o build/bc build/bc.c -lm
# a source line must fit LINE INPUT (255 characters): the P-System's BC reads them so
awk 'length > 250 { print FILENAME ":" FNR ": line too long"; bad = 1 } END { exit bad }' bc/*.bas lib/*.bas
