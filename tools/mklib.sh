#!/bin/sh
# mklib.sh -- build/BASLIB.OBJ: the run-time library compiled by the host BC
set -e
cd "$(dirname "$0")/.."
mkdir -p build/lib
cp lib/*.bas build/lib/
cd build/lib
M="RTCORE RTFILE RTSTR RTNUM RTARR RTINPUT RTDATA RTSUBV"
for m in $M; do ../bc -Q -C $m; done
../bc -Q -J BASLIB=$(echo $M | tr ' ' ,)
cp BASLIB.OBJ ..
