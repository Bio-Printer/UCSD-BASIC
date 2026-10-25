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

' ---- expression nodes
CONST NICON = 1, NRCON = 2, NSCON = 3, NVAR = 4, NELEM = 5, NCALL = 6
CONST NBUILT = 7, NNEG = 8, NNOT = 9, NBIN = 10, NCONV = 11, NBOOL = 12
CONST NADDR = 13

' ---- control structures (EXIT, CONTINUE)
CONST CFOR = 1, CDO = 2, CWHILE = 3, CSELECT = 4

' ---- the emitter: one procedure's code
COMMON SHARED Code() AS BYTE, PC
COMMON SHARED LabPos(), NLab, FixPos(), FixLab(), NFix
COMMON SHARED RelPos(), RelType() AS BYTE, RelSym(), NRel
COMMON SHARED CurLocal, MaxLocal, NParamWords, ResWords, NeedZero
COMMON SHARED ProcSym, ExitLab, RetLab, MarkOff, UsedMark, TempUsed
COMMON SHARED NGosub, GosubOff, ResultOff, InProc, EntryBytes, CodeEndPos, NLong

' ---- expression nodes (one statement's)
COMMON SHARED NNode, NOp() AS BYTE, NTy() AS BYTE, NA(), NB(), NV(), NX()
COMMON SHARED NN(), NS$(), NIsBool() AS BYTE, PreNode, ArgCount

' ---- control structures being compiled
COMMON SHARED NCtl, CtlKind(), CtlExit(), CtlCont(), NFor, PendNext

' ---- constants' texts (CONST X = "..." or a real)
COMMON SHARED ConstText$(), NConst

' ---- the listing
COMMON SHARED LstOpen, HiNode, HiPC, HiFix, HiLab, HiRel, HiSym

