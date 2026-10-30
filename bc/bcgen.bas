' BCGEN -- pass 3: statements, procedures, the module's object file
'
' The token file is read twice: first for the module's body (its
' statements outside every SUB and FUNCTION: one procedure, MODULE'BODY),
' then for the procedures.  Each procedure is compiled and written to the
' object file (BCEMIT) as soon as its END SUB / END FUNCTION is read.
' String temporaries a statement makes are given back after it (and on
' both ways out of a condition).
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"

' ---- helpers

SEGMENT STMT
SUB StmtEnd ()
    IF NOT AtEnd THEN
        ErrRec 26, 0, Tok, ""   ' the end of the statement expected, not {t}
        SkipStmt
    END IF
END SUB

' ---- labels

SEGMENT DECL
FUNCTION LabelText$ ()
    SELECT CASE Tok
    CASE TINT
        LabelText$ = IStr$(TokV)
    CASE TIDENT, TSNG, TDBL, TLABEL
        LabelText$ = TokS$
    CASE ELSE
        ErrNo 32   ' a label expected
    END SELECT
    GetTok
END FUNCTION

FUNCTION LabelSym (nm$)
    DIM s
    s = FindSym("@" + nm$)
    IF s > 0 THEN
        IF SScope(s) <> InProc THEN s = 0
    END IF
    IF s = 0 THEN
        s = AddSym("@" + nm$, SKLABEL, 0)
        SScope(s) = InProc
        SAux(s) = NewLabel
    END IF
    LabelSym = s
END FUNCTION

SUB DefineLabel (nm$)
    DIM s
    s = LabelSym(nm$)
    IF SFlags(s) AND SFSETLAB THEN ErrRec 33, 0, 0, nm$   ' label {s} defined twice
    SFlags(s) = SFlags(s) OR SFSETLAB
    SetLabel SAux(s)
END SUB

' ---- control structures

SEGMENT EXPRGEN
FUNCTION PushCtl (kind, ex, cont)
    IF NCtl >= MAXCTL THEN
        ErrNo 34   ' blocks nested too deep
        NCtl = 0
    END IF
    NCtl = NCtl + 1
    CtlKind(NCtl) = kind
    CtlExit(NCtl) = ex
    CtlCont(NCtl) = cont
    PushCtl = NCtl
END FUNCTION

SEGMENT DECL
FUNCTION FindCtl (kind)
    DIM i
    FOR i = NCtl TO 1 STEP -1
        IF CtlKind(i) = kind THEN
            FindCtl = i
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

SUB GenExitStmt (cont)
    DIM k, kind
    GetTok
    SELECT CASE Tok
    CASE KFOR: kind = CFOR
    CASE KDO: kind = CDO
    CASE KWHILE: kind = CWHILE
    CASE KSELECT: kind = CSELECT
    CASE KSUB, KFUNCTION
        IF cont THEN ErrNo 44   ' CONTINUE FOR, DO or WHILE expected
        IF InProc = 0 THEN ErrRec 45, 0, Tok, ""   ' EXIT {t} outside a procedure
        GetTok
        Jump OUJP, ExitLab
        EXIT SUB
    CASE ELSE
        ErrNo 46   ' FOR, DO, WHILE, SELECT, SUB or FUNCTION expected
        EXIT SUB
    END SELECT
    GetTok
    k = FindCtl(kind)
    IF k = 0 THEN
        ErrNo 47   ' not inside such a block
    ELSEIF cont THEN
        IF kind = CSELECT THEN ErrNo 48 ELSE Jump OUJP, CtlCont(k)   ' CONTINUE SELECT?
    ELSE
        Jump OUJP, CtlExit(k)
    END IF
END SUB

' ---- declarations

' STATIC x [AS type], ...: kept between calls (a module static)
SUB GenStatic ()
    DIM nm$, ty, s
    GetTok
    DO
        IF Tok <> TIDENT THEN
            ErrNo 23   ' a variable name expected
            SkipStmt
            EXIT SUB
        END IF
        nm$ = TokS$
        GetTok
        IF Tok = TLPAR THEN ErrNo 60   ' STATIC arrays are not supported
        ty = DeclType(nm$, 0)
        s = AddSym(DeclName$, SKVAR, ty)
        SFlags(s) = DeclFlags
        SScope(s) = InProc
        SCls(s) = SCSTATIC
        SOff(s) = StaticWords
        StaticWords = StaticWords + TypeWords(ty)
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' SHARED x, y inside a procedure: the module's variables of these names
SUB GenShared ()
    DIM nm$, s, t, a
    GetTok
    DO
        IF Tok <> TIDENT THEN
            ErrNo 23   ' a variable name expected
            SkipStmt
            EXIT SUB
        END IF
        nm$ = TokS$
        GetTok
        IF Tok = TLPAR THEN
            GetTok
            Expect TRPAR
        END IF
        IF Tok = KAS THEN
            GetTok
            t = ParseType
        END IF
        s = FindSym(nm$)
        IF s = 0 AND SuffixType(nm$) = 0 THEN s = FindSym(nm$ + TypeChar$(NameType(nm$)))
        IF s = 0 THEN
            ErrRec 61, 0, 0, nm$   ' no module variable {s}
        ELSEIF SScope(s) <> 0 OR SKind(s) > SKARRAY THEN
            ErrRec 61, 0, 0, nm$   ' no module variable {s}
        ELSE
            a = AddSym(SName$(s), SKind(s), SType(s))
            SFlags(a) = SFlags(s)
            SScope(a) = 1
            SCls(a) = SCls(s)
            SOff(a) = SOff(s)
            SAux(a) = SAux(s)
        END IF
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' ---- DATA, READ, RESTORE

SEGMENT
' the module's DATA statements (the declaration pass kept them in a file):
' given to the library's list when the body starts
SUB GenDataList ()
    DIM l$, n, i
    OB 0
    CallRt "_DMARK"
    GlobOp OSRO, FindSym("$DB"), 0
    OPEN DatName$ FOR INPUT AS #CHLTMP
    FOR i = 1 TO NData
        LINE INPUT #CHLTMP, l$
        OB OLSA
        OB LEN(l$)
        FOR n = 1 TO LEN(l$)
            OB ASC(l$, n)
        NEXT n
        CallRt "_DATA"
    NEXT i
    CLOSE #CHLTMP
    KILL DatName$
END SUB

' ---- other statements

' skip a SUB or FUNCTION (its body is compiled in the second reading)
SUB SkipProc ()
    DO
        SkipStmt
        IF Tok = TEOF THEN EXIT SUB
        GetTok
        DO WHILE Tok = TLABEL OR Tok = TLINE
            GetTok
        LOOP
        IF Tok = KEND THEN
            GetTok
            IF Tok = KSUB OR Tok = KFUNCTION THEN
                GetTok
                EXIT SUB
            END IF
        END IF
    LOOP
END SUB

SEGMENT STMT
' statements up to the end of a block: returns what ended it (ELSE,
' ELSEIF, NEXT, LOOP, WEND, CASE: the keyword read; END IF / SUB /
' FUNCTION / SELECT: TMEND + the keyword, both read; TEOF)
FUNCTION GenBlock ()
    DIM t
    DO
        SELECT CASE Tok
        CASE TEOF
            GenBlock = TEOF
            EXIT FUNCTION
        CASE TLINE
            ListLine
            GetTok
        CASE TCOLON
            GetTok
        CASE TLABEL
            DefineLabel TokS$
            GetTok
        CASE KELSE, KELSEIF, KNEXT, KLOOP, KWEND, KCASE
            t = Tok
            GetTok
            GenBlock = t
            EXIT FUNCTION
        CASE KEND
            GetTok
            IF Tok = KIF OR Tok = KSUB OR Tok = KFUNCTION OR Tok = KSELECT THEN
                t = TMEND + Tok
                GetTok
                GenBlock = t
                EXIT FUNCTION
            END IF
            GenEnd
            StmtEnd
        CASE KSUB, KFUNCTION, KPRIVATE
            IF InProc THEN
                ErrNo 78   ' a SUB or FUNCTION inside a procedure (END SUB missing?)
                GenBlock = TEOF
                EXIT FUNCTION
            END IF
            IF OptList THEN ListDrop
            SkipProc
        CASE ELSE
            GenStmt
            TempReset
            ResetNodes
            IF PendNext = 0 THEN StmtEnd
        END SELECT
        IF PendNext THEN
            GenBlock = KNEXT
            EXIT FUNCTION
        END IF
    LOOP
END FUNCTION

' ---- procedures

SEGMENT
SUB GenProc (priv)
    DIM isfunc, nm$, ty, np, s, i, pw, rw, off, w, p, t, r, ht$, hl, sv$, sl
    ht$ = TokText$
    hl = TokLine
    isfunc = Tok = KFUNCTION
    GetTok
    nm$ = TokS$
    GetTok
    np = ParseParams
    IF isfunc THEN
        ty = DeclType(nm$, 1)
        nm$ = DeclName$
    END IF
    IF Tok = KSTATIC THEN GetTok
    s = FindProc(nm$)
    IF s = 0 THEN
        ErrRec 79, 0, 0, nm$   ' internal: {s} not declared
        SkipProc
        EXIT SUB
    END IF
    InProc = 1
    ' the parameters' words: the first is pushed first (highest offset)
    pw = 0
    FOR i = 1 TO np
        p = SAux(s) + i - 1
        IF PFlg(p) <> 0 THEN pw = pw + 1 ELSE pw = pw + TypeWords(PType(p))
    NEXT i
    rw = 0
    IF isfunc THEN rw = TypeWords(SType(s))
    ResWords = rw
    off = 1
    IF rw > pw THEN off = rw - pw + 1
    NParamWords = off - 1 + pw
    BeginProc s
    ' the header line first in the listing
    sv$ = TokText$
    sl = TokLine
    TokText$ = ht$
    TokLine = hl
    ListLine
    TokText$ = sv$
    TokLine = sl
    FOR i = np TO 1 STEP -1
        p = SAux(s) + i - 1
        IF PFlg(p) AND PFARRAY THEN
            t = AddSym(ParName$(i), SKARRAY, PType(p))
        ELSE
            t = AddSym(ParName$(i), SKVAR, PType(p))
        END IF
        SFlags(t) = ParFlags(i)
        SScope(t) = 1
        IF PFlg(p) <> 0 THEN
            SCls(t) = SCREF
            w = 1
        ELSE
            SCls(t) = SCPARAM
            w = TypeWords(PType(p))
        END IF
        SOff(t) = off
        off = off + w
    NEXT i
    IF isfunc THEN
        r = AddSym("!R", SKVAR, SType(s))
        SScope(r) = 1
        SCls(r) = SCLOCAL
        SOff(r) = ResultOff
    END IF
    t = GenBlock
    IF isfunc THEN
        IF t <> TMEND + KFUNCTION THEN ErrNo 80   ' END FUNCTION expected
    ELSE
        IF t <> TMEND + KSUB THEN ErrNo 81   ' END SUB expected
    END IF
    EndProc
    InProc = 0
END SUB

' ---- the pass

SUB GenPass ()
    DIM t, s, k, w
    REDIM NOp(NodeCap) AS BYTE, NTy(NodeCap) AS BYTE, NA(NodeCap), NB(NodeCap)
    REDIM NV(NodeCap), NX(NodeCap), NN(NodeCap), NS$(NodeCap), NIsBool(NodeCap) AS BYTE
    REDIM CtlKind(MAXCTL), CtlExit(MAXCTL), CtlCont(MAXCTL)
    NNode = 0
    MemNote "gen arrays"
    ' the stream to BCASM (pass 4): it makes the object file and the
    ' listing's records
    IF FileExists(AsmName$) THEN KILL AsmName$
    OPEN AsmName$ FOR BINARY AS #CHASM
    StmRec AMSIZE
    StmWord LnCap
    ' the module's body
    ResetDefs
    InProc = 0
    NParamWords = 0
    ResWords = 0
    OpenTok
    BeginProc 0
    IF NData > 0 THEN GenDataList
    DO
        t = GenBlock
        IF t = TEOF THEN EXIT DO
        ErrRec 82, 0, t, ""   ' {t} without its block
    LOOP
    EndProc
    CLOSE #CHTOK
    MemNote "body"
    ' the procedures
    ResetDefs
    OpenTok
    DO WHILE Tok <> TEOF
        k = Tok
        IF k = KPRIVATE THEN
            GetTok
            k = Tok
        END IF
        SELECT CASE k
        CASE KSUB, KFUNCTION
            GenProc 0
        CASE KDEFINT, KDEFSNG, KDEFDBL, KDEFSTR
            GetTok
            DefLetters DefKw(k)
        CASE ELSE
            SkipStmt
            IF Tok <> TEOF THEN GetTok
        END SELECT
    LOOP
    CLOSE #CHTOK
    ' the module's COMMON variables, its statics, the end
    FOR s = 1 TO NSym
        IF SCls(s) = SCCOMMON AND SScope(s) = 0 AND (SFlags(s) AND SFRUNTIME) = 0 THEN
            ObjByte 68
            ObjByte 0
            ObjStr LinkName$(s)
            IF SKind(s) = SKARRAY THEN w = 1 ELSE w = TypeWords(SType(s))
            ObjWord w
        END IF
    NEXT s
    ObjByte 71
    ObjWord StaticWords
    ObjByte 69
    StmRec AMEOF
    CLOSE #CHASM
    IF OptMem THEN
        Say "  [high: code " + IStr$(HiPC) + ", jumps " + IStr$(HiFix) + ", labels " + IStr$(HiLab) + ", calls " + IStr$(HiRel) + ", nodes " + IStr$(HiNode)
        SayLn ", names " + IStr$(HiSym) + ", parameters " + IStr$(NPar) + "; tables grown " + IStr$(NGrown) + " times]"
    END IF
    ERASE NOp, NTy, NA, NB, NV, NX, NN, NS$, NIsBool, CtlKind, CtlExit, CtlCont
END SUB

' ---- BCGEN, the program: passes 2 and 3 of the job's compile step (the
' declarations, the code), then BCLIST for a listing

ReadJob
StepNames
ErrCount = 0
TokLine = 0
TokText$ = ""
' the tables: as large as BCLEX's counts (the token file's header) say
' they need, MAX constants at most -- the symbols, parameters and string
' constants for certain; an expression's nodes estimated (growing, Grown,
' if that was too few).  (A procedure's code and its labels, jumps, calls
' and lines are BCASM's: pass 4.)
OpenTok
CLOSE #CHTOK
IF TokHead(THMAGIC) <> TOKMAGIC THEN FatalRec 83, TokName$   ' not BCLEX's token file: {s}
' (and the run-time library's procedures a procedure calls)
SymCap = Capped(TokHead(THGLOB) + TokHead(THLOC) + 48, MAXSYM)
' (pass 3 reads each procedure's parameters again, after all of them)
ParCap = Capped(TokHead(THPARAMS) + TokHead(THMAXPAR) + 1, MAXPAR)
NodeCap = Capped(TokHead(THSTMT) \ 2 + 16, MAXNODE)
' (a procedure's lines, its header and its files' changes)
LnCap = Capped(TokHead(THLINES) + 8, 32000)
IF OptMem THEN
    SayLn "  [tables: " + IStr$(SymCap) + " names, " + IStr$(ParCap) + " parameters, nodes " + IStr$(NodeCap) + ", lines " + IStr$(LnCap) + "]"
END IF
REDIM SName$(SymCap), SKind(SymCap) AS BYTE, SType(SymCap) AS BYTE, SCls(SymCap) AS BYTE
REDIM SOff(SymCap), SFlags(SymCap) AS BYTE, SScope(SymCap) AS BYTE, SNext(SymCap)
REDIM SAux(SymCap), SAux2(SymCap), SSeg(SymCap) AS BYTE, HashHead(HSIZE)
REDIM PType(ParCap) AS BYTE, PFlg(ParCap) AS BYTE
MemNote "symbols"
InitSyms
DeclPass
MemNote "declared"
IF ErrCount = 0 THEN GenPass
IF ErrCount > 0 THEN CompileFailed
IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words (BCGEN)"
ChainTo "BCASM", ""
