' BCCOM -- shared by every module of the BASIC compiler (#INCLUDE "BCCOM")
' Constants, the globals the passes share (COMMON SHARED) and the
' procedures one module calls in another (DECLARE).
DEFINT A-Z

' ---- limits
CONST MAXSYM = 640, HSIZE = 128, MAXPAR = 600
CONST MAXNODE = 120, MAXCODE = 3200, MAXLAB = 260, MAXFIX = 320, MAXREL = 360
CONST MAXSEG = 12, MAXCTL = 40, MAXLNF = 16

' ---- file numbers
' the token file's header: THWORDS words, what BCLEX counted (THxxx: the
' word's index) -- BCGEN sizes its tables from it
CONST THWORDS = 16, THMAGIC = 0, THGLOB = 1, THLOC = 2, THPARAMS = 3, THCONSTS = 4
CONST THCODE = 5, THCTL = 6, THSTMT = 7, THMAXPAR = 8, THLINES = 9, TOKMAGIC = 16980
CONST CHSRC = 1, CHTOK = 2, CHOBJ = 3, CHLST = 4, CHLTMP = 5, CHBAT = 6, CHINC = 7
' (the listing's two temporary files, written by pass 3, read by LIST)
CONST CHLREC = 11, CHLCOD = 12

' the end of a block GenBlock returns: TMEND + KIF (END IF), KSUB ...
CONST TMEND = 200
' ---- token codes: keywords 1..99, operators 100..127, others 128..
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

CONST TIDENT = 128, TINT = 129, TSNG = 130, TDBL = 131, TSTR = 132
CONST TLINE = 133, TLABEL = 134, TEOF = 135, TFILE = 136

' ---- types
CONST TYVOID = 0, TYINT = 1, TYSNG = 2, TYDBL = 3, TYSTR = 4, TYBYTE = 5

' ---- symbols: kinds, storage classes, flags
CONST SKVAR = 1, SKARRAY = 2, SKCONST = 3, SKSUB = 4, SKFUNC = 5, SKLABEL = 6
CONST SCLOCAL = 1, SCSTATIC = 2, SCCOMMON = 3, SCPARAM = 4, SCREF = 5
CONST SFSHARED = 1, SFDEFINED = 2, SFPRIVATE = 4, SFAS = 8, SFUSED = 16
CONST SFRUNTIME = 32, SFSETLAB = 64, SFGOSUB = 128
' parameter flags
CONST PFBYREF = 1, PFARRAY = 2

' ---- the driver and its options
COMMON SHARED ErrCount, OptList, OptQuiet, OptExplicit, OptMem
COMMON SHARED SrcName$, ModName$, ObjName$, LstName$, TokName$, LTmpName$, LCodName$
COMMON SHARED BcVol$
' ---- the job file (BCUTIL): where the programs are (#unit:), the options
' (JF...), the step being done
COMMON SHARED JobHome$, JobFlags, JobCur$, JobName$, ErrName$
CONST MAXERR = 10
CONST JFASK = 1, JFQUIET = 2, JFMEM = 4, JFMAP = 8, CHJOB = 13, MAXSTEP = 300

' ---- the token reader (passes 2 and 3)
COMMON SHARED Tok, TokS$, TokV, TokLine, TokFile$, TokText$, TokNewLine
' the line TokLine is in (its file), and the line before it: while Tok is
' TLINE (the end of a statement) the statement was on the line before
COMMON SHARED LineFile$, PrevLine, PrevText$, PrevFile$

' ---- the symbol table
COMMON SHARED NSym, NModSym, NPar, CurSeg, NSegName, SymCap, ParCap
COMMON SHARED CodeCap, LabCap, FixCap, RelCap, NodeCap, ConstCap, NGrown, TokHead()
COMMON SHARED SName$(), SKind() AS BYTE, SType() AS BYTE, SCls() AS BYTE
COMMON SHARED SOff(), SFlags() AS BYTE, SScope() AS BYTE, SNext()
COMMON SHARED SAux(), SAux2(), SSeg() AS BYTE, HashHead()
COMMON SHARED PType() AS BYTE, PFlg() AS BYTE, SegName$()
COMMON SHARED DefType()
COMMON SHARED StaticWords
COMMON SHARED DeclName$, DeclFlags, ParName$(), ParFlags()
COMMON SHARED NData, DatName$

' ---- the procedures one module calls in another (generated: tools/mkdecls.py)
#INCLUDE "BCPROCS"
