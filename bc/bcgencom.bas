' BCGENCOM -- shared by the modules of pass 3 (BCEMIT, BCEXPR, BCGEN, BCLIST)

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

' ---- the stream BCGEN writes and BCASM reads (:BCTEMP.ASM): records, a
' byte each and its operands (b a byte, w a word, s a string)
' AMBYTES n, n bytes: code     AMJUMP op, label   AMCASE label (a case word)
' AMLABEL label (set here)     AMALIAS l, m (l is where m is)
' AMREL type, s (the name)     AMFILE s (the lines' file)
' AMLINE w (the line), s (its text, with a listing)
' AMDROP (a skipped procedure: its listing record goes)
' AMBEGIN, AMLEXIT (the listing's "(exit)"), AMENTRY ... AMENTRYEND (the
' entry code, made last, put in front), AMEND (exit label, data words,
' parameter words, result words, flags, name, segment, and where: line,
' file, text), AMOBJB b, AMOBJW w, AMOBJS s (the object file's other
' records), AMSIZE w (the most lines of a procedure), AMEOF
CONST AMBYTES = 1, AMJUMP = 2, AMCASE = 3, AMLABEL = 4, AMALIAS = 5, AMREL = 6
CONST AMFILE = 7, AMLINE = 8, AMDROP = 9, AMBEGIN = 10, AMLEXIT = 11, AMENTRY = 12
CONST AMENTRYEND = 13, AMEND = 14, AMOBJB = 15, AMOBJW = 16, AMOBJS = 17
CONST AMSIZE = 18, AMEOF = 19

' ---- expression nodes
CONST NICON = 1, NRCON = 2, NSCON = 3, NVAR = 4, NELEM = 5, NCALL = 6
CONST NBUILT = 7, NNEG = 8, NNOT = 9, NBIN = 10, NCONV = 11, NBOOL = 12
CONST NADDR = 13

' ---- control structures (EXIT, CONTINUE)
CONST CFOR = 1, CDO = 2, CWHILE = 3, CSELECT = 4

' ---- the emitter: one procedure's code
COMMON SHARED Code() AS BYTE, PC
COMMON SHARED LabPos(), NLab, FixPos(), FixLab(), NFix
COMMON SHARED RelPos(), RelType() AS BYTE, RelSym(), NRel, RelName$()
COMMON SHARED CurLocal, MaxLocal, NParamWords, ResWords, NeedZero
COMMON SHARED ProcSym, ExitLab, RetLab, MarkOff, UsedMark, TempUsed
COMMON SHARED NGosub, GosubOff, ResultOff, InProc, EntryBytes, CodeEndPos, NLong

' ---- expression nodes (one statement's)
COMMON SHARED NNode, NOp() AS BYTE, NTy() AS BYTE, NA(), NB(), NV(), NX()
COMMON SHARED NN(), NS$(), NIsBool() AS BYTE, PreNode, ArgCount

' ---- control structures being compiled
COMMON SHARED NCtl, CtlKind(), CtlExit(), CtlCont(), NFor, PendNext

' ---- the procedure's line table (the object file's: where each line's
' code starts; LnPC -1 a file change, LnNo its LnFile$)
COMMON SHARED LnPC(), LnNo(), NLn, LnCap, LnFile$(), NLnFile, LnCurF$

' ---- the listing
COMMON SHARED LstOpen, HiNode, HiPC, HiFix, HiLab, HiRel, HiSym

