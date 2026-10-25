# UCSD-BASIC: a BASIC compiler for the UCSD Pascal II.0 P-System, written in BASIC

BC compiles a modern BASIC (SUB and FUNCTION, optional line numbers, INTEGER /
BYTE / SINGLE / DOUBLE / STRING, multi-dimensional arrays from element 0,
block IF, SELECT CASE, DO/LOOP, WHILE, FOR (30 deep), GOSUB (50 deep), DATA,
files) into P-code `.CODE` files that run on the P-System.  It is written in
that same BASIC and **compiles itself on the P-System, byte for byte the same
as the host build** (`tools/selfcompile.py`).

## Layout

| Path | What |
|---|---|
| `bc/` | the compiler: `bc` driver, `bclex` pass 1 (tokens, comments dropped), `bcdecl` pass 2 (declarations), `bcgen`/`bcexpr`/`bcemit` pass 3 (code, object file), `bclist` listing (each BASIC statement with its P-code), `bclink` linker |
| `lib/` | the run-time library BASLIB, in BASIC (heap, strings, arrays, PRINT/INPUT, UCSD text and byte files, DATA) |
| `tests/` | test programs and their expected output (`subvol.dirs`: the sub-volumes that test needs) |
| `demos/` | the example programs of the volume's DEMO/ |
| `tools/` | `bas2c.py` + `hostrt.h` (the bootstrap: BC's BASIC translated to C), `buildhost.sh`, `mklib.sh`, `mkself.sh`, `runtests.py`, `selfcompile.py`, `brun.py`, `objdump.py`, `pdis.py` |

## The volume BASIC:

`tools/mkvolume.py` makes `build/BASIC.BLK` (also in UCSD-Pascal-Volumes'
BLK_format), laid out in sub-volumes (Tiny-C's: data files holding a volume,
`BASIC:/SRC/BC.TEXT`):

| File | What |
|---|---|
| `BC.CODE` | the compiler |
| `README.TEXT`, `LANGUAGE.TEXT`, `DESIGN.TEXT` | the manuals |
| `ALL.TEXT` | `@BASIC:ALL`: the four batch files below |
| `FILES.TEXT` | every file, the sub-volumes' too |
| `SRC/` | the compiler's sources; `BUILD.TEXT`: `@BASIC:/SRC/BUILD` rebuilds the compiler as BASIC:BC2.CODE |
| `LIB/` | `BASLIB.OBJ`, the run-time library, and its sources; `LIBS.TEXT`: `@BASIC:/LIB/LIBS` rebuilds it as BASIC:/LIB/BASLIB2.OBJ |
| `DEMO/` | HELLO, PRIMES, HANOI, MANDEL, GUESS and STATS (two modules: STATS + STATLIB); `DEMOS.TEXT` compiles them |
| `TEST/` | the compiler's tests; `TESTS.TEXT` compiles them; `EXPECT/` what each prints |

`tools/voltest.py` checks it (`--pascal`: under SYSTEM.PASCAL).

Documentation: [docs/LANGUAGE.md](docs/LANGUAGE.md) (the language and the
compiler's use) and [docs/DESIGN.md](docs/DESIGN.md) (how BC works).

## Using BC on the P-System

`X(ecute BC`, then at "Compile what file?" (or as the command line from Tiny-C's shell):

* `NAME` — compile NAME.TEXT and link NAME.CODE (NAME may be a path: `BASIC:/DEMO/HELLO`;
  the object and code file go beside the source)
* `-C NAME` — compile only (NAME.OBJ); `-S NAME` — also a listing NAME.LST.TEXT
* `-L OUT=A,B,C` — link several modules (and BASLIB.OBJ) into OUT.CODE
* `-J LIB=A,B` — join object files into a library
* `@FILE` — the commands in FILE.TEXT; `-M` — memory report

Modules share variables with `COMMON SHARED`, call each other's procedures
after `DECLARE`; `SEGMENT name` puts the following procedures in a code
segment of their own.  BC needs the emulator's Harvard layout (its default);
it works under SYSTEM.PASCAL and SYSTEM.C, and from Tiny-C's shell
(`BASIC:BC -C PROG`: COMMAND$, exit status 0 or 1).  Programs open files in
sub-volumes by their paths (`OPEN "BASIC:/DEMO/X.TEXT" ...`), and a code file
in one runs with `X(ecute BASIC:/DEMO/HELLO`.

## Building and testing (Linux)

```
tools/setup.sh          # the emulator runner (needs the sibling emulator / Tiny-C checkouts)
tools/buildhost.sh      # build/bc: the host build (bas2c.py + gcc)
tools/mklib.sh          # build/BASLIB.OBJ
tools/mkself.sh         # build/BC.CODE
python3 tools/runtests.py
python3 tools/selfcompile.py   # BC and BASLIB rebuilt on the P-System: IDENTICAL
python3 tools/mkvolume.py && python3 tools/voltest.py   # build/BASIC.BLK, checked (also --pascal)
```
