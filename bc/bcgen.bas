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
SEGMENT GEN

CONST TMEND = 200
DIM SHARED CtlVar(MAXCTL), CtlLim(MAXCTL), CtlStep(MAXCTL), CtlStepI(MAXCTL)
DIM SHARED CtlStepS$(MAXCTL), CtlSign(MAXCTL)

' ---- helpers

SUB StmtEnd ()
    IF NOT AtEnd THEN
        ErrMsg "the end of the statement expected, not " + KwName$(Tok)
        SkipStmt
    END IF
END SUB

' a condition: jump to falselab when it is false; the temporaries it made
' are given back on the way through (and AtFalse does it at falselab)
FUNCTION CondJ (c, falselab)
    GenCond c, falselab
    CondJ = TempUsed
    TempReset
END FUNCTION

SUB AtFalse (f)
    IF f THEN
        TempUsed = 1
        TempReset
    END IF
END SUB

' NOT c as a condition
FUNCTION NotCond (c)
    DIM n
    IF NIsBool(c) THEN
        n = NewNode(NNOT, TYINT)
        NA(n) = c
        NIsBool(n) = 2
        NotCond = n
    ELSE
        IF NTy(c) = TYSTR THEN ErrMsg "type mismatch: a string as a condition"
        NotCond = Compare(TEQ, c, ConvNode(IConst(0), NTy(c)))
    END IF
END FUNCTION


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
        ErrMsg "a variable expected"
        SkipStmt
        EXIT FUNCTION
    END IF
    nm$ = TokS$
    GetTok
    s = FindVar(nm$)
    IF s > 0 THEN
        IF SKind(s) = SKARRAY THEN
            IF Tok <> TLPAR THEN
                ErrMsg nm$ + " is an array: an index expected"
                EXIT FUNCTION
            END IF
            LValue = ElemNode(s)
            EXIT FUNCTION
        END IF
        IF SKind(s) = SKCONST THEN
            ErrMsg nm$ + " is a constant"
            EXIT FUNCTION
        END IF
        LValue = SymNode(s)
        EXIT FUNCTION
    END IF
    IF Tok = TLPAR THEN
        ErrMsg nm$ + ": no such array (DIM it first)"
        EXIT FUNCTION
    END IF
    s = LookupVar(nm$, 1)
    LValue = SymNode(s)
END FUNCTION

SUB Assign (lv, e)
    DIM ty
    ty = StoreType(lv)
    IF ty = TYBYTE THEN ty = TYINT
    StorePre lv
    GenValueAs e, ty
    GenStore lv
END SUB

' ---- labels

FUNCTION LabelText$ ()
    SELECT CASE Tok
    CASE TINT
        LabelText$ = IStr$(TokV)
    CASE TIDENT, TSNG, TDBL, TLABEL
        LabelText$ = TokS$
    CASE ELSE
        ErrMsg "a label expected"
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
    IF SFlags(s) AND SFSETLAB THEN ErrMsg "label " + nm$ + " defined twice"
    SFlags(s) = SFlags(s) OR SFSETLAB
    SetLabel SAux(s)
END SUB

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

FUNCTION PushCtl (kind, ex, cont)
    IF NCtl >= MAXCTL THEN
        ErrMsg "blocks nested too deep"
        NCtl = 0
    END IF
    NCtl = NCtl + 1
    CtlKind(NCtl) = kind
    CtlExit(NCtl) = ex
    CtlCont(NCtl) = cont
    PushCtl = NCtl
END FUNCTION

FUNCTION FindCtl (kind)
    DIM i
    FOR i = NCtl TO 1 STEP -1
        IF CtlKind(i) = kind THEN
            FindCtl = i
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

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
    Expect KTHEN, "THEN"
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
                Expect KTHEN, "THEN"
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
        IF t <> TMEND + KIF THEN ErrMsg "END IF expected"
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

SUB GenFor ()
    DIM nm$, s, ty, e1, e2, e3, lv, w, k, ltop, lcont, lexit, lneg, lbody, t
    GetTok
    IF Tok <> TIDENT THEN
        ErrMsg "a FOR variable expected"
        SkipStmt
        EXIT SUB
    END IF
    nm$ = TokS$
    GetTok
    s = FindVar(nm$)
    IF s = 0 THEN s = LookupVar(nm$, 1)
    IF SKind(s) <> SKVAR OR SType(s) = TYSTR THEN ErrMsg "FOR needs a numeric variable"
    ty = SType(s)
    IF ty = TYBYTE THEN ty = TYINT
    w = TypeWords(ty)
    Expect TEQ, "="
    e1 = Expr
    Expect KTO, "TO"
    e2 = Expr
    IF Tok = KSTEP THEN
        GetTok
        e3 = Expr
    ELSE
        e3 = IConst(1)
    END IF
    NFor = NFor + 1
    IF NFor > 30 THEN ErrMsg "FOR loops nested more than 30 deep"
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
    IF t <> KNEXT THEN ErrMsg "NEXT expected"
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
        Csp 100
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
    IF t <> KLOOP THEN ErrMsg "LOOP expected"
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
    IF t <> KWEND THEN ErrMsg "WEND expected"
    NCtl = NCtl - 1
    Jump OUJP, ltop
    SetLabel lexit
    AtFalse f
END SUB

SUB GenSelect ()
    DIM e, ty, sel, lend, lnext, lbody, lskip, t, c, v1, v2, op, k, f, w
    GetTok
    Expect KCASE, "CASE"
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
                    ErrMsg "a comparison expected after IS"
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
    IF t <> TMEND + KSELECT THEN ErrMsg "END SELECT expected"
    SetLabel lend
    NCtl = NCtl - 1
    IF ty = TYSTR THEN
        Lla SOff(sel)
        CallRt "_SFREE"
    END IF
END SUB

SUB GenExitStmt (cont)
    DIM k, kind
    GetTok
    SELECT CASE Tok
    CASE KFOR: kind = CFOR
    CASE KDO: kind = CDO
    CASE KWHILE: kind = CWHILE
    CASE KSELECT: kind = CSELECT
    CASE KSUB, KFUNCTION
        IF cont THEN ErrMsg "CONTINUE FOR, DO or WHILE expected"
        IF InProc = 0 THEN ErrMsg "EXIT " + KwName$(Tok) + " outside a procedure"
        GetTok
        Jump OUJP, ExitLab
        EXIT SUB
    CASE ELSE
        ErrMsg "FOR, DO, WHILE, SELECT, SUB or FUNCTION expected"
        EXIT SUB
    END SELECT
    GetTok
    k = FindCtl(kind)
    IF k = 0 THEN
        ErrMsg "not inside such a block"
    ELSEIF cont THEN
        IF kind = CSELECT THEN ErrMsg "CONTINUE SELECT?" ELSE Jump OUJP, CtlCont(k)
    ELSE
        Jump OUJP, CtlExit(k)
    END IF
END SUB

SUB GenReturn ()
    DIM e
    GetTok
    IF AtEnd THEN
        Jump OUJP, RetLab
        EXIT SUB
    END IF
    IF ResultOff = 0 THEN
        ErrMsg "RETURN with a value outside a FUNCTION"
        SkipStmt
        EXIT SUB
    END IF
    e = Expr
    Assign SymNode(FindSym("!R")), e
    Jump OUJP, ExitLab
END SUB

' ON n GOTO / GOSUB labels; ON ERROR GOTO 0 / RESUME NEXT
SUB GenOn ()
    DIM e, isgosub, n, i, lafter, site, labs(50), stubs(50)
    GetTok
    IF Tok = KERROR THEN
        GetTok
        IF Tok = KRESUME THEN
            GetTok
            Expect KNEXT, "NEXT"
            Ldc 1
        ELSE
            Expect KGOTO, "GOTO"
            IF Tok <> TINT THEN
                ErrMsg "only ON ERROR GOTO 0 and ON ERROR RESUME NEXT"
            ELSEIF TokV <> 0 THEN
                ErrMsg "only ON ERROR GOTO 0 and ON ERROR RESUME NEXT"
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
        ErrMsg "GOTO or GOSUB expected"
        EXIT SUB
    END IF
    GetTok
    n = 0
    DO
        n = n + 1
        IF n > 50 THEN
            ErrMsg "more than 50 labels"
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
        IF Tok = TCOMMA OR Tok = TSEMI THEN GetTok ELSE ErrMsg ", expected"
    END IF
    IF Tok = KUSING THEN
        ErrMsg "PRINT USING is not supported"
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
                Expect TLPAR, "("
                PushCh ch
                GenValueAs Expr, TYINT
                Expect TRPAR, ")"
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
        Expect TCOMMA, ","
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
                Expect TSEMI, ";"
            END IF
        END IF
    END IF
    IF isline THEN
        lv = LValue
        IF lv = 0 THEN EXIT SUB
        IF StoreType(lv) <> TYSTR THEN ErrMsg "LINE INPUT needs a string variable"
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
            Csp 107
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

SUB GenOpen ()
    DIM f, mode, n, r
    GetTok
    f = Expr
    Expect KFOR, "FOR"
    SELECT CASE Tok
    CASE KINPUT: mode = 1
    CASE KOUTPUT: mode = 2
    CASE KAPPEND: mode = 3
    CASE KBINARY: mode = 4
    CASE KRANDOM: mode = 5
    CASE ELSE
        ErrMsg "INPUT, OUTPUT, APPEND, BINARY or RANDOM expected"
    END SELECT
    GetTok
    Expect KAS, "AS"
    IF Tok = THASH THEN GetTok
    n = Expr
    r = IConst(0)
    IF Tok = TIDENT THEN
        IF TokS$ = "LEN" THEN
            GetTok
            Expect TEQ, "="
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

' the bytes GET and PUT move for a type
FUNCTION TypeBytes (ty)
    SELECT CASE ty
    CASE TYBYTE: TypeBytes = 1
    CASE TYINT: TypeBytes = 2
    CASE TYSNG: TypeBytes = 4
    CASE TYDBL: TypeBytes = 8
    END SELECT
END FUNCTION

' GET #n, [pos], var  /  PUT #n, [pos], value
SUB GenGetPut (isput)
    DIM n, p, lv, e, ty, t, x
    GetTok
    IF Tok = THASH THEN GetTok
    n = ToInt(Expr)
    Expect TCOMMA, ","
    p = 0
    IF Tok <> TCOMMA THEN p = Expr
    Expect TCOMMA, ","
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
        IF InProc THEN ErrMsg "DIM SHARED inside a procedure"
    END IF
    IF Tok = KPRESERVE THEN
        ispreserve = 1
        GetTok
    END IF
    DO
        IF Tok <> TIDENT THEN
            ErrMsg "a variable name expected"
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
                IF SScope(s) = 1 THEN ErrMsg nm$ + " declared twice"
            END IF
            s = 0
        END IF
        IF s = 0 THEN
            IF isarr THEN k = SKARRAY ELSE k = SKVAR
            s = NewVar(DeclName$, k, ty, fl)
            IF isarr THEN SAux(s) = nd
        END IF
        IF isarr AND nd = 0 THEN
            IF SKind(s) <> SKARRAY THEN ErrMsg nm$ + " is not an array"
        ELSEIF isarr THEN
            IF SKind(s) <> SKARRAY THEN ErrMsg nm$ + " is not an array"
            IF SAux(s) > 0 AND SAux(s) <> nd THEN ErrMsg nm$ + ": the wrong number of dimensions"
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

' STATIC x [AS type], ...: kept between calls (a module static)
SUB GenStatic ()
    DIM nm$, ty, s
    GetTok
    DO
        IF Tok <> TIDENT THEN
            ErrMsg "a variable name expected"
            SkipStmt
            EXIT SUB
        END IF
        nm$ = TokS$
        GetTok
        IF Tok = TLPAR THEN ErrMsg "STATIC arrays are not supported"
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
            ErrMsg "a variable name expected"
            SkipStmt
            EXIT SUB
        END IF
        nm$ = TokS$
        GetTok
        IF Tok = TLPAR THEN
            GetTok
            Expect TRPAR, ")"
        END IF
        IF Tok = KAS THEN
            GetTok
            t = ParseType
        END IF
        s = FindSym(nm$)
        IF s = 0 AND SuffixType(nm$) = 0 THEN s = FindSym(nm$ + TypeChar$(NameType(nm$)))
        IF s = 0 THEN
            ErrMsg "no module variable " + nm$
        ELSEIF SScope(s) <> 0 OR SKind(s) > SKARRAY THEN
            ErrMsg "no module variable " + nm$
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

SUB GenConst ()
    DIM nm$, n, v, ty, s, t$
    GetTok
    DO
        IF Tok <> TIDENT THEN
            ErrMsg "a constant name expected"
            SkipStmt
            EXIT SUB
        END IF
        nm$ = TokS$
        GetTok
        Expect TEQ, "="
        v = 0
        n = ConstExpr(v)
        ty = NTy(n)
        IF SuffixType(nm$) > 0 AND SuffixType(nm$) <> ty THEN
            n = ConvNode(n, SuffixType(nm$))
            ty = SuffixType(nm$)
        END IF
        s = FindSym(nm$)
        IF s > 0 THEN
            IF SScope(s) = InProc THEN ErrMsg nm$ + " declared twice"
        END IF
        s = AddSym(nm$, SKCONST, ty)
        SScope(s) = InProc
        IF NOp(n) = NICON THEN
            SAux(s) = NV(n)
        ELSE
            t$ = NS$(n)
            IF NOp(n) = NRCON AND NX(n) THEN t$ = "-" + t$
            NConst = NConst + 1
            IF NConst > 300 THEN
                ErrMsg "too many string and real constants"
                NConst = 1
            END IF
            ConstText$(NConst) = t$
            SAux(s) = NConst
        END IF
        ResetNodes
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' ---- DATA, READ, RESTORE

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
                Csp 107
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

SUB GenRestore ()
    DIM s, db
    GetTok
    db = FindSym("$DB")
    IF db = 0 THEN
        ErrMsg "RESTORE without DATA"
        SkipStmt
        EXIT SUB
    END IF
    GlobOp OLDO, db, 0
    IF NOT AtEnd THEN
        s = FindSym("%" + LabelText$)
        IF s = 0 THEN ErrMsg "no such label" ELSE Ldc SAux(s): OB OADI
    END IF
    CallRt "_RESTORE"
END SUB

' WRITE [#n,] items: strings in quotes, numbers without blanks, commas
SUB GenWrite ()
    DIM ch, e, ty, first
    GetTok
    ch = 0
    IF Tok = THASH THEN
        GetTok
        ch = FileNum
        Expect TCOMMA, ","
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

SUB GenSwap ()
    DIM a, b, ty
    GetTok
    a = LValue
    Expect TCOMMA, ","
    b = LValue
    IF a = 0 OR b = 0 THEN EXIT SUB
    ty = StoreType(a)
    IF ty <> StoreType(b) THEN ErrMsg "SWAP needs two variables of one type"
    GenAddr a
    GenAddr b
    IF ty = TYSTR THEN
        CallRt "_SSWAP"
    ELSE
        Ldc TypeBytes(ty)
        CallRt "_SWAP"
    END IF
END SUB

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
        IF ArgCount <> SAux2(s) THEN ErrMsg SName$(s) + ": " + IStr$(SAux2(s)) + " argument(s) expected"
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
        Expect TLPAR, "("
        lv = LValue
        IF lv = 0 THEN EXIT SUB
        IF StoreType(lv) <> TYSTR THEN ErrMsg "MID$ needs a string variable"
        GenAddr lv
        Expect TCOMMA, ","
        GenValueAs Expr, TYINT
        IF Tok = TCOMMA THEN
            GetTok
            GenValueAs Expr, TYINT
        ELSE
            Ldc 255
        END IF
        Expect TRPAR, ")"
        Expect TEQ, "="
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
        Expect TCOMMA, ","
        GenValueAs Expr, TYINT
        IF nm$ = "POKEB" THEN OB OSTB ELSE OB OSTO
        EXIT SUB
    END IF
    IF nm$ = "CSP" OR nm$ = "OSCALL" THEN
        GetTok
        e = Expr
        IF NOp(e) <> NICON THEN ErrMsg nm$ + ": a constant expected"
        k = NV(e)
        DO WHILE Tok = TCOMMA
            GetTok
            a = Expr
            GenValue a
        LOOP
        IF nm$ = "CSP" THEN
            Csp k
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
            ErrMsg "= expected after the function's name"
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
    Expect TEQ, "="
    Assign lv, Expr
END SUB

SUB GenEnd ()
    ' END [n]: the program stops (files closed)
    IF AtEnd THEN Ldc 0 ELSE GenValueAs Expr, TYINT
    CallRt "_HALT"
END SUB

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
        IF Tok <> KINPUT THEN ErrMsg "LINE INPUT expected"
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
        IF InProc = 0 THEN ErrMsg "SHARED outside a procedure"
        GenShared
    CASE KERASE
        GetTok
        DO
            IF Tok = TIDENT THEN
                s = FindVar(TokS$)
                IF s = 0 THEN
                    ErrMsg "no array " + TokS$
                ELSEIF SKind(s) <> SKARRAY THEN
                    ErrMsg TokS$ + " is not an array"
                ELSE
                    GenSlot s
                    CallRt "_AFREE"
                END IF
                GetTok
            ELSE
                ErrMsg "an array name expected"
            END IF
            IF Tok <> TCOMMA THEN EXIT DO
            GetTok
        LOOP
    CASE KCONST
        GenConst
    CASE KCALL
        GetTok
        IF Tok <> TIDENT THEN
            ErrMsg "a SUB name expected"
        ELSE
            s = FindProc(TokS$)
            IF s = 0 THEN
                ErrMsg "no SUB " + TokS$
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
        Expect TCOMMA, ","
        GenValueAs Expr, TYSNG
        CallRt "_SEEK"
    CASE KKILL
        GetTok
        GenValueAs Expr, TYSTR
        CallRt "_KILL"
    CASE KSWAP
        GenSwap
    CASE KRANDOMIZE
        GetTok
        IF AtEnd THEN Ldc 0 ELSE GenValueAs Expr, TYINT
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
    CASE KOPTION, KDECLARE, KCOMMON, KSEGMENT, KDATA
        SkipStmt
    CASE KREAD
        GenRead
    CASE KRESTORE
        GenRestore
    CASE KWRITE
        GenWrite
    CASE ELSE
        ErrMsg "a statement expected, not " + KwName$(Tok)
        SkipStmt
    END SELECT
END SUB

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
                ErrMsg "a SUB or FUNCTION inside a procedure (END SUB missing?)"
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
        ErrMsg "internal: " + nm$ + " not declared"
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
        IF t <> TMEND + KFUNCTION THEN ErrMsg "END FUNCTION expected"
    ELSE
        IF t <> TMEND + KSUB THEN ErrMsg "END SUB expected"
    END IF
    EndProc
    InProc = 0
END SUB

' ---- the pass

SUB GenPass ()
    DIM t, s, k, w
    REDIM Code(MAXCODE) AS BYTE, LabPos(MAXLAB), FixPos(MAXFIX), FixLab(MAXFIX)
    REDIM RelPos(MAXREL), RelType(MAXREL) AS BYTE, RelSym(MAXREL)
    REDIM NOp(MAXNODE) AS BYTE, NTy(MAXNODE) AS BYTE, NA(MAXNODE), NB(MAXNODE)
    REDIM NV(MAXNODE), NX(MAXNODE), NN(MAXNODE), NS$(MAXNODE), NIsBool(MAXNODE) AS BYTE
    REDIM CtlKind(MAXCTL), CtlExit(MAXCTL), CtlCont(MAXCTL), ConstText$(300)
    NNode = 0
    NConst = 0
    MemNote "gen arrays"
    OPEN ObjName$ FOR OUTPUT AS #CHOBJ
    PUT #CHOBJ, , "BCOB"
    ObjByte 77
    ObjStr ModName$
    IF OptList THEN
        OPEN LstName$ FOR OUTPUT AS #CHLST
        PRINT #CHLST, "BC listing of "; SrcName$
        LstOpen = 1
    END IF
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
        ErrMsg KwName$(t) + " without its block"
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
    CLOSE #CHOBJ
    IF OptList THEN
        CLOSE #CHLST
        LstOpen = 0
        KILL LTmpName$
    END IF
    IF OptMem THEN SayLn "  [high: code " + IStr$(HiPC) + ", jumps " + IStr$(HiFix) + ", labels " + IStr$(HiLab) + ", calls " + IStr$(HiRel) + ", nodes " + IStr$(HiNode) + ", names " + IStr$(HiSym) + "]"
    ERASE Code, LabPos, FixPos, FixLab, RelPos, RelType, RelSym
    ERASE NOp, NTy, NA, NB, NV, NX, NN, NS$, NIsBool, CtlKind, CtlExit, CtlCont, ConstText$
END SUB
