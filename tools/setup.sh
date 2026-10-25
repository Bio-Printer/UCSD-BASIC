#!/bin/bash
# setup.sh -- build/psys: the P-System emulator's Linux runner (run_verify) and
# the boot disk, from a checkout of UCSD-Pascal_Windows_Emulator and the boot
# disk images of UCSD-TinyC (or UCSD-Pascal-Volumes):
#   ENGINE_DIR=/path/to/UCSD-Pascal_Windows_Emulator  (default ../ucsd-pascal_windows_emulator)
#   IMAGES_ZIP=/path/to/Usefull_System_Disk_Images.zip (default ../ucsd-tinyc/Usefull_System_Disk_Images.zip)
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ENGINE_DIR=${ENGINE_DIR:-$ROOT/../bio-printer/ucsd-pascal_windows_emulator}
IMAGES_ZIP=${IMAGES_ZIP:-$ROOT/../bio-printer/ucsd-tinyc/Usefull_System_Disk_Images.zip}
# the boot disk: BIGGY of UCSD-Pascal-Volumes (SYSTEM.C, the Tiny-C shell), else the images zip's
BOOT_DISK=${BOOT_DISK:-$ROOT/../bio-printer/ucsd-pascal-volumes/BLK_format/Big_Disk.BLK}
B=build/psys
mkdir -p $B/data $B/img
if [ ! -f $B/img/Big_Disk.BLK ]; then (cd $B/img && unzip -q -o "$IMAGES_ZIP"); fi
if [ ! -f $B/data/Big_Disk.BLK ]; then
    if [ -f "$BOOT_DISK" ]; then cp "$BOOT_DISK" $B/data/Big_Disk.BLK; else cp $B/img/Big_Disk.BLK $B/data/Big_Disk.BLK; fi
fi
[ -f $B/data/pascal.bin ] || head -c 4096 /dev/zero > $B/data/pascal.bin
if [ ! -x $B/run_verify ]; then
    g++ -std=c++17 -O2 -w -I "$ENGINE_DIR/verify/linux-shim" -I "$ENGINE_DIR/UCSDPascal" \
        -o $B/run_verify "$ENGINE_DIR/verify/run_verify.cpp" \
        "$ENGINE_DIR/UCSDPascal/PSystemEngine.cpp" "$ENGINE_DIR/UCSDPascal/z80.cpp" -lpthread
fi
echo "setup OK"
