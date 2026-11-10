# Notes for Claude

- Build: `tools/setup.sh` (emulator runner, boot disk), `tools/buildhost.sh`
  (host BC: build/bc, bclex, bcgen, bclist, bclink), `tools/mklib.sh`,
  `tools/mkself.sh`, `tools/mkvolume.py`.
  The sibling checkouts are expected in `../bio-printer/` (the emulator,
  UCSD-C, UCSD-Pascal-Volumes); see setup.sh's variables.
- BC is eight programs: seven CHAIN to each other through the job file
  :BCTEMP.JOB (docs/DESIGN.md section 1), and BCDEBUG is chained to by a
  program's run-time error; tools/bcprogs.py lists each one's
  modules (the first its main one) for every build tool.  A new module goes
  there.  BCGEN's segments: DECL, STMT, STMTA, STMTD, STMTIO, EXPR, EXPRGEN,
  RTSELDOM -- with the main one nine; a program has at most ten (one segment
  holds at most 255 procedures and 32000 bytes).  BCGEN's modules are
  small enough for its tables in Z80 mode: bcgen.bas (the pass, blocks,
  labels) and bcstmt.bas (the statements), bcexpr.bas (parsing) and
  bcexgen.bas (an expression's code; both include bcbuilt.bas).  A
  procedure moved to another module takes its module's CONSTs and DIM
  SHAREDs along (an include, or COMMON): there a name not declared is a
  new variable, silently -- compare every source's object after.  The SEGMENT lines in
  bcgen/bcstmt/bcexpr/bcexgen/bcemit were placed by a call-graph analysis (DESIGN.md
  section 10: the code in memory along a chain, RTSELDOM's too, and the
  calls' counts -- a call into another segment reads it from the disk):
  keep a call chain to three statement/expression segments, and what pass
  3 calls often out of RTSELDOM.
- After a change to the compiler or the library run `tools/runtests.py`,
  `tools/selfcompile.py` (must say IDENTICAL nine times: BASLIB and the eight programs;
  also in Z80 mode, `PSYS_MODE=z80 VERIFY_HARVARD=0`, about an hour, after a
  change that adds memory), `tools/errtest.py` and, for the volume,
  `tools/voltest.py`, and for memory `tools/smalltest.py` (PI in Z80 mode
  and P-Code mode without the Harvard layout); for the console's line ends
  `tools/crtest.py` (a CR alone, CHR$(13), goes back to the line's start;
  PRINT's line end is CR LF: the library's UNITWRITE has CRLFBIT); for the
  emulator's Import/Export of NAME.BAS and of several files, replacing, into nested sub-volumes, Export All of a volume `tools/importtest.py` (emulator 2.12;
  setup.sh rebuilds build/psys/run_verify when the emulator's sources are
  newer).  New cross-module calls need
  `tools/mkdecls.py` (buildhost.sh runs it).
- Errors in BCLEX and BCGEN are numbers (ErrNo n / ErrRec n, a, t, s$ /
  Expect t / LexErr n, s$ / FatalRec n, s$, each with its text as a
  comment); BCERR (bcerr.bas) has the texts and says them (DESIGN.md
  section 5).  The 10th error (MAXERR) ends the step; an error while Tok is
  TLINE is reported on the line before (PrevLine: GetTok keeps it).  A new error: the next number, its text in bcerr.bas's
  MsgA$/MsgB$/MsgC$ (keep each under BC's 3200 bytes a procedure), and a
  case in tests/errors if it is easy to make.
- Type suffixes: % INTEGER, # SINGLE (and no suffix), ! DOUBLE, $ STRING,
  ~ BYTE -- not QuickBASIC's ! and # (BCLEX, BCUTIL's SuffixType and
  TypeChar$, bas2c's SUFFIX/TYPECHAR; a literal 1.5! is DOUBLE, 1.5#
  SINGLE).  tests/suffix.
- Bitwise & and | (INTEGERs and BYTEs; & of strings joins): bcexpr's
  ParseConcat and ParseBitOr (Logic KAND/KOR), the token TBAR; bas2c does
  not translate them (BC's sources use AND and OR).  tests/bitwise,
  tests/errors/err9.
- Run-time error locations (docs/DESIGN.md sections 5, 8, 9): BCGEN
  writes each procedure's line table into its P record (ListLine; file
  names without volume and path, or selfcompile and voltest differ); BCLINK -MAP writes
  them into NAME.MAP (segment MAP), never into the code file (a link step
  M, not L: -MAP before it, in a batch file for that file's links only --
  BUILD's, not DEMOS' and TESTS': TEST holds 77 files, the most a UCSD
  directory has; the volume has BC's own maps beside its code files:
  mkself links with -MAP, INSTALL moves BC2.MAP ...); _RTERR gives
  back the heap and calls _RTWHERE (lib/rtwhere.bas, RTSELDOM), which
  follows the frames and runs BCDEBUG (bc/bcdebug.bas: its own small
  pexec, _WRUN, not _CHAIN) with "unit block S#,P#,I# ..."; BCDEBUG finds
  the code file in the directory (sub-volumes too) and its map.  Without
  the map: s=,p=,i= each.  tests/rterr* (rterr4: NOMAP); runtests links
  with -MAP and puts NAME.MAP, BCDEBUG.CODE and the source beside the test;
  chaintest: one in a sub-volume; tools/objdump.py shows the line tables.
  BCLINK's names are two hashes (an undefined one's text: LinkUndef), the
  names each procedure uses are in :BCTEMP.LNK (MarkAll reads them), its
  tables start at 600 names, 400 procedures (BC's programs grow none), and
  its once-only phases are segments (LKPASS1, LKLAY, LKHEAD, JOIN, MAP):
  BC's programs link in Z80 mode (DESIGN.md section 8).
- BC's sources must stay within the part of the language tools/bas2c.py
  translates, and their lines under 250 characters.
- Keep docs/LANGUAGE.md and docs/DESIGN.md current; they are on the volume.
- When the volume changes, update UCSD-Pascal-Volumes too: BLK_format/BASIC.BLK,
  the extracted files (`tools/extract_all.py BLK_format .`), the manifest and a
  README.txt entry.
- Pascal booleans passed to the OS must be 1, not BASIC's -1 (SYSTEM.C).
- A library procedure that makes a temporary string it does not return
  (e.g. prints `_ISTR`'s text) must give it back itself: `t = _TTOP` ...
  `_TTOP = t`; the compiler only resets after string expressions it sees.
- Sub-volumes: lib/rtsubv.bas (tests/subvol, runtests makes the
  sub-volumes from tests/subvol.dirs).  The volume's layout and batch files
  are made by tools/mkvolume.py; run voltest.py and voltest.py --pascal
  after changing it.
- BASIC sources are NAME.BAS (text files) on the P-System and in the
  volume; BC still takes NAME.TEXT.  The library writes a new .BAS or
  .TEXT file as text and sets its kind (the FIB's DFKIND) itself.
- BC's emitter procedure is EmitCsp: a SUB named Csp would take the CSP
  statement's place.  bas2c turns the CSP statement into nothing and
  CSP%() into 0.  BC does not check for the Harvard layout (docs/DESIGN.md
  section 10: what the other layouts leave).  PSYS_MODE=z80 needs the Z80
  interpreter pascal.bin (setup.sh copies UCSD-C's).
- The linker links procedures, not modules.  BCLEX counts what BCGEN's
  tables need into the token file's 16-word header (THxxx in bccom.bas,
  written at the end with SEEK: bas2c's b_seek; DESIGN.md sections 3 and
  10); BCGEN sizes them from it, and grows one that was too small by 100
  entries (Grown, REDIM PRESERVE: bas2c's ar_dimp) -- -M says "tables grown
  N times"; keep it 0 for the sources, the demos and the tests.  BCLINK's tables start small and double (LinkGrown; by 100 it
  ran out of memory linking BCGEN on the P-System).  The
  library's segment RTSELDOM holds what is done seldom (OPEN, finding
  CHAIN's code file, the sub-volumes, _ARGS; BCUTIL's job and file-name
  code; GenExit; _RTINIT, _KILL, _ERRTEXT: _RTERR gives the heap back first).  _CHAIN itself is RTCHAIN (510 bytes): BC's ChainTo
  runs "@unit,block NAME" (the driver's FindBlocks puts each program's
  block into the job file), which opens no file -- a pass has little left.
- Pass 4, BCASM (bcasm.bas): BCGEN's emitter writes the code as records to
  :BCTEMP.ASM (BCGENCOM's AMxxx), BCASM assembles them (jumps, entry code,
  P records, the listing's records).  The objects and listings must stay
  byte for byte what BCGEN made in memory: compare every source's with the
  old compiler's after a change there.  BCLEX's names are hashes (LxHashes:
  15 bits and a second hash), and it marks the DECLAREs a module never uses
  (TSKIP; DESIGN.md section 3).  The CONSTs are BCLEX's: a CONST statement
  is read, not written (LxConstOne, LXCONST), and its value written where
  the name comes (LxPut); BCGEN has no CONSTs.  A CONST's name means
  nothing else in the module (errors 24, 30, 119 from BCLEX):
  tests/constin, tests/errors/err10.  BCLEX's peak is opening an #INCLUDE
  file (RTSELDOM): KwTable$ is the segment KWTAB, LxUnused and LexErr LXEND.
- The volumes are rebuilt with UCSD-C's MAKE (on its TOOLS: volume; the tests mount it on #11:
  psys.tools_blk()): tools/basmake.py writes VOL:MAKEFILE.TEXT (the MAKE of SRC, LIB, DEMO,
  TEST; INSTALL: the shell's MOVE of PROG2.CODE onto PROG.CODE), and each sub-volume's, a
  module's #INCLUDEs among its prerequisites.  voltest runs make -f basic:makefile, then
  again (up to date), then its INSTALL.  A link longer than the shell's 79 characters MAKE
  runs as BC @#4:MAKEnRk (its commands in that file).
- The tests boot build/psys/data/Big_Disk.BLK (setup.sh copies BOOT_DISK);
  BIGGY 1.29 is the first whose systems make a new NAME.BAS a text file;
  1.30's shell (and UCSD-C's library: __istext) reads NAME.BAS as text.
- Code space (Harvard): BCGEN is the largest program; LIST is a program of
  its own (BCLIST, after BCGEN).
  voltest compares the P-System's listing (-S) with the host's.
- The shell's >FILE, >>FILE, <FILE and | for BASIC programs: _ARGS takes
  them off COMMAND$ (only then are its words re-joined: tests/chain wants
  its blanks kept), _REDOPEN opens channels 16/17, _CONFLUSH / _CONLINE use
  them, _REDCLOSE in _HALT and _RTERR.  tools/chaintest.py checks them.
- CHAIN: lib/rtchain.bas (_CHAIN), the pexec protocol of BIGGY's GETCMD;
  tests/chain (+ chain.progs) and tools/chaintest.py (from the shell; also
  --pascal).  bas2c translates CHAIN (hostrt.h b_chain: execv of the host
  program of that name beside the running one), PEEK and OSVAR (0).

# B2 (the Rewrite branch: b2/, docs/B2DESIGN.md)

- B2 is BC's language in many passes, each a program (tools/b2progs.py: B2, B2LEX, B2CONST,
  B2SYN, B2DECL, B2NAME, B2EXPR, B2CTL, B2STMT, B2ASM, B2LIST, B2LINK, B2ERR, B2DEBUG).  The
  passes read and write intermediate files of records (b2com.bas, b2rec.bas: the kinds and
  each one's operands; B2IO's NextRec / PutRec, the writer's counts in the header).  A new
  record kind: its operands in NextRec and PutRec (b2io.bas) and in tools/b2dump.py.
- Build and check: `tools/buildb2.sh` (host: build/b2/), `tools/mklib2.sh` (build/BASLIB2.OBJ),
  `tools/mkself2.sh` (build/B2*.CODE and maps), then `tools/runtests.py --b2`,
  `tools/b2self.py` (IDENTICAL 15 times; `PSYS_MODE=z80 VERIFY_HARVARD=0` for Z80 mode, -m
  for each pass's memory), `tools/crossb2.py` (BC compiled by B2 builds BC identically),
  `tools/errtest.py --b2` (NAME.expect2 where B2 says other errors),
  `tools/mkvolume2.py` + `tools/voltest2.py` (BASIC2.BLK; UCSD-Pascal-Volumes gets it too).
- B2's modules are OPTION EXPLICIT (b2com.bas): every local is DIMmed, every global a COMMON
  or DIM SHARED, every constant in an include.  A module includes only the includes it uses
  (B2REC records, B2OPS opcodes, B2SYM symbols, B2NODE nodes, B2BUILT built-ins): each CONST
  costs the lexer a name.  Procedure names are unique across all of b2/ (mkdecls makes one
  B2PROCS of every one called from another module), and none is a keyword (WEnd ...) or the
  name of a COMMON array (SNext ...).
- No pass loads RTSELDOM in its middle (OPEN, KILL, PassFile$, ReadJob, CompileFailed are
  RTSELDOM's): names at the start, a second reading with InRewind (SEEK), KILL at the end
  after ERASE of the tables.  The Z80 mode is where that shows.
- Positions in an intermediate file are a block and a byte (OutBlk, OutOff): a file passes
  32K bytes (an INTEGER's).  CBEGIN's counts are written again at CEND (WEndProc).
- B2 #DEFINEs B2 (BC defines BC): lib/rtwhere.bas chooses B2DEBUG / BCDEBUG with #IFDEF B2.
- -K's NAME.Wn and -MAP's NAME.MAP go into BASIC2:/MAP when it is there (the driver's
  MapDirLook sets JFMAPDIR; B2UTIL's AuxDir$), NAME.Wn into BASIC2:/MAP/Wn when those are
  there (JFWDIRS: a whole -K build is 140 files, 7900 blocks; a sub-volume holds 77), else
  beside the file; B2DUMP writes NAME.Dn beside the source (the header's path), with -MAP
  into BASIC2:/MAP/Dn (BASIC2:/SRC/MAKEFILE's DUMPALL uses -MAP: a whole build's, 140 files, 11500
  blocks), so BASIC2.BLK is 32000 blocks, near a volume's most.  BASIC2:'s
  INSTALL and DUMPALL are targets of BASIC2:/SRC/MAKEFILE (and INSTALL of BASIC2:MAKEFILE).  The library's _RTERR traps errors while it closes the files (the file
  that filled its disk failed again and ended the program silently, status 0).  The header's words
  16..57 hold the source's path with its volume's name (FullName$; HeadPath$ reads it), the
  object's record F (70, after BCOB) too, B2LINK's map its MODULE lines; -J leaves the F
  record out, so BASLIB.OBJ is the same wherever it was compiled.  voltest2 checks them.
