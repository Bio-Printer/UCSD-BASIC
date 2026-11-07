# B2 -- the second BASIC compiler: design

B2 compiles the same language as BC (docs/LANGUAGE.md), plus `#DEFINE`,
`#UNDEF`, `#IFDEF`, `#IFNDEF`, `#ELSE` and `#ENDIF` (section 7), into the same
kind of code files.  It is a rewrite of BC's architecture, not of its
language or library: the run-time library (lib/), its run-time errors and
BCDEBUG (B2DEBUG), batch files, CHAIN, the command prompt and its options
stay.  Its sources are in b2/, its volume is BASIC2: (B2.CODE, B2LEX.CODE ...:
the names never clash with BASIC:'s).

The aim: memory is never tight, in Z80 mode too.  BC is one large program
(BCGEN) holding the symbol table, the statement compiler, the expression
parser, the code generator and their tables at once.  B2 compiles a module
in many small passes.  Each one is a program of its own (all of memory for
its code and its tables), and each compiles a few kinds of tokens -- a "token
set", things that belong together: IF/ELSEIF/ELSE/END IF, FOR/NEXT, PRINT --
and copies everything else through, unchanged, to the next.  When one pass
needs too much memory it is split in two (B2CONST came out of B2LEX so), down
to one token set a pass.

## 1. What is kept from BC (the lessons)

- **Chaining without opening a file.**  The driver reads the volume's
  directory once (FindBlocks) and writes into the job file where every
  program's code file starts (" B2LEX=123 B2CONST=150 ...").  A pass chains to
  the next with `CHAIN "@unit,block NAME"` (B2UTIL's ChainTo; the library's
  RTCHAIN is a 510-byte segment of its own): no directory read, no FOPEN.
- **Tables sized from counts made before.**  Every intermediate file starts
  with a header of 58 words (section 3) that the pass writing it fills in at
  the end with SEEK: the counts the next passes need.  A pass makes its
  arrays that large, once, before anything else is in memory: nothing grows,
  nothing leaves a hole behind (REDIM PRESERVE copies, and the old block is a
  hole too small for the next).  Most of the counts are exact: B2IO's writer
  counts, per procedure, the code bytes (at most), the labels, jumps,
  relocations and the largest compiled block as it writes them.
- **Seldom code in RTSELDOM, and nothing of it mid-pass.**  OPEN, KILL and
  the file names are the library's segment RTSELDOM (some 3,000 words with
  the operating system's directory buffer).  A pass works out its files'
  names at its start, opens its two files then, reads its input a second
  time with SEEK (B2IO's InRewind), not OPEN, and gives its tables back
  (ERASE) before the KILL of its input at its end.
- **Names as hashes** where only telling them apart is needed (B2CONST, the
  linker); **errors as numbers**, their texts in B2ERR; **a module includes
  only what it uses** (each CONST is a name the lexer keeps): B2COM, and
  B2REC, B2OPS, B2SYM, B2NODE beside it.  B2's modules are OPTION EXPLICIT: a
  mistyped name is an error, not a new variable.
- **The linker links procedures, not modules**; B2LINK is BC's.
- **The bootstrap**: tools/bas2c.py translates B2's BASIC into C for the host
  build; B2 compiled by itself on the P-System is byte for byte the host's
  (tools/b2self.py).

## 2. The passes

    B2       the driver: commands, options, batch files -> the job file
    B2LEX    1   the characters: lines, comments, #INCLUDE, #DEFINE, #IFDEF
                 ...; tokens (NAME.W0)
    B2CONST  1b  the names: the CONSTs worked out and their values written
                 where their names come, the DECLAREs never used marked
                 (TSKIP), the header's counts (NAME.W1, BC's token file)
    B2SYN    2   the statements' syntax: each statement marked with its
                 kind, expressions and targets bracketed, the forms made one
                 (NAME.W2)
    B2DECL   3   the declarations -> the symbol file :B2TEMP.SYM, DATA ->
                 :B2TEMP.DAT
    B2NAME   4   every name resolved; locals laid out; labels numbered; the
                 module's body first, then the procedures (NAME.W4)
    B2EXPR   5   every expression and target -> P-code (NAME.W5)
    B2CTL    6   IF, DO, WHILE, FOR, SELECT CASE, EXIT, CONTINUE, GOTO, GOSUB,
                 RETURN, ON ... GOTO/GOSUB -> jumps and labels (NAME.W6)
    B2STMT   7   the other statements -> the library's calls (NAME.W7)
    B2ASM    8   the templates (entry and exit code, GOSUB's return table,
                 the string temporaries' resets), jumps resolved, NAME.OBJ
    B2LIST       the listing (-S)
    B2LINK       the linker; -J
    B2ERR        a pass's errors said
    B2DEBUG      where a program's run-time error was

Each pass reads the file the one before wrote and writes the next: on the
prefix volume as :B2TEMP.Wn, or with -K as NAME.Wn, kept: in BASIC2:/MAP/Wn
when the volume BASIC2: has those sub-volumes (one a pass: a build's 140
files are more than one sub-volume's 77; JFWDIRS), else in BASIC2:/MAP
(JFMAPDIR in the job's options, B2UTIL's AuxDir$), else beside the source (B2DUMP on the
P-System and tools/b2dump.py on the host show any of them as text, each
BASIC line as a comment above what it has become).  The order is chosen so that a pass knows what it
needs from the ones before: after B2NAME every operand carries its type, so
B2EXPR types and compiles every expression; a compiled expression carries
its type, so B2STMT knows which PRINT routine to call and B2CTL which FOR
loop to make.  A pass that finds errors ends the compile (B2ERR says them):
the next pass's errors are said once they are mended.

## 3. The intermediate file

A header of 58 words, then records: a byte, the record's kind, and its
operands (b a byte, w a word, s a string: a length byte, its characters).

    header  0 16980; 1..9 B2CONST's counts (BC's: the module's names, the most
            of one procedure, parameters, code estimate, control keywords,
            the longest statement's tokens, one line's parameters, the
            longest procedure's lines); 10..14 B2IO's, of the pass that wrote
            the file: the most code bytes, labels, jumps, relocations of one
            procedure, the largest compiled block; 15 the pass; 16..57
            the source's path (B2LEX's, every pass's after it): its length,
            then two characters a word -- the path with its volume's name,
            not "#5:" or the prefix's ":" (B2UTIL's FullName$: a unit's
            directory, the system's DKVID and SYVID, OS words 59 and 63)

    1..99    keywords (KPRINT ..);  100..127 operators (TANDALSO, TORELSE too)
    128..137 tokens: TIDENT s, TINT w, TSNG s, TDBL s, TSTR s, TLINE w s,
             TLABEL s, TEOF, TFILE s, TSKIP
    140..147 B2SYN's: RSTMT b (a statement of kind b starts), RX b ... RXE
             (an expression, wanted as b), RLV b ... RLVE (a target), RMARK b
             (PRINT's TAB, SPC; a #channel; a CASE item, the last or not),
             RSEL (SELECT CASE's value), RLREF s (a label gone to)
    160..163 B2NAME's: RVAR kind type class offset dims name, RPROC type kind
             linkname np (type flags)*np text, RBUILT id text, RLAB w
    180..185 B2EXPR's: RXC type flags value ... RXCE temps; RLVC type flags
             [pre] RLVL [load] RLVS [store] RLVCE temps
    200..214 code: CBYTES n bytes, CJUMP op label, CCASE label, CLABEL label,
             CALIAS l m, CREL kind name, CALIGN, CTEMP, CGOSUB label, CFREE
             kind offset, CBEGIN (10 words, name, segment) ... CEND line file
             text, COBJB b, COBJW w, COBJS s

A procedure is CBEGIN ... CEND.  CBEGIN holds the frame (parameter words,
result words and offset, the string mark's local, the locals so far), the
next free label number, whether the locals are zeroed: a pass that makes a
temporary (NewLocal) or a label (NewLabel) takes them from there, and B2IO
writes its CBEGIN's three counts again at the CEND (SEEK back): the numbers
stay unique and dense, and no pass keeps a table of them.  Labels 0 and 1
are every procedure's exit and RETURN's.

The labels are relocatable: a jump is "op, label number" and a label is set
by a record, wherever it is, so no pass before B2ASM knows the code's
addresses -- an LDC's and XJP's words are aligned by B2ASM too (CALIGN).
More and more of the file becomes CBYTES with a few CJUMP and CLABEL records
between; B2ASM resolves a procedure's (its tables as large as the most of
one procedure, the header's 10..13).  A pass that folds the jumps of
finished stretches early, or one of peephole optimizations, can be put in
anywhere (section 8).

## 4. What each statement becomes (B2SYN's forms)

    a = e            RSTMT SASSIGN, RLV LVASSIGN a RLVE, RX XLVT e RXE
    name args        RSTMT SCALL, RX XCALL name args RXE (CALL name(args) too)
    IF c THEN        RSTMT KIF, RX XCOND c RXE; RSTMT KELSEIF, RX XCOND ...;
                     RSTMT KELSE; RSTMT SENDIF (a one-line IF the same)
    FOR v = a TO b   RSTMT KFOR, TIDENT v, RLV LVASSIGN v RLVE, RX XLVT a,
       STEP c        RX XLVT b, RX XLVT c (1 if none); NEXT v, w: two KNEXT
    DO / LOOP        RSTMT KDO [RX XCOND | XNCOND], RSTMT KLOOP [...]
    SELECT CASE e    RSTMT KSELECT, RX XSEL e; CASE: RSTMT KCASE, each item
                     RMARK MLAST|MMORE, RX XCOND (RSEL = (v) | RSEL >= (a)
                     ANDALSO RSEL <= (b) | RSEL op (v)); RSTMT SCASEELSE
    RETURN e         an assignment to the function's name, RSTMT SEXITSUB
    PRINT #n, ...    RSTMT KPRINT, [RMARK MCHAN, RX XCHAN n], items RX XANY,
                     TSEMI, TCOMMA, RMARK MTAB / MSPC RX TYINT
    GET #n, p, v     RSTMT KGET, TINT (p?), [RX n, RX TYSNG p], RLV LVGET v,
                     RX n again (B2SYN writes the channel twice)

and so on (b2syn.bas, above each procedure).  Defaults are written in (CLOSE
nothing, LOCATE's 0, MID$'s 255, RANDOMIZE's 0) so the passes after need no
special cases.

## 5. Templates

What BC made at the end of a procedure (GenExit, GenEntry) is B2ASM's: it
reads the records the passes left for it -- CFREE (a string or array local
to give back), CGOSUB (a return point), CTEMP (the string work area's mark
reset: LDL mark, SRO _TTOP), the frame in CBEGIN -- and makes the exit code
(the frees, the result, GOSUB's stack, RETURN's case table) and the entry
code (zeroing, the marks), put in front.  GOSUB's own local is B2ASM's, after
all the others.

## 6. The object file, the library, the linker

As BC's (DESIGN.md sections 7, 8, 9), with one record more: after "BCOB",
F (70) the source's path (the header's), which B2LINK's map says and -J
leaves out of a library (BASLIB.OBJ is the same wherever its modules were
compiled).  -MAP's NAME.MAP goes where -K's files go (BASIC2:/MAP or beside
the code file); its first lines are the code file (FullName$), each module
with its source and object file ("  MODULE NAME from VOL:/A/NAME.BAS (object
VOL:/A/NAME.OBJ)") and the library.  B2DEBUG reads BASIC2:/MAP/NAME.MAP when
its first line names the program's code file, else NAME.MAP beside it, else
BASIC2:/MAP/NAME.MAP all the same (a program renamed with its map, as
BASIC2:/SRC/INSTALL does B2's); it reads a line's source beside each source the map
names first.  B2 compiles lib/ itself (BASLIB2.OBJ
on the host, BASIC2:/LIB/BASLIB.OBJ); with B2 #DEFINEd, lib/rtwhere.bas
chains to B2DEBUG.CODE and looks for it on BASIC2: (BC's lexer knows #IFDEF
too, with BC defined).

## 7. #DEFINE, #IFDEF ...

Lines of their own, like #INCLUDE, B2LEX's (BC's lexer has them too):

    #DEFINE NAME        NAME is defined (in this module, from here on)
    #UNDEF NAME         ... no longer
    #IFDEF NAME         the lines up to #ELSE or #ENDIF are compiled only
    #IFNDEF NAME        when NAME is (is not) defined
    #ELSE
    #ENDIF

They nest 8 deep, across #INCLUDE files too (errors 120 to 124).  `B2 -D
NAME[,NAME...]` defines names for the compiles after it on its command line
or in its batch file (as -MAP); B2 is always defined (BC in BC).  Lines
skipped are not tokens: they may hold anything.

## 8. Memory

Each pass says its least free memory with -M.  tools/b2self.py with
PSYS_MODE=z80 VERIFY_HARVARD=0 rebuilds B2 in Z80 mode, the least memory.
What it took (each from a failure in that run): B2COM split by what a module
uses; B2EXPR's parsing and code-making in two segments (XPARSE, XGEN) that
are never in memory together; B2NAME reading its file again with SEEK, its
KILLs after its tables are given back; the lexer's name work a pass of its
own (B2CONST: its tables were in memory when B2LEX opened an #INCLUDE file,
the lexer's peak).  Early folding of finished stretches' jumps (when B2STMT
is done, a FOR loop's body is code and its jumps can be resolved before
B2ASM) is a pass that can be added where B2ASM's tables are the largest.

LENGTH strings added a list of lengths to the symbol tables; to keep them
small it is sparse (only the symbols and parameters that have a LENGTH),
B2NAME opens its files before it loads the symbols (an OPEN in RTSELDOM
after them was its peak), and the intermediate files' KILLs are the
driver's (TempGone).  The Z80 self-compile then had, in words free at the
least: B2's four largest modules compiled, 2768 (B2CONST on B2EXPR.BAS) and
1805 (B2ASM on B2EXPR.BAS); the links, 954 (B2LINK on B2DUMP, as it reads
RTCHAIN).  tools/b2mem.py shows each pass's for chosen modules.

## 9. Testing

- tools/runtests.py --b2: the tests compiled by B2 (with B2's library and
  B2DEBUG), run on the P-System.
- tools/b2self.py: B2 and its library rebuilt by B2 on the P-System, each
  byte for byte the host's (also PSYS_MODE=z80 VERIFY_HARVARD=0).
- tools/crossb2.py: BC compiled by B2; that BC rebuilds BC and its library
  on the P-System, each byte for byte what the host BC makes.
- tools/errtest.py --b2: the compile errors (NAME.expect2 where B2 says other
  ones than BC).
- tools/mkvolume2.py, tools/voltest2.py: BASIC2.BLK, `make -f basic2:makefile` on it (tools/basmake.py writes the makefiles).
