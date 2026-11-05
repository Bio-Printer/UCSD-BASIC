#!/bin/sh
# mkself2.sh -- build/B2.CODE, B2LEX.CODE ... B2DEBUG.CODE (and their maps): B2's sources compiled
# and linked by the host B2, with B2's library build/BASLIB2.OBJ (tools/mklib2.sh)
set -e
cd "$(dirname "$0")/.."
mkdir -p build/self2
cp b2/*.bas build/self2/
cp build/BASLIB2.OBJ build/self2/BASLIB.OBJ
cd build/self2
for m in $(python3 ../../tools/b2progs.py modules); do ../b2/b2 -Q -C $m; done
for pm in $(python3 ../../tools/b2progs.py); do ../b2/b2 -Q -MAP -L $pm; done
for pm in $(python3 ../../tools/b2progs.py); do cp ${pm%%=*}.CODE ${pm%%=*}.MAP ..; done
