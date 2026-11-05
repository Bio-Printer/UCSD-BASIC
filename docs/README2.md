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
* `-K` -- keep each pass's file beside the source: NAME.W0 ... NAME.W7, the
  tokens and what each pass made of them, the BASIC lines in them
  (tools/b2dump.py on the host shows one as text)
* `@FILE` -- the commands in FILE.TEXT; `-M` -- each pass's memory; `-Q` fewer messages

```
#IFDEF DEBUG
PRINT "x ="; x
#ENDIF
```
compiles the PRINT only with `B2 -D DEBUG PROG` or after `#DEFINE DEBUG`.
The lines skipped are not read as BASIC; #IFDEFs nest 8 deep, through
#INCLUDE files too.

## The volume

| File | What |
|---|---|
| `B2.CODE` | the compiler's driver; `B2LEX`, `B2CONST`, `B2SYN`, `B2DECL`, `B2NAME`, `B2EXPR`, `B2CTL`, `B2STMT`, `B2ASM` its passes, `B2LIST` (the listing), `B2LINK` (the linker), `B2ERR` (a compile's errors), `B2DEBUG` (where a run-time error was), each with its map |
| `ALL.TEXT` | `@BASIC2:ALL`: the four batch files below |
| `INSTALL.TEXT` | after `@BASIC2:/SRC/BUILD`, in the shell: `@BASIC2:INSTALL` puts the rebuilt compiler in the old one's place |
| `SRC/` | B2's sources; `@BASIC2:/SRC/BUILD` rebuilds it as BASIC2:B22.CODE, B2LEX2.CODE ... |
| `LIB/` | BASLIB.OBJ (compiled by B2) and its sources; `@BASIC2:/LIB/LIBS` rebuilds it |
| `DEMO/`, `TEST/` | the demos and the tests, `DEMOS.TEXT` and `TESTS.TEXT` compile them |

B2's programs are named B2*, so they and BASIC:'s BC can be on one disk.
A program B2 compiled looks for B2DEBUG.CODE (beside it, on the prefix,
the boot disk, BASIC2:) when it stops with a run-time error.
