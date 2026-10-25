# BC BASIC -- the language

BC compiles a modern, QuickBASIC-like BASIC for the UCSD Pascal II.0
P-System.  This is the reference of the language BC accepts; how to run
the compiler is in USAGE (section 13), how it works inside in DESIGN.

Contents:
 1. Program text      2. Types and values    3. Variables and scope
 4. Expressions       5. Arrays              6. SUB and FUNCTION
 7. Statements        8. Built-in functions  9. Strings
10. Files and devices 11. Low-level access  12. Run-time errors
13. Using the compiler  14. Limits         15. Not supported

## 1. Program text

A program is one or more modules (source files).  A module is plain text:
on the P-System NAME.BAS, a text file (the kind the Editor makes), on Linux
a .bas file.  NAME.TEXT is taken as well.  The Editor adds .TEXT to a name
unless it ends with a dot: E(dit PI.BAS. (and the same name with the dot to
save it).  BIGGY 1.29's systems, SYSTEM.PASCAL and SYSTEM.C, make every new
NAME.BAS a text file, as NAME.TEXT; with an older system a .BAS file the
Editor writes is a data file in the directory, which BC reads all the same.

- Lines.  One or more statements a line, separated by colons.  A line
  ending in " _" (blank, underscore) goes on in the next line.  A source
  line may be at most 255 characters long.
- Case.  Keywords and names may be written in any case: Print, PRINT and
  print are the same, and so are Count and COUNT.
- Comments.  An apostrophe ' starts a comment that runs to the end of the
  line, and so does REM at the start of a statement.  Comments are dropped
  by the compiler's first pass.
- Line numbers and labels are optional.  A number at the start of a line,
  or a name followed by a colon at the start of a line, is a label:

      100 PRINT "a numbered line"
      again: PRINT "a named label"

  A label belongs to the procedure (or the module's body) it is in.
- `#INCLUDE "FILE"` puts the text of FILE.BAS (or FILE.TEXT) in place of the line
  (looked for beside the source first -- on its volume, in its
  sub-volume -- then as named, on the prefix volume).
  Include files may be nested 3 deep.
- `?` is short for PRINT.

Names: a letter or _ first, then letters, digits and _, then optionally
one type suffix: % INTEGER, ! SINGLE, # DOUBLE, $ STRING.  A name may not
be a keyword (but a keyword with a suffix, as in STRING$, is a name).
Names that start with an underscore are used by the run-time library.

Keywords: AND ANDALSO APPEND AS BINARY BYREF BYTE BYVAL CALL CASE CLOSE CLS
COMMON CONST CONTINUE DATA DECLARE DEFDBL DEFINT DEFSNG DEFSTR DIM DO
DOUBLE ELSE ELSEIF END ERASE ERROR EXIT EXPLICIT FOR FUNCTION GET GOSUB
GOTO IF INPUT INTEGER IS KILL LET LINE LOCATE LOOP MOD NEXT NOT ON OPEN
OPTION OR ORELSE OUTPUT PRESERVE PRINT PRIVATE PUT RANDOM RANDOMIZE READ
REAL REDIM RESTORE RESUME RETURN SEEK SEGMENT SELECT SHARED SINGLE STATIC
STEP STOP STRING SUB SWAP SYSTEM THEN TO UNTIL USING WEND WHILE WRITE XOR
(ANDALSO and ORELSE are recognized as operators.)

Numbers:
- 123, -5: INTEGER when they fit in 16 bits (-32768..32767).
- &HFF, &O17, &B101: hexadecimal, octal, binary INTEGERs (16 bits:
  &HFFFF is -1).
- 1.5, 2E10, .25: SINGLE.  A number with more than 7 significant digits,
  a D exponent (1.5D300) or the suffix # is DOUBLE.  Suffix ! makes a
  SINGLE, % an INTEGER.  A whole number too big for an INTEGER is SINGLE.

Strings: "text in double quotes".  There is no escape character: a
quotation mark inside a string is CHR$(34).  A string not closed ends at
the end of the line.

## 2. Types and values

- INTEGER: 16 bits, -32768..32767.  Arithmetic wraps around (32767 + 1
  is -32768); there is no overflow error.
- BYTE: 0..255.  A BYTE variable is stored in a word, a BYTE array
  element in one byte; a value stored is cut to its low 8 bits.  In
  expressions a BYTE is an INTEGER.
- SINGLE (also REAL): the P-machine's 4-byte real, about 7 digits,
  magnitude up to about 1.7E38.
- DOUBLE: 8-byte IEEE floating point, 15-16 digits, up to about 1E308
  (the emulator's double-precision CSPs: P-Code mode, or Z80 mode with the
  coprocessor).
- STRING: 0 to 255 characters.

The type of a variable comes from, in this order: an AS clause
(`DIM n AS INTEGER`), its suffix (`n%`), or the DEFtype statement for
its first letter:

    DEFINT A-Z          ' names without a suffix are INTEGERs
    DEFDBL D, X-Z       ' ... except these
    DEFSTR S

Without any DEFtype a name without a suffix is SINGLE.  A name declared
AS a type may also be written with that type's suffix (`DIM s AS STRING`:
s and s$ are the same).  n%, n! and n$ are three different variables.

Truth: comparisons and the logical operators give -1 for true and 0 for
false.  IF, WHILE, UNTIL and the other conditions take any number: 0 is
false, anything else true.

Conversion between the number types is automatic.  A real stored in an
INTEGER is rounded to the nearest whole number (a half away from 0);
CINT does the same, FIX and INT cut.  Numbers and strings never convert
by themselves: use STR$ and VAL.

## 3. Variables and scope

A variable need not be declared: using a name makes the variable, with
the value 0 or "".  `OPTION EXPLICIT` at the top of a module makes the
use of an undeclared variable an error.

- Module level.  Variables of the module's body (the statements outside
  every SUB and FUNCTION) belong to the module.  They are seen in the
  module's procedures only when declared `DIM SHARED`.
- Locals.  A variable of a SUB or FUNCTION is local to it and starts at
  0 or "" on every call.  `STATIC x` keeps its value between calls.
  `SHARED x` inside a procedure lets it use the module variable x.
- Several modules.  `COMMON SHARED x, a()` makes x and the array a common
  to every module that says so (a header file with the COMMON SHARED
  lines is the usual way: #INCLUDE it everywhere).
- Constants.  `CONST MAX = 100, NAME$ = "x", PI = 3.14159` (integer,
  real and string constants; integer constants may be expressions of
  other constants).  A CONST at module level is seen in every procedure
  of the module.

DIM declares variables explicitly:

    DIM i, j AS INTEGER, s$, buf AS STRING
    DIM SHARED total#, names$(100)

## 4. Expressions

Operators, from the highest priority to the lowest:

    ^                   power (the result is SINGLE or DOUBLE)
    -  +                unary minus and plus
    *  /                times; / is always real division
    \                   integer division, the result cut toward 0
    MOD                 remainder (the sign of the left operand)
    +  -                add, subtract; + also joins strings
    &                   joins strings
    =  <>  <  >  <=  >= comparisons (numbers or strings)
    NOT                 bitwise complement (of an INTEGER)
    AND  ANDALSO        bitwise and; ANDALSO: both conditions, the
                        second only evaluated when the first is true
    OR   ORELSE         bitwise or; ORELSE: the second only when the
                        first is false
    XOR                 bitwise exclusive or

The operands of \ MOD AND OR XOR NOT are converted to INTEGER.  Mixed
INTEGER, SINGLE and DOUBLE operands are converted to the widest.  Strings
compare character by character (by their codes), a shorter string before
a longer one it begins.  AND and OR evaluate both sides: write
`IF i <= n ANDALSO a(i) = x` when the second test must not run.

## 5. Arrays

    DIM a(10)                ' 11 elements, a(0) .. a(10)
    DIM m(3, 4) AS DOUBLE    ' 4 x 5
    DIM b(511) AS BYTE       ' bytes
    DIM grid(n, n)           ' bounds may be expressions

Every dimension's index starts at 0; DIM gives the highest index.  An
array may have up to 8 dimensions and at most 32000 bytes.  Indexes are
checked: one out of its range stops the program (run-time error 9).

- `REDIM a(20)` gives an array new bounds (its elements are 0 / "");
  `REDIM PRESERVE a(20)` keeps the elements that are still there.
- `ERASE a` gives an array's memory back.
- `UBOUND(a)`, `UBOUND(m, 2)`: the highest index of a dimension;
  LBOUND is always 0.
- An array is passed to a procedure whole: `Total a()` (the procedure's
  parameter is written `v()`); it is passed by reference.
- An array must be DIMmed before it is used (there is no automatic
  10-element array).

## 6. SUB and FUNCTION

    SUB Greet (who$, BYREF count)
        PRINT "Hello, "; who$
        count = count + 1
    END SUB

    FUNCTION Fact# (n)
        IF n <= 1 THEN RETURN 1
        RETURN n * Fact#(n - 1)
    END FUNCTION

    FUNCTION Pad (s$, n) AS STRING
        Pad = s$ + SPACE$(n - LEN(s$))
    END FUNCTION

- Parameters are BYVAL by default: the procedure gets a copy.  BYREF
  passes the variable itself (an expression, or a variable of another
  type, is passed as a temporary copy).  Arrays are passed by reference.
- A FUNCTION's result: assign to its name, or `RETURN expression`.  The
  type is the name's suffix, the AS clause, or its DEFtype.
- `EXIT SUB`, `EXIT FUNCTION` return at once.
- Procedures may call themselves (recursion); calls may nest as deep as
  memory allows (50 deep is always possible).
- Calling a SUB: `Greet "Ann", n`, `Greet("Ann", n)` or
  `CALL Greet("Ann", n)`.  A FUNCTION may also be called as a statement
  (its result is dropped).  A call of a FUNCTION without arguments needs
  no parentheses.
- `DECLARE SUB Name (params)` / `DECLARE FUNCTION Name (params) AS type`
  make a procedure of another module known.  Procedures of the module
  being compiled need no DECLARE.
- `PRIVATE SUB` / `PRIVATE FUNCTION`: a procedure only its own module can
  call (two modules may each have a private procedure of the same name).
- `SEGMENT NAME` before procedures puts them into the code segment NAME
  (a UCSD code segment: loaded when called, so a program can be bigger
  than memory); `SEGMENT` alone goes back to the main segment.  A program
  has at most 10 segments.  The module's body is always in the main one.

## 7. Statements

Assignment
- `[LET] var = expression`; `MID$(s$, start[, n]) = t$` replaces
  characters of s$ in place.
- `SWAP a, b` exchanges two variables (or elements) of one type.

Output
- `PRINT [#n,] items` -- items separated by ; (nothing between) or , (to
  the next 14-column zone); TAB(n) moves to column n, SPC(n) prints n
  blanks.  A PRINT that does not end in ; or , ends the line.  A number
  is printed with a blank (or -) before it and a blank after it.
- `WRITE [#n,] items` -- items separated by commas, strings in quotes,
  numbers without blanks, then the end of the line.

Input
- `INPUT ["prompt";] a, b$, ...` -- reads a line and gives its comma
  separated fields to the variables ("quoted" fields may hold commas).
  With ; after the prompt a "? " follows it, with , not.
- `INPUT #n, a, b$` reads them from a file.
- `LINE INPUT ["prompt";] s$` / `LINE INPUT #n, s$` -- a whole line.

Decisions
- `IF cond THEN statements [ELSE statements]` on one line; THEN 100 or
  GOTO 100 jumps to line 100.
- Block IF:

      IF a > b THEN
          ...
      ELSEIF a = b THEN
          ...
      ELSE
          ...
      END IF

- SELECT CASE:

      SELECT CASE n
      CASE 1, 3, 5:  PRINT "odd small"
      CASE 10 TO 20: PRINT "teens"
      CASE IS < 0:   PRINT "negative"
      CASE ELSE:     PRINT "other"
      END SELECT

  The selector may be a number or a string.

Loops
- `FOR v = a TO b [STEP s] ... NEXT [v]` -- the limit and step are
  evaluated once; the loop runs no times when a is past b.  `NEXT i, j`
  closes two loops.  FOR loops may nest 30 deep.
- `DO [WHILE c | UNTIL c] ... LOOP [WHILE c | UNTIL c]`
- `WHILE c ... WEND`
- `EXIT FOR / DO / WHILE / SELECT` leaves the innermost such block;
  `CONTINUE FOR / DO / WHILE` starts its next round.

Jumps
- `GOTO label`, `GOSUB label` ... `RETURN` (within one procedure or the
  module's body; GOSUB nests 50 deep).  RETURN without GOSUBs in the
  procedure leaves the procedure.
- `ON n GOTO l1, l2, ...` / `ON n GOSUB l1, l2, ...` -- to the n-th label
  (nothing when n is not 1..count).

Data
- `DATA 1, 2.5, "text", plain text` -- items for READ (at module level;
  the rest of the line is the DATA).
- `READ a, b$` takes the next items.
- `RESTORE` starts from the module's first DATA again; `RESTORE label`
  from the first DATA after the label.

Program
- `END [n]`, `STOP`, `SYSTEM [n]` -- the program ends (files are closed);
  n is the exit status a program started by Tiny-C's shell returns.
- `RANDOMIZE n` -- start RND's sequence from n.
- `CLS` clears the screen; `LOCATE row, column` moves the cursor (from 1).
- `ON ERROR RESUME NEXT` -- a failing file operation sets ERR instead of
  stopping the program; `ON ERROR GOTO 0` stops that.

Declarations
- DIM, REDIM, ERASE, CONST, STATIC, SHARED, COMMON SHARED, DECLARE,
  DEFINT / DEFSNG / DEFDBL / DEFSTR, OPTION EXPLICIT, SEGMENT (above).

Files
- OPEN, CLOSE, GET, PUT, SEEK, KILL (section 10).

## 8. Built-in functions

Strings
- LEN(s$), ASC(s$[, p]) (the code of character p, 0 when there is none),
  CHR$(n)
- MID$(s$, start[, n]), LEFT$(s$, n), RIGHT$(s$, n)
- INSTR([start,] s$, find$) (0 when not found)
- UCASE$, LCASE$, LTRIM$, RTRIM$, TRIM$
- SPACE$(n), STRING$(n, c) / STRING$(n, "c")
- STR$(x) (a blank before a number that is not negative), VAL(s$) (the
  number at the start of s$, blanks skipped, &H hexadecimal; a DOUBLE),
  HEX$(n)
- MKI$(i), MKS$(x!), MKD$(d#): a number's bytes as a string; CVI, CVS,
  CVD: back.

Numbers
- ABS, SGN, INT (the next lower whole number), FIX (cut toward 0),
  CINT (rounded INTEGER), CSNG, CDBL
- SQR, SIN, COS, TAN, ATN, EXP, LOG (natural): SINGLE, or DOUBLE for a
  DOUBLE argument
- RND (0 <= RND < 1), TIMER (seconds, from the P-machine's clock)

Other
- EOF(n), LOF(n) (always 0), FREEFILE (a free file number), POS(0) (the
  console's column)
- INKEY$ (a key that was typed, or "")
- COMMAND$: the command line, when the program was started by Tiny-C's
  shell (e.g. `BC @BUILD`), without the program's name; "" otherwise
- ERR: the error of the last failing file operation under ON ERROR
  RESUME NEXT (0: none)
- FRE(0): the words of memory free; FRE(-1): the fewest there have been
- LBOUND, UBOUND (section 5)

## 9. Strings

A string holds 0 to 255 characters (longer gives run-time error 15).
Strings are values: `b$ = a$` copies.  A string variable owns its own
memory, given back when the variable is assigned a longer value or goes
away.  The intermediate strings of an expression are made in a string
work area (1.5K) and given back after each statement.

## 10. Files and devices

    OPEN name$ FOR INPUT  | OUTPUT | APPEND | BINARY | RANDOM AS [#]n
    CLOSE [#n [, #m ...]]        ' CLOSE alone: every file
    PRINT #n, ...   WRITE #n, ...   INPUT #n, ...   LINE INPUT #n, s$
    GET #n, [pos], var           PUT #n, [pos], value
    SEEK #n, pos                 EOF(n)          KILL name$

- File numbers are 1..15.  A name is a P-System file name, with a volume
  if wanted: "#5:DATA.TEXT", "WORK:NOTES.TEXT".
- A path names a file in a sub-volume (a data file that holds a volume of
  its own, as Tiny-C's shell's MKDIR makes them): "BASIC:/DEMO/HELLO.TEXT"
  or "BASIC:DEMO/HELLO.TEXT" (HELLO.TEXT in the sub-volume DEMO of the
  volume BASIC:), "#5:/A/B/X.TEXT" (B inside A), "/A/X.TEXT" or
  "A/X.TEXT" (on the prefix volume); \ may be written for /.  Every OPEN
  mode and KILL work there.  A file written in a sub-volume takes its
  largest free area (two written at once share it); it gets its
  directory entry, today's date and its kind (.TEXT text, .CODE code,
  anything else data) when it is closed -- a sub-volume that is too full
  gives run-time error 61 when a file no longer fits (a new file that did
  not fit is not kept).
- A name without a volume, in a program started by Tiny-C's shell after
  a CD into a sub-volume (CD BASIC:/DEMO), is on that path: "PI.BAS" is
  BASIC:/DEMO/PI.BAS, as for the shell's own commands.  Otherwise it is
  on the prefix volume.
- A name ending in .TEXT or .BAS is a UCSD text file (the Editor's format: a
  2-block header, 1K pages, blank compression); PRINT # and LINE INPUT #
  read and write it by lines.  A new one is of the kind text in the
  directory whatever system runs.  Any other file is its bytes; lines in it
  end with CR, and the zero bytes that fill a file's last block end it
  when it is read with INPUT.
- GET and PUT move bytes: a BYTE 1, an INTEGER 2 (low byte first), a
  SINGLE 4, a DOUBLE 8; a string as many bytes as it is long (GET reads
  LEN(var$) bytes into var$).  pos (from 1) sets the position first.
  BINARY opens a file to read and write (made if missing); GET and PUT
  also work on INPUT and OUTPUT files of bytes.
- "CONSOLE:" opens the console as a file.
- A missing file stops the program (run-time error 53) unless
  ON ERROR RESUME NEXT is in force; then ERR says 53.

## 11. Low-level access

For system programming (the run-time library is written with them):

- PEEK(a), PEEKB(a): the word / byte at byte address a; `POKE a, v`,
  `POKEB a, v`.
- VARPTR(var): a variable's address; SADD(s$): a string's address (its
  length byte, then its characters).
- `CSP n, args` and CSP%(n, args), CSP!(...), CSP#(...): the P-machine's
  standard procedure n (an INTEGER, SINGLE or DOUBLE result).
- `OSCALL n, args`, OSCALL%(n, args): procedure n of the operating system
  (CXP 0,n).
- OSVAR(n), OSADDR(n): the value / address of the operating system's
  global word n.
- DVI%(a, b), MDI%(a, b): the P-machine's own DIV and MOD.

## 12. Run-time errors

A run-time error prints "Run-time error N: text" and stops the program.

     3 RETURN without GOSUB        4 Out of DATA
     5 Illegal function call      6 Overflow
     7 Out of memory              9 Subscript out of range
    11 Division by zero          14 Out of string space
    15 String too long           16 GOSUB nesting too deep
    52 Bad file number           53 File not found
    54 Bad file mode             55 File already open
    61 Disk full                 62 Input past end of file
    67 Too many files

Errors the P-machine finds itself (a stack overflow, for example) are
reported by the operating system as usual.

## 13. Using the compiler

On the P-System: `X(ecute BASIC:BC`, then at "Compile what file?" (a
NAME may be a path into sub-volumes: BASIC:/DEMO/HELLO):

    NAME              compile NAME.BAS (or NAME.TEXT), link NAME.CODE
    -C NAME           compile only: NAME.OBJ
    -S NAME           compile with a listing: NAME.LST.TEXT
    -S -C NAME        both
    -L OUT=A,B,C      link A.OBJ, B.OBJ, C.OBJ (and BASLIB.OBJ) into
                      OUT.CODE; the first is the main program
    -J LIB=A,B        join object files into one library LIB.OBJ
    @FILE             the commands in FILE.TEXT
    -Q                fewer messages;  -M  memory use
    (an empty line)   ends BC

Several commands may be given on one line; the first that fails stops
the rest.  From Tiny-C's shell the same commands are BC's command line:
`BC -C MYPROG`.

Files: the source is NAME.BAS (or NAME.TEXT); the object NAME.OBJ is put
beside it (on its volume, in its sub-volume); the code file NAME.CODE
too, and the listing.  The library BASLIB.OBJ is looked for beside the
first object, then on the prefix volume, in BASIC:/LIB, and on the boot
volume.  BC writes its temporary files BCTEMP.TOK, BCTEMP.LST and
BCTEMP.DAT on the prefix volume.  The names in a batch file are as they
would be typed (BASIC:'s batch files name every file with its path).

A code file in a sub-volume runs with X(ecute BASIC:/DEMO/HELLO (BIGGY's
SYSTEM.PASCAL and SYSTEM.C), or from Tiny-C's shell.

The volume BASIC: holds:

    BC.CODE                     the compiler
    README.TEXT LANGUAGE.TEXT DESIGN.TEXT
    ALL.TEXT                    @BASIC:ALL: the four batch files below
    FILES.TEXT                  every file, the sub-volumes' too
    SRC/   BC*.BAS              the compiler's sources;
           BUILD.TEXT           @BASIC:/SRC/BUILD: BASIC:BC2.CODE
    LIB/   BASLIB.OBJ           the run-time library, RT*.BAS its sources;
           LIBS.TEXT            @BASIC:/LIB/LIBS: BASIC:/LIB/BASLIB2.OBJ
    DEMO/  HELLO PRIMES HANOI MANDEL PI GUESS, STATS + STATLIB (two modules);
           DEMOS.TEXT           @BASIC:/DEMO/DEMOS compiles them
    TEST/  the compiler's tests; TESTS.TEXT compiles them,
           EXPECT/NAME.TEXT     what each prints

The sub-volumes have room for what their batch files make; Tiny-C's GROW
(TOOLS:) makes one bigger.

The listing (-S) shows, for every procedure, each BASIC statement
followed by the P-code made for it: offsets within the procedure, calls
and global variables by name, and the entry and exit code.

A program of several modules:

    -C MAIN
    -C UTIL
    -L MAIN=MAIN,UTIL

The body (module-level statements) of every module runs when the program
starts, the main program's (the first module's) last.

BC needs the emulator's Harvard layout (Options > Harvard Mode, the
default, in P-Code mode with Reclaim Z80 Interpreter Memory on): its code
does not fit in the memory of the other layouts.  Started in another one
it says so and stops (exit status 1).  The programs it makes run in any
layout.

## 14. Limits

- A source line: 255 characters.  A string: 255 characters.
- An array: 32000 bytes, 8 dimensions.
- FOR loops nested 30 deep, GOSUB 50 deep, blocks 40 deep.
- A procedure: about 3200 bytes of P-code, 60 far jump targets, 260
  labels, 360 calls; an expression: 120 nodes.  (BC says "split it".)
- A module: 640 names, 600 parameters of procedures.
- A program: 10 code segments, 255 procedures in a segment.

## 15. Not supported

PRINT USING, TYPE ... END TYPE, LONG and other types, DEF FN, ON ERROR
GOTO label (only RESUME NEXT and GOTO 0), INPUT$, LOF, a shared DATA
list per module (all modules' DATA form one list), automatic arrays.
