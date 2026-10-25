#!/bin/sh
# mkself.sh -- build/BC.CODE: BC's sources compiled and linked by the host BC
set -e
cd "$(dirname "$0")/.."
mkdir -p build/self
cp bc/*.bas build/self/
cp build/BASLIB.OBJ build/self/
cd build/self
M="BC BCLEX BCDECL BCGEN BCEXPR BCEMIT BCLIST BCLINK"
for m in $M; do ../bc -Q -C $m; done
../bc -Q -L BC=$(echo $M | tr ' ' ,)
cp BC.CODE ..
