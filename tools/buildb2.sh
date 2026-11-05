#!/bin/sh
# buildb2.sh -- the host (Linux) build of B2: bas2c.py, then gcc -> build/b2/b2, b2lex, b2syn ...
# (B2's programs; CHAIN runs one beside the other)
set -e
cd "$(dirname "$0")/.."
ALL=$(python3 tools/b2progs.py modules | tr 'A-Z' 'a-z' | sed 's|\([a-z0-9]*\)|b2/\1.bas|g')
python3 tools/mkdecls.py $ALL | sed 's/BCPROCS/B2PROCS/' > b2/b2procs.bas
mkdir -p build/b2
python3 tools/b2progs.py | while IFS== read p m; do
    lp=$(echo $p | tr 'A-Z' 'a-z')
    files=$(echo $m | tr 'A-Z,' 'a-z ' | sed 's|\([a-z0-9]*\)|b2/\1.bas|g')
    python3 tools/bas2c.py -o build/b2/$lp.c $files
    gcc -O1 -w -I tools -o build/b2/$lp build/b2/$lp.c -lm
done
# a source line must fit LINE INPUT (255 characters): the P-System's B2 reads them so
awk 'length > 250 { print FILENAME ":" FNR ": line too long"; bad = 1 } END { exit bad }' b2/*.bas
