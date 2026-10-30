' BCEXPR -- pass 3: expressions
'
' An expression is parsed into a tree of nodes (one statement's nodes at a
' time), typed as it is built (conversions are nodes), and then its code
' is generated.  A comparison is a "boolean": 1 or 0 on the stack (FJP
' tests bit 0), made -1 / 0 when it is used as a number, as BASIC wants.
#INCLUDE "BCBUILT"
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"

' ---- nodes

SUB ResetNodes ()
    DIM i
    FOR i = 1 TO NNode
        IF NS$(i) <> "" THEN NS$(i) = ""
    NEXT i
    NNode = 0
END SUB

FUNCTION NewNode (op, ty)
    IF NNode >= NodeCap THEN
        IF NodeCap < MAXNODE THEN
            NodeCap = Grown(NodeCap, MAXNODE)
            REDIM PRESERVE NOp(NodeCap) AS BYTE, NTy(NodeCap) AS BYTE, NA(NodeCap), NB(NodeCap)
            REDIM PRESERVE NV(NodeCap), NX(NodeCap), NN(NodeCap), NS$(NodeCap), NIsBool(NodeCap) AS BYTE
        ELSE
            ErrNo 84   ' expression too complex
            NNode = 1
        END IF
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
        ErrNo 85   ' type mismatch
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

SEGMENT EXPR
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

SEGMENT
FUNCTION MaxType (a, b)
    DIM ta, tb
    ta = NTy(a)
    tb = NTy(b)
    IF ta = TYSTR OR tb = TYSTR THEN
        IF ta <> tb THEN ErrNo 85   ' type mismatch
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

SEGMENT EXPR
' + - * / \ MOD ^ & on two operands (& of strings joins them; of INTEGERs
' and BYTEs it is a bitwise and: ParseConcat)
FUNCTION Arith (op, a, b)
    DIM t, va, vb, r
    t = MaxType(a, b)
    IF t = TYSTR THEN
        IF op <> TPLUS AND op <> TAMP THEN ErrNo 85   ' type mismatch
        Arith = BinNode(TPLUS, TYSTR, a, b)
        EXIT FUNCTION
    END IF
    IF op = TAMP THEN ErrNo 86   ' & needs strings, INTEGERs or BYTEs
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

SEGMENT
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

SEGMENT EXPR
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

SEGMENT
' may a symbol of the module be seen here (in a procedure: constants,
' procedures and shared variables only)
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
        IF OptExplicit THEN ErrRec 87, 0, 0, n$   ' {s} not declared (OPTION EXPLICIT)
        IF SuffixType(n$) THEN
            s = NewVar(n$, SKVAR, SuffixType(n$), 0)
        ELSE
            s = NewVar(n$ + TypeChar$(NameType(n$)), SKVAR, NameType(n$), 0)
        END IF
    END IF
    LookupVar = s
END FUNCTION

' ---- parsing

SEGMENT EXPR
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
    a = ParseBitOr
    DO WHILE Tok >= TEQ AND Tok <= TGE
        op = Tok
        GetTok
        b = ParseBitOr
        a = Compare(op, a, b)
    LOOP
    ParseCmp = a
END FUNCTION

SEGMENT
' an INTEGER or a BYTE (& and |: no other type)
FUNCTION IsIntNode (n)
    IsIntNode = NTy(n) = TYINT OR NTy(n) = TYBYTE
END FUNCTION

SEGMENT EXPR
' a | b: bitwise or, of INTEGERs and BYTEs
FUNCTION ParseBitOr ()
    DIM a, b
    a = ParseConcat
    DO WHILE Tok = TBAR
        GetTok
        b = ParseConcat
        IF IsIntNode(a) AND IsIntNode(b) THEN a = Logic(KOR, a, b) ELSE ErrNo 118   ' | needs INTEGERs or BYTEs
    LOOP
    ParseBitOr = a
END FUNCTION

' a & b: strings joined, or a bitwise and of INTEGERs and BYTEs
FUNCTION ParseConcat ()
    DIM a, b
    a = ParseAdd
    DO WHILE Tok = TAMP
        GetTok
        b = ParseAdd
        IF IsIntNode(a) AND IsIntNode(b) THEN a = Logic(KAND, a, b) ELSE a = Arith(TAMP, a, b)
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
    IF NTy(a) = TYSTR THEN ErrNo 85   ' type mismatch
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
    Expect TRPAR
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
        Expect TLPAR
        IF Tok <> TIDENT THEN
            ErrNo 74   ' an array name expected
        ELSE
            a = FindVar(TokS$)
            IF a = 0 THEN ErrRec 58, 0, 0, TokS$ ELSE IF SKind(a) <> SKARRAY THEN ErrRec 58, 0, 0, TokS$   ' {s} is not an array
            NX(n) = a
            GetTok
            IF Tok = TLPAR THEN
                GetTok
                Expect TRPAR
            END IF
        END IF
        NA(n) = IConst(1)
        IF Tok = TCOMMA THEN
            GetTok
            NA(n) = ToInt(Expr)
        END IF
        Expect TRPAR
        Builtin = n
        EXIT FUNCTION
    END IF
    IF id = BVARPTR THEN
        Expect TLPAR
        a = Expr
        Expect TRPAR
        IF NOT IsLvalue(a) THEN ErrNo 89   ' VARPTR needs a variable
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
        IF nargs < 1 THEN ErrRec 90, 0, 0, nm$ ELSE a = ConvKeep(a, TYSTR)   ' {s}: an argument expected
        SELECT CASE id
        CASE BCVS: ty = TYSNG
        CASE BCVD, BVAL: ty = TYDBL
        CASE BUCASE, BLCASE, BLTRIM, BRTRIM, BTRIM: ty = TYSTR
        END SELECT
        IF id = BASC AND nargs = 2 THEN NN(a) = ConvKeep(NN(a), TYINT)
    CASE BMID, BLEFT, BRIGHT
        ty = TYSTR
        IF nargs < 2 THEN
            ErrRec 91, 0, 0, nm$   ' {s}: arguments expected
        ELSE
            a = ConvKeep(a, TYSTR)
            NN(a) = ConvKeep(NN(a), TYINT)
            IF nargs = 3 THEN NN(NN(a)) = ConvKeep(NN(NN(a)), TYINT)
        END IF
    CASE BFRE
        IF nargs <> 1 THEN ErrNo 92   ' FRE: one argument expected
    CASE BCHR, BSPACE, BHEX, BMKI, BEOF, BPEEK, BPEEKB, BOSVAR, BPOS, BLOF
        IF nargs <> 1 THEN ErrRec 93, 0, 0, nm$ ELSE a = ConvKeep(a, TYINT)   ' {s}: one argument expected
        IF id = BOSVAR AND NOp(a) <> NICON THEN ErrNo 94   ' OSVAR: a constant expected
        IF id = BCHR OR id = BSPACE OR id = BHEX OR id = BMKI THEN ty = TYSTR
    CASE BOSADDR
        IF nargs <> 1 THEN ErrRec 93, 0, 0, nm$   ' {s}: one argument expected
        IF NOp(a) <> NICON THEN ErrNo 95   ' OSADDR: a constant expected
    CASE BSTRING
        ty = TYSTR
        IF nargs <> 2 THEN
            ErrRec 96, 0, 0, nm$   ' {s}: two arguments expected
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
            ErrNo 97   ' INSTR: arguments expected
        ELSE
            a = ConvKeep(a, TYINT)
            NN(a) = ConvKeep(NN(a), TYSTR)
            NN(NN(a)) = ConvKeep(NN(NN(a)), TYSTR)
        END IF
    CASE BSTR
        ty = TYSTR
        IF nargs <> 1 THEN ErrNo 98 ELSE a = ConvKeep(a, t1)   ' STR$: one argument expected
    CASE BCINT
        IF nargs <> 1 THEN ErrRec 93, 0, 0, nm$   ' {s}: one argument expected
    CASE BFIX, BINT, BABS
        IF nargs <> 1 THEN ErrRec 93, 0, 0, nm$ ELSE a = ConvKeep(a, t1)   ' {s}: one argument expected
        ty = t1
    CASE BSGN
        IF nargs <> 1 THEN ErrRec 93, 0, 0, nm$ ELSE a = ConvKeep(a, t1)   ' {s}: one argument expected
    CASE BCSNG, BCDBL
        IF nargs <> 1 THEN ErrRec 93, 0, 0, nm$   ' {s}: one argument expected
        IF id = BCSNG THEN ty = TYSNG ELSE ty = TYDBL
        a = ConvNode(a, ty)
        Builtin = a
        EXIT FUNCTION
    CASE BSQR, BSIN, BCOS, BTAN, BATN, BEXP, BLOG
        IF nargs <> 1 THEN ErrRec 93, 0, 0, nm$   ' {s}: one argument expected
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
            ErrRec 96, 0, 0, nm$   ' {s}: two arguments expected
        ELSE
            a = ConvKeep(a, TYINT)
            NN(a) = ConvKeep(NN(a), TYINT)
        END IF
    CASE BSADD
        IF nargs <> 1 THEN ErrNo 99 ELSE a = ConvKeep(a, TYSTR)   ' SADD: one argument expected
    CASE BCSPI, BCSPS, BCSPD, BOSCALLI
        IF nargs < 1 THEN ErrRec 91, 0, 0, nm$   ' {s}: arguments expected
        IF NOp(a) <> NICON THEN ErrRec 100, 0, 0, nm$   ' {s}: a constant first
        IF id = BCSPS THEN ty = TYSNG
        IF id = BCSPD THEN ty = TYDBL
        x = NN(a)
        DO WHILE x > 0
            IF NIsBool(x) THEN ErrRec 101, 0, 0, nm$   ' {s}: a comparison as an argument
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
    IF k = 0 THEN ErrNo 102   ' an index expected
    IF SAux(s) > 0 AND SAux(s) <> k THEN ErrRec 103, 0, 0, SName$(s)   ' {s}: the wrong number of indexes
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
        ErrRec 91, 0, 0, SName$(s)   ' {s}: arguments expected
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
                                    Expect TRPAR
                                END IF
                                a = NewNode(NVAR, SType(s2))
                                NV(a) = s2
                                NX(a) = 1
                            END IF
                        END IF
                    END IF
                    IF a = 0 THEN ErrRec 104, k, 0, SName$(s)   ' an array expected as argument {a} of {s}
                END IF
            END IF
            IF a = 0 THEN a = Expr
            IF first = 0 THEN first = a ELSE NN(last) = a
            last = a
            IF Tok <> TCOMMA THEN EXIT DO
            GetTok
        LOOP
        IF paren THEN Expect TRPAR
    END IF
    IF k <> np AND check THEN ErrRec 67, np, 0, SName$(s)   ' {s}: {a} argument(s) expected
    ArgCount = k
    ArgList = first
END FUNCTION

FUNCTION VarNode (n$)
    DIM s, n
    s = LookupVar(n$, 1)
    IF SKind(s) = SKARRAY THEN ErrRec 29, 0, 0, SName$(s)   ' {s} is an array: an index expected
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
        Expect TRPAR
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
                    ErrRec 29, 0, 0, nm$   ' {s} is an array: an index expected
                    n = IConst(0)
                END IF
            ELSE
                n = VarNode(nm$)
            END IF
        ELSE
            s = FindProc(nm$)
            IF s > 0 THEN
                IF SKind(s) = SKSUB THEN ErrRec 105, 0, 0, nm$   ' {s} is a SUB, not a FUNCTION
                n = CallNode(s)
            ELSE
                id = BuiltinId(nm$)
                IF id > 0 THEN
                    n = Builtin(id, nm$)
                ELSEIF Tok = TLPAR THEN
                    ErrRec 106, 0, 0, nm$   ' {s}: no such array or function
                    n = ParseArgs
                    n = IConst(0)
                ELSE
                    n = VarNode(nm$)
                END IF
            END IF
        END IF
    CASE ELSE
        ErrRec 107, 0, Tok, ""   ' an expression expected, not {t}
        n = IConst(0)
        IF NOT AtEnd THEN GetTok
    END SELECT
    Primary = n
END FUNCTION

' ---- code: calls

SEGMENT EXPRGEN
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
