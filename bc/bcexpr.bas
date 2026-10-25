' BCEXPR -- pass 3: expressions
'
' An expression is parsed into a tree of nodes (one statement's nodes at a
' time), typed as it is built (conversions are nodes), and then its code
' is generated.  A comparison is a "boolean": 1 or 0 on the stack (FJP
' tests bit 0), made -1 / 0 when it is used as a number, as BASIC wants.
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"
SEGMENT GEN

' ---- nodes

SUB ResetNodes ()
    DIM i
    FOR i = 1 TO NNode
        IF NS$(i) <> "" THEN NS$(i) = ""
    NEXT i
    NNode = 0
END SUB

FUNCTION NewNode (op, ty)
    IF NNode >= MAXNODE THEN
        ErrMsg "expression too complex"
        NNode = 1
    END IF
    NNode = NNode + 1
    IF NNode > HiNode THEN HiNode = NNode
    NOp(NNode) = op
    NTy(NNode) = ty
    NA(NNode) = 0
    NB(NNode) = 0
    NV(NNode) = 0
    NX(NNode) = 0
    NN(NNode) = 0
    NIsBool(NNode) = 0
    NewNode = NNode
END FUNCTION

FUNCTION IConst (v)
    DIM n
    n = NewNode(NICON, TYINT)
    NV(n) = v
    IConst = n
END FUNCTION

FUNCTION IntConst (n)
    IntConst = NOp(n) = NICON
END FUNCTION

FUNCTION NodeWords (n)
    NodeWords = TypeWords(NTy(n))
END FUNCTION

' a boolean used as a number: -1 / 0
FUNCTION BoolToInt (n)
    DIM m
    IF NIsBool(n) = 0 THEN
        BoolToInt = n
        EXIT FUNCTION
    END IF
    m = NewNode(NBOOL, TYINT)
    NA(m) = n
    BoolToInt = m
END FUNCTION

FUNCTION ConvNode (n, ty)
    DIM m, t
    t = NTy(n)
    IF t = ty THEN
        IF NIsBool(n) THEN n = BoolToInt(n)
        ConvNode = n
        EXIT FUNCTION
    END IF
    IF t = TYSTR OR ty = TYSTR OR t = TYVOID THEN
        ErrMsg "type mismatch"
        ConvNode = n
        EXIT FUNCTION
    END IF
    n = BoolToInt(n)
    IF NOp(n) = NICON AND (ty = TYSNG OR ty = TYDBL) THEN
        m = NewNode(NRCON, ty)
        NS$(m) = IStr$(NV(n))
        ConvNode = m
        EXIT FUNCTION
    END IF
    IF NOp(n) = NRCON AND ty <> TYINT THEN
        NTy(n) = ty
        ConvNode = n
        EXIT FUNCTION
    END IF
    m = NewNode(NCONV, ty)
    NA(m) = n
    ConvNode = m
END FUNCTION

FUNCTION ToInt (n)
    ToInt = ConvNode(n, TYINT)
END FUNCTION

' a converted argument keeps its place in the argument chain
FUNCTION ConvKeep (a, ty)
    DIM m
    m = ConvNode(a, ty)
    IF m <> a THEN
        NN(m) = NN(a)
        NN(a) = 0
    END IF
    ConvKeep = m
END FUNCTION

FUNCTION MaxType (a, b)
    DIM ta, tb
    ta = NTy(a)
    tb = NTy(b)
    IF ta = TYSTR OR tb = TYSTR THEN
        IF ta <> tb THEN ErrMsg "type mismatch"
        MaxType = TYSTR
        EXIT FUNCTION
    END IF
    IF tb > ta THEN ta = tb
    MaxType = ta
END FUNCTION

FUNCTION BinNode (op, ty, a, b)
    DIM n
    n = NewNode(NBIN, ty)
    NV(n) = op
    NA(n) = a
    NB(n) = b
    BinNode = n
END FUNCTION

' + - * / \ MOD ^ & on two operands
FUNCTION Arith (op, a, b)
    DIM t, va, vb, r
    t = MaxType(a, b)
    IF t = TYSTR THEN
        IF op <> TPLUS AND op <> TAMP THEN ErrMsg "type mismatch"
        Arith = BinNode(TPLUS, TYSTR, a, b)
        EXIT FUNCTION
    END IF
    IF op = TAMP THEN ErrMsg "& needs strings"
    IF op = TDIV AND t = TYINT THEN t = TYSNG
    IF op = TIDIV OR op = KMOD THEN t = TYINT
    IF op = TPOW THEN
        r = BinNode(TPOW, TYDBL, ConvNode(a, TYDBL), ConvNode(b, TYDBL))
        IF t = TYDBL THEN Arith = r ELSE Arith = ConvNode(r, TYSNG)
        EXIT FUNCTION
    END IF
    a = ConvNode(a, t)
    b = ConvNode(b, t)
    IF t = TYINT AND NOp(a) = NICON AND NOp(b) = NICON THEN
        va = NV(a)
        vb = NV(b)
        SELECT CASE op
        CASE TPLUS
            Arith = IConst(va + vb)
            EXIT FUNCTION
        CASE TMINUS
            Arith = IConst(va - vb)
            EXIT FUNCTION
        CASE TMUL
            Arith = IConst(va * vb)
            EXIT FUNCTION
        CASE TIDIV
            IF vb <> 0 THEN
                Arith = IConst(va \ vb)
                EXIT FUNCTION
            END IF
        CASE KMOD
            IF vb <> 0 THEN
                Arith = IConst(va MOD vb)
                EXIT FUNCTION
            END IF
        END SELECT
    END IF
    Arith = BinNode(op, t, a, b)
END FUNCTION

FUNCTION Compare (op, a, b)
    DIM t, n
    t = MaxType(a, b)
    IF t <> TYSTR THEN
        a = ConvNode(a, t)
        b = ConvNode(b, t)
    END IF
    n = BinNode(op, TYINT, a, b)
    NX(n) = t
    NIsBool(n) = 1
    Compare = n
END FUNCTION

' AND OR XOR (and ANDALSO ORELSE, op 1 and 2)
FUNCTION Logic (op, a, b)
    DIM n
    IF op = 1 OR op = 2 THEN
        n = BinNode(op, TYINT, a, b)
        NIsBool(n) = 1
        Logic = n
        EXIT FUNCTION
    END IF
    IF NIsBool(a) AND NIsBool(b) THEN
        n = BinNode(op, TYINT, a, b)
        IF NIsBool(a) = 1 AND NIsBool(b) = 1 THEN NIsBool(n) = 1 ELSE NIsBool(n) = 2
        Logic = n
        EXIT FUNCTION
    END IF
    a = ToInt(a)
    b = ToInt(b)
    IF NOp(a) = NICON AND NOp(b) = NICON THEN
        IF op = KAND THEN
            Logic = IConst(NV(a) AND NV(b))
        ELSEIF op = KOR THEN
            Logic = IConst(NV(a) OR NV(b))
        ELSE
            Logic = IConst(NV(a) XOR NV(b))
        END IF
        EXIT FUNCTION
    END IF
    Logic = BinNode(op, TYINT, a, b)
END FUNCTION

' ---- names

' may a symbol of the module be seen here (in a procedure: constants,
' procedures and shared variables only)
FUNCTION Visible (s)
    IF s = 0 THEN EXIT FUNCTION
    IF SScope(s) = 1 OR InProc = 0 THEN
        Visible = -1
        EXIT FUNCTION
    END IF
    SELECT CASE SKind(s)
    CASE SKCONST, SKSUB, SKFUNC
        Visible = -1
    CASE SKVAR, SKARRAY
        Visible = (SFlags(s) AND SFSHARED) <> 0 OR SCls(s) = SCCOMMON
    END SELECT
END FUNCTION

' a variable, array or constant by its name as written: 0 if there is none
FUNCTION FindVar (n$)
    DIM s, t
    t = SuffixType(n$)
    IF t = 0 THEN
        s = FindSym(n$)
        IF Visible(s) AND SKind(s) <= SKCONST THEN
            FindVar = s
            EXIT FUNCTION
        END IF
        s = FindSym(n$ + TypeChar$(NameType(n$)))
        IF Visible(s) AND SKind(s) <= SKCONST THEN FindVar = s
        EXIT FUNCTION
    END IF
    s = FindSym(n$)
    IF Visible(s) AND SKind(s) <= SKCONST THEN
        FindVar = s
        EXIT FUNCTION
    END IF
    s = FindSym(BaseName$(n$))
    IF Visible(s) AND SKind(s) <= SKCONST THEN
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
        NeedZero = 1
    ELSE
        SCls(s) = SCSTATIC
        SOff(s) = StaticWords
        StaticWords = StaticWords + w
    END IF
    NewVar = s
END FUNCTION

' a variable by its name: found, or (create) made implicitly
FUNCTION LookupVar (n$, create)
    DIM s
    s = FindVar(n$)
    IF s = 0 AND create THEN
        IF OptExplicit THEN ErrMsg n$ + " not declared (OPTION EXPLICIT)"
        IF SuffixType(n$) THEN
            s = NewVar(n$, SKVAR, SuffixType(n$), 0)
        ELSE
            s = NewVar(n$ + TypeChar$(NameType(n$)), SKVAR, NameType(n$), 0)
        END IF
    END IF
    LookupVar = s
END FUNCTION

' ---- real constants

' the P-machine's 4-byte real of a double: [exp+128][sign|m22..m16][m15..m8][m7..m0]
FUNCTION RealImage$ (d#)
    DIM b$, b3, b4, b5, b6, b7, e, m1, m2, m3, sg
    IF d# = 0 THEN
        RealImage$ = STRING$(4, 0)
        EXIT FUNCTION
    END IF
    b$ = MKD$(d#)
    b3 = ASC(b$, 4)
    b4 = ASC(b$, 5)
    b5 = ASC(b$, 6)
    b6 = ASC(b$, 7)
    b7 = ASC(b$, 8)
    sg = b7 AND 128
    e = (b7 AND 127) * 16 + b6 \ 16 - 894
    m1 = (b6 AND 15) * 8 + b5 \ 32
    m2 = (b5 AND 31) * 8 + b4 \ 32
    m3 = (b4 AND 31) * 8 + b3 \ 32
    IF (b3 \ 16) AND 1 THEN
        m3 = m3 + 1
        IF m3 = 256 THEN
            m3 = 0
            m2 = m2 + 1
            IF m2 = 256 THEN
                m2 = 0
                m1 = m1 + 1
                IF m1 = 128 THEN
                    m1 = 0
                    e = e + 1
                END IF
            END IF
        END IF
    END IF
    IF e > 255 THEN
        ErrMsg "real constant too large"
        e = 255
    END IF
    IF e < 1 THEN
        RealImage$ = STRING$(4, 0)
        EXIT FUNCTION
    END IF
    RealImage$ = CHR$(e) + CHR$(sg OR m1) + CHR$(m2) + CHR$(m3)
END FUNCTION

SUB GenRConst (n)
    DIM d#, b$, i
    d# = VAL(NS$(n))
    IF NX(n) THEN d# = -d#
    OB OLDC
    IF NTy(n) = TYDBL THEN
        b$ = MKD$(d#)
        OB 4
        IF PC AND 1 THEN OB 0
        FOR i = 3 TO 0 STEP -1
            OB ASC(b$, 2 * i + 1)
            OB ASC(b$, 2 * i + 2)
        NEXT i
    ELSE
        b$ = RealImage$(d#)
        OB 2
        IF PC AND 1 THEN OB 0
        OB ASC(b$, 3)
        OB ASC(b$, 4)
        OB ASC(b$, 1)
        OB ASC(b$, 2)
    END IF
END SUB

' ---- parsing

FUNCTION Expr ()
    DIM a, b
    a = ParseOr
    DO WHILE Tok = KXOR
        GetTok
        b = ParseOr
        a = Logic(KXOR, a, b)
    LOOP
    Expr = a
END FUNCTION

' an expression of type ty (converted)
FUNCTION ExprType (n, ty)
    ExprType = ConvNode(n, ty)
END FUNCTION

FUNCTION ParseNot ()
    DIM a, n
    IF Tok = KNOT AND PreNode = 0 THEN
        GetTok
        a = ParseNot
        IF NIsBool(a) THEN
            n = NewNode(NNOT, TYINT)
            NA(n) = a
            NIsBool(n) = 2
        ELSE
            a = ToInt(a)
            IF NOp(a) = NICON THEN
                n = IConst(NOT NV(a))
            ELSE
                n = NewNode(NNOT, TYINT)
                NA(n) = a
            END IF
        END IF
        ParseNot = n
        EXIT FUNCTION
    END IF
    ParseNot = ParseCmp
END FUNCTION

FUNCTION ParseAnd ()
    DIM a, b, op
    a = ParseNot
    DO
        IF Tok = KAND THEN
            op = KAND
        ELSEIF Tok = TIDENT AND TokS$ = "ANDALSO" THEN
            op = 1
        ELSE
            EXIT DO
        END IF
        GetTok
        b = ParseNot
        a = Logic(op, a, b)
    LOOP
    ParseAnd = a
END FUNCTION

FUNCTION ParseOr ()
    DIM a, b, op
    a = ParseAnd
    DO
        IF Tok = KOR THEN
            op = KOR
        ELSEIF Tok = TIDENT AND TokS$ = "ORELSE" THEN
            op = 2
        ELSE
            EXIT DO
        END IF
        GetTok
        b = ParseAnd
        a = Logic(op, a, b)
    LOOP
    ParseOr = a
END FUNCTION

FUNCTION ParseCmp ()
    DIM a, b, op
    a = ParseConcat
    DO WHILE Tok >= TEQ AND Tok <= TGE
        op = Tok
        GetTok
        b = ParseConcat
        a = Compare(op, a, b)
    LOOP
    ParseCmp = a
END FUNCTION

FUNCTION ParseConcat ()
    DIM a, b
    a = ParseAdd
    DO WHILE Tok = TAMP
        GetTok
        b = ParseAdd
        a = Arith(TAMP, a, b)
    LOOP
    ParseConcat = a
END FUNCTION

FUNCTION ParseAdd ()
    DIM a, b, op
    a = ParseMod
    DO WHILE Tok = TPLUS OR Tok = TMINUS
        op = Tok
        GetTok
        b = ParseMod
        a = Arith(op, a, b)
    LOOP
    ParseAdd = a
END FUNCTION

FUNCTION ParseMod ()
    DIM a, b
    a = ParseIDiv
    DO WHILE Tok = KMOD
        GetTok
        b = ParseIDiv
        a = Arith(KMOD, a, b)
    LOOP
    ParseMod = a
END FUNCTION

FUNCTION ParseIDiv ()
    DIM a, b
    a = ParseMul
    DO WHILE Tok = TIDIV
        GetTok
        b = ParseMul
        a = Arith(TIDIV, a, b)
    LOOP
    ParseIDiv = a
END FUNCTION

FUNCTION ParseMul ()
    DIM a, b, op
    a = ParseNeg
    DO WHILE Tok = TMUL OR Tok = TDIV
        op = Tok
        GetTok
        b = ParseNeg
        a = Arith(op, a, b)
    LOOP
    ParseMul = a
END FUNCTION

FUNCTION Negate (a)
    DIM n
    a = BoolToInt(a)
    IF NTy(a) = TYSTR THEN ErrMsg "type mismatch"
    IF NOp(a) = NICON THEN
        Negate = IConst(-NV(a))
        EXIT FUNCTION
    END IF
    IF NOp(a) = NRCON THEN
        NX(a) = 1 - NX(a)
        Negate = a
        EXIT FUNCTION
    END IF
    n = NewNode(NNEG, NTy(a))
    NA(n) = a
    Negate = n
END FUNCTION

FUNCTION ParsePow ()
    DIM a, b
    a = Primary
    DO WHILE Tok = TPOW
        GetTok
        IF Tok = TMINUS THEN
            GetTok
            b = Negate(Primary)
        ELSE
            b = Primary
        END IF
        a = Arith(TPOW, a, b)
    LOOP
    ParsePow = a
END FUNCTION

FUNCTION ParseNeg ()
    IF PreNode THEN
        ParseNeg = ParsePow
        EXIT FUNCTION
    END IF
    IF Tok = TMINUS THEN
        GetTok
        ParseNeg = Negate(ParseNeg)
        EXIT FUNCTION
    END IF
    IF Tok = TPLUS THEN GetTok
    ParseNeg = ParsePow
END FUNCTION

' ---- built-in functions

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
        tb$ = tb$ + "CSP%    CSP!    CSP#    OSCALL% OSVAR   POS     FREEFILELOF     DVI%    "
        tb$ = tb$ + "MDI%    SADD    "
    END SELECT
    BuiltTable$ = tb$
END FUNCTION

CONST BLEN = 1, BASC = 2, BCHR = 3, BMID = 4, BLEFT = 5, BRIGHT = 6, BINSTR = 7
CONST BUCASE = 8, BLCASE = 9, BLTRIM = 10, BRTRIM = 11, BTRIM = 12, BSPACE = 13
CONST BSTRING = 14, BSTR = 15, BVAL = 16, BHEX = 17, BCINT = 18, BFIX = 19
CONST BINT = 20, BCSNG = 21, BCDBL = 22, BABS = 23, BSGN = 24, BSQR = 25
CONST BSIN = 26, BCOS = 27, BTAN = 28, BATN = 29, BEXP = 30, BLOG = 31
CONST BRND = 32, BTIMER = 33, BEOF = 34, BINKEY = 35, BCOMMAND = 36, BERR = 37
CONST BMKI = 38, BCVI = 39, BMKS = 40, BCVS = 41, BMKD = 42, BCVD = 43
CONST BLBOUND = 44, BUBOUND = 45, BFRE = 46, BVARPTR = 47, BPEEK = 48
CONST BPEEKB = 49, BCSPI = 50, BCSPS = 51, BCSPD = 52, BOSCALLI = 53
CONST BOSVAR = 54, BPOS = 55, BFREEFILE = 56, BLOF = 57, BDVI = 58, BMDI = 59, BSADD = 60

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

' the arguments of a call in ( ): a chain of nodes (NN); the count in ArgCount

FUNCTION ParseArgs ()
    DIM first, last, a, k
    ArgCount = 0
    IF Tok <> TLPAR THEN EXIT FUNCTION
    GetTok
    IF Tok = TRPAR THEN
        GetTok
        EXIT FUNCTION
    END IF
    DO
        a = Expr
        k = k + 1
        IF first = 0 THEN first = a ELSE NN(last) = a
        last = a
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
    Expect TRPAR, ")"
    ArgCount = k
    ParseArgs = first
END FUNCTION

FUNCTION NthArg (a, k)
    DIM i
    FOR i = 2 TO k
        IF a > 0 THEN a = NN(a)
    NEXT i
    NthArg = a
END FUNCTION

' the result type of a built-in, its arguments converted (in place)
FUNCTION Builtin (id, nm$)
    DIM n, a, nargs, ty, t1, i, x
    IF id = BLBOUND OR id = BUBOUND THEN
        n = NewNode(NBUILT, TYINT)
        NV(n) = id
        Expect TLPAR, "("
        IF Tok <> TIDENT THEN
            ErrMsg "an array name expected"
        ELSE
            a = FindVar(TokS$)
            IF a = 0 THEN ErrMsg TokS$ + " is not an array" ELSE IF SKind(a) <> SKARRAY THEN ErrMsg TokS$ + " is not an array"
            NX(n) = a
            GetTok
            IF Tok = TLPAR THEN
                GetTok
                Expect TRPAR, ")"
            END IF
        END IF
        NA(n) = IConst(1)
        IF Tok = TCOMMA THEN
            GetTok
            NA(n) = ToInt(Expr)
        END IF
        Expect TRPAR, ")"
        Builtin = n
        EXIT FUNCTION
    END IF
    IF id = BVARPTR THEN
        Expect TLPAR, "("
        a = Expr
        Expect TRPAR, ")"
        IF NOT IsLvalue(a) THEN ErrMsg "VARPTR needs a variable"
        n = NewNode(NADDR, TYINT)
        NA(n) = a
        Builtin = n
        EXIT FUNCTION
    END IF
    a = ParseArgs
    nargs = ArgCount
    n = NewNode(NBUILT, TYINT)
    NV(n) = id
    NX(n) = nargs
    t1 = TYINT
    IF a > 0 THEN
        t1 = NTy(a)
        IF NIsBool(a) THEN t1 = TYINT
    END IF
    ty = TYINT
    SELECT CASE id
    CASE BLEN, BASC, BCVI, BCVS, BCVD, BVAL, BUCASE, BLCASE, BLTRIM, BRTRIM, BTRIM
        ' string first
        IF nargs < 1 THEN ErrMsg nm$ + ": an argument expected" ELSE a = ConvKeep(a, TYSTR)
        SELECT CASE id
        CASE BCVS: ty = TYSNG
        CASE BCVD, BVAL: ty = TYDBL
        CASE BUCASE, BLCASE, BLTRIM, BRTRIM, BTRIM: ty = TYSTR
        END SELECT
        IF id = BASC AND nargs = 2 THEN NN(a) = ConvKeep(NN(a), TYINT)
    CASE BMID, BLEFT, BRIGHT
        ty = TYSTR
        IF nargs < 2 THEN
            ErrMsg nm$ + ": arguments expected"
        ELSE
            a = ConvKeep(a, TYSTR)
            NN(a) = ConvKeep(NN(a), TYINT)
            IF nargs = 3 THEN NN(NN(a)) = ConvKeep(NN(NN(a)), TYINT)
        END IF
    CASE BFRE
        IF nargs <> 1 THEN ErrMsg "FRE: one argument expected"
    CASE BCHR, BSPACE, BHEX, BMKI, BEOF, BPEEK, BPEEKB, BOSVAR, BPOS, BLOF
        IF nargs <> 1 THEN ErrMsg nm$ + ": one argument expected" ELSE a = ConvKeep(a, TYINT)
        IF id = BOSVAR AND NOp(a) <> NICON THEN ErrMsg "OSVAR: a constant expected"
        IF id = BCHR OR id = BSPACE OR id = BHEX OR id = BMKI THEN ty = TYSTR
    CASE BSTRING
        ty = TYSTR
        IF nargs <> 2 THEN
            ErrMsg nm$ + ": two arguments expected"
        ELSE
            a = ConvKeep(a, TYINT)
            x = NN(a)
            IF NTy(x) = TYSTR THEN
                ' STRING$(n, "c"): its first character
                i = NewNode(NBUILT, TYINT)
                NV(i) = BASC
                NX(i) = 1
                NA(i) = x
                NN(a) = i
            ELSE
                NN(a) = ConvKeep(x, TYINT)
            END IF
        END IF
    CASE BINSTR
        IF nargs = 2 THEN
            x = IConst(1)
            NN(x) = a
            a = x
            nargs = 3
            NX(n) = 3
        END IF
        IF nargs <> 3 THEN
            ErrMsg "INSTR: arguments expected"
        ELSE
            a = ConvKeep(a, TYINT)
            NN(a) = ConvKeep(NN(a), TYSTR)
            NN(NN(a)) = ConvKeep(NN(NN(a)), TYSTR)
        END IF
    CASE BSTR
        ty = TYSTR
        IF nargs <> 1 THEN ErrMsg "STR$: one argument expected" ELSE a = ConvKeep(a, t1)
    CASE BCINT
        IF nargs <> 1 THEN ErrMsg nm$ + ": one argument expected"
    CASE BFIX, BINT, BABS
        IF nargs <> 1 THEN ErrMsg nm$ + ": one argument expected" ELSE a = ConvKeep(a, t1)
        ty = t1
    CASE BSGN
        IF nargs <> 1 THEN ErrMsg nm$ + ": one argument expected" ELSE a = ConvKeep(a, t1)
    CASE BCSNG, BCDBL
        IF nargs <> 1 THEN ErrMsg nm$ + ": one argument expected"
        IF id = BCSNG THEN ty = TYSNG ELSE ty = TYDBL
        a = ConvNode(a, ty)
        Builtin = a
        EXIT FUNCTION
    CASE BSQR, BSIN, BCOS, BTAN, BATN, BEXP, BLOG
        IF nargs <> 1 THEN ErrMsg nm$ + ": one argument expected"
        IF t1 = TYDBL THEN ty = TYDBL ELSE ty = TYSNG
        IF nargs = 1 THEN a = ConvKeep(a, ty)
    CASE BMKS
        ty = TYSTR
        IF nargs = 1 THEN a = ConvKeep(a, TYSNG)
    CASE BMKD
        ty = TYSTR
        IF nargs = 1 THEN a = ConvKeep(a, TYDBL)
    CASE BRND, BTIMER
        ty = TYSNG
    CASE BINKEY, BCOMMAND
        ty = TYSTR
    CASE BERR, BFREEFILE
    CASE BDVI, BMDI
        IF nargs <> 2 THEN
            ErrMsg nm$ + ": two arguments expected"
        ELSE
            a = ConvKeep(a, TYINT)
            NN(a) = ConvKeep(NN(a), TYINT)
        END IF
    CASE BSADD
        IF nargs <> 1 THEN ErrMsg "SADD: one argument expected" ELSE a = ConvKeep(a, TYSTR)
    CASE BCSPI, BCSPS, BCSPD, BOSCALLI
        IF nargs < 1 THEN ErrMsg nm$ + ": arguments expected"
        IF NOp(a) <> NICON THEN ErrMsg nm$ + ": a constant first"
        IF id = BCSPS THEN ty = TYSNG
        IF id = BCSPD THEN ty = TYDBL
        x = NN(a)
        DO WHILE x > 0
            IF NIsBool(x) THEN ErrMsg nm$ + ": a comparison as an argument"
            x = NN(x)
        LOOP
    END SELECT
    IF id = BCINT THEN
        a = ToInt(a)
        Builtin = a
        EXIT FUNCTION
    END IF
    NA(n) = a
    NTy(n) = ty
    Builtin = n
END FUNCTION

' ---- primaries: constants, variables, elements, calls, built-ins

' an array element: name ( indexes ) -- the "(" is current
FUNCTION ElemNode (s)
    DIM n, a, x, k
    n = NewNode(NELEM, SType(s))
    IF SType(s) = TYBYTE THEN NTy(n) = TYINT
    NV(n) = s
    a = ParseArgs
    k = ArgCount
    IF k = 0 THEN ErrMsg "an index expected"
    IF SAux(s) > 0 AND SAux(s) <> k THEN ErrMsg SName$(s) + ": the wrong number of indexes"
    ' the indexes as integers (the chain kept in order)
    x = a
    a = 0
    DO WHILE x > 0
        k = NN(x)
        NN(x) = 0
        x = ToInt(x)
        IF a = 0 THEN NA(n) = x ELSE NN(a) = x
        a = x
        x = k
    LOOP
    NX(n) = ArgCount
    ElemNode = n
END FUNCTION

FUNCTION CallNode (s)
    DIM n, a, k, i, p, x, prev, nxt
    n = NewNode(NCALL, SType(s))
    NV(n) = s
    IF Tok = TLPAR THEN
        a = ArgList(s, 1, 1)
    ELSEIF SAux2(s) > 0 THEN
        ErrMsg SName$(s) + ": arguments expected"
    END IF
    NA(n) = a
    CallNode = n
END FUNCTION

' the arguments of a call of procedure s ( ... ) or, for a SUB called
' without CALL, without the ( ): their nodes, an array argument as an
' NVAR of the array.  paren: the "(" is current.
FUNCTION ArgList (s, paren, check)
    DIM first, last, a, k, np, pk, s2
    np = SAux2(s)
    IF paren THEN GetTok
    k = 0
    IF (paren AND Tok = TRPAR) OR (paren = 0 AND AtEnd) THEN
        IF paren THEN GetTok
    ELSE
        DO
            k = k + 1
            pk = SAux(s) + k - 1
            a = 0
            IF k <= np THEN
                IF PFlg(pk) AND PFARRAY THEN
                    IF Tok = TIDENT THEN
                        s2 = FindVar(TokS$)
                        IF s2 > 0 THEN
                            IF SKind(s2) = SKARRAY THEN
                                GetTok
                                IF Tok = TLPAR THEN
                                    GetTok
                                    Expect TRPAR, ")"
                                END IF
                                a = NewNode(NVAR, SType(s2))
                                NV(a) = s2
                                NX(a) = 1
                            END IF
                        END IF
                    END IF
                    IF a = 0 THEN ErrMsg "an array expected as argument " + IStr$(k) + " of " + SName$(s)
                END IF
            END IF
            IF a = 0 THEN a = Expr
            IF first = 0 THEN first = a ELSE NN(last) = a
            last = a
            IF Tok <> TCOMMA THEN EXIT DO
            GetTok
        LOOP
        IF paren THEN Expect TRPAR, ")"
    END IF
    IF k <> np AND check THEN ErrMsg SName$(s) + ": " + IStr$(np) + " argument(s) expected"
    ArgCount = k
    ArgList = first
END FUNCTION

FUNCTION VarNode (n$)
    DIM s, n
    s = LookupVar(n$, 1)
    IF SKind(s) = SKCONST THEN
        IF SType(s) = TYINT THEN
            n = IConst(SAux(s))
        ELSEIF SType(s) = TYSTR THEN
            n = NewNode(NSCON, TYSTR)
            NS$(n) = ConstText$(SAux(s))
        ELSE
            n = NewNode(NRCON, SType(s))
            NS$(n) = ConstText$(SAux(s))
        END IF
        VarNode = n
        EXIT FUNCTION
    END IF
    IF SKind(s) = SKARRAY THEN ErrMsg SName$(s) + " is an array: an index expected"
    n = NewNode(NVAR, SType(s))
    IF SType(s) = TYBYTE THEN NTy(n) = TYINT
    NV(n) = s
    VarNode = n
END FUNCTION

FUNCTION Primary ()
    DIM n, s, nm$, id
    IF PreNode THEN
        ' a SUB call's (x) + ...: the parenthesized start of its argument
        Primary = PreNode
        PreNode = 0
        EXIT FUNCTION
    END IF
    SELECT CASE Tok
    CASE TINT
        n = IConst(TokV)
        GetTok
    CASE TSNG, TDBL
        IF Tok = TSNG THEN n = NewNode(NRCON, TYSNG) ELSE n = NewNode(NRCON, TYDBL)
        NS$(n) = TokS$
        GetTok
    CASE TSTR
        n = NewNode(NSCON, TYSTR)
        NS$(n) = TokS$
        GetTok
    CASE TLPAR
        GetTok
        n = Expr
        Expect TRPAR, ")"
    CASE TIDENT
        nm$ = TokS$
        GetTok
        ' a variable, array, constant or function of the program first
        s = FindVar(nm$)
        IF s > 0 THEN
            IF SKind(s) = SKARRAY THEN
                IF Tok = TLPAR THEN
                    n = ElemNode(s)
                ELSE
                    ErrMsg nm$ + " is an array: an index expected"
                    n = IConst(0)
                END IF
            ELSE
                n = VarNode(nm$)
            END IF
        ELSE
            s = FindProc(nm$)
            IF s > 0 THEN
                IF SKind(s) = SKSUB THEN ErrMsg nm$ + " is a SUB, not a FUNCTION"
                n = CallNode(s)
            ELSE
                id = BuiltinId(nm$)
                IF id > 0 THEN
                    n = Builtin(id, nm$)
                ELSEIF Tok = TLPAR THEN
                    ErrMsg nm$ + ": no such array or function"
                    n = ParseArgs
                    n = IConst(0)
                ELSE
                    n = VarNode(nm$)
                END IF
            END IF
        END IF
    CASE ELSE
        ErrMsg "an expression expected, not " + KwName$(Tok)
        n = IConst(0)
        IF NOT AtEnd THEN GetTok
    END SELECT
    Primary = n
END FUNCTION

' CONST: an expression of constants only; its value in v (integers), the
' node returned
FUNCTION ConstExpr (v)
    DIM n
    n = Expr
    IF NOp(n) = NBOOL THEN n = NA(n)
    IF NOp(n) = NICON THEN
        v = NV(n)
    ELSEIF NOp(n) <> NRCON AND NOp(n) <> NSCON THEN
        ErrMsg "a constant expression expected"
    END IF
    ConstExpr = n
END FUNCTION

' ---- code: values

FUNCTION IsLvalue (n)
    IF NOp(n) = NVAR THEN
        IsLvalue = SKind(NV(n)) = SKVAR
    ELSEIF NOp(n) = NELEM THEN
        IsLvalue = -1
    END IF
END FUNCTION

' an array's slot: its address (an array parameter holds the caller's)
SUB GenSlot (s)
    SELECT CASE SCls(s)
    CASE SCLOCAL, SCPARAM: Lla SOff(s)
    CASE SCSTATIC, SCCOMMON: GlobOp OLAO, s, 0
    CASE SCREF: Ldl SOff(s)
    END SELECT
END SUB

' an element's address
SUB GenElem (n)
    DIM s, x, k
    s = NV(n)
    k = NX(n)
    IF k = 1 THEN
        GenSlot s
        GenValue NA(n)
        CallRt "_AX1"
    ELSEIF k = 2 THEN
        GenSlot s
        GenValue NA(n)
        GenValue NN(NA(n))
        CallRt "_AX2"
    ELSE
        x = NA(n)
        DO WHILE x > 0
            GenValue x
            CallRt "_AIDX"
            x = NN(x)
        LOOP
        GenSlot s
        Ldc k
        CallRt "_AXN"
    END IF
END SUB

SUB GenAddr (n)
    DIM s
    IF NOp(n) = NELEM THEN
        GenElem n
        EXIT SUB
    END IF
    s = NV(n)
    SELECT CASE SCls(s)
    CASE SCLOCAL, SCPARAM: Lla SOff(s)
    CASE SCSTATIC, SCCOMMON: GlobOp OLAO, s, 0
    CASE SCREF: Ldl SOff(s)
    END SELECT
END SUB

' the type a variable or element is stored as (TYBYTE stays)
FUNCTION StoreType (n)
    StoreType = SType(NV(n))
END FUNCTION

SUB GenLoad (n)
    DIM s, w, ty
    s = NV(n)
    ty = StoreType(n)
    w = TypeWords(ty)
    IF NOp(n) = NELEM THEN
        GenElem n
        IF ty = TYBYTE THEN
            OB 0
            OB OLDB
        ELSEIF w = 1 THEN
            Ind0
        ELSE
            OB OLDM
            OB w
        END IF
        EXIT SUB
    END IF
    SELECT CASE SCls(s)
    CASE SCLOCAL, SCPARAM
        IF w = 1 THEN
            Ldl SOff(s)
        ELSE
            Lla SOff(s)
            OB OLDM
            OB w
        END IF
    CASE SCSTATIC, SCCOMMON
        IF w = 1 THEN
            GlobOp OLDO, s, 0
        ELSE
            GlobOp OLAO, s, 0
            OB OLDM
            OB w
        END IF
    CASE SCREF
        Ldl SOff(s)
        IF ty = TYBYTE THEN
            OB 0
            OB OLDB
        ELSEIF w = 1 THEN
            Ind0
        ELSE
            OB OLDM
            OB w
        END IF
    END SELECT
END SUB

' a store: the part before the value (an address, if one is needed)
SUB StorePre (n)
    DIM s, w, ty
    s = NV(n)
    ty = StoreType(n)
    w = TypeWords(ty)
    IF ty = TYSTR THEN
        GenAddr n
        EXIT SUB
    END IF
    IF NOp(n) = NELEM THEN
        GenElem n
        IF ty = TYBYTE THEN OB 0
        EXIT SUB
    END IF
    SELECT CASE SCls(s)
    CASE SCLOCAL, SCPARAM
        IF w > 1 THEN Lla SOff(s)
    CASE SCSTATIC, SCCOMMON
        IF w > 1 THEN GlobOp OLAO, s, 0
    CASE SCREF
        Ldl SOff(s)
        IF ty = TYBYTE THEN OB 0
    END SELECT
END SUB

' a store: after the value
SUB GenStore (n)
    DIM s, w, ty
    s = NV(n)
    ty = StoreType(n)
    w = TypeWords(ty)
    IF ty = TYSTR THEN
        CallRt "_SASG"
        EXIT SUB
    END IF
    IF NOp(n) = NELEM OR SCls(s) = SCREF THEN
        IF ty = TYBYTE THEN
            OB OSTB
        ELSEIF w = 1 THEN
            OB OSTO
        ELSE
            OB OSTM
            OB w
        END IF
        EXIT SUB
    END IF
    IF ty = TYBYTE THEN
        Ldc 255
        OB OLAND
    END IF
    SELECT CASE SCls(s)
    CASE SCLOCAL, SCPARAM
        IF w = 1 THEN
            Stl SOff(s)
        ELSE
            OB OSTM
            OB w
        END IF
    CASE SCSTATIC, SCCOMMON
        IF w = 1 THEN
            GlobOp OSRO, s, 0
        ELSE
            OB OSTM
            OB w
        END IF
    END SELECT
END SUB

SUB GenValueAs (n, ty)
    GenValue ConvNode(n, ty)
END SUB

' a conversion: the value of NA(n) is on the stack
SUB GenConv (n)
    DIM f, t
    f = NTy(NA(n))
    t = NTy(n)
    IF t = TYSNG THEN
        IF f = TYINT THEN OB OFLT ELSE Csp 107
    ELSEIF t = TYDBL THEN
        IF f = TYINT THEN Csp 108 ELSE Csp 106
    ELSE
        IF f = TYSNG THEN Csp 24 ELSE CallRt "_DCINT"
    END IF
END SUB

' DCMP's relation codes: 0 == 1 <> 2 < 3 <= 4 > 5 >=
FUNCTION DRel (op)
    SELECT CASE op
    CASE TEQ: DRel = 0
    CASE TNE: DRel = 1
    CASE TLT: DRel = 2
    CASE TLE: DRel = 3
    CASE TGT: DRel = 4
    CASE TGE: DRel = 5
    END SELECT
END FUNCTION

SUB GenCompare (op, ty)
    DIM o
    IF ty = TYDBL THEN
        Ldc DRel(op)
        Csp 105
        EXIT SUB
    END IF
    IF ty = TYSTR THEN
        CallRt "_SCMP"
        OB 0
        ty = TYINT
    END IF
    SELECT CASE op
    CASE TEQ: o = OEQUI
    CASE TNE: o = ONEQI
    CASE TLT: o = OLESI
    CASE TGT: o = OGRTI
    CASE TLE: o = OLEQI
    CASE TGE: o = OGEQI
    END SELECT
    IF ty = TYINT THEN
        OB o
    ELSE
        ' the real comparisons: EQU REAL ...
        SELECT CASE op
        CASE TEQ: OB OEQU
        CASE TNE: OB ONEQ
        CASE TLT: OB OLES
        CASE TGT: OB OGRT
        CASE TLE: OB OLEQ
        CASE TGE: OB OGEQ
        END SELECT
        OB 2
    END IF
END SUB

SUB GenBin (n)
    DIM op, ty, l1, l2
    op = NV(n)
    ty = NTy(n)
    IF op = 1 OR op = 2 THEN
        ' ANDALSO / ORELSE as a value
        l1 = NewLabel
        l2 = NewLabel
        GenCond n, l1
        OB 1
        Jump OUJP, l2
        SetLabel l1
        OB 0
        SetLabel l2
        EXIT SUB
    END IF
    GenValue NA(n)
    GenValue NB(n)
    IF op >= TEQ AND op <= TGE THEN
        GenCompare op, NX(n)
        EXIT SUB
    END IF
    SELECT CASE op
    CASE KAND
        OB OLAND
    CASE KOR
        OB OLOR
    CASE KXOR
        CallRt "_XOR"
    CASE TPOW
        Csp 123
    CASE TPLUS
        IF ty = TYSTR THEN
            CallRt "_SCAT"
            TempUsed = 1
        ELSEIF ty = TYINT THEN
            OB OADI
        ELSEIF ty = TYSNG THEN
            OB OADR
        ELSE
            Csp 100
        END IF
    CASE TMINUS
        IF ty = TYINT THEN OB OSBI ELSE IF ty = TYSNG THEN OB OSBR ELSE Csp 101
    CASE TMUL
        IF ty = TYINT THEN OB OMPI ELSE IF ty = TYSNG THEN OB OMPR ELSE Csp 102
    CASE TDIV
        IF ty = TYSNG THEN OB ODVR ELSE Csp 103
    CASE TIDIV
        CallRt "_DIVI"
    CASE KMOD
        CallRt "_MODI"
    END SELECT
END SUB

' words pushed as the room of a result bigger than the arguments
SUB DropPad (n)
    DIM i
    FOR i = 1 TO n
        OB 0
    NEXT i
END SUB

' the run-time procedure of a built-in, by the type of its argument
SUB GenBuiltin (n)
    DIM id, a, t1, x, nm$
    id = NV(n)
    a = NA(n)
    t1 = TYINT
    IF a > 0 THEN t1 = NTy(a)
    SELECT CASE id
    CASE BLBOUND
        Ldc 0
        EXIT SUB
    CASE BUBOUND
        GenSlot NX(n)
        GenValue NA(n)
        CallRt "_AUB"
        EXIT SUB
    CASE BCSPI, BCSPS, BCSPD, BOSCALLI
        x = NN(a)
        DO WHILE x > 0
            GenValue x
            x = NN(x)
        LOOP
        IF id = BOSCALLI THEN
            OB OCXP
            OB 0
            OB NV(a)
        ELSE
            Csp NV(a)
        END IF
        EXIT SUB
    CASE BOSVAR
        OB OLOD
        OB 2
        OBig NV(a)
        EXIT SUB
    END SELECT
    IF NTy(n) = TYSTR THEN TempUsed = 1
    ' the arguments, in order
    x = a
    DO WHILE x > 0
        GenValue x
        x = NN(x)
    LOOP
    ' a real result from the library: its words in the parameters' place
    SELECT CASE id
    CASE BVAL, BCVD: DropPad 3
    CASE BCVS: DropPad 1
    CASE BRND, BTIMER: IF NX(n) = 0 THEN DropPad 2
    CASE BINKEY, BCOMMAND, BERR, BFREEFILE: DropPad 1
    END SELECT
    SELECT CASE id
    CASE BLEN: CallRt "_SLEN"
    CASE BASC
        IF NX(n) = 1 THEN Ldc 1
        CallRt "_ASC"
    CASE BCHR: CallRt "_CHR"
    CASE BMID
        IF NX(n) = 2 THEN Ldc 255
        CallRt "_MID"
    CASE BLEFT: CallRt "_LEFT"
    CASE BRIGHT: CallRt "_RIGHT"
    CASE BINSTR: CallRt "_INSTR"
    CASE BUCASE: CallRt "_UCASE"
    CASE BLCASE: CallRt "_LCASE"
    CASE BLTRIM: CallRt "_LTRIM"
    CASE BRTRIM: CallRt "_RTRIM"
    CASE BTRIM: CallRt "_TRIM"
    CASE BSPACE: CallRt "_SPACE"
    CASE BSTRING: CallRt "_STRNG"
    CASE BSTR
        IF t1 = TYINT THEN
            CallRt "_STRI"
        ELSEIF t1 = TYSNG THEN
            CallRt "_STRS"
        ELSE
            CallRt "_STRD"
        END IF
    CASE BVAL: CallRt "_VAL"
    CASE BHEX: CallRt "_HEX"
    CASE BFIX
        IF t1 = TYSNG THEN CallRt "_FIXS" ELSE IF t1 = TYDBL THEN CallRt "_FIXD"
    CASE BINT
        IF t1 = TYSNG THEN CallRt "_INTS" ELSE IF t1 = TYDBL THEN Csp 124
    CASE BABS
        IF t1 = TYINT THEN
            OB OABI
        ELSEIF t1 = TYSNG THEN
            OB OABR
        ELSE
            Csp 126
        END IF
    CASE BSGN
        IF t1 = TYINT THEN
            CallRt "_SGNI"
        ELSEIF t1 = TYSNG THEN
            CallRt "_SGNS"
        ELSE
            CallRt "_SGND"
        END IF
    CASE BSQR
        IF t1 = TYDBL THEN Csp 112 ELSE Csp 31
    CASE BSIN
        IF t1 = TYDBL THEN Csp 113 ELSE Csp 25
    CASE BCOS
        IF t1 = TYDBL THEN Csp 114 ELSE Csp 26
    CASE BTAN
        IF t1 = TYDBL THEN Csp 115 ELSE CallRt "_TANS"
    CASE BATN
        IF t1 = TYDBL THEN Csp 118 ELSE Csp 28
    CASE BEXP
        IF t1 = TYDBL THEN Csp 120 ELSE Csp 30
    CASE BLOG
        IF t1 = TYDBL THEN Csp 121 ELSE Csp 29
    CASE BRND
        IF NX(n) = 1 THEN
            DropWords NodeWords(a)
            DropPad 2
        END IF
        CallRt "_RND"
    CASE BTIMER: CallRt "_TIMER"
    CASE BEOF: CallRt "_EOF"
    CASE BLOF: CallRt "_LOF"
    CASE BINKEY: CallRt "_INKEY"
    CASE BCOMMAND: CallRt "_CMD"
    CASE BERR: CallRt "_ERRNO"
    CASE BMKI: CallRt "_MKI"
    CASE BCVI: CallRt "_CVI"
    CASE BMKS: CallRt "_MKS"
    CASE BCVS: CallRt "_CVS"
    CASE BMKD: CallRt "_MKD"
    CASE BCVD: CallRt "_CVD"
    CASE BFRE
        IF NTy(a) = TYSTR THEN
            DropWords 1
            Ldc 0
        END IF
        CallRt "_FRE"
    CASE BPEEK: Ind0
    CASE BPEEKB
        OB 0
        OB OLDB
    CASE BPOS: CallRt "_POS"
    CASE BFREEFILE: CallRt "_FREEF"
    CASE BDVI: OB &H86
    CASE BMDI: OB &H8E
    CASE BSADD
    END SELECT
END SUB

SUB GenValue (n)
    DIM s, op
    op = NOp(n)
    SELECT CASE op
    CASE NICON
        Ldc NV(n)
    CASE NRCON
        GenRConst n
    CASE NSCON
        OB OLSA
        OB LEN(NS$(n))
        FOR s = 1 TO LEN(NS$(n))
            OB ASC(NS$(n), s)
        NEXT s
    CASE NVAR, NELEM
        GenLoad n
    CASE NCALL
        GenCall n, 1
    CASE NBUILT
        GenBuiltin n
    CASE NNEG
        GenValue NA(n)
        IF NTy(n) = TYINT THEN
            OB ONGI
        ELSEIF NTy(n) = TYSNG THEN
            OB ONGR
        ELSE
            Csp 104
        END IF
    CASE NNOT
        GenValue NA(n)
        OB ONOT
    CASE NBIN
        GenBin n
    CASE NCONV
        GenValue NA(n)
        GenConv n
    CASE NBOOL
        GenValue NA(n)
        IF NIsBool(NA(n)) <> 1 THEN
            OB 1
            OB OLAND
        END IF
        OB ONGI
    CASE NADDR
        GenAddr NA(n)
    END SELECT
END SUB

' ---- code: conditions (jump to falselab when n is false)

SUB GenCond (n, falselab)
    DIM op, l
    IF NOp(n) = NICON THEN
        IF NV(n) = 0 THEN Jump OUJP, falselab
        EXIT SUB
    END IF
    IF NOp(n) = NBIN THEN
        op = NV(n)
        IF op = 1 THEN
            GenCond NA(n), falselab
            GenCond NB(n), falselab
            EXIT SUB
        END IF
        IF op = 2 THEN
            l = NewLabel
            op = NewLabel
            GenCond NA(n), l
            Jump OUJP, op
            SetLabel l
            GenCond NB(n), falselab
            SetLabel op
            EXIT SUB
        END IF
        IF (op = TEQ OR op = TNE) AND NX(n) = TYINT THEN
            GenValue NA(n)
            GenValue NB(n)
            IF op = TEQ THEN Jump OEFJ, falselab ELSE Jump ONFJ, falselab
            EXIT SUB
        END IF
    END IF
    IF NTy(n) = TYSTR THEN
        ErrMsg "type mismatch: a string as a condition"
        EXIT SUB
    END IF
    GenValue n
    IF NIsBool(n) THEN
        Jump OFJP, falselab
    ELSEIF NTy(n) = TYINT THEN
        OB 0
        Jump ONFJ, falselab
    ELSEIF NTy(n) = TYSNG THEN
        OB OLDC
        OB 2
        IF PC AND 1 THEN OB 0
        OW 0
        OW 0
        OB ONEQ
        OB 2
        Jump OFJP, falselab
    ELSE
        OB 0
        Csp 108
        Ldc 1
        Csp 105
        Jump OFJP, falselab
    END IF
END SUB

' ---- code: calls

' a temporary for a BYREF argument that is not a variable of its type
FUNCTION TempFor (ty)
    DIM s
    s = AddSym("", SKVAR, ty)
    SScope(s) = 1
    SCls(s) = SCLOCAL
    SOff(s) = NewLocal(TypeWords(ty))
    NeedZero = 1
    TempFor = s
END FUNCTION

SUB GenCall (n, want)
    DIM s, a, i, pk, pt, pf, pw, rw, t, ok, x
    s = NV(n)
    a = NA(n)
    pw = 0
    FOR i = 1 TO SAux2(s)
        IF a = 0 THEN EXIT FOR
        pk = SAux(s) + i - 1
        pt = PType(pk)
        pf = PFlg(pk)
        IF pf AND PFARRAY THEN
            IF NOp(a) = NVAR THEN
                IF SKind(NV(a)) = SKARRAY THEN
                    IF SType(NV(a)) <> pt THEN ErrMsg "argument " + IStr$(i) + " of " + SName$(s) + ": an array of another type"
                    GenSlot NV(a)
                END IF
            END IF
            pw = pw + 1
        ELSEIF pf AND PFBYREF THEN
            ok = IsLvalue(a)
            IF ok THEN ok = StoreType(a) = pt
            IF ok THEN
                GenAddr a
            ELSE
                t = TempFor(pt)
                x = NewNode(NVAR, pt)
                NV(x) = t
                StorePre x
                GenValueAs a, pt
                GenStore x
                Lla SOff(t)
            END IF
            pw = pw + 1
        ELSE
            IF pt = TYBYTE THEN pt = TYINT
            GenValueAs a, pt
            IF pt = TYSTR AND IsLvalue(a) THEN
                CallRt "_STMP"
                TempUsed = 1
            END IF
            pw = pw + TypeWords(pt)
        END IF
        a = NN(a)
    NEXT i
    rw = TypeWords(SType(s))
    DO WHILE pw < rw
        OB 0
        pw = pw + 1
    LOOP
    CallSym s
    IF SType(s) = TYSTR THEN TempUsed = 1
    IF want = 0 THEN DropWords rw
END SUB
