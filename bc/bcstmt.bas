' BCSTMT -- pass 3: the statements (BCGEN: the module, its procedures, their
' blocks, the labels and the control structures; BCEXPR and BCEXGEN: their
' expressions)
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"

DIM SHARED CtlVar(MAXCTL), CtlLim(MAXCTL), CtlStep(MAXCTL), CtlStepI(MAXCTL)
DIM SHARED CtlStepS$(MAXCTL), CtlSign(MAXCTL)

' ---- helpers

SEGMENT EXPRGEN
' a condition: jump to falselab when it is false; the temporaries it made
' are given back on the way through (and AtFalse does it at falselab)
FUNCTION CondJ (c, falselab)
    GenCond c, falselab
    CondJ = TempUsed
    TempReset
END FUNCTION

SEGMENT STMT
SUB AtFalse (f)
    IF f THEN
        TempUsed = 1
        TempReset
    END IF
END SUB

SEGMENT DECL
' NOT c as a condition
FUNCTION NotCond (c)
    DIM n
    IF NIsBool(c) THEN
        n = NewNode(NNOT, TYINT)
        NA(n) = c
        NIsBool(n) = 2
        NotCond = n
    ELSE
        IF NTy(c) = TYSTR THEN ErrNo 27   ' type mismatch: a string as a condition
        NotCond = Compare(TEQ, c, ConvNode(IConst(0), NTy(c)))
    END IF
END FUNCTION

SEGMENT
FUNCTION SymNode (s)
    DIM n
    n = NewNode(NVAR, SType(s))
    IF SType(s) = TYBYTE THEN NTy(n) = TYINT
    NV(n) = s
    SymNode = n
END FUNCTION

' the target of an assignment, INPUT, READ ...: a variable or an element
' (made if it is new); 0 after an error
FUNCTION LValue ()
    DIM nm$, s
    IF Tok <> TIDENT THEN
        ErrNo 28   ' a variable expected
        SkipStmt
        EXIT FUNCTION
    END IF
    nm$ = TokS$
    GetTok
    s = FindVar(nm$)
    IF s > 0 THEN
        IF SKind(s) = SKARRAY THEN
            IF Tok <> TLPAR THEN
                ErrRec 29, 0, 0, nm$   ' {s} is an array: an index expected
                EXIT FUNCTION
            END IF
            LValue = ElemNode(s)
            EXIT FUNCTION
        END IF
        LValue = SymNode(s)
        EXIT FUNCTION
    END IF
    IF Tok = TLPAR THEN
        ErrRec 31, 0, 0, nm$   ' {s}: no such array (DIM it first)
        EXIT FUNCTION
    END IF
    s = LookupVar(nm$, 1)
    LValue = SymNode(s)
END FUNCTION

SEGMENT EXPRGEN
SUB Assign (lv, e)
    DIM ty
    ty = StoreType(lv)
    IF ty = TYBYTE THEN ty = TYINT
    StorePre lv
    GenValueAs e, ty
    GenStore lv
END SUB

' ---- labels

SEGMENT DECL
SUB GenGoto ()
    DIM s
    s = LabelSym(LabelText$)
    Jump OUJP, SAux(s)
END SUB

SUB GenGosub ()
    DIM s, l, k
    s = LabelSym(LabelText$)
    l = NewLabel
    k = GosubSite(l)
    Ldc k
    CallRt "_GSPUSH"
    Jump OUJP, SAux(s)
    SetLabel l
END SUB

' ---- control structures

SEGMENT STMT
SUB GenIf ()
    DIM c, lfalse, lend, f, t, l
    GetTok
    c = Expr
    IF Tok = KGOTO THEN
        ' IF c GOTO label
        GetTok
        lfalse = NewLabel
        f = CondJ(c, lfalse)
        GenGoto
        SetLabel lfalse
        AtFalse f
        EXIT SUB
    END IF
    Expect KTHEN
    lfalse = NewLabel
    IF Tok = TLINE OR Tok = TEOF THEN
        ' a block IF
        lend = NewLabel
        f = CondJ(c, lfalse)
        ResetNodes
        t = GenBlock
        DO
            IF t = KELSEIF THEN
                Jump OUJP, lend
                SetLabel lfalse
                AtFalse f
                c = Expr
                Expect KTHEN
                lfalse = NewLabel
                f = CondJ(c, lfalse)
                ResetNodes
                t = GenBlock
            ELSEIF t = KELSE THEN
                Jump OUJP, lend
                SetLabel lfalse
                AtFalse f
                f = 0
                lfalse = -1
                t = GenBlock
                EXIT DO
            ELSE
                EXIT DO
            END IF
        LOOP
        IF t <> TMEND + KIF THEN ErrNo 35   ' END IF expected
        IF lfalse >= 0 THEN
            SetLabel lfalse
            AtFalse f
        END IF
        SetLabel lend
        EXIT SUB
    END IF
    ' IF c THEN statements [ELSE statements] on one line
    f = CondJ(c, lfalse)
    ResetNodes
    IF Tok = TINT THEN GenGoto ELSE GenLineStmts
    IF Tok = KELSE THEN
        GetTok
        lend = NewLabel
        Jump OUJP, lend
        SetLabel lfalse
        AtFalse f
        IF Tok = TINT THEN GenGoto ELSE GenLineStmts
        SetLabel lend
    ELSE
        SetLabel lfalse
        AtFalse f
    END IF
END SUB

' the statements of a one-line IF: up to ELSE or the end of the line
SUB GenLineStmts ()
    DO
        IF Tok = TLINE OR Tok = TEOF OR Tok = KELSE THEN EXIT DO
        IF Tok = TCOLON THEN
            GetTok
        ELSE
            GenStmt
            TempReset
            ResetNodes
            IF Tok <> TCOLON THEN EXIT DO
        END IF
    LOOP
END SUB

SEGMENT EXPRGEN
' the comparison of a FOR: v <= limit (up) or v >= limit (down)
SUB ForTest (k, up, lexit)
    DIM s, ty, w
    s = CtlVar(k)
    ty = SType(s)
    IF ty = TYBYTE THEN ty = TYINT
    GenLoad SymNode(s)
    w = TypeWords(ty)
    IF w = 1 THEN
        Ldl CtlLim(k)
    ELSE
        Lla CtlLim(k)
        OB OLDM
        OB w
    END IF
    IF up THEN GenCompare TLE, ty ELSE GenCompare TGE, ty
    Jump OFJP, lexit
END SUB

' the step of a FOR (a constant, or its local)
SUB ForStep (k, ty)
    DIM n
    IF CtlStep(k) > 0 THEN
        IF TypeWords(ty) = 1 THEN
            Ldl CtlStep(k)
        ELSE
            Lla CtlStep(k)
            OB OLDM
            OB TypeWords(ty)
        END IF
    ELSEIF ty = TYINT THEN
        Ldc CtlStepI(k)
    ELSE
        n = NewNode(NRCON, ty)
        NS$(n) = CtlStepS$(k)
        GenValue n
    END IF
END SUB

SEGMENT STMT
SUB GenFor ()
    DIM nm$, s, ty, e1, e2, e3, lv, w, k, ltop, lcont, lexit, lneg, lbody, t
    GetTok
    IF Tok <> TIDENT THEN
        ErrNo 36   ' a FOR variable expected
        SkipStmt
        EXIT SUB
    END IF
    nm$ = TokS$
    GetTok
    s = FindVar(nm$)
    IF s = 0 THEN s = LookupVar(nm$, 1)
    IF SKind(s) <> SKVAR OR SType(s) = TYSTR THEN ErrNo 37   ' FOR needs a numeric variable
    ty = SType(s)
    IF ty = TYBYTE THEN ty = TYINT
    w = TypeWords(ty)
    Expect TEQ
    e1 = Expr
    Expect KTO
    e2 = Expr
    IF Tok = KSTEP THEN
        GetTok
        e3 = Expr
    ELSE
        e3 = IConst(1)
    END IF
    NFor = NFor + 1
    IF NFor > 30 THEN ErrNo 38   ' FOR loops nested more than 30 deep
    ltop = NewLabel
    lcont = NewLabel
    lexit = NewLabel
    k = PushCtl(CFOR, lexit, lcont)
    CtlVar(k) = s
    lv = SymNode(s)
    Assign lv, e1
    CtlLim(k) = NewLocal(w)
    IF w > 1 THEN Lla CtlLim(k)
    GenValueAs e2, ty
    IF w = 1 THEN
        Stl CtlLim(k)
    ELSE
        OB OSTM
        OB w
    END IF
    e3 = ConvNode(e3, ty)
    CtlStep(k) = 0
    CtlSign(k) = 0
    IF NOp(e3) = NICON THEN
        CtlStepI(k) = NV(e3)
        IF NV(e3) < 0 THEN CtlSign(k) = -1 ELSE CtlSign(k) = 1
    ELSEIF NOp(e3) = NRCON THEN
        IF NX(e3) THEN
            CtlStepS$(k) = "-" + NS$(e3)
            CtlSign(k) = -1
        ELSE
            CtlStepS$(k) = NS$(e3)
            CtlSign(k) = 1
        END IF
    ELSE
        CtlStep(k) = NewLocal(w)
        IF w > 1 THEN Lla CtlStep(k)
        GenValue e3
        IF w = 1 THEN
            Stl CtlStep(k)
        ELSE
            OB OSTM
            OB w
        END IF
    END IF
    TempReset
    ResetNodes
    SetLabel ltop
    IF CtlSign(k) > 0 THEN
        ForTest k, 1, lexit
    ELSEIF CtlSign(k) < 0 THEN
        ForTest k, 0, lexit
    ELSE
        ' the step's sign at run time
        lneg = NewLabel
        lbody = NewLabel
        ForStep k, ty
        GenValue ConvNode(IConst(0), ty)
        GenCompare TGE, ty
        Jump OFJP, lneg
        ForTest k, 1, lexit
        Jump OUJP, lbody
        SetLabel lneg
        ForTest k, 0, lexit
        SetLabel lbody
        ResetNodes
    END IF
    t = GenBlock
    IF t <> KNEXT THEN ErrNo 39   ' NEXT expected
    IF PendNext THEN PendNext = 0
    IF Tok = TIDENT THEN
        GetTok
        IF Tok = TCOMMA THEN
            GetTok
            PendNext = 1
        END IF
    END IF
    ' v = v + step
    SetLabel lcont
    lv = SymNode(s)
    StorePre lv
    GenLoad lv
    ForStep k, ty
    IF ty = TYINT THEN
        OB OADI
    ELSEIF ty = TYSNG THEN
        OB OADR
    ELSE
        EmitCsp 100
    END IF
    GenStore lv
    Jump OUJP, ltop
    SetLabel lexit
    NCtl = NCtl - 1
    NFor = NFor - 1
    ResetNodes
END SUB

SUB GenDo ()
    DIM c, ltop, lcont, lexit, f1, f2, t, k
    GetTok
    ltop = NewLabel
    lcont = NewLabel
    lexit = NewLabel
    SetLabel ltop
    IF Tok = KWHILE OR Tok = KUNTIL THEN
        k = Tok
        GetTok
        c = Expr
        IF k = KUNTIL THEN c = NotCond(c)
        f1 = CondJ(c, lexit)
        ResetNodes
    END IF
    k = PushCtl(CDO, lexit, lcont)
    t = GenBlock
    IF t <> KLOOP THEN ErrNo 40   ' LOOP expected
    NCtl = NCtl - 1
    SetLabel lcont
    IF Tok = KWHILE OR Tok = KUNTIL THEN
        k = Tok
        GetTok
        c = Expr
        IF k = KUNTIL THEN c = NotCond(c)
        f2 = CondJ(c, lexit)
        ResetNodes
    END IF
    Jump OUJP, ltop
    SetLabel lexit
    IF f1 OR f2 THEN AtFalse 1
END SUB

SUB GenWhile ()
    DIM c, ltop, lexit, f, t, k
    GetTok
    ltop = NewLabel
    lexit = NewLabel
    SetLabel ltop
    c = Expr
    f = CondJ(c, lexit)
    ResetNodes
    k = PushCtl(CWHILE, lexit, ltop)
    t = GenBlock
    IF t <> KWEND THEN ErrNo 41   ' WEND expected
    NCtl = NCtl - 1
    Jump OUJP, ltop
    SetLabel lexit
    AtFalse f
END SUB

SUB GenSelect ()
    DIM e, ty, sel, lend, lnext, lbody, lskip, t, c, v1, v2, op, k, f, w
    GetTok
    Expect KCASE
    e = Expr
    ty = NTy(e)
    IF NIsBool(e) THEN ty = TYINT
    sel = TempFor(ty)
    Assign SymNode(sel), e
    TempReset
    ResetNodes
    lend = NewLabel
    k = PushCtl(CSELECT, lend, 0)
    t = GenBlock
    lnext = -1
    f = 0
    DO WHILE t = KCASE
        IF lnext >= 0 THEN
            SetLabel lnext
            AtFalse f
            lnext = -1
        END IF
        IF Tok = KELSE THEN
            GetTok
            t = GenBlock
            EXIT DO
        END IF
        lbody = NewLabel
        lnext = NewLabel
        f = 0
        DO
            IF Tok = KIS THEN
                GetTok
                op = Tok
                IF op < TEQ OR op > TGE THEN
                    ErrNo 42   ' a comparison expected after IS
                    op = TEQ
                ELSE
                    GetTok
                END IF
                c = Compare(op, SymNode(sel), Expr)
            ELSE
                v1 = Expr
                IF Tok = KTO THEN
                    GetTok
                    v2 = Expr
                    c = Logic(1, Compare(TGE, SymNode(sel), v1), Compare(TLE, SymNode(sel), v2))
                ELSE
                    c = Compare(TEQ, SymNode(sel), v1)
                END IF
            END IF
            IF Tok = TCOMMA THEN
                GetTok
                lskip = NewLabel
                GenCond c, lskip
                Jump OUJP, lbody
                SetLabel lskip
                ResetNodes
            ELSE
                GenCond c, lnext
                EXIT DO
            END IF
        LOOP
        f = TempUsed
        SetLabel lbody
        TempReset
        ResetNodes
        t = GenBlock
        Jump OUJP, lend
    LOOP
    IF lnext >= 0 THEN
        SetLabel lnext
        AtFalse f
    END IF
    IF t <> TMEND + KSELECT THEN ErrNo 43   ' END SELECT expected
    SetLabel lend
    NCtl = NCtl - 1
    IF ty = TYSTR THEN
        Lla SOff(sel)
        CallRt "_SFREE"
    END IF
END SUB

SEGMENT STMTIO
SUB GenReturn ()
    DIM e
    GetTok
    IF AtEnd THEN
        Jump OUJP, RetLab
        EXIT SUB
    END IF
    IF ResultOff = 0 THEN
        ErrNo 49   ' RETURN with a value outside a FUNCTION
        SkipStmt
        EXIT SUB
    END IF
    e = Expr
    Assign SymNode(FindSym("!R")), e
    Jump OUJP, ExitLab
END SUB

SEGMENT STMTA
' ON n GOTO / GOSUB labels; ON ERROR GOTO 0 / RESUME NEXT
SUB GenOn ()
    DIM e, isgosub, n, i, lafter, site, labs(50), stubs(50)
    GetTok
    IF Tok = KERROR THEN
        GetTok
        IF Tok = KRESUME THEN
            GetTok
            Expect KNEXT
            Ldc 1
        ELSE
            Expect KGOTO
            IF Tok <> TINT THEN
                ErrNo 50   ' only ON ERROR GOTO 0 and ON ERROR RESUME NEXT
            ELSEIF TokV <> 0 THEN
                ErrNo 50   ' only ON ERROR GOTO 0 and ON ERROR RESUME NEXT
            END IF
            GetTok
            Ldc 0
        END IF
        CallRt "_ONERR"
        EXIT SUB
    END IF
    e = ToInt(Expr)
    IF Tok = KGOSUB THEN
        isgosub = 1
    ELSEIF Tok <> KGOTO THEN
        ErrNo 51   ' GOTO or GOSUB expected
        EXIT SUB
    END IF
    GetTok
    n = 0
    DO
        n = n + 1
        IF n > 50 THEN
            ErrNo 52   ' more than 50 labels
            n = 50
        END IF
        labs(n) = SAux(LabelSym(LabelText$))
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
    GenValue e
    TempReset
    lafter = NewLabel
    OB OXJP
    IF PC AND 1 THEN OB 0
    OW 1
    OW n
    Jump OUJP, lafter
    IF isgosub THEN
        site = GosubSite(lafter)
        FOR i = 1 TO n
            stubs(i) = NewLabel
            CaseWord stubs(i)
        NEXT i
        FOR i = 1 TO n
            SetLabel stubs(i)
            Ldc site
            CallRt "_GSPUSH"
            Jump OUJP, labs(i)
        NEXT i
    ELSE
        FOR i = 1 TO n
            CaseWord labs(i)
        NEXT i
    END IF
    SetLabel lafter
END SUB

' ---- PRINT, INPUT

SEGMENT STMTIO
' the file number of PRINT # / INPUT #: a constant or a local (ch < 0)
FUNCTION FileNum ()
    DIM e, t
    e = ToInt(Expr)
    IF NOp(e) = NICON THEN
        FileNum = NV(e)
        EXIT FUNCTION
    END IF
    t = NewLocal(1)
    GenValue e
    Stl t
    FileNum = -t
END FUNCTION

SUB PushCh (ch)
    IF ch >= 0 THEN Ldc ch ELSE Ldl -ch
END SUB

SUB GenPrint ()
    DIM ch, nl, e, ty, nm$
    GetTok
    ch = 0
    IF Tok = THASH THEN
        GetTok
        ch = FileNum
        IF Tok = TCOMMA OR Tok = TSEMI THEN GetTok ELSE ErrNo 53   ' , expected
    END IF
    IF Tok = KUSING THEN
        ErrNo 54   ' PRINT USING is not supported
        SkipStmt
        EXIT SUB
    END IF
    nl = 1
    DO WHILE NOT AtEnd
        IF Tok = TSEMI THEN
            GetTok
            nl = 0
        ELSEIF Tok = TCOMMA THEN
            GetTok
            PushCh ch
            CallRt "_PCOMMA"
            nl = 0
        ELSE
            nm$ = ""
            IF Tok = TIDENT THEN nm$ = TokS$
            IF nm$ = "TAB" OR nm$ = "SPC" THEN
                GetTok
                Expect TLPAR
                PushCh ch
                GenValueAs Expr, TYINT
                Expect TRPAR
                IF nm$ = "TAB" THEN CallRt "_PTAB" ELSE CallRt "_PSPC"
            ELSE
                e = Expr
                PushCh ch
                ty = NTy(e)
                IF NIsBool(e) THEN ty = TYINT
                GenValueAs e, ty
                SELECT CASE ty
                CASE TYSTR: CallRt "_PSTR"
                CASE TYINT: CallRt "_PINT"
                CASE TYSNG: CallRt "_PSNG"
                CASE TYDBL: CallRt "_PDBL"
                END SELECT
            END IF
            nl = 1
            TempReset
            ResetNodes
        END IF
    LOOP
    IF nl THEN
        PushCh ch
        CallRt "_PNL"
    END IF
END SUB

' INPUT / LINE INPUT: the file or the prompt; CallRt _INPUT or leaves the
' prompt for LINE INPUT
SUB GenInput (isline)
    DIM ch, qm, lv, ty, e, hasprompt
    GetTok
    ch = 0
    IF Tok = THASH THEN
        GetTok
        ch = FileNum
        Expect TCOMMA
    ELSE
        IF Tok = TSEMI THEN GetTok
        qm = 1
        IF Tok = TSTR THEN
            e = NewNode(NSCON, TYSTR)
            NS$(e) = TokS$
            hasprompt = 1
            GetTok
            IF Tok = TCOMMA THEN
                qm = 0
                GetTok
            ELSE
                Expect TSEMI
            END IF
        END IF
    END IF
    IF isline THEN
        lv = LValue
        IF lv = 0 THEN EXIT SUB
        IF StoreType(lv) <> TYSTR THEN ErrNo 55   ' LINE INPUT needs a string variable
        StorePre lv
        PushCh ch
        IF hasprompt THEN GenValue e ELSE Ldc 0
        CallRt "_LINPUT"
        TempUsed = 1
        GenStore lv
        EXIT SUB
    END IF
    PushCh ch
    IF hasprompt THEN GenValue e ELSE Ldc 0
    Ldc qm
    CallRt "_INPUT"
    DO
        lv = LValue
        IF lv = 0 THEN EXIT SUB
        ty = StoreType(lv)
        StorePre lv
        SELECT CASE ty
        CASE TYSTR
            OB 0
            CallRt "_INFS"
            TempUsed = 1
        CASE TYINT, TYBYTE
            OB 0
            CallRt "_INFI"
        CASE TYSNG
            DropPad 4
            CallRt "_INFD"
            EmitCsp 107
        CASE TYDBL
            DropPad 4
            CallRt "_INFD"
        END SELECT
        GenStore lv
        ResetNodes
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' ---- files

SEGMENT STMTA
SUB GenOpen ()
    DIM f, mode, n, r
    GetTok
    f = Expr
    Expect KFOR
    SELECT CASE Tok
    CASE KINPUT: mode = 1
    CASE KOUTPUT: mode = 2
    CASE KAPPEND: mode = 3
    CASE KBINARY: mode = 4
    CASE KRANDOM: mode = 5
    CASE ELSE
        ErrNo 56   ' INPUT, OUTPUT, APPEND, BINARY or RANDOM expected
    END SELECT
    GetTok
    Expect KAS
    IF Tok = THASH THEN GetTok
    n = Expr
    r = IConst(0)
    IF Tok = TIDENT THEN
        IF TokS$ = "LEN" THEN
            GetTok
            Expect TEQ
            r = Expr
        END IF
    END IF
    GenValueAs f, TYSTR
    Ldc mode
    GenValueAs n, TYINT
    GenValueAs r, TYINT
    CallRt "_OPEN"
END SUB

SUB GenClose ()
    GetTok
    IF AtEnd THEN
        Ldc 0
        CallRt "_CLOSE"
        EXIT SUB
    END IF
    DO
        IF Tok = THASH THEN GetTok
        GenValueAs Expr, TYINT
        CallRt "_CLOSE"
        ResetNodes
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

SEGMENT EXPRGEN
' the bytes GET and PUT move for a type
FUNCTION TypeBytes (ty)
    SELECT CASE ty
    CASE TYBYTE: TypeBytes = 1
    CASE TYINT: TypeBytes = 2
    CASE TYSNG: TypeBytes = 4
    CASE TYDBL: TypeBytes = 8
    END SELECT
END FUNCTION

SEGMENT STMTIO
' GET #n, [pos], var  /  PUT #n, [pos], value
SUB GenGetPut (isput)
    DIM n, p, lv, e, ty, t, x
    GetTok
    IF Tok = THASH THEN GetTok
    n = ToInt(Expr)
    Expect TCOMMA
    p = 0
    IF Tok <> TCOMMA THEN p = Expr
    Expect TCOMMA
    IF p > 0 THEN
        GenValue n
        GenValueAs p, TYSNG
        CallRt "_SEEK"
    END IF
    IF isput THEN
        e = Expr
        ty = NTy(e)
        IF NIsBool(e) THEN ty = TYINT
        IF IsLvalue(e) THEN ty = StoreType(e)
        IF ty = TYSTR THEN
            GenValue n
            GenValue e
            CallRt "_PUTS"
            EXIT SUB
        END IF
        IF IsLvalue(e) THEN
            GenAddr e
        ELSE
            t = TempFor(ty)
            x = SymNode(t)
            Assign x, e
            Lla SOff(t)
        END IF
        GenValue n
        Ldc TypeBytes(ty)
        CallRt "_PUTR"
        EXIT SUB
    END IF
    lv = LValue
    IF lv = 0 THEN EXIT SUB
    ty = StoreType(lv)
    IF ty = TYSTR THEN
        StorePre lv
        GenValue n
        GenLoad lv
        CallRt "_SLEN"
        CallRt "_GETS"
        TempUsed = 1
        GenStore lv
    ELSE
        GenAddr lv
        GenValue n
        Ldc TypeBytes(ty)
        CallRt "_GETR"
    END IF
END SUB

' ---- declarations

SEGMENT STMTD
' the bytes of an array element
FUNCTION ElemBytes (ty)
    SELECT CASE ty
    CASE TYBYTE: ElemBytes = 1
    CASE TYSNG: ElemBytes = 4
    CASE TYDBL: ElemBytes = 8
    CASE ELSE: ElemBytes = 2
    END SELECT
END FUNCTION

' DIM / REDIM [SHARED] [PRESERVE] name[(bounds)] [AS type], ...
SUB GenDim (isredim)
    DIM isshared, ispreserve, nm$, ty, fl, s, b, nd, x, isarr, k
    GetTok
    IF Tok = KSHARED THEN
        isshared = 1
        GetTok
        IF InProc THEN ErrNo 57   ' DIM SHARED inside a procedure
    END IF
    IF Tok = KPRESERVE THEN
        ispreserve = 1
        GetTok
    END IF
    DO
        IF Tok <> TIDENT THEN
            ErrNo 23   ' a variable name expected
            SkipStmt
            EXIT SUB
        END IF
        nm$ = TokS$
        GetTok
        isarr = 0
        b = 0
        nd = 0
        IF Tok = TLPAR THEN
            isarr = 1
            b = ParseArgs
            nd = ArgCount
        END IF
        ty = DeclType(nm$, 0)
        fl = DeclFlags
        s = 0
        IF isshared THEN
            s = FindSym(DeclName$)
        ELSEIF isredim THEN
            s = FindVar(nm$)
            IF s > 0 THEN
                IF SKind(s) <> SKARRAY THEN s = 0
            END IF
        ELSEIF InProc = 0 THEN
            s = FindSym(DeclName$)
            IF s > 0 THEN
                IF SScope(s) <> 0 OR SKind(s) > SKARRAY THEN s = 0
            END IF
        ELSE
            s = FindSym(DeclName$)
            IF s > 0 THEN
                IF SScope(s) = 1 THEN ErrRec 24, 0, 0, nm$   ' {s} declared twice
            END IF
            s = 0
        END IF
        IF s = 0 THEN
            IF isarr THEN k = SKARRAY ELSE k = SKVAR
            s = NewVar(DeclName$, k, ty, fl)
            IF isarr THEN SAux(s) = nd
        END IF
        IF isarr AND nd = 0 THEN
            IF SKind(s) <> SKARRAY THEN ErrRec 58, 0, 0, nm$   ' {s} is not an array
        ELSEIF isarr THEN
            IF SKind(s) <> SKARRAY THEN ErrRec 58, 0, 0, nm$   ' {s} is not an array
            IF SAux(s) > 0 AND SAux(s) <> nd THEN ErrRec 59, 0, 0, nm$   ' {s}: the wrong number of dimensions
            IF SAux(s) = 0 THEN SAux(s) = nd
            x = b
            DO WHILE x > 0
                GenValueAs x, TYINT
                CallRt "_ABND"
                x = NN(x)
            LOOP
            GenSlot s
            Ldc ElemBytes(SType(s))
            k = 0
            IF SType(s) = TYSTR THEN k = 1
            IF ispreserve THEN k = k + 2
            Ldc k
            Ldc nd
            CallRt "_ADIM"
            TempReset
        END IF
        ResetNodes
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' ---- DATA, READ, RESTORE

SUB GenRead ()
    DIM lv, ty
    GetTok
    DO
        lv = LValue
        IF lv = 0 THEN EXIT SUB
        ty = StoreType(lv)
        StorePre lv
        OB 0
        CallRt "_READ"
        IF ty <> TYSTR THEN
            DropPad 3
            CallRt "_VAL"
            IF ty = TYSNG THEN
                EmitCsp 107
            ELSEIF ty <> TYDBL THEN
                CallRt "_DCINT"
            END IF
        END IF
        TempUsed = 1
        GenStore lv
        TempReset
        ResetNodes
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

SEGMENT DECL
SUB GenRestore ()
    DIM s, db
    GetTok
    db = FindSym("$DB")
    IF db = 0 THEN
        ErrNo 64   ' RESTORE without DATA
        SkipStmt
        EXIT SUB
    END IF
    GlobOp OLDO, db, 0
    IF NOT AtEnd THEN
        s = FindSym("%" + LabelText$)
        IF s = 0 THEN ErrNo 65 ELSE Ldc SAux(s): OB OADI   ' no such label
    END IF
    CallRt "_RESTORE"
END SUB

SEGMENT STMTIO
' WRITE [#n,] items: strings in quotes, numbers without blanks, commas
SUB GenWrite ()
    DIM ch, e, ty, first
    GetTok
    ch = 0
    IF Tok = THASH THEN
        GetTok
        ch = FileNum
        Expect TCOMMA
    END IF
    first = 1
    DO WHILE NOT AtEnd
        IF first = 0 THEN
            PushCh ch
            OB OLSA
            OB 1
            OB 44
            CallRt "_PSTR"
        END IF
        first = 0
        e = Expr
        ty = NTy(e)
        IF NIsBool(e) THEN ty = TYINT
        PushCh ch
        GenValueAs e, ty
        SELECT CASE ty
        CASE TYSTR: CallRt "_WQSTR"
        CASE TYINT
            CallRt "_STRI"
            CallRt "_LTRIM"
            CallRt "_PSTR"
        CASE TYSNG
            CallRt "_STRS"
            CallRt "_LTRIM"
            CallRt "_PSTR"
        CASE TYDBL
            CallRt "_STRD"
            CallRt "_LTRIM"
            CallRt "_PSTR"
        END SELECT
        TempUsed = 1
        TempReset
        ResetNodes
        IF Tok = TCOMMA OR Tok = TSEMI THEN GetTok
    LOOP
    PushCh ch
    CallRt "_PNL"
END SUB

' ---- other statements

SEGMENT STMTD
SUB GenSwap ()
    DIM a, b, ty
    GetTok
    a = LValue
    Expect TCOMMA
    b = LValue
    IF a = 0 OR b = 0 THEN EXIT SUB
    ty = StoreType(a)
    IF ty <> StoreType(b) THEN ErrNo 66   ' SWAP needs two variables of one type
    GenAddr a
    GenAddr b
    IF ty = TYSTR THEN
        CallRt "_SSWAP"
    ELSE
        Ldc TypeBytes(ty)
        CallRt "_SWAP"
    END IF
END SUB

SEGMENT STMTA
' a SUB called: name args / name(args) / CALL name(args)
SUB GenCallStmt (s)
    DIM n, a, k, last, x
    n = NewNode(NCALL, SType(s))
    NV(n) = s
    IF Tok = TLPAR THEN
        a = ArgList(s, 1, 0)
        IF NOT AtEnd AND ArgCount = 1 THEN
            ' name (x) * 2, y: (x) starts the first argument
            PreNode = a
            a = Expr
            k = 1
            last = a
            DO WHILE Tok = TCOMMA
                GetTok
                x = Expr
                NN(last) = x
                last = x
                k = k + 1
            LOOP
            ArgCount = k
        END IF
        IF ArgCount <> SAux2(s) THEN ErrRec 67, SAux2(s), 0, SName$(s)   ' {s}: {a} argument(s) expected
    ELSE
        a = ArgList(s, 0, 1)
    END IF
    NA(n) = a
    GenCall n, 0
END SUB

' a statement that starts with a name: an assignment, a SUB call, MID$( ) =,
' or one of the low-level statements (POKE, POKEB, CSP, OSCALL)
SUB GenIdentStmt ()
    DIM nm$, s, lv, e, a, n, k
    nm$ = TokS$
    IF nm$ = "MID$" AND FindProc(nm$) = 0 THEN
        GetTok
        Expect TLPAR
        lv = LValue
        IF lv = 0 THEN EXIT SUB
        IF StoreType(lv) <> TYSTR THEN ErrNo 68   ' MID$ needs a string variable
        GenAddr lv
        Expect TCOMMA
        GenValueAs Expr, TYINT
        IF Tok = TCOMMA THEN
            GetTok
            GenValueAs Expr, TYINT
        ELSE
            Ldc 255
        END IF
        Expect TRPAR
        Expect TEQ
        GenValueAs Expr, TYSTR
        CallRt "_MIDSET"
        EXIT SUB
    END IF
    ' (a procedure of the program by such a name is called instead)
    IF FindProc(nm$) > 0 THEN nm$ = ""
    IF nm$ = "POKE" OR nm$ = "POKEB" THEN
        GetTok
        GenValueAs Expr, TYINT
        IF nm$ = "POKEB" THEN OB 0
        Expect TCOMMA
        GenValueAs Expr, TYINT
        IF nm$ = "POKEB" THEN OB OSTB ELSE OB OSTO
        EXIT SUB
    END IF
    IF nm$ = "CSP" OR nm$ = "OSCALL" THEN
        GetTok
        e = Expr
        IF NOp(e) <> NICON THEN ErrRec 69, 0, 0, nm$   ' {s}: a constant expected
        k = NV(e)
        DO WHILE Tok = TCOMMA
            GetTok
            a = Expr
            GenValue a
        LOOP
        IF nm$ = "CSP" THEN
            EmitCsp k
        ELSE
            OB OCXP
            OB 0
            OB k
        END IF
        EXIT SUB
    END IF
    nm$ = TokS$
    ' the function's own name: its result
    IF InProc AND ResultOff > 0 THEN
        IF FindProc(nm$) = ProcSym THEN
            GetTok
            IF Tok = TEQ THEN
                GetTok
                Assign SymNode(FindSym("!R")), Expr
                EXIT SUB
            END IF
            ErrNo 70   ' = expected after the function's name
            EXIT SUB
        END IF
    END IF
    s = FindVar(nm$)
    IF s = 0 THEN
        s = FindProc(nm$)
        IF s > 0 THEN
            GetTok
            GenCallStmt s
            EXIT SUB
        END IF
    END IF
    lv = LValue
    IF lv = 0 THEN EXIT SUB
    Expect TEQ
    Assign lv, Expr
END SUB

SEGMENT STMTD
SUB GenEnd ()
    ' END [n]: the program stops (files closed)
    IF AtEnd THEN Ldc 0 ELSE GenValueAs Expr, TYINT
    CallRt "_HALT"
END SUB

SEGMENT STMT
SUB GenStmt ()
    DIM k, s
    k = Tok
    SELECT CASE k
    CASE TIDENT
        GenIdentStmt
    CASE KLET
        GetTok
        GenIdentStmt
    CASE KPRINT
        GenPrint
    CASE KINPUT
        GenInput 0
    CASE KLINE
        GetTok
        IF Tok <> KINPUT THEN ErrNo 71   ' LINE INPUT expected
        GenInput 1
    CASE KIF
        GenIf
    CASE KFOR
        GenFor
    CASE KDO
        GenDo
    CASE KWHILE
        GenWhile
    CASE KSELECT
        GenSelect
    CASE KGOTO
        GetTok
        GenGoto
    CASE KGOSUB
        GetTok
        GenGosub
    CASE KRETURN
        GenReturn
    CASE KON
        GenOn
    CASE KEXIT
        GenExitStmt 0
    CASE KCONTINUE
        GenExitStmt 1
    CASE KSTOP
        GetTok
        Ldc 0
        CallRt "_HALT"
    CASE KSYSTEM
        GetTok
        GenEnd
    CASE KDIM
        GenDim 0
    CASE KREDIM
        GenDim 1
    CASE KSTATIC
        GenStatic
    CASE KSHARED
        IF InProc = 0 THEN ErrNo 72   ' SHARED outside a procedure
        GenShared
    CASE KERASE
        GetTok
        DO
            IF Tok = TIDENT THEN
                s = FindVar(TokS$)
                IF s = 0 THEN
                    ErrRec 73, 0, 0, TokS$   ' no array {s}
                ELSEIF SKind(s) <> SKARRAY THEN
                    ErrRec 58, 0, 0, TokS$   ' {s} is not an array
                ELSE
                    GenSlot s
                    CallRt "_AFREE"
                END IF
                GetTok
            ELSE
                ErrNo 74   ' an array name expected
            END IF
            IF Tok <> TCOMMA THEN EXIT DO
            GetTok
        LOOP
    CASE KCALL
        GetTok
        IF Tok <> TIDENT THEN
            ErrNo 75   ' a SUB name expected
        ELSE
            s = FindProc(TokS$)
            IF s = 0 THEN
                ErrRec 76, 0, 0, TokS$   ' no SUB {s}
                SkipStmt
            ELSE
                GetTok
                GenCallStmt s
            END IF
        END IF
    CASE KOPEN
        GenOpen
    CASE KCLOSE
        GenClose
    CASE KGET
        GenGetPut 0
    CASE KPUT
        GenGetPut 1
    CASE KSEEK
        GetTok
        IF Tok = THASH THEN GetTok
        GenValueAs Expr, TYINT
        Expect TCOMMA
        GenValueAs Expr, TYSNG
        CallRt "_SEEK"
    CASE KKILL
        GetTok
        GenValueAs Expr, TYSTR
        CallRt "_KILL"
    CASE KCHAIN
        ' CHAIN "[VOL:]PROGRAM [options]": this program ends, that one runs
        GetTok
        GenValueAs Expr, TYSTR
        CallRt "_CHAIN"
    CASE KSWAP
        GenSwap
    CASE KRANDOMIZE
        GetTok
        ' (a DOUBLE: RANDOMIZE TIMER, beyond an INTEGER)
        IF AtEnd THEN GenValueAs IConst(0), TYDBL ELSE GenValueAs Expr, TYDBL
        CallRt "_RANDOMIZE"
    CASE KCLS
        GetTok
        CallRt "_CLS"
    CASE KLOCATE
        GetTok
        IF Tok = TCOMMA THEN Ldc 0 ELSE GenValueAs Expr, TYINT
        IF Tok = TCOMMA THEN
            GetTok
            GenValueAs Expr, TYINT
        ELSE
            Ldc 0
        END IF
        CallRt "_LOCATE"
    CASE KDEFINT, KDEFSNG, KDEFDBL, KDEFSTR
        GetTok
        DefLetters DefKw(k)
    CASE KOPTION, KDECLARE, KCOMMON, KSEGMENT, KDATA, TSKIP
        SkipStmt
    CASE KREAD
        GenRead
    CASE KRESTORE
        GenRestore
    CASE KWRITE
        GenWrite
    CASE ELSE
        ErrRec 77, 0, Tok, ""   ' a statement expected, not {t}
        SkipStmt
    END SELECT
END SUB
