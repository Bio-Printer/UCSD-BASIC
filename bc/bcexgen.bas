' BCEXGEN -- pass 3: an expression's code (BCEXPR parses it into a tree of
' nodes; its code is made here, from the tree)
#INCLUDE "BCBUILT"
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"

' ---- nodes

SEGMENT EXPRGEN
FUNCTION NodeWords (n)
    NodeWords = TypeWords(NTy(n))
END FUNCTION

' ---- real constants

' the P-machine's 4-byte real of a double: [exp+128][sign|m22..m16][m15..m8][m7..m0]
FUNCTION RealImage$ (d!)
    DIM b$, b3, b4, b5, b6, b7, e, m1, m2, m3, sg
    IF d! = 0 THEN
        RealImage$ = STRING$(4, 0)
        EXIT FUNCTION
    END IF
    b$ = MKD$(d!)
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
        ErrNo 88   ' real constant too large
        e = 255
    END IF
    IF e < 1 THEN
        RealImage$ = STRING$(4, 0)
        EXIT FUNCTION
    END IF
    RealImage$ = CHR$(e) + CHR$(sg OR m1) + CHR$(m2) + CHR$(m3)
END FUNCTION

SUB GenRConst (n)
    DIM d!, b$, i
    d! = VAL(NS$(n))
    IF NX(n) THEN d! = -d!
    OB OLDC
    IF NTy(n) = TYDBL THEN
        b$ = MKD$(d!)
        OB 4
        IF PC AND 1 THEN OB 0
        FOR i = 3 TO 0 STEP -1
            OB ASC(b$, 2 * i + 1)
            OB ASC(b$, 2 * i + 2)
        NEXT i
    ELSE
        b$ = RealImage$(d!)
        OB 2
        IF PC AND 1 THEN OB 0
        OB ASC(b$, 3)
        OB ASC(b$, 4)
        OB ASC(b$, 1)
        OB ASC(b$, 2)
    END IF
END SUB

' ---- code: values

SEGMENT
FUNCTION IsLvalue (n)
    IF NOp(n) = NVAR THEN
        IsLvalue = SKind(NV(n)) = SKVAR
    ELSEIF NOp(n) = NELEM THEN
        IsLvalue = -1
    END IF
END FUNCTION

SEGMENT EXPRGEN
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

SEGMENT
' the type a variable or element is stored as (TYBYTE stays)
FUNCTION StoreType (n)
    StoreType = SType(NV(n))
END FUNCTION

SEGMENT EXPRGEN
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
        IF f = TYINT THEN OB OFLT ELSE EmitCsp 107
    ELSEIF t = TYDBL THEN
        IF f = TYINT THEN EmitCsp 108 ELSE EmitCsp 106
    ELSE
        IF f = TYSNG THEN EmitCsp 24 ELSE CallRt "_DCINT"
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
        EmitCsp 105
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
        EmitCsp 123
    CASE TPLUS
        IF ty = TYSTR THEN
            CallRt "_SCAT"
            TempUsed = 1
        ELSEIF ty = TYINT THEN
            OB OADI
        ELSEIF ty = TYSNG THEN
            OB OADR
        ELSE
            EmitCsp 100
        END IF
    CASE TMINUS
        IF ty = TYINT THEN OB OSBI ELSE IF ty = TYSNG THEN OB OSBR ELSE EmitCsp 101
    CASE TMUL
        IF ty = TYINT THEN OB OMPI ELSE IF ty = TYSNG THEN OB OMPR ELSE EmitCsp 102
    CASE TDIV
        IF ty = TYSNG THEN OB ODVR ELSE EmitCsp 103
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
            EmitCsp NV(a)
        END IF
        EXIT SUB
    CASE BOSVAR
        OB OLOD
        OB 2
        OBig NV(a)
        EXIT SUB
    CASE BOSADDR
        OB &HB2
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
        IF t1 = TYSNG THEN CallRt "_INTS" ELSE IF t1 = TYDBL THEN EmitCsp 124
    CASE BABS
        IF t1 = TYINT THEN
            OB OABI
        ELSEIF t1 = TYSNG THEN
            OB OABR
        ELSE
            EmitCsp 126
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
        IF t1 = TYDBL THEN EmitCsp 112 ELSE EmitCsp 31
    CASE BSIN
        IF t1 = TYDBL THEN EmitCsp 113 ELSE EmitCsp 25
    CASE BCOS
        IF t1 = TYDBL THEN EmitCsp 114 ELSE EmitCsp 26
    CASE BTAN
        IF t1 = TYDBL THEN EmitCsp 115 ELSE CallRt "_TANS"
    CASE BATN
        IF t1 = TYDBL THEN EmitCsp 118 ELSE EmitCsp 28
    CASE BEXP
        IF t1 = TYDBL THEN EmitCsp 120 ELSE EmitCsp 30
    CASE BLOG
        IF t1 = TYDBL THEN EmitCsp 121 ELSE EmitCsp 29
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
            EmitCsp 104
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
        ErrNo 27   ' type mismatch: a string as a condition
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
        EmitCsp 108
        Ldc 1
        EmitCsp 105
        Jump OFJP, falselab
    END IF
END SUB

' ---- code: calls

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
                    IF SType(NV(a)) <> pt THEN ErrRec 109, i, 0, SName$(s)   ' argument {a} of {s}: an array of another type
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
