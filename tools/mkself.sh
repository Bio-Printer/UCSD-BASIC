#!/bin/sh
# mkself.sh -- build/BC.CODE, BCLEX.CODE, BCGEN.CODE, BCLIST.CODE, BCLINK.CODE: BC's sources compiled
# and linked by the host BC
set -e
cd "$(dirname "$0")/.."
mkdir -p build/self
cp bc/*.bas build/self/
cp build/BASLIB.OBJ build/self/
cd build/self
for m in $(python3 ../../tools/bcprogs.py modules); do ../bc -Q -C $m; done
for pm in $(python3 ../../tools/bcprogs.py); do ../bc -Q -L $pm; done
for pm in $(python3 ../../tools/bcprogs.py); do cp ${pm%%=*}.CODE ..; done
