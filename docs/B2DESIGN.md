# B2 -- the second BASIC compiler: design

B2 compiles the same language as BC (docs/LANGUAGE.md), plus `#DEFINE`,
`#UNDEF`, `#IFDEF`, `#IFNDEF`, `#ELSE` and `#ENDIF` (section 7).  It is a
rewrite of BC's architecture, not of its language or library: the run-time
library (lib/), its run-time errors and BCDEBUG, batch files, CHAIN, the
command prompt and its options stay.  Its sources are in b2/, its volume is
BASIC2: (B2.CODE, B2LEX.CODE ...: the names never clash with BASIC:'s).

The aim: memory is never tight, in Z80 mode too.  BC is one large program
(BCGEN) holding the symbol table, the statement compiler, the expression
parser, the code generator and their tables at once; in Z80 mode it has
1,000 words left compiling its own lexer.  B2 compiles a module in many
small passes.  Each one is a program of its own (all of memory for its code
and its tables), and each compiles a few kinds of tokens -- a "token set",
things that belong together: IF/ELSEIF/ELSE/END IF, FOR/NEXT, PRINT -- and
copies everything else through, unchanged, to the next.  When one pass
needs too much memory it can be split in two, down to one token set a pass.

## 1. What is kept from BC (the lessons)

- **Chaining without opening a file.**  The driver reads the volume's
  directory once (FindBlocks) and writes into the job file where every
  program's code file starts (" B2LEX=123 B2SYN=150 ...").  A pass chains to
  the next with `CHAIN "@unit,block NAME"` (BCUTIL's ChainTo; the library's
  RTCHAIN is a 510-byte segment of its own): no directory read, no FOPEN,
  no 2 KB buffers -- a pass needs almost no memory left to chain.
- **Tables sized from counts made before.**  Every intermediate file starts
  with a header of 16 words (WHxxx, section 3) that the pass writing it fills
  in at the end with SEEK: the counts the next passes need -- the most
  labels, jumps, calls, code bytes and lines of one procedure, the names at
  the module's level and in the largest procedure, the tokens of the
  longest expression.  A pass makes its arrays exactly that large, once,
  before anything else is in memory: nothing grows, nothing leaves a hole
  behind (REDIM PRESERVE copies and the old block is a hole too small for
  the next).  Counts that are only estimates are upper bounds.
- **Names as hashes.**  A pass that only needs to tell names apart keeps
  two hashes (15 bits, and the length and each character times its place
  mod 27011), never their strings (each string at least an 8-word heap
  block).  Only the names the linker sees (procedures, COMMON) are kept as
  text.
- **Errors as numbers**, their texts in B2ERR, which a failed pass chains
  to; the 10th error ends the pass.
- **Seldom code in a segment of its own** (the library's RTSELDOM: OPEN,
  the job file, file names), the keyword table's text a segment called
  once.
- **The linker links procedures, not modules**; its names are hashes, the
  references each procedure makes are in a file, its once-only phases are
  segments.
- The bootstrap: tools/bas2c.py translates B2's BASIC into C for the host
  build; B2 compiled by itself on the P-System must be byte for byte the
  host's (tools/b2self.py).

## 2. The passes

    B2       the driver: commands, options, batch files -> the job file
    B2LEX    source -> tokens: #INCLUDE, #DEFINE/#IFDEF..., CONSTs
    B2SYN    statements' syntax: each statement marked with its kind,
             one-line IF and NEXT i, j made block forms, expressions and
             assignment targets bracketed
    B2DECL   declarations: SUBs, FUNCTIONs, DECLAREs, DIM SHARED, COMMON,
             DATA, OPTION EXPLICIT -> the symbol file :B2TEMP.SYM
    B2NAME   names: every identifier resolved -- a local at offset n of
             type t, a module static, a COMMON variable, an array, a call
             of a procedure (its linker name and parameters written beside
             it), a built-in; locals and temporaries laid out; labels made
             numbers.  After this pass no pass needs a symbol table.
    B2EXPR   every bracketed expression -> P-code (a condition: code that
             jumps to "the false label" of its statement)
    B2CTL    IF/ELSEIF/ELSE/END IF, DO/LOOP, WHILE/WEND, FOR/NEXT,
             SELECT CASE, EXIT, CONTINUE, GOTO, GOSUB, RETURN, ON ... GOTO/
             GOSUB, labels -> jumps and labels
    B2STMT   the other statements: assignments, PRINT, INPUT, WRITE, OPEN,
             CLOSE, GET, PUT, DIM, READ, CALL ... -> calls of the library
    B2ASM    the procedures' templates (entry code, exit code, GOSUB's
             return table, the string temporaries' resets), jumps resolved,
             the object file
    B2LIST   the listing (-S)
    B2LINK   the linker; -J
    B2ERR    a pass's errors said
    B2DEBUG  where a program's run-time error was (the library chains to it)
    B2DUMP   any intermediate file as text (-K keeps them)

Each pass reads the file the one before wrote and writes the next
(:B2TEMP.W1, .W2 ... alternately, on the prefix volume).  The order is
chosen so that a pass knows what it needs from the ones before it: types
are known when B2NAME is done (every operand carries its type), so B2EXPR
can type and compile every expression; a compiled expression carries its
type, so B2STMT knows which PRINT routine to call and B2CTL which FOR loop to
make.

## 3. The intermediate file

A header of 16 words (WHxxx in b2com.bas), then records: a byte, the
record's kind, and its operands (b a byte, w a word, s a string: a length
byte and its characters).  The kinds are one space:

    1..99      keywords (as BC's tokens: KPRINT ..)
    100..127   operators and punctuation
    128..139   BC's tokens: TIDENT s, TINT w, TSNG s, TDBL s, TSTR s,
               TLINE w s (a line's number and its text), TLABEL s, TEOF,
               TFILE s
    140..159   B2SYN's marks: RSTMT b (a statement of kind b starts),
               RX b (an expression starts; b: the type it is wanted as,
               or a mode: any type, a condition), RXE (its end), RLV, RLVE
               (an assignment's target), RBLK (a block's end) ...
    160..179   B2NAME's operands: RVAR (class, type, offset; a COMMON
               variable's name), RARR, RCALL (the procedure's linker name,
               its result type, its parameters' types and flags), RBUILT
               (a built-in's number), RLAB w (a label's number)
    180..199   B2EXPR's: RXC b b (a compiled expression: its type, its
               flags -- made string temporaries, a constant and its sign,
               a comparison) ... RXCE
    200..239   code (BC's AMxxx records, as BCASM read them): CBYTES n
               bytes, CJUMP op label, CCASE label, CLABEL label, CREL kind
               name, CTEMP (the string temporaries given back: a template
               B2ASM fills in), CGOSUB label, CFREE kind offset, CBEGIN,
               CEND (the procedure's frame, name, segment) ...

A procedure is CBEGIN ... CEND.  CBEGIN holds the frame's size so far and
the next free label number: a pass that makes a temporary or a label
starts from them and writes its own CBEGIN with the new values (SEEK back
at CEND), so the numbers stay unique and dense without any table.

The labels a pass makes are relocatable: a jump is "op, label number" and
a label is set by a record, wherever in the stream it is, so a pass never
needs to know the code's addresses.  More and more of the file becomes
CBYTES with a few CJUMP/CLABEL records between them; B2ASM, at the end,
resolves a procedure's labels (its tables as large as the most labels and
jumps of one procedure, counted in the header).  A pass that folds the
jumps of finished stretches early (section 8) can be put anywhere, as can
one that does peephole optimizations.

The BASIC lines stay in the file: every pass copies TLINE through, so
B2DUMP shows each line as a comment above what it has become (`-K` keeps
each pass's file as NAME.W1 ... beside the source; tools/b2dump.py reads
them on the host).

## 4. What each pass keeps in memory

- B2LEX: its names' hashes (to know the CONSTs and the DECLAREs never
  used), the CONSTs' values, #DEFINE's names.
- B2SYN: nothing but the open blocks' kinds (to normalize one-line IF and
  NEXT i, j, and to find a block's end).
- B2DECL: the module's procedures and shared variables, written to
  :B2TEMP.SYM with their counts.
- B2NAME: the module's symbols (from the SYM file) and one procedure's.
- B2EXPR: one expression's nodes; the procedure's temporaries.
- B2CTL: the open blocks' labels.
- B2STMT: one statement.
- B2ASM: one procedure's code, labels, jumps, relocations and lines.

## 5. Templates

What BC made at the end of a procedure (GenExit, GenEntry) is B2ASM's: it
reads the records the passes left for it -- CFREE (a string or array local
to give back), CGOSUB (a return point), CTEMP (the string work area's
mark reset), the frame in CEND -- and makes the entry code (zeroing, the
marks) and the exit code (the frees, the result, RETURN's case table) from
them.  The other passes only write records.

## 6. The object file and the linker

As BC's (DESIGN.md sections 7, 8), with B2's own BASLIB.OBJ: B2 compiles
lib/ itself.  B2's object format may change where a pass can leave the
linker less to do.

## 7. #DEFINE, #IFDEF ...

Lines of their own, like #INCLUDE, B2LEX's:

    #DEFINE NAME        NAME is defined (in this module, from here on)
    #UNDEF NAME         ... no longer
    #IFDEF NAME         the lines up to #ELSE or #ENDIF are compiled only
    #IFNDEF NAME        when NAME is (is not) defined
    #ELSE
    #ENDIF

They nest 8 deep, across #INCLUDE files too.  `B2 -D NAME[,NAME...] FILE`
defines names for the compiles after it on the command line or in the
batch file (as -MAP).  Lines skipped are not tokens: they may hold
anything, but #IFDEF/#ENDIF in them still count.

## 8. Memory, and what can still be done

Each pass's peak is measured (-M) compiling B2's own sources in Z80 mode
(tools/b2small.py, tools/b2self.py with PSYS_MODE=z80).  When a pass is
too tight it is split: its token sets go into two programs (the
infrastructure -- b2io.bas: reading, copying and writing records, the
header, CBEGIN/CEND -- is the same in each).  Early folding of the jumps in
finished stretches (when B2STMT is done, a FOR loop's body is code and its
jumps can be resolved before B2ASM) is a pass that can be added when
B2ASM's tables are the largest.
