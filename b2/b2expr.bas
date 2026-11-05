' B2EXPR -- pass 5: the expressions (docs/B2DESIGN.md)
'
' Every expression B2SYN bracketed (RX how ... RXE) and every target (RLV
' what ... RLVE) is compiled here: parsed into a tree of nodes (BC's
' BCEXPR: typed as it is built, conversions are nodes, integer constants
' folded, a comparison a "boolean": 1 / 0 on the stack, -1 / 0 when used
' as a number), its code made (B2EXGEN), and written as RXC type flags
' value, the code, RXCE temps (RLVC ... RLVCE for a target).  Its
' operands are B2NAME's records (RVAR, RPROC, RBUILT): each becomes a
' symbol of the statement's own small table (OpSym), so no pass after
' B2NAME has a symbol table.  A condition jumps to LFALSE when it is false
' (B2CTL puts its statement's label in).  An assignment (RLV LVASSIGN and
' the RX XLVT after it) is all code here.  SELECT CASE's value goes into a
' temporary (RSEL in the CASEs' conditions); a string one is given back
' after END SELECT.  The rest is copied through.
#INCLUDE "B2BUILT"
#INCLUDE "B2COM"

' the targets' type (XLVT: the expressions after FOR's target too), an
' assignment's target waiting for its value; SELECT CASE's temporaries
DIM SHARED LvType, PendLv, SelS(MAXCTL), SelOff(MAXCTL), SelTy(MAXCTL), NSel

' ---- the records

SUB GetTok ()
    NextRec
END SUB

' the end of an expression (B2SYN made it one)
FUNCTION AtEnd ()
    AtEnd = Tok = RXE OR Tok = RLVE OR Tok = RSTMT OR Tok = TEOF
END FUNCTION

FUNCTION IsTok (t)
    IF Tok = t THEN
        GetTok
        IsTok = -1
    END IF
END FUNCTION

SUB Expect (t)
    IF Tok = t THEN
        GetTok
    ELSE
        ErrRec 1, t, Tok, ""   ' {k} expected, not {t}
    END IF
END SUB

' ---- the statement's symbols: its operands

FUNCTION OpNew ()
    IF NSym >= SymCap THEN
        ErrNo 84   ' expression too complex
        NSym = 0
    END IF
    NSym = NSym + 1
    SName$(NSym) = ""
    STx$(NSym) = ""
    SAux(NSym) = 0
    SAux2(NSym) = 0
    SFlags(NSym) = 0
    OpNew = NSym
END FUNCTION

' the operand just read (RVAR, RPROC): a symbol
FUNCTION OpSym ()
    DIM s, i
    s = OpNew
    IF Rk = RVAR THEN
        SKind(s) = RB1
        SType(s) = RB2
        SCls(s) = RB3
        SOff(s) = RW1
        SAux(s) = RW2
        SName$(s) = RS$
        STx$(s) = RS$
    ELSE
        SKind(s) = RB2
        SType(s) = RB1
        SName$(s) = RS$
        STx$(s) = RS2$
        IF NPar + RNP > ParCap THEN
            ErrNo 84   ' expression too complex
            NPar = 0
        END IF
        SAux(s) = NPar + 1
        SAux2(s) = RNP
        FOR i = 1 TO RNP
            PType(NPar + i) = RPT(i)
            PFlg(NPar + i) = RPF(i)
        NEXT i
        NPar = NPar + RNP
    END IF
    OpSym = s
END FUNCTION

' SELECT CASE's value: a symbol of the innermost one's temporary
FUNCTION SelSym ()
    DIM s
    s = OpNew
    SKind(s) = SKVAR
    IF NSel > 0 THEN
        SType(s) = SelTy(NSel)
        SOff(s) = SelOff(NSel)
    END IF
    SCls(s) = SCLOCAL
    SelSym = s
END FUNCTION

FUNCTION SymNode (s)
    DIM n
    n = NewNode(NVAR, SType(s))
    IF SType(s) = TYBYTE THEN NTy(n) = TYINT
    NV(n) = s
    SymNode = n
END FUNCTION

' the target of an assignment, INPUT, READ ...: a variable or an element
FUNCTION LValue ()
    DIM s
    IF Tok <> RVAR THEN
        ErrNo 28   ' a variable expected
        DO WHILE NOT AtEnd
            GetTok
        LOOP
        EXIT FUNCTION
    END IF
    s = OpSym
    GetTok
    IF SKind(s) = SKARRAY THEN
        IF Tok <> TLPAR THEN
            ErrRec 29, 0, 0, STx$(s)   ' {s} is an array: an index expected
            EXIT FUNCTION
        END IF
        LValue = ElemNode(s)
        EXIT FUNCTION
    END IF
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
        ELSEIF Tok = TANDALSO THEN
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
        ELSEIF Tok = TORELSE THEN
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

' an INTEGER or a BYTE (& and |: no other type)
FUNCTION IsIntNode (n)
    IsIntNode = NTy(n) = TYINT OR NTy(n) = TYBYTE
END FUNCTION

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

' ---- built-in functions (B2NAME found them: RBUILT)

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
        IF Tok <> RVAR THEN
            ErrNo 74   ' an array name expected
        ELSE
            a = OpSym
            IF SKind(a) <> SKARRAY THEN ErrRec 58, 0, 0, RS$   ' {s} is not an array
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
    IF SAux(s) > 0 AND SAux(s) <> k THEN ErrRec 103, 0, 0, STx$(s)   ' {s}: the wrong number of indexes
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
        ErrRec 91, 0, 0, STx$(s)   ' {s}: arguments expected
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
                    IF Tok = RVAR THEN
                        IF RB1 = SKARRAY THEN
                            s2 = OpSym
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
                    IF a = 0 THEN ErrRec 104, k, 0, STx$(s)   ' an array expected as argument {a} of {s}
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
    IF k <> np AND check THEN ErrRec 67, np, 0, STx$(s)   ' {s}: {a} argument(s) expected
    ArgCount = k
    ArgList = first
END FUNCTION

FUNCTION VarNode (s)
    DIM n
    IF SKind(s) = SKARRAY THEN ErrRec 29, 0, 0, STx$(s)   ' {s} is an array: an index expected
    n = NewNode(NVAR, SType(s))
    IF SType(s) = TYBYTE THEN NTy(n) = TYINT
    NV(n) = s
    VarNode = n
END FUNCTION

FUNCTION Primary ()
    DIM n, s, nm$
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
    CASE RSEL
        ' SELECT CASE's value
        GetTok
        n = SymNode(SelSym)
    CASE RVAR
        s = OpSym
        GetTok
        IF SKind(s) = SKARRAY THEN
            IF Tok = TLPAR THEN
                n = ElemNode(s)
            ELSE
                ErrRec 29, 0, 0, STx$(s)   ' {s} is an array: an index expected
                n = IConst(0)
            END IF
        ELSE
            n = VarNode(s)
        END IF
    CASE RPROC
        s = OpSym
        GetTok
        n = CallNode(s)
    CASE RBUILT
        s = RB1
        nm$ = RS$
        GetTok
        n = Builtin(s, nm$)
    CASE ELSE
        ErrRec 107, 0, Tok, ""   ' an expression expected, not {t}
        n = IConst(0)
        IF NOT AtEnd THEN GetTok
    END SELECT
    Primary = n
END FUNCTION
' ---- the pass

SUB ResetStmt ()
    DIM i
    ResetNodes
    FOR i = 1 TO NSym
        SName$(i) = ""
        STx$(i) = ""
    NEXT i
    NSym = 0
    NPar = 0
END SUB

' a constant's flags (XFICON its value: RW1), for RXC
FUNCTION ConstFlags (n)
    DIM f
    IF NOp(n) = NICON THEN
        f = XFICON
    ELSEIF NOp(n) = NRCON THEN
        f = XFRCON
        IF NX(n) THEN f = f OR XFNEG
    END IF
    ConstFlags = f
END FUNCTION

' RXC type flags value
SUB XHead (ty, n)
    WRec RXC
    WB ty
    IF n > 0 THEN
        WB ConstFlags(n)
        IF NOp(n) = NICON THEN WW NV(n) ELSE WW 0
    ELSE
        WB 0
        WW 0
    END IF
END SUB

' ... RXCE temps
SUB XTail (k)
    WRec k
    IF TempUsed THEN WB XFTEMP ELSE WB 0
    TempUsed = 0
END SUB

' a SUB called: name args / name(args) / CALL name(args)
FUNCTION CallStmtNode ()
    DIM s, n, a, k, last, x
    IF Tok <> RPROC THEN
        DO WHILE NOT AtEnd
            GetTok
        LOOP
        CallStmtNode = IConst(0)
        EXIT FUNCTION
    END IF
    s = OpSym
    GetTok
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
        IF ArgCount <> SAux2(s) THEN ErrRec 67, SAux2(s), 0, STx$(s)   ' {s}: {a} argument(s) expected
    ELSE
        a = ArgList(s, 0, 1)
    END IF
    NA(n) = a
    CallStmtNode = n
END FUNCTION

' RX how ... RXE (RX read): its code
SUB ExprRegion (how)
    DIM e, ty, s
    IF PendLv = 0 THEN ResetStmt
    TempUsed = 0
    GetTok
    SELECT CASE how
    CASE XCALL
        e = CallStmtNode
        XHead TYVOID, 0
        IF NOp(e) = NCALL THEN GenCall e, 0
    CASE XCOND, XNCOND
        e = Expr
        IF how = XNCOND THEN e = NotCond(e)
        XHead TYINT, 0
        GenCond e, LFALSE
    CASE XLVT
        e = Expr
        ty = LvType
        IF ty = TYBYTE THEN ty = TYINT
        IF PendLv THEN
            XHead ty, 0
            Assign PendLv, e
            PendLv = 0
        ELSE
            e = ConvNode(e, ty)
            XHead ty, e
            GenValue e
        END IF
    CASE XSEL
        e = Expr
        ty = NTy(e)
        IF NIsBool(e) THEN ty = TYINT
        s = TempFor(ty)
        IF NSel < MAXCTL THEN NSel = NSel + 1
        SelOff(NSel) = SOff(s)
        SelTy(NSel) = ty
        XHead ty, 0
        Assign SymNode(s), e
    CASE XCHAN
        e = ToInt(Expr)
        XHead TYINT, e
        IF NOp(e) <> NICON THEN GenValue e
    CASE XPUT
        e = Expr
        ty = NTy(e)
        IF NIsBool(e) THEN ty = TYINT
        IF IsLvalue(e) THEN ty = StoreType(e)
        IF ty = TYSTR THEN
            XHead TYSTR, 0
            GenValue e
        ELSE
            WRec RXC
            WB ty
            WB XFADDR
            WW 0
            IF IsLvalue(e) THEN
                GenAddr e
            ELSE
                s = TempFor(ty)
                Assign SymNode(s), e
                Lla SOff(s)
            END IF
        END IF
    CASE XRAW
        e = Expr
        ty = NTy(e)
        IF NIsBool(e) THEN ty = TYINT
        XHead ty, e
        GenValue e
    CASE XANY
        e = Expr
        ty = NTy(e)
        IF NIsBool(e) THEN ty = TYINT
        e = ConvNode(e, ty)
        XHead ty, e
        GenValue e
    CASE ELSE
        e = ConvNode(Expr, how)
        XHead how, e
        GenValue e
    END SELECT
    IF Tok <> RXE THEN
        ErrRec 26, 0, Tok, ""   ' the end of the statement expected, not {t}
        DO WHILE NOT AtEnd
            GetTok
        LOOP
    END IF
    XTail RXCE
END SUB

' RLV what ... RLVE (RLV read): the target's code
SUB LvRegion (what)
    DIM lv, ty
    ResetStmt
    PendLv = 0
    TempUsed = 0
    GetTok
    lv = LValue
    IF lv > 0 THEN
        ty = StoreType(lv)
        LvType = ty
        SELECT CASE what
        CASE LVASSIGN
            PendLv = lv
        CASE LVPS
            WRec RLVC
            WB ty
            WB 0
            StorePre lv
            WRec RLVS
            GenStore lv
            XTail RLVCE
        CASE LVGET
            IF ty = TYSTR THEN
                WRec RLVC
                WB ty
                WB 0
                StorePre lv
                WRec RLVL
                GenLoad lv
                WRec RLVS
                GenStore lv
            ELSE
                WRec RLVC
                WB ty
                WB XFADDR
                GenAddr lv
            END IF
            XTail RLVCE
        CASE LVADDR
            WRec RLVC
            WB ty
            WB XFADDR
            GenAddr lv
            XTail RLVCE
        END SELECT
    END IF
    DO WHILE Tok <> RLVE AND NOT AtEnd
        GetTok
    LOOP
END SUB

SUB ExprPass ()
    DO
        NextRec
        SELECT CASE Rk
        CASE TEOF
            EXIT DO
        CASE RX
            ExprRegion RB1
        CASE RLV
            LvRegion RB1
        CASE RSTMT
            PendLv = 0
            PutRec
            IF RB1 = SENDSEL AND NSel > 0 THEN
                ' a string's temporary given back after END SELECT
                IF SelTy(NSel) = TYSTR THEN
                    XHead TYVOID, 0
                    Lla SelOff(NSel)
                    CallRt "_SFREE"
                    XTail RXCE
                END IF
                NSel = NSel - 1
            END IF
        CASE ELSE
            PutRec
        END SELECT
    LOOP
END SUB

' ---- B2EXPR, the program: pass 5 of the job's compile step, then B2CTL

ReadJob
StepNames
ErrCount = 0
InOpen PassFile$(4)
' (one statement's: its nodes, its operands, their procedures' parameters)
NodeCap = Capped(InHead(THSTMT) \ 2 + 16, MAXNODE)
SymCap = Capped(InHead(THSTMT) + 16, MAXSYM)
ParCap = Capped(InHead(THSTMT) + 32, MAXPAR)
REDIM NOp(NodeCap) AS BYTE, NTy(NodeCap) AS BYTE, NA(NodeCap), NB(NodeCap)
REDIM NV(NodeCap), NX(NodeCap), NN(NodeCap), NS$(NodeCap), NIsBool(NodeCap) AS BYTE
REDIM SName$(SymCap), STx$(SymCap), SKind(SymCap) AS BYTE, SType(SymCap) AS BYTE, SCls(SymCap) AS BYTE
REDIM SOff(SymCap), SFlags(SymCap) AS BYTE, SAux(SymCap), SAux2(SymCap)
REDIM PType(ParCap) AS BYTE, PFlg(ParCap) AS BYTE
OutOpen PassFile$(5)
MemNote "tables"
ExprPass
CLOSE #CHIN
OutClose 5
IF OptMem THEN SayLn "  [nodes " + IStr$(NodeCap) + ", most " + IStr$(HiNode) + "]"
IF ErrCount > 0 THEN CompileFailed
IF OptKeep = 0 THEN KILL PassFile$(4)
IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words (B2EXPR)"
ChainTo "B2CTL", ""
