' B2DECL -- pass 3: the module's declarations (BC's pass 2)
'
' Reads B2SYN's file once and enters what every procedure may use before
' its text is compiled: the SUBs and FUNCTIONs (defined here or DECLAREd:
' their parameters and types, their segment), the shared variables (DIM
' SHARED, COMMON SHARED), OPTION EXPLICIT, the DATA statements (into
' :B2TEMP.DAT) and the labels' DATA numbers.  DEFINT ... are followed in
' order, so a parameter gets the type its letter has where the procedure
' is.  Writes them to the symbol file :B2TEMP.SYM for B2NAME.
#INCLUDE "B2COM"
#INCLUDE "B2REC"
#INCLUDE "B2SYM"

' SUB/FUNCTION NAME (params) [AS type] [STATIC]: the procedure's symbol
' (made, or the DECLAREd one checked).  isfunc: a FUNCTION; the name is
' current.
FUNCTION ProcHeader (isfunc, defining, priv)
    DIM nm$, ty, fl, np, s, i, j, same
    IF Tok <> TIDENT THEN
        ErrNo 17   ' a procedure name expected
        SkipStmt
        EXIT FUNCTION
    END IF
    nm$ = TokS$
    GetTok
    np = ParseParams
    IF isfunc THEN
        ty = DeclType(nm$, 1)
        nm$ = DeclName$
        fl = DeclFlags
    ELSE
        ty = TYVOID
        IF SuffixType(nm$) THEN ErrNo 18   ' a SUB name with a type suffix
    END IF
    IF Tok = KSTATIC THEN GetTok
    s = FindProc(nm$)
    IF s > 0 THEN
        ' declared before: the same parameters?
        same = SAux2(s) = np AND SType(s) = ty
        IF same THEN
            FOR i = 1 TO np
                j = SAux(s) + i - 1
                IF PType(j) <> PType(NPar + i) OR PFlg(j) <> PFlg(NPar + i) OR PLen(j) <> PLen(NPar + i) THEN same = 0
            NEXT i
        END IF
        IF NOT same THEN ErrRec 19, 0, 0, nm$   ' {s}: not as declared before
        IF defining THEN
            IF SFlags(s) AND SFDEFINED THEN ErrRec 20, 0, 0, nm$   ' {s} defined twice
            SFlags(s) = SFlags(s) OR SFDEFINED
            SSeg(s) = CurSeg
        END IF
    ELSE
        IF FindSym(nm$) > 0 THEN ErrRec 21, 0, 0, nm$   ' {s} is already the name of something else
        IF isfunc THEN s = AddSym(nm$, SKFUNC, ty) ELSE s = AddSym(nm$, SKSUB, ty)
        SFlags(s) = fl
        SAux(s) = NPar + 1
        SAux2(s) = np
        NPar = NPar + np
        SSeg(s) = CurSeg
        IF defining THEN SFlags(s) = SFlags(s) OR SFDEFINED
    END IF
    IF priv THEN SFlags(s) = SFlags(s) OR SFPRIVATE
    ProcHeader = s
END FUNCTION

' a shared variable (DIM SHARED, COMMON SHARED): nm$, an array of nd
' dimensions (-1: not an array), its type after it (AS)
SUB DeclVar (nm$, nd, iscommon)
    DIM ty, s, kind
    kind = SKVAR
    IF nd >= 0 THEN kind = SKARRAY
    IF iscommon OR nd < 0 THEN nd = 0
    ty = DeclType(nm$, 0)
    nm$ = DeclName$
    s = FindSym(nm$)
    IF s > 0 THEN
        ErrRec 24, 0, 0, nm$   ' {s} declared twice
        EXIT SUB
    END IF
    s = AddSym(nm$, kind, ty)
    SFlags(s) = DeclFlags OR SFSHARED
    SLen(s) = DeclLen
    SAux(s) = nd
    IF iscommon THEN
        SCls(s) = SCCOMMON
    ELSE
        SCls(s) = SCSTATIC
        SOff(s) = StaticWords
        IF kind = SKARRAY THEN
            StaticWords = StaticWords + 1
        ELSE
            StaticWords = StaticWords + TypeWords(ty)
        END IF
    END IF
END SUB

' DIM SHARED's items (B2SYN's form: TIDENT, TINT n, n bounds, [AS type])
SUB DeclDim ()
    DIM nm$, nd
    DO WHILE Tok = TIDENT
        nm$ = TokS$
        GetTok
        nd = TokV
        GetTok
        ' (the bounds: B2STMT's)
        DO WHILE Tok = RX
            DO
                GetTok
            LOOP UNTIL Tok = RXE OR AtEnd
            IF Tok = RXE THEN GetTok
        LOOP
        DeclVar nm$, nd, 0
    LOOP
END SUB

' COMMON [SHARED] items: name [()] [AS type], ...
SUB DeclCommon ()
    DIM nm$, nd
    IF Tok = KSHARED THEN GetTok
    DO
        IF Tok <> TIDENT THEN
            ErrNo 23   ' a variable name expected
            SkipStmt
            EXIT SUB
        END IF
        nm$ = TokS$
        GetTok
        nd = -1
        IF Tok = TLPAR THEN
            nd = 0
            GetTok
            DO WHILE Tok <> TRPAR AND NOT AtEnd
                GetTok
            LOOP
            Expect TRPAR
        END IF
        DeclVar nm$, nd, 1
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

SUB DeclPass ()
    DIM s, k, priv
    ResetDefs
    OptExplicit = 0
    CurSeg = 1
    NData = 0
    GetTok
    DO WHILE Tok <> TEOF
        IF Tok = TLABEL THEN
            ' RESTORE label: the DATA statements before it
            s = AddSym("%" + TokS$, SKLABEL, 0)
            SAux(s) = NData
            GetTok
        ELSEIF Tok <> RSTMT THEN
            GetTok
        ELSE
            k = RB1
            GetTok
            SELECT CASE k
            CASE KDATA
                IF NData = 0 THEN OPEN DatName$ FOR OUTPUT AS #CHDAT
                PRINT #CHDAT, TokS$
                NData = NData + 1
                GetTok
            CASE KDEFINT, KDEFSNG, KDEFDBL, KDEFSTR
                DefLetters DefKw(k)
            CASE KOPTION
                IF Tok = KEXPLICIT THEN
                    OptExplicit = 1
                    GetTok
                END IF
            CASE KSEGMENT
                IF Tok = TIDENT THEN
                    CurSeg = SegIndex(TokS$)
                    GetTok
                ELSE
                    CurSeg = 1
                END IF
            CASE KDECLARE
                IF Tok = KSUB OR Tok = KFUNCTION THEN
                    k = Tok
                    GetTok
                    s = ProcHeader(k = KFUNCTION, 0, 0)
                ELSE
                    ErrNo 25   ' SUB or FUNCTION expected
                END IF
            CASE KSUB, KFUNCTION
                priv = TokV
                GetTok
                s = ProcHeader(k = KFUNCTION, 1, priv)
            CASE KDIM
                IF TokV = 1 THEN
                    GetTok
                    GetTok
                    DeclDim
                END IF
            CASE KCOMMON
                DeclCommon
            END SELECT
            SkipStmt
        END IF
    LOOP
    IF NData > 0 THEN
        CLOSE #CHDAT
        ' the module's first DATA statement's number in the program's list
        s = AddSym("$DB", SKVAR, TYINT)
        SFlags(s) = SFSHARED
        SCls(s) = SCSTATIC
        SOff(s) = StaticWords
        StaticWords = StaticWords + 1
    END IF
    NModSym = NSym
END SUB

' ---- B2DECL, the program: pass 3 of the job's compile step, then B2NAME

ReadJob
StepNames
ErrCount = 0
InOpen PassFile$(2)
SymTables InHead(THGLOB) + 8, InHead(THPARAMS) + 1
InitSyms
MemNote "tables"
DeclPass
CLOSE #CHIN
IF ErrCount > 0 THEN CompileFailed
SymSave
IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words (B2DECL)"
ChainTo "B2NAME", ""
