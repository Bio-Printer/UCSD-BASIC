' B2COM -- shared by every module of B2 (#INCLUDE "B2COM"): the limits,
' the files' header, the tokens, the types, the globals every program has
' (COMMON SHARED) and the procedures one module calls in another
' (DECLARE).  A module includes what else it uses, and only that (each
' CONST is a name the lexer keeps): B2REC the records, B2OPS the opcodes,
' B2SYM the symbol table, B2NODE the expression nodes.
' (docs/B2DESIGN.md)
DEFINT A-Z
' (every name declared: a mistyped one is an error, not a new variable)
OPTION EXPLICIT

' ---- limits
CONST MAXSYM = 640, HSIZE = 128, MAXPAR = 600, MAXNODE = 160
CONST MAXSEG = 12, MAXCTL = 40, MAXLNF = 16, MAXERR = 10, MAXSTEP = 300

' ---- the intermediate files' header: WHWORDS words.  0..9 B2LEX's counts
' (THxxx: for B2DECL, B2NAME and B2EXPR's tables); 10..14 counted by B2IO's
' writer in every pass, per procedure, the most of one (for the next
' passes' tables); 15 the pass that wrote it; 16.. the source's path (B2LEX's,
' each pass's after it: its length, then two characters a word)
CONST WHWORDS = 58, THSRC = 16, THMAGIC = 0, THGLOB = 1, THLOC = 2, THPARAMS = 3, THCONSTS = 4
CONST THCODE = 5, THCTL = 6, THSTMT = 7, THMAXPAR = 8, THLINES = 9, TOKMAGIC = 16980
CONST WHCODE = 10, WHLABS = 11, WHJUMPS = 12, WHRELS = 13, WHBLK = 14, WHPASS = 15

' ---- file numbers
CONST CHSRC = 1, CHIN = 2, CHOUT = 3, CHOBJ = 4, CHLTMP = 5, CHBAT = 6, CHINC = 7
CONST CHLREC = 11, CHLCOD = 12, CHJOB = 13, CHSYM = 14, CHDAT = 15, CHLST = 10

' ---- token codes: keywords 1..99, operators 100..127, others 128..139
CONST KPRINT = 1, KINPUT = 2, KLET = 3, KIF = 4, KTHEN = 5, KELSE = 6
CONST KELSEIF = 7, KEND = 8, KFOR = 9, KTO = 10, KSTEP = 11, KNEXT = 12
CONST KWHILE = 13, KWEND = 14, KDO = 15, KLOOP = 16, KUNTIL = 17, KEXIT = 18
CONST KGOTO = 19, KGOSUB = 20, KRETURN = 21, KON = 22, KSUB = 23, KFUNCTION = 24
CONST KCALL = 25, KDIM = 26, KREDIM = 27, KSHARED = 28, KCOMMON = 29, KAS = 30
CONST KINTEGER = 31, KSINGLE = 32, KDOUBLE = 33, KSTRING = 34, KBYTE = 35
CONST KCONST = 36, KDECLARE = 37, KDEFINT = 38, KDEFSNG = 39, KDEFDBL = 40
CONST KDEFSTR = 41, KSELECT = 42, KCASE = 43, KIS = 44, KOPEN = 45, KCLOSE = 46
CONST KOUTPUT = 47, KAPPEND = 48, KBINARY = 49, KRANDOM = 50, KLINE = 51
CONST KGET = 52, KPUT = 53, KKILL = 54, KSTOP = 55, KSYSTEM = 56, KAND = 57
CONST KOR = 58, KXOR = 59, KNOT = 60, KMOD = 61, KBYREF = 62, KBYVAL = 63
CONST KSTATIC = 64, KSEGMENT = 65, KPRIVATE = 66, KSWAP = 67, KERASE = 68
CONST KDATA = 69, KREAD = 70, KRESTORE = 71, KCONTINUE = 72, KRANDOMIZE = 73
CONST KOPTION = 74, KEXPLICIT = 75, KREAL = 76, KCLS = 77, KLOCATE = 78
CONST KWRITE = 79, KPRESERVE = 80, KERROR = 81, KRESUME = 82, KSEEK = 83
CONST KUSING = 84, KCHAIN = 85
CONST NKEYWORD = 85

CONST TEQ = 100, TNE = 101, TLT = 102, TGT = 103, TLE = 104, TGE = 105
CONST TPLUS = 106, TMINUS = 107, TMUL = 108, TDIV = 109, TIDIV = 110
CONST TPOW = 111, TLPAR = 112, TRPAR = 113, TCOMMA = 114, TSEMI = 115
CONST THASH = 116, TAMP = 117, TCOLON = 118, TBAR = 119
' (in messages: TMEND + KIF is END IF ...)
CONST TMEND = 200
' (B2NAME's: ANDALSO and ORELSE, which the lexer leaves names)
CONST TANDALSO = 120, TORELSE = 121

CONST TIDENT = 128, TINT = 129, TSNG = 130, TDBL = 131, TSTR = 132
CONST TLINE = 133, TLABEL = 134, TEOF = 135, TFILE = 136, TSKIP = 137

' ---- types
CONST TYVOID = 0, TYINT = 1, TYSNG = 2, TYDBL = 3, TYSTR = 4, TYBYTE = 5

' ---- relocations (the object file)
CONST RCALL = 1, RGSTAT = 3, RGNAME = 4

' ---- the driver and its options
COMMON SHARED ErrCount, OptList, OptQuiet, OptExplicit, OptMem, OptKeep
COMMON SHARED SrcName$, ModName$, ObjName$, LstName$, TokName$, LTmpName$, LCodName$
COMMON SHARED SymName$, InName$, OutName$, Defines$
' ---- the job file (B2UTIL): where the programs are (#unit:), their first
' blocks (" B2LEX=123 ..."), the options (JF...), the step being done
COMMON SHARED JobHome$, JobFlags, JobCur$, JobName$, ErrName$, DatName$, JobBlk$
' (JFMAPDIR: -K's and -MAP's files in BASIC2:/MAP, the driver found it there)
CONST JFASK = 1, JFQUIET = 2, JFMEM = 4, JFKEEP = 8, JFMAPDIR = 16

' ---- the token reader (B2SYN, B2DECL: the token file) and the record
' reader (B2IO: the passes after) -- where they are, for errors
COMMON SHARED Tok, TokS$, TokV, TokLine, TokFile$, TokText$, TokNewLine
COMMON SHARED LineFile$, PrevLine, PrevText$, PrevFile$
COMMON SHARED NGrown

' ---- the procedures one module calls in another (generated: tools/mkdecls.py)
#INCLUDE "B2PROCS"

