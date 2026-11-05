' B2NAME -- pass 4: the names
'
' Reads B2SYN's file twice -- the module's body first (its statements
' outside every SUB and FUNCTION: one procedure, MODULE'BODY), then each
' SUB and FUNCTION -- with the module's symbols B2DECL saved, and writes
' each procedure between CBEGIN and CEND: every name resolved (RVAR: a
' variable's or array's class, type, offset; RCALL: a procedure called,
' its linker name and parameters; RBUILT: a built-in), the locals laid
' out (CBEGIN's frame), labels made numbers (CLABEL where one is, RLAB
' where one is gone to), the declarations used up (DIM of a variable,
' STATIC, SHARED, DEFINT ... make no record), the locals to give back at
' the exit (CFREE).  At the end the object file's other records: the
' COMMON variables, the statics.  After this pass no pass needs a symbol.
#INCLUDE "B2BUILT"
#INCLUDE "B2COM"

' the procedure's symbol, the symbols before its own, its result's offset;
' the line waiting to be written (written before the next record of the
' procedure: a procedure's header line is its first); the file of the
' last line written
DIM SHARED ProcSym, ProcKeep, ResultOff, PendLn, PendNo, PendText$, PendFile$, LastFile$
' DIM's bounds: read (BndSkip: the records kept in BnK, BnS$, BnV), written
' after the array (BndOut)
DIM SHARED BnK(), BnS$(), BnV(), NBn, NBnd, BnCap

' ---- writing

SUB FlushLine ()
    IF PendLn = 0 THEN EXIT SUB
    IF PendFile$ <> LastFile$ THEN
        LastFile$ = PendFile$
        WRec TFILE
        WS LastFile$
    END IF
    WRec TLINE
    WW PendNo
    WS PendText$
    PendLn = 0
END SUB

' the current record, after the line waiting
SUB Copy ()
    FlushLine
    PutRec
END SUB

SUB WVar (s)
    FlushLine
    WRec RVAR
    WB SKind(s)
    WB SType(s)
    WB SCls(s)
    WW SOff(s)
    IF SKind(s) = SKARRAY THEN WB SAux(s) ELSE WB 0
    IF SCls(s) = SCCOMMON THEN WS LinkName$(s) ELSE WS SName$(s)
END SUB

SUB WCall (s)
    DIM i
    FlushLine
    WRec RCALL
    WB SType(s)
    WB SKind(s)
    WS LinkName$(s)
    WB SAux2(s)
    FOR i = 1 TO SAux2(s)
        WB PType(SAux(s) + i - 1)
        WB PFlg(SAux(s) + i - 1)
    NEXT i
    WS SName$(s)
    SFlags(s) = SFlags(s) OR SFUSED
END SUB

' ---- names

' may a symbol of the module be seen here (in a procedure: procedures and
' shared variables only)
FUNCTION Visible (s)
    IF s = 0 THEN EXIT FUNCTION
    IF SScope(s) = 1 OR InProc = 0 THEN
        Visible = -1
        EXIT FUNCTION
    END IF
    SELECT CASE SKind(s)
    CASE SKSUB, SKFUNC
        Visible = -1
    CASE SKVAR, SKARRAY
        Visible = (SFlags(s) AND SFSHARED) <> 0 OR SCls(s) = SCCOMMON
    END SELECT
END FUNCTION

' a variable or array by its name as written: 0 if there is none
FUNCTION FindVar (n$)
    DIM s, t
    t = SuffixType(n$)
    IF t = 0 THEN
        s = FindSym(n$)
        IF Visible(s) AND SKind(s) <= SKARRAY THEN
            FindVar = s
            EXIT FUNCTION
        END IF
        s = FindSym(n$ + TypeChar$(NameType(n$)))
        IF Visible(s) AND SKind(s) <= SKARRAY THEN FindVar = s
        EXIT FUNCTION
    END IF
    s = FindSym(n$)
    IF Visible(s) AND SKind(s) <= SKARRAY THEN
        FindVar = s
        EXIT FUNCTION
    END IF
    s = FindSym(BaseName$(n$))
    IF Visible(s) AND SKind(s) <= SKARRAY THEN
        IF SType(s) = t AND (SFlags(s) AND SFAS) <> 0 THEN FindVar = s
    END IF
END FUNCTION

' a new variable: a local in a procedure, a module static at module level
FUNCTION NewVar (n$, kind, ty, fl)
    DIM s, w
    s = AddSym(n$, kind, ty)
    SFlags(s) = fl
    IF kind = SKARRAY THEN w = 1 ELSE w = TypeWords(ty)
    IF InProc THEN
        SScope(s) = 1
        SCls(s) = SCLOCAL
        SOff(s) = NewLocal(w)
        CbZero = 1
    ELSE
        SCls(s) = SCSTATIC
        SOff(s) = StaticWords
        StaticWords = StaticWords + w
    END IF
    NewVar = s
END FUNCTION

' a variable by its name: found, or made (implicitly)
FUNCTION LookupVar (n$)
    DIM s
    s = FindVar(n$)
    IF s = 0 THEN
        IF OptExplicit THEN ErrRec 87, 0, 0, n$   ' {s} not declared (OPTION EXPLICIT)
        IF SuffixType(n$) THEN
            s = NewVar(n$, SKVAR, SuffixType(n$), 0)
        ELSE
            s = NewVar(n$ + TypeChar$(NameType(n$)), SKVAR, NameType(n$), 0)
        END IF
    END IF
    LookupVar = s
END FUNCTION

FUNCTION BuiltTable$ (part)
    DIM tb$
    SELECT CASE part
    CASE 0
        tb$ = "LEN     ASC     CHR$    MID$    LEFT$   RIGHT$  INSTR   UCASE$  LCASE$  "
        tb$ = tb$ + "LTRIM$  RTRIM$  TRIM$   SPACE$  STRING$ STR$    VAL     HEX$    CINT    "
        tb$ = tb$ + "FIX     INT     CSNG    CDBL    ABS     SGN     SQR     SIN     COS     "
        tb$ = tb$ + "TAN     ATN     EXP     LOG     "
    CASE ELSE
        tb$ = "RND     TIMER   EOF     INKEY$  COMMAND$ERR     MKI$    CVI     MKS$    "
        tb$ = tb$ + "CVS     MKD$    CVD     LBOUND  UBOUND  FRE     VARPTR  PEEK    PEEKB   "
        tb$ = tb$ + "CSP%    CSP#    CSP!    OSCALL% OSVAR   POS     FREEFILELOF     DVI%    "
        tb$ = tb$ + "MDI%    SADD    OSADDR  "
    END SELECT
    BuiltTable$ = tb$
END FUNCTION

FUNCTION BuiltinId (n$)
    DIM part, p, t$, pad$
    IF LEN(n$) > 8 THEN EXIT FUNCTION
    pad$ = LEFT$(n$ + "        ", 8)
    FOR part = 0 TO 1
        t$ = BuiltTable$(part)
        p = INSTR(t$, pad$)
        DO WHILE p > 0
            IF (p - 1) MOD 8 = 0 THEN
                BuiltinId = part * 31 + (p - 1) \ 8 + 1
                EXIT FUNCTION
            END IF
            p = INSTR(p + 1, t$, pad$)
        LOOP
    NEXT part
END FUNCTION

' a name in an expression (TIDENT current): a variable, an array, a
' procedure, a built-in, or a variable made
SUB NameExpr ()
    DIM nm$, s, id
    nm$ = TokS$
    s = FindVar(nm$)
    IF s > 0 THEN
        WVar s
        EXIT SUB
    END IF
    s = FindProc(nm$)
    IF s > 0 THEN
        IF SKind(s) = SKSUB THEN ErrRec 105, 0, 0, nm$   ' {s} is a SUB, not a FUNCTION
        WCall s
        EXIT SUB
    END IF
    id = BuiltinId(nm$)
    IF id > 0 THEN
        FlushLine
        WRec RBUILT
        WB id
        WS nm$
        EXIT SUB
    END IF
    IF PeekRec = TLPAR THEN
        ErrRec 106, 0, 0, nm$   ' {s}: no such array or function
        EXIT SUB
    END IF
    WVar LookupVar(nm$)
END SUB

' a target's name (TIDENT current): a variable or array (made if it is
' new), or a FUNCTION's own name: its result
SUB NameLv ()
    DIM nm$, s
    nm$ = TokS$
    IF ResultOff > 0 THEN
        IF FindProc(nm$) = ProcSym THEN
            WVar FindSym("!R")
            EXIT SUB
        END IF
    END IF
    s = FindVar(nm$)
    IF s > 0 THEN
        IF SKind(s) = SKARRAY AND PeekRec <> TLPAR THEN ErrRec 29, 0, 0, nm$   ' {s} is an array: an index expected
        WVar s
        EXIT SUB
    END IF
    IF PeekRec = TLPAR THEN
        ErrRec 31, 0, 0, nm$   ' {s}: no such array (DIM it first)
        EXIT SUB
    END IF
    WVar LookupVar(nm$)
END SUB

' the records up to the end of the statement, the names resolved
SUB NameRest ()
    DIM first
    DO WHILE NOT AtEnd
        SELECT CASE Tok
        CASE RX
            Copy
            first = RB1 = XCALL
            GetTok
            DO WHILE Tok <> RXE AND NOT AtEnd
                IF Tok = TIDENT THEN
                    IF first THEN NameCall ELSE NameExpr
                    first = 0
                ELSE
                    Copy
                END IF
                GetTok
            LOOP
            IF Tok = RXE THEN Copy
        CASE RLV
            Copy
            GetTok
            IF Tok = TIDENT THEN
                NameLv
                GetTok
            END IF
            DO WHILE Tok <> RLVE AND NOT AtEnd
                IF Tok = TIDENT THEN NameExpr ELSE Copy
                GetTok
            LOOP
            IF Tok = RLVE THEN Copy
        CASE RLREF
            FlushLine
            WRec RLAB
            WW SAux(LabelSym(TokS$))
        CASE ELSE
            Copy
        END SELECT
        GetTok
    LOOP
END SUB

' a SUB called (the first name of XCALL's expression)
SUB NameCall ()
    DIM s, nm$
    nm$ = TokS$
    s = FindVar(nm$)
    IF s = 0 THEN s = FindProc(nm$)
    IF s > 0 THEN
        IF SKind(s) = SKSUB OR SKind(s) = SKFUNC THEN
            IF s = ProcSym AND ResultOff > 0 THEN
                ErrNo 70   ' = expected after the function's name
            END IF
            WCall s
            EXIT SUB
        END IF
    END IF
    IF PeekRec = TLPAR OR s > 0 THEN
        ErrRec 1, TEQ, PeekRec, ""   ' = expected, not {t}
    ELSE
        ErrRec 76, 0, 0, nm$   ' no SUB {s}
    END IF
END SUB

' ---- labels

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
    FlushLine
    SetLabel SAux(s)
END SUB

' ---- declarations

' STATIC x [AS type], ...: kept between calls (a module static)
SUB NameStatic ()
    DIM nm$, ty, s
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
SUB NameShared ()
    DIM nm$, s, t, a
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

' DIM / REDIM (B2SYN's form: TINT shared, TINT preserve, the items): the
' variables declared; for each array with bounds RVAR, TINT dimensions,
' the bounds (RX ...), after TINT preserve
SUB NameDim (isredim)
    DIM isshared, nm$, ty, fl, s, nd, k
    isshared = TokV
    GetTok
    FlushLine
    WB RSTMT
    IF isredim THEN WB KREDIM ELSE WB KDIM
    PutRec
    GetTok
    DO WHILE Tok = TIDENT
        nm$ = TokS$
        GetTok
        nd = TokV
        GetTok
        ' (the bounds wait: the type after them comes first)
        NBnd = 0
        DO WHILE Tok = RX
            NBnd = NBnd + 1
            BndSkip
        LOOP
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
            IF nd >= 0 THEN k = SKARRAY ELSE k = SKVAR
            s = NewVar(DeclName$, k, ty, fl)
            IF nd > 0 THEN SAux(s) = nd
        END IF
        IF nd = 0 THEN
            IF SKind(s) <> SKARRAY THEN ErrRec 58, 0, 0, nm$   ' {s} is not an array
        ELSEIF nd > 0 THEN
            IF SKind(s) <> SKARRAY THEN ErrRec 58, 0, 0, nm$   ' {s} is not an array
            IF SAux(s) > 0 AND SAux(s) <> nd THEN ErrRec 59, 0, 0, nm$   ' {s}: the wrong number of dimensions
            IF SAux(s) = 0 THEN SAux(s) = nd
            WVar s
            WRec TINT
            WW nd
            BndOut
        END IF
    LOOP
END SUB

SUB BndSkip ()
    IF NBnd = 1 THEN NBn = 0
    DO
        IF NBn < BnCap THEN
            NBn = NBn + 1
            BnK(NBn) = Tok
            BnS$(NBn) = TokS$
            BnV(NBn) = TokV
            IF Tok = RX THEN BnV(NBn) = RB1
        END IF
        IF Tok = RXE OR AtEnd THEN EXIT DO
        GetTok
    LOOP
    IF Tok = RXE THEN GetTok
END SUB

SUB BndOut ()
    DIM i, p, pk
    ' (NameExpr peeks at the record after a name: the one kept)
    p = InPend
    pk = InPendK
    FOR i = 1 TO NBn
        SELECT CASE BnK(i)
        CASE TIDENT
            TokS$ = BnS$(i)
            Rk = TIDENT
            Tok = TIDENT
            InPend = 1
            InPendK = RXE
            IF i < NBn THEN InPendK = BnK(i + 1)
            NameExpr
        CASE RX
            WRec RX
            WB BnV(i)
        CASE TINT
            WRec TINT
            WW BnV(i)
        CASE TSNG, TDBL, TSTR
            WRec BnK(i)
            WS BnS$(i)
        CASE ELSE
            WRec BnK(i)
        END SELECT
        BnS$(i) = ""
    NEXT i
    NBn = 0
    InPend = p
    InPendK = pk
END SUB

' ERASE a, b: RVAR each
SUB NameErase ()
    DIM s
    DO
        IF Tok = TIDENT THEN
            s = FindVar(TokS$)
            IF s = 0 THEN
                ErrRec 73, 0, 0, TokS$   ' no array {s}
            ELSEIF SKind(s) <> SKARRAY THEN
                ErrRec 58, 0, 0, TokS$   ' {s} is not an array
            ELSE
                WVar s
            END IF
            GetTok
        ELSE
            ErrNo 74   ' an array name expected
        END IF
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' RESTORE [label]: RVAR the module's DATA number, TINT the label's (-1)
SUB NameRestore ()
    DIM s, db
    db = FindSym("$DB")
    IF db = 0 THEN
        ErrNo 64   ' RESTORE without DATA
        SkipStmt
        EXIT SUB
    END IF
    WVar db
    s = -1
    IF Tok = RLREF THEN
        s = FindSym("%" + TokS$)
        IF s = 0 THEN ErrNo 65 ELSE s = SAux(s)   ' no such label
        GetTok
    END IF
    WRec TINT
    WW s
END SUB

' ---- statements

' a statement (RSTMT k read; the record after it current)
SUB NameStmt (k)
    DIM s
    SELECT CASE k
    CASE KDEFINT, KDEFSNG, KDEFDBL, KDEFSTR
        DefLetters DefKw(k)
    CASE KOPTION, KDECLARE, KCOMMON, KSEGMENT, KDATA
    CASE KSTATIC
        NameStatic
    CASE KSHARED
        NameShared
    CASE KDIM, KREDIM
        NameDim k = KREDIM
    CASE KFOR
        ' the variable: RVAR
        FlushLine
        WB RSTMT
        WB KFOR
        s = FindVar(TokS$)
        IF s = 0 THEN s = LookupVar(TokS$)
        IF SKind(s) <> SKVAR OR SType(s) = TYSTR THEN ErrNo 37   ' FOR needs a numeric variable
        WVar s
        GetTok
        NameRest
    CASE KERASE
        FlushLine
        WB RSTMT
        WB KERASE
        NameErase
    CASE KRESTORE
        FlushLine
        WB RSTMT
        WB KRESTORE
        NameRestore
    CASE ELSE
        FlushLine
        WB RSTMT
        WB k
        NameRest
    END SELECT
    SkipStmt
END SUB

' the statements up to SENDSUB / SENDFN (a procedure) or the end, a
' procedure's skipped in the module's body
SUB NameBlock ()
    DIM k
    DO
        SELECT CASE Tok
        CASE TEOF
            EXIT SUB
        CASE TLINE
            PendLn = 1
            PendNo = TokLine
            PendText$ = TokText$
            PendFile$ = LineFile$
            IF PendFile$ = "" THEN PendFile$ = TokFile$
            GetTok
        CASE TLABEL
            DefineLabel TokS$
            GetTok
        CASE RSTMT
            k = RB1
            GetTok
            SELECT CASE k
            CASE SENDSUB, SENDFN
                EXIT SUB
            CASE KSUB, KFUNCTION
                ' (in the body: skipped)
                PendLn = 0
                DO
                    SkipStmt
                    IF Tok = TEOF THEN EXIT SUB
                    IF Tok = RSTMT THEN
                        IF RB1 = SENDSUB OR RB1 = SENDFN THEN EXIT DO
                    END IF
                    GetTok
                LOOP
                GetTok
            CASE ELSE
                NameStmt k
            END SELECT
        CASE ELSE
            GetTok
        END SELECT
    LOOP
END SUB

' ---- procedures

' a procedure starts: s its symbol (0: the module's body); the parameters'
' frame words np
SUB BeginProc (s, pw)
    CbKind = 0
    IF s = 0 THEN CbKind = 1
    ProcSym = s
    ProcKeep = NSym
    CbLocal = pw
    CbPw = pw
    CbLab = 2
    CbZero = 0
    CbMark = NewLocal(1)
    ResultOff = 0
    CbResTy = 0
    IF s > 0 THEN
        IF SKind(s) = SKFUNC THEN
            ResultOff = NewLocal(TypeWords(SType(s)))
            CbZero = 1
            CbResTy = SType(s)
        END IF
    END IF
    CbResOff = ResultOff
    CbFlags = 0
    IF s = 0 THEN
        CbName$ = ModName$ + "'BODY"
        CbSeg$ = ""
        CbFlags = 1
    ELSE
        IF SFlags(s) AND SFPRIVATE THEN CbFlags = 2
        CbName$ = LinkName$(s)
        CbSeg$ = SegName$(SSeg(s))
    END IF
    WBegin
END SUB

' its end: the labels checked, the locals to give back (CFREE), CEND
SUB EndProc ()
    DIM s
    FOR s = ProcKeep + 1 TO NSym
        IF SKind(s) = SKLABEL AND SScope(s) = InProc AND (SFlags(s) AND SFSETLAB) = 0 THEN
            ErrRec 115, 0, 0, MID$(SName$(s), 2)   ' label {s} not defined
        END IF
        IF SKind(s) = SKVAR AND SType(s) = TYSTR AND (SCls(s) = SCLOCAL OR SCls(s) = SCPARAM) AND SOff(s) <> ResultOff THEN
            WRec CFREE
            WB 1
            WW SOff(s)
        ELSEIF SKind(s) = SKARRAY AND SCls(s) = SCLOCAL THEN
            WRec CFREE
            WB 2
            WW SOff(s)
        END IF
    NEXT s
    PendLn = 0
    IF Tok = TLINE THEN
        WEndProc PrevLine, PrevFile$, PrevText$
    ELSE
        WEndProc TokLine, LineFile$, TokText$
    END IF
    IF ProcSym > 0 THEN PopSyms ProcKeep
END SUB

' SUB / FUNCTION (RSTMT read; TINT private current), to its end
SUB NameProc (isfunc)
    DIM nm$, ty, np, s, i, pw, rw, off, w, p, t, r
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
    off = 1
    IF rw > pw THEN off = rw - pw + 1
    CbRw = rw
    BeginProc s, off - 1 + pw
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
    SkipStmt
    NameBlock
    EndProc
    InProc = 0
END SUB

' ---- the pass

SUB NamePass ()
    DIM s, k, w, l$
    ' the module's body
    ResetDefs
    InProc = 0
    InOpen PassFile$(2)
    OutHead(WHPASS) = 4
    OutOpen PassFile$(4)
    CbRw = 0
    BeginProc 0, 0
    IF NData > 0 THEN
        ' its DATA statements: RSTMT SDATAL, RVAR $DB, TSTR each
        WB RSTMT
        WB SDATAL
        WVar FindSym("$DB")
        OPEN DatName$ FOR INPUT AS #CHDAT
        FOR s = 1 TO NData
            LINE INPUT #CHDAT, l$
            WRec TSTR
            WS l$
        NEXT s
        CLOSE #CHDAT
        KILL DatName$
    END IF
    GetTok
    NameBlock
    EndProc
    CLOSE #CHIN
    MemNote "body"
    ' the procedures
    ResetDefs
    InOpen PassFile$(2)
    GetTok
    DO WHILE Tok <> TEOF
        IF Tok = RSTMT THEN
            k = RB1
            GetTok
            SELECT CASE k
            CASE KSUB, KFUNCTION
                NameProc k = KFUNCTION
            CASE KDEFINT, KDEFSNG, KDEFDBL, KDEFSTR
                DefLetters DefKw(k)
            END SELECT
        ELSE
            GetTok
        END IF
    LOOP
    CLOSE #CHIN
    ' the module's COMMON variables, its statics, the end
    FOR s = 1 TO NSym
        IF SCls(s) = SCCOMMON AND SScope(s) = 0 THEN
            WRec COBJB
            WB 68
            WRec COBJB
            WB 0
            WRec COBJS
            WS LinkName$(s)
            IF SKind(s) = SKARRAY THEN w = 1 ELSE w = TypeWords(SType(s))
            WRec COBJW
            WW w
        END IF
    NEXT s
    WRec COBJB
    WB 71
    WRec COBJW
    WW StaticWords
    WRec COBJB
    WB 69
    OutClose 4
END SUB

' ---- B2NAME, the program: pass 4 of the job's compile step, then B2EXPR

ReadJob
StepNames
ErrCount = 0
InOpen PassFile$(2)
CLOSE #CHIN
' (the module's symbols, and the most of one procedure)
SymLoad InHead(THLOC) + 8, InHead(THMAXPAR) + 1
BnCap = Capped(InHead(THSTMT) + 8, 2000)
REDIM BnK(BnCap), BnS$(BnCap), BnV(BnCap)
MemNote "symbols"
NamePass
IF ErrCount > 0 THEN CompileFailed
KILL SymName$
IF OptKeep = 0 THEN KILL PassFile$(2)
IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words (B2NAME)"
ChainTo "B2EXPR", ""
