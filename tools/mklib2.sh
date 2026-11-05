#!/bin/sh
# mklib2.sh -- build/BASLIB2.OBJ: the run-time library compiled by the host B2 (B2's own library)
set -e
cd "$(dirname "$0")/.."
mkdir -p build/lib2
cp lib/*.bas build/lib2/
cd build/lib2
M="RTCORE RTFILE RTSTR RTNUM RTARR RTINPUT RTDATA RTSUBV RTCHAIN RTWHERE"
for m in $M; do ../b2/b2 -Q -C $m; done
../b2/b2 -Q -J BASLIB=$(echo $M | tr ' ' ,)
cp BASLIB.OBJ ../BASLIB2.OBJ
