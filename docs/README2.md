# B2: the second BASIC compiler for the UCSD Pascal II.0 P-System

B2 compiles the same BASIC as BC (LANGUAGE.TEXT), plus `#DEFINE`, `#UNDEF`,
`#IFDEF`, `#IFNDEF`, `#ELSE` and `#ENDIF`, into the same P-code `.CODE`
files, with the same run-time library, run-time error messages (the file
and line, from NAME.MAP) and batch files.  What is new is how it works:
many small passes, each a program of its own with all of memory for its
tables, so that memory is never tight -- B2 compiles and links itself in
the emulator's Z80 mode (B2DESIGN.TEXT).

## Using B2

`X(ecute BASIC2:B2`, then at "Compile what file?" (or as the command line
from Tiny-C's shell: `BASIC2:B2 -C PROG`):

* `NAME` -- compile NAME.BAS (or NAME.TEXT) and link NAME.CODE (NAME may be a path)
* `-C NAME` -- compile only (NAME.OBJ); `-S NAME` -- also a listing NAME.LST
* `-L OUT=A,B,C` -- link several modules (and BASLIB.OBJ) into OUT.CODE
* `-J LIB=A,B` -- join object files into a library
* `-MAP` -- the links after it write NAME.MAP: a run-time error says its line
* `-D A,B` -- the compiles after it have A and B #DEFINEd (B2 is always)
* `-K` -- keep each pass's file: NAME.W0 ... NAME.W7, the tokens and what
  each pass made of them, the BASIC lines in them (B2DUMP shows one as text)
* `@FILE` -- the commands in FILE.TEXT; `-M` -- each pass's memory; `-Q` fewer messages

```
#IFDEF DEBUG
PRINT "x ="; x
#ENDIF
```
compiles the PRINT only with `B2 -D DEBUG PROG` or after `#DEFINE DEBUG`.
The lines skipped are not read as BASIC; #IFDEFs nest 8 deep, through
#INCLUDE files too.

## BASIC2:/MAP

-MAP's files go into the sub-volume BASIC2:/MAP, not beside your program,
and -K's into the sub-volumes in it, one for each pass: NAME.W0 into
BASIC2:/MAP/W0, NAME.W1 into BASIC2:/MAP/W1 ... (when BASIC2: is not on
line, or has no MAP, beside the source and the code file as before).  A
whole `MAKE -B -f BASIC2:/SRC/MAKEFILE FLAGS=-K` fits: each Wn holds 1500 blocks, B2's
21 modules take 1040 to 1250 of them.  Each names the source it was made from, with its
volume's name (`WORK:/A/PROG.BAS`, not `#5:` or the prefix).  Two programs
of one name on two volumes share MAP's NAME.MAP: its first lines say whose
it is.  A sub-volume holds 77 files: delete the ones you are done with.  A
program that fills its disk stops with "Run-time error 61: Disk full".

| File | What is in it | Shown with |
|---|---|---|
| `NAME.MAP` (-MAP) | the code file; each module, its source and object file; the library; then each segment (S#), its procedures (P#) with their lengths, and each line's code offset (I#:N, after `FILE NAME.BAS`) | in the shell: `TYPE BASIC2:/MAP/NAME.MAP`; B2DEBUG reads it after a run-time error |
| `NAME.W0` | B2LEX's tokens: each line's text, its tokens, #INCLUDE files, #IFDEFs done | in the shell: `B2DUMP NAME.W0` (or `X(ecute BASIC2:B2DUMP`, then `NAME.W0`) writes NAME.D0 beside the source (`B2DUMP -MAP NAME.W0`: into BASIC2:/MAP/D0); then `TYPE` it |
| `NAME.W1` | B2CONST's: CONSTs replaced by their values, DECLAREs never used marked, the header's table counts | `B2DUMP NAME.W1` |
| `NAME.W2` | B2SYN's: every statement in its parts, expressions and targets marked out | `B2DUMP NAME.W2` |
| `NAME.W4` | B2NAME's: every name resolved (variable, array, procedure, built-in, label), the module's body first, then the procedures | `B2DUMP NAME.W4` |
| `NAME.W5` | B2EXPR's: every expression and target compiled to P-code, with its type | `B2DUMP NAME.W5` |
| `NAME.W6` | B2CTL's: IF, loops, SELECT, GOTO, GOSUB as jumps and labels | `B2DUMP NAME.W6` |
| `NAME.W7` | B2STMT's: all of it P-code and the library's calls, for B2ASM | `B2DUMP NAME.W7` |

(There is no NAME.W3: B2DECL writes the module's declarations to a
temporary symbol file.)  Each W file starts with the source's path; B2DUMP
looks for a NAME.Wn named without a volume in BASIC2:/MAP/Wn (and BASIC2:/MAP) too.  It
writes NAME.Dn beside the module's source (the path the W file names: `BASIC2:/SRC/B2LEX.D0`),
or, with `-MAP`, into BASIC2:/MAP/Dn (`B2DUMP -MAP NAME.W0`); when the source is not on line,
beside the W file.  An old dump is replaced.

A whole build, every pass of every module, as text: in the shell,

```
MAKE -B -f BASIC2:/SRC/MAKEFILE FLAGS=-K
MAKE -f BASIC2:/SRC/MAKEFILE DUMPALL
```

DUMPALL (a target of that makefile) runs `B2DUMP -MAP` on each of the 140 W files (beside the sources
they would be more than SRC's 77 files); the dumps fill MAP/D0 ... D7
(1900 blocks each, 1360 to 1810 of them for B2's build).  Options > Export
File > Export All in the emulator (2.12) copies MAP, or the whole volume,
to a Windows folder, the dumps as Windows text.  On the host, `tools/b2dump.py NAME.W5` shows the same.

## The volume

| File | What |
|---|---|
| `B2.CODE` | the compiler's driver; `B2LEX`, `B2CONST`, `B2SYN`, `B2DECL`, `B2NAME`, `B2EXPR`, `B2CTL`, `B2STMT`, `B2ASM` its passes, `B2LIST` (the listing), `B2LINK` (the linker), `B2ERR` (a compile's errors), `B2DEBUG` (where a run-time error was), `B2DUMP` (shows a -K file) |
| `MAP/` | their maps (B2.MAP ...) and what -MAP makes; `MAP/W0` ... `MAP/W7` what -K makes, `MAP/D0` ... `MAP/D7` B2DUMP's dumps of them |
| `MAKEFILE.TEXT` | `MAKE -f BASIC2:MAKEFILE` (Tiny-C's MAKE, on TOOLS:, from the shell): the MAKE of the four makefiles below, each compiling only what changed (`MAKE -B ...`: everything); `MAKE -f BASIC2:MAKEFILE INSTALL` |
| `SRC/` | B2's sources; `MAKE -f BASIC2:/SRC/MAKEFILE` rebuilds it as BASIC2:B22.CODE, B2LEX2.CODE ...; its target INSTALL puts the rebuilt compiler in the old one's place; DUMPALL dumps a `-K` build's files (above) |
| `LIB/` | BASLIB.OBJ (compiled by B2) and its sources; its MAKEFILE.TEXT rebuilds it |
| `DEMO/`, `TEST/` | the demos and the tests; their MAKEFILE.TEXT compiles them |

B2's programs are named B2*, so they and BASIC:'s BC can be on one disk.
A program B2 compiled looks for B2DEBUG.CODE (beside it, on the prefix,
the boot disk, BASIC2:) when it stops with a run-time error.
