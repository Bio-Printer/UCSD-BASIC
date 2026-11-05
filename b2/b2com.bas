' B2COM -- shared by every module of B2 (#INCLUDE "B2COM"): the tokens,
' the intermediate file's records, the globals the passes share (COMMON
' SHARED) and the procedures one module calls in another (DECLARE)
' (docs/B2DESIGN.md)
DEFINT A-Z

' ---- limits
CONST MAXSYM = 640, HSIZE = 128, MAXPAR = 600, MAXNODE = 160
CONST MAXSEG = 12, MAXCTL = 40, MAXLNF = 16, MAXERR = 10, MAXSTEP = 300

' ---- the intermediate files' header: WHWORDS words.  0..9 B2LEX's counts
' (THxxx: for B2DECL, B2NAME and B2EXPR's tables); 10..14 counted by B2IO's
' writer in every pass, per procedure, the most of one (for the next
' passes' tables); 15 the pass that wrote it
CONST WHWORDS = 16, THMAGIC = 0, THGLOB = 1, THLOC = 2, THPARAMS = 3, THCONSTS = 4
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
' (B2NAME's: ANDALSO and ORELSE, which the lexer leaves names)
CONST TANDALSO = 120, TORELSE = 121

CONST TIDENT = 128, TINT = 129, TSNG = 130, TDBL = 131, TSTR = 132
CONST TLINE = 133, TLABEL = 134, TEOF = 135, TFILE = 136, TSKIP = 137

' ---- B2SYN's marks (140..159)
' RSTMT b: a statement of kind b starts (a keyword's code, or SAAAA)
' RX b ... RXE: an expression (b: XAAAA, how it is wanted)
' RLV b ... RLVE: a target (b: LVAAAA, what is made of it)
' RMARK b: PRINT's TAB( and SPC( (MTAB, MSPC), a #channel (MCHAN), a CASE's
' item, the last (MLAST) or not (MMORE)
' RSEL: the value of SELECT CASE (in a CASE's condition); RLREF s: a label
' gone to (GOTO, GOSUB, ON, RESTORE: its text)
CONST RSTMT = 140, RX = 141, RXE = 142, RLV = 143, RLVE = 144, RMARK = 145, RSEL = 146, RLREF = 147
' ---- B2NAME's operands (160..179)
' RVAR kind type class offset dims name: a variable or array (name: a
'   COMMON variable's, for the linker; else "")
' RPROC type kind name np (type flags) * np text: a procedure called
' RBUILT id text: a built-in function;  RLAB w: a label (by number)
CONST RVAR = 160, RPROC = 161, RBUILT = 162, RLAB = 163
' ---- B2EXPR's (180..199)
' RXC type flags value ... RXCE t: a compiled expression (or assignment); t:
'   it made string temporaries (XFTEMP)
' RLVC type flags [pre] RLVL [load] RLVS [store] RLVCE t: a compiled target
CONST RXC = 180, RXCE = 181, RLVC = 182, RLVL = 183, RLVS = 184, RLVCE = 185
' ---- code (200..219): what B2ASM assembles
' CBYTES n bytes; CJUMP op label; CCASE label; CLABEL label; CALIAS l m
' CREL kind name; CALIGN (a 0 if the code is at an odd byte); CTEMP (the
' string temporaries given back); CGOSUB label (a GOSUB's return point);
' CFREE kind offset (a local given back at the exit: 1 string, 2 array);
' CBEGIN ... CEND a procedure (CBxxx below); COBJB b, COBJW w, COBJS s the
' object file's other records
CONST CBYTES = 200, CJUMP = 201, CCASE = 202, CLABEL = 203, CALIAS = 204
CONST CREL = 205, CALIGN = 206, CTEMP = 207, CGOSUB = 208, CFREE = 209
CONST CBEGIN = 210, CEND = 211, COBJB = 212, COBJW = 213, COBJS = 214

' statement kinds besides the keywords' (RSTMT's operand)
CONST SASSIGN = 100, SCALL = 101, SMIDSET = 102, SPOKE = 103, SPOKEB = 104
CONST SCSP = 105, SOSCALL = 106, SENDIF = 107, SENDSEL = 108, SENDSUB = 109
CONST SENDFN = 110, SLINPUT = 111, SDATAL = 112, SONERR = 113, SEXITSUB = 114
CONST SCASEELSE = 115
' how an expression is wanted (RX's operand): a value of its own type
' (XANY), of a type (TYxxx), the jumps of a condition to the statement's
' "false" label (XCOND; XNCOND its NOT), the type of the target before it
' (XLVT), a SUB called (XCALL), SELECT CASE's value (XSEL), a channel
' (XCHAN: a constant, else a local), PUT's value (XPUT), CSP's arguments
' (XRAW: a comparison as 1/0)
CONST XANY = 0, XCOND = 10, XNCOND = 11, XLVT = 12, XCALL = 13, XSEL = 14
CONST XCHAN = 15, XPUT = 16, XRAW = 17
' a target (RLV's operand): an assignment (with the RX XLVT after it: all
' code), its parts before and after the value (LVPS), GET's (LVGET), its
' address (LVADDR)
CONST LVASSIGN = 1, LVPS = 2, LVGET = 3, LVADDR = 4
CONST MTAB = 1, MSPC = 2, MCHAN = 3, MLAST = 4, MMORE = 5
' RXC's flags: made string temporaries; an INTEGER constant (its value
' follows); a real constant, negative; an address (PUT's lvalue)
CONST XFTEMP = 1, XFICON = 2, XFRCON = 4, XFNEG = 8, XFADDR = 16
' the label a condition jumps to when it is false (B2CTL sets the real one)
CONST LFALSE = -1

' ---- types
CONST TYVOID = 0, TYINT = 1, TYSNG = 2, TYDBL = 3, TYSTR = 4, TYBYTE = 5

' ---- symbols: kinds, storage classes, flags
CONST SKVAR = 1, SKARRAY = 2, SKSUB = 4, SKFUNC = 5, SKLABEL = 6
CONST SCLOCAL = 1, SCSTATIC = 2, SCCOMMON = 3, SCPARAM = 4, SCREF = 5
CONST SFSHARED = 1, SFDEFINED = 2, SFPRIVATE = 4, SFAS = 8, SFUSED = 16
CONST SFRUNTIME = 32, SFSETLAB = 64, SFGOSUB = 128
CONST PFBYREF = 1, PFARRAY = 2

' ---- opcodes
CONST OABI = &H80, OABR = &H81, OADI = &H82, OADR = &H83, OLAND = &H84
CONST ODVR = &H87, OFLT = &H8A, OLOR = &H8D, OMPI = &H8F, OMPR = &H90
CONST ONGI = &H91, ONGR = &H92, ONOT = &H93, OSBI = &H95, OSBR = &H96
CONST OSTO = &H9A, OCSP = &H9E, OFJP = &HA1, OINC = &HA2, OIND = &HA3
CONST OLAO = &HA5, OLSA = &HA6, OLDO = &HA9, OSRO = &HAB, OXJP = &HAC
CONST ORNP = &HAD, OEQU = &HAF, OGEQ = &HB0, OGRT = &HB1, OLDC = &HB3
CONST OLEQ = &HB4, OLES = &HB5, OLOD = &HB6, ONEQ = &HB7, OUJP = &HB9
CONST OLDM = &HBC, OSTM = &HBD, OLDB = &HBE, OSTB = &HBF
CONST OEQUI = &HC3, OGEQI = &HC4, OGRTI = &HC5, OLLA = &HC6, OLDCI = &HC7
CONST OLEQI = &HC8, OLESI = &HC9, OLDL = &HCA, ONEQI = &HCB, OSTL = &HCC
CONST OCXP = &HCD, OCGP = &HCF, OEFJ = &HD3, ONFJ = &HD4, ONOP = &HD7
CONST OSIND0 = &HF8
' ---- relocations (the object file)
CONST RCALL = 1, RGSTAT = 3, RGNAME = 4

' ---- the driver and its options
COMMON SHARED ErrCount, OptList, OptQuiet, OptExplicit, OptMem, OptKeep
COMMON SHARED SrcName$, ModName$, ObjName$, LstName$, TokName$, LTmpName$, LCodName$
COMMON SHARED SymName$, InName$, OutName$, Defines$
' ---- the job file (B2UTIL): where the programs are (#unit:), their first
' blocks (" B2LEX=123 ..."), the options (JF...), the step being done
COMMON SHARED JobHome$, JobFlags, JobCur$, JobName$, ErrName$, DatName$, JobBlk$
CONST JFASK = 1, JFQUIET = 2, JFMEM = 4, JFKEEP = 8

' ---- the token reader (B2SYN, B2DECL: the token file) and the record
' reader (B2IO: the passes after) -- where they are, for errors
COMMON SHARED Tok, TokS$, TokV, TokLine, TokFile$, TokText$, TokNewLine
COMMON SHARED LineFile$, PrevLine, PrevText$, PrevFile$

' ---- B2IO: the record just read (its kind Rk and operands), the header
' read (InHead) and the counts written (OutHead)
COMMON SHARED Rk, RB1, RB2, RB3, RW1, RW2, RS$, RS2$, RNP, RPT(), RPF()
COMMON SHARED InHead(), OutHead(), OutPos, InPend, InPendK
' the procedure being copied: CBEGIN's fields (CBxxx)
COMMON SHARED CbKind, CbPw, CbRw, CbResOff, CbResTy, CbMark, CbLocal, CbLab
COMMON SHARED CbZero, CbFlags, CbName$, CbSeg$, CbPos, InProc
' the bytes of code being collected for a CBYTES record
COMMON SHARED OutBuf() AS BYTE, NOutBuf, InBuf() AS BYTE, TempUsed, NGrown

' ---- the symbol table (B2DECL, B2NAME: B2SYMT)
COMMON SHARED NSym, NModSym, NPar, CurSeg, NSegName, SymCap, ParCap, NodeCap
COMMON SHARED SName$(), SKind() AS BYTE, SType() AS BYTE, SCls() AS BYTE
COMMON SHARED SOff(), SFlags() AS BYTE, SScope() AS BYTE, SNext()
COMMON SHARED SAux(), SAux2(), SSeg() AS BYTE, HashHead()
COMMON SHARED PType() AS BYTE, PFlg() AS BYTE, SegName$(), DefType()
COMMON SHARED StaticWords, DeclName$, DeclFlags, ParName$(), ParFlags(), NData

' ---- B2EXPR's: one statement's expression nodes, and the operands they
' name (its symbols: SKind ... above, STx$ their names in messages)
COMMON SHARED NNode, NOp() AS BYTE, NTy() AS BYTE, NA(), NB(), NV(), NX()
COMMON SHARED NN(), NS$(), NIsBool() AS BYTE, PreNode, ArgCount, HiNode, STx$()
CONST NICON = 1, NRCON = 2, NSCON = 3, NVAR = 4, NELEM = 5, NCALL = 6
CONST NBUILT = 7, NNEG = 8, NNOT = 9, NBIN = 10, NCONV = 11, NBOOL = 12
CONST NADDR = 13

' ---- the procedures one module calls in another (generated: tools/mkdecls.py)
#INCLUDE "B2PROCS"
