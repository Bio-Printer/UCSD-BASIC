#!/bin/sh
# buildhost.sh -- the host (Linux) build of BC: bas2c.py, then gcc -> build/bc, build/bclex, build/bcgen,
# build/bclist, build/bclink (the compiler's five programs; CHAIN runs one beside the other)
set -e
cd "$(dirname "$0")/.."
ALL=$(python3 tools/bcprogs.py modules | tr 'A-Z' 'a-z' | sed 's|\([a-z]*\)|bc/\1.bas|g')
python3 tools/mkdecls.py $ALL > bc/bcprocs.bas
mkdir -p build
python3 tools/bcprogs.py | while IFS== read p m; do
    lp=$(echo $p | tr 'A-Z' 'a-z')
    files=$(echo $m | tr 'A-Z,' 'a-z ' | sed 's|\([a-z]*\)|bc/\1.bas|g')
    python3 tools/bas2c.py -o build/$lp.c $files
    gcc -O1 -w -I tools -o build/$lp build/$lp.c -lm
done
# a source line must fit LINE INPUT (255 characters): the P-System's BC reads them so
awk 'length > 250 { print FILENAME ":" FNR ": line too long"; bad = 1 } END { exit bad }' bc/*.bas lib/*.bas
