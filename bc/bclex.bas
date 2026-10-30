' BCLEX -- pass 1: the source (and its #INCLUDE files) into tokens
'
' Comments (' and REM) are dropped.  Each source line with tokens starts
' with TLINE: its number and its text (for messages and the listing);
' TFILE names the file the lines come from.  A line ending in " _" goes
' on in the next one.  Numbers are converted here: TINT holds the value,
' TSNG and TDBL the text of a real (digits, ".", "E", exponent).
#INCLUDE "BCCOM"

DIM SHARED LxDepth, LxLine$, LxPos, LxLen, LxLineNo, LxFile$

' What the token file's header says (THWORDS, BCCOM): the names declared or
' used at the module's level and the procedures' names (LxGlob), and, of
' each procedure (the module's body as one), the names in it (a name in
' the table NmHash remembers whether it was counted at the module's level,
' NmGlob, and the procedure it was last counted for, NmProc), the code's
' tokens and its
' strings' bytes, the keywords that make labels and jumps; the parameters
' of SUB, FUNCTION and DECLARE lines (and the most of one line), the tokens
' of the longest statement, the lines of the longest procedure (BCGEN's
' line table: LxLines).  LxProc is the procedure being read (0: none),
' LxLead the keyword the statement starts with, LxParen its ( depth.
' A name is known by its hash (LxHash: 15 bits, its suffix too) and a second hash of its
' base name (LxH2: its length, each character times its place, mod 27011), not its text,
' which took more memory than Z80 mode has (NmHash, NmH2).
DIM SHARED NmHash(), NmGlob() AS BYTE, NmProc(), NmNext(), NmHead(127), NNm, NmCap
' What the module never uses: each name's uses (NmUse, 2 at most), and each module-level
' DECLAREd procedure (a candidate: CdNm its name, CdBsH and CdH2 its base name's hashes, CdB
' (a byte) and CdO where its DECLARE is in the token file, block and byte, CdPar its
' parameters); at the end one whose name with any suffix (DEFINT's X is X%: the hashes follow
' from CdBsH, LxMix) has no other use is marked there, TSKIP, and not counted (LxUnused).
' LxPB, LxPO: where the next byte goes; LxWant: a CONST's (1) or DECLARE's (2) name comes
' next; LxLastNm: LxName's name
DIM SHARED NmUse() AS BYTE, NmH2(), CdNm(), CdBsH(), CdH2(), CdB() AS BYTE, CdO(), CdPar(), NCd, CdCap
' The CONSTs are the lexer's: a CONST statement is read into CBk (the tokens), CBv (a name's
' index, an integer's value), CBs$ (a name's or real's or string's text), not written
' (LxCMode), and its values worked out; where a CONST's name comes after, its
' value is written (LxPut: TINT, TSNG, TDBL, TSTR), and BCGEN never sees a CONST.  Each
' NAME = value is one at its comma or the statement's end (LxConstOne).  A CONST
' is CnTy (TYINT, TYSNG, TYDBL, TYSTR), CnVal (an integer's value) or CnTxt$ (a real's or
' string's text); its name's NmProc is minus its number.  Its name means only that: an
' error where it is declared again (24) or assigned (30), after GOTO, GOSUB, RESTORE,
' RESUME, RETURN (a label: LxNoLab, 30), and where it is used before its CONST (119).
' LxRaw: TB writes no token, LxPrevK the last token
DIM SHARED CnTy() AS BYTE, CnVal(), CnTxt$(), NCn, CnCap
DIM SHARED CBk(127) AS BYTE, CBv(127), CBs$(127), NCB, CBp, CErr, LxCMode
DIM SHARED LxRaw, LxNoLab, LxPrevK, LxH2
DIM SHARED LxPB, LxPO, LxWant, LxDB, LxDO, LxCdDecl, LxLastNm, LxHash, LxBsHash
DIM SHARED LxProc, LxNProc, LxProcName, LxLead, LxParen, LxStmtTok, LxDecl
DIM SHARED LxGlob, LxParams, LxLoc, LxCode, LxStrB, LxCtl, LxHdrPar, LxMaxPar
DIM SHARED LxMaxLoc, LxMaxCode, LxMaxCtl, LxMaxStmt, LxBodyCode, LxBodyStrB, LxBodyCtl
DIM SHARED LxLines, LxMaxLines, LxBodyLines

' n more bytes in the token file
SUB LxAdv (n)
    LxPO = LxPO + n
    DO WHILE LxPO >= 512
        LxPO = LxPO - 512
        LxPB = LxPB + 1
    LOOP
END SUB

' a token (or, LxRaw, a string's length); a CONST statement's: kept in CBk
SUB TB (v)
    DIM b AS BYTE
    IF LxRaw = 0 THEN
        LxPrevK = v
        IF LxCMode THEN
            IF NCB < 126 THEN NCB = NCB + 1 ELSE CErr = 1
            CBk(NCB) = v
            CBv(NCB) = 0
            EXIT SUB
        END IF
    END IF
    b = v
    PUT #CHTOK, , b
    LxAdv 1
    LxStmtTok = LxStmtTok + 1
    IF LxDecl = 0 THEN
        IF LxProc THEN LxCode = LxCode + 1 ELSE LxBodyCode = LxBodyCode + 1
    END IF
END SUB

' a string constant's bytes (they are in the code)
SUB LxStrBytes (n)
    IF LxCMode THEN EXIT SUB
    IF LxProc THEN LxStrB = LxStrB + n ELSE LxBodyStrB = LxBodyStrB + n
END SUB

' the hash h with the character c after it
FUNCTION LxMix (h, c)
    LxMix = (((h AND &HFFF) * 8) + h \ 4096) XOR c
END FUNCTION

' w$'s hash (LxHash), and its base name's, without its suffix (LxBsHash, LxH2)
SUB LxHashes (w$)
    DIM h, h2, i, n
    n = LEN(w$)
    IF SuffixType(w$) > 0 THEN n = n - 1
    h2 = n
    FOR i = 1 TO n
        h = LxMix(h, ASC(w$, i))
        h2 = (h2 + ASC(w$, i) * ((i AND 31) + 1)) MOD 27011
    NEXT i
    LxBsHash = h
    LxH2 = h2
    IF n < LEN(w$) THEN h = LxMix(h, ASC(w$, LEN(w$)))
    LxHash = h
END SUB

' the name whose hashes are h and h2 (0: none)
FUNCTION NmFind (h, h2)
    DIM i
    i = NmHead(h AND 127)
    DO WHILE i > 0
        IF NmHash(i) = h AND NmH2(i) = h2 THEN EXIT DO
        i = NmNext(i)
    LOOP
    NmFind = i
END FUNCTION

' the name LxHashes found (made if it is new)
FUNCTION NmAt ()
    DIM h, i
    i = NmFind(LxHash, LxH2)
    IF i = 0 THEN
        IF NNm >= NmCap THEN
            ' (256 more: fewer holes the old tables leave)
            NmCap = NmCap + 256
            REDIM PRESERVE NmHash(NmCap), NmH2(NmCap), NmGlob(NmCap) AS BYTE, NmProc(NmCap), NmNext(NmCap)
            REDIM PRESERVE NmUse(NmCap) AS BYTE
        END IF
        h = LxHash AND 127
        NNm = NNm + 1
        i = NNm
        NmHash(i) = LxHash
        NmH2(i) = LxH2
        NmGlob(i) = 0
        NmUse(i) = 0
        NmProc(i) = 0
        NmNext(i) = NmHead(h)
        NmHead(h) = i
    END IF
    NmAt = i
END FUNCTION

' a name (or label: twice, as pass 2 and pass 3 each make a symbol for it)
' counted once at the module's level, once in each procedure
SUB LxName (w$, times)
    DIM i
    LxHashes w$
    i = NmAt
    LxLastNm = i
    IF NmUse(i) < 2 THEN NmUse(i) = NmUse(i) + 1
    IF LxLead = KDECLARE AND LxParen > 0 THEN
        ' (a DECLARE's parameter: no symbol is made for it)
    ELSEIF LxProc = 0 OR LxProcName THEN
        ' the module's level, or the procedure's own name
        LxProcName = 0
        IF NmGlob(i) = 0 THEN
            NmGlob(i) = 1
            LxGlob = LxGlob + times
        END IF
    ELSEIF NmProc(i) <> LxProc AND NmGlob(i) = 0 THEN
        ' (a name of the module's level, already counted, makes no symbol here)
        NmProc(i) = LxProc
        LxLoc = LxLoc + times
    END IF
    IF LxParen > 0 THEN
        IF LxLead = KSUB OR LxLead = KFUNCTION OR LxLead = KDECLARE OR LxLead = KPRIVATE THEN
            LxParams = LxParams + 1
            LxHdrPar = LxHdrPar + 1
        END IF
    END IF
END SUB

' the name just read (LxLastNm, its base name's hashes LxBsHash, LxH2) is a DECLARE's, its
' mark goes at block b, byte o
SUB LxCand (b, o)
    ' (CdB is a byte: none past the token file's first 128K)
    IF b > 255 THEN EXIT SUB
    IF NCd >= CdCap THEN
        CdCap = CdCap + 128
        REDIM PRESERVE CdNm(CdCap), CdBsH(CdCap), CdH2(CdCap), CdB(CdCap) AS BYTE, CdO(CdCap), CdPar(CdCap)
    END IF
    NCd = NCd + 1
    CdNm(NCd) = LxLastNm
    CdBsH(NCd) = LxBsHash
    CdH2(NCd) = LxH2
    CdB(NCd) = b
    CdO(NCd) = o
    CdPar(NCd) = 0
    LxCdDecl = NCd
END SUB

' the CONST c's value written where its name is
SUB LxPut (c)
    SELECT CASE CnTy(c)
    CASE TYINT
        TB TINT
        TW CnVal(c)
        ' (counted as the name's two bytes were)
        IF LxCMode = 0 THEN
            LxStmtTok = LxStmtTok + 1
            IF LxDecl = 0 THEN
                IF LxProc THEN LxCode = LxCode + 1 ELSE LxBodyCode = LxBodyCode + 1
            END IF
        END IF
    CASE TYSTR
        TB TSTR
        TS CnTxt$(c)
        LxStrBytes LEN(CnTxt$(c))
    CASE TYSNG
        TB TSNG
        TS CnTxt$(c)
    CASE ELSE
        TB TDBL
        TS CnTxt$(c)
    END SELECT
END SUB

' (the end's and the errors': a segment of their own, not in memory with the library's
' RTSELDOM when an #INCLUDE file is opened)
SEGMENT LXEND
' is the name with the base name's hashes h, h2 used twice in all, with any suffix
FUNCTION NmUsed (h, h2)
    DIM n, j, k
    FOR j = 0 TO 5
        IF j = 0 THEN k = NmFind(h, h2) ELSE k = NmFind(LxMix(h, ASC("%#!$~", j)), h2)
        IF k > 0 THEN n = n + NmUse(k)
    NEXT j
    NmUsed = n >= 2
END FUNCTION

' each candidate the module does not use (its name once only: where it is declared):
' marked in the token file (TSKIP), and not counted in the header
SUB LxUnused ()
    DIM c, b AS BYTE
    b = TSKIP
    FOR c = 1 TO NCd
        IF NOT NmUsed(CdBsH(c), CdH2(c)) THEN
            SEEK #CHTOK, CdB(c) * 512# + CdO(c) + 1
            LxParams = LxParams - CdPar(c)
            PUT #CHTOK, , b
            IF NmGlob(CdNm(c)) THEN LxGlob = LxGlob - 1
        END IF
    NEXT c
END SUB

SEGMENT
' a procedure's start (SUB or FUNCTION) or end (END SUB, END FUNCTION, or
' the end of the source): the most of each count so far
SUB ProcMark (start)
    IF LxProc THEN
        IF LxLoc > LxMaxLoc THEN LxMaxLoc = LxLoc
        IF 3 * LxCode + LxStrB > LxMaxCode THEN LxMaxCode = 3 * LxCode + LxStrB
        IF LxCtl > LxMaxCtl THEN LxMaxCtl = LxCtl
        IF LxLines > LxMaxLines THEN LxMaxLines = LxLines
    END IF
    LxProc = 0
    IF start THEN
        LxNProc = LxNProc + 1
        LxProc = LxNProc
        LxProcName = 1
        LxLoc = 0
        LxCode = 0
        LxStrB = 0
        LxCtl = 0
        LxLines = 0
    END IF
END SUB

SUB TW (v)
    IF LxCMode THEN
        CBv(NCB) = v
        EXIT SUB
    END IF
    PUT #CHTOK, , v
    LxAdv 2
END SUB

SUB TS (s$)
    IF LxCMode THEN
        CBs$(NCB) = s$
        EXIT SUB
    END IF
    LxRaw = 1
    TB LEN(s$)
    LxRaw = 0
    IF LEN(s$) > 0 THEN PUT #CHTOK, , s$
    LxAdv LEN(s$)
END SUB

' ---- a CONST statement (its tokens in CBk, CBv, CBs$; CBp the next): its values; but for
' NAME = integer, a segment of their own, LXCONST

SEGMENT LXCONST
' an integer expression: OR XOR, AND, NOT, + -, MOD, \, *, - (CErr: not one)
FUNCTION CExpr ()
    DIM v, k
    v = CAnd
    DO
        k = CBk(CBp)
        IF k <> KOR AND k <> KXOR THEN EXIT DO
        CBp = CBp + 1
        IF k = KOR THEN v = v OR CAnd ELSE v = v XOR CAnd
    LOOP
    CExpr = v
END FUNCTION

FUNCTION CAnd ()
    DIM v
    v = CNot
    DO WHILE CBk(CBp) = KAND
        CBp = CBp + 1
        v = v AND CNot
    LOOP
    CAnd = v
END FUNCTION

FUNCTION CNot ()
    IF CBk(CBp) = KNOT THEN
        CBp = CBp + 1
        CNot = NOT CNot
    ELSE
        CNot = CAdd
    END IF
END FUNCTION

FUNCTION CAdd ()
    DIM v, k
    v = CMod
    DO
        k = CBk(CBp)
        IF k <> TPLUS AND k <> TMINUS THEN EXIT DO
        CBp = CBp + 1
        IF k = TPLUS THEN v = v + CMod ELSE v = v - CMod
    LOOP
    CAdd = v
END FUNCTION

FUNCTION CMod ()
    DIM v, w
    v = CIdiv
    DO WHILE CBk(CBp) = KMOD
        CBp = CBp + 1
        w = CIdiv
        IF w = 0 THEN CErr = 1 ELSE v = v MOD w
    LOOP
    CMod = v
END FUNCTION

FUNCTION CIdiv ()
    DIM v, w
    v = CMul
    DO WHILE CBk(CBp) = TIDIV
        CBp = CBp + 1
        w = CMul
        IF w = 0 THEN CErr = 1 ELSE v = v \ w
    LOOP
    CIdiv = v
END FUNCTION

FUNCTION CMul ()
    DIM v
    v = CNeg
    DO WHILE CBk(CBp) = TMUL
        CBp = CBp + 1
        v = v * CNeg
    LOOP
    CMul = v
END FUNCTION

FUNCTION CNeg ()
    DIM k
    k = CBk(CBp)
    IF k = TMINUS THEN
        CBp = CBp + 1
        CNeg = -CNeg
    ELSEIF k = TPLUS THEN
        CBp = CBp + 1
        CNeg = CNeg
    ELSEIF k = TINT THEN
        CNeg = CBv(CBp)
        CBp = CBp + 1
    ELSEIF k = TLPAR THEN
        CBp = CBp + 1
        CNeg = CExpr
        IF CBk(CBp) = TRPAR THEN CBp = CBp + 1 ELSE CErr = 1
    ELSE
        CErr = 1
    END IF
END FUNCTION

' NAME = value: the CONST of the name i (nm$ its text)
SUB LxConstVal (i, nm$)
    DIM ty, st, v, t$, k, neg
    k = CBk(CBp)
    IF k = TMINUS THEN
        IF CBk(CBp + 1) = TSNG OR CBk(CBp + 1) = TDBL THEN
            neg = 1
            CBp = CBp + 1
            k = CBk(CBp)
        END IF
    END IF
    k = CBk(CBp)
    IF (k = TSNG OR k = TDBL OR k = TSTR) AND CBp = NCB THEN
        ' a real or a string: one (a real perhaps after -)
        t$ = CBs$(CBp)
        IF neg THEN
            IF LEFT$(t$, 1) = "-" THEN t$ = MID$(t$, 2) ELSE t$ = "-" + t$
        END IF
        IF k = TSNG THEN ty = TYSNG ELSE IF k = TDBL THEN ty = TYDBL ELSE ty = TYSTR
        CBp = CBp + 1
    ELSE
        CErr = 0
        v = CExpr
        IF CErr OR CBp <= NCB THEN
            LexErr 108, ""   ' a constant expression expected
            EXIT SUB
        END IF
        ty = TYINT
    END IF
    ' its name's suffix: the type (an integer as a real's text)
    st = SuffixType(nm$)
    IF st > 0 AND st <> ty THEN
        IF ty = TYINT AND (st = TYSNG OR st = TYDBL) THEN
            t$ = LTRIM$(STR$(v))
        ELSEIF ty = TYSTR OR st = TYSTR OR st = TYINT OR st = TYBYTE THEN
            LexErr 85, ""   ' type mismatch
            EXIT SUB
        END IF
        ty = st
    END IF
    LxConstSet i, ty, v, t$
END SUB

SEGMENT
' the name i is the CONST ty, v, t$ (CnTy, CnVal, CnTxt$)
SUB LxConstSet (i, ty, v, t$)
    IF NCn >= CnCap THEN
        CnCap = CnCap + 128
        REDIM PRESERVE CnTy(CnCap) AS BYTE, CnVal(CnCap), CnTxt$(CnCap)
    END IF
    NCn = NCn + 1
    CnTy(NCn) = ty
    CnVal(NCn) = v
    CnTxt$(NCn) = t$
    NmProc(i) = -NCn
END SUB

' one NAME = value of a CONST statement (at its comma or its end): that CONST
SUB LxConstOne ()
    DIM i
    CBk(NCB + 1) = 0
    CBp = 1
    IF CErr THEN
        LexErr 108, ""   ' a constant expression expected
    ELSEIF CBk(1) <> TIDENT OR CBv(1) = 0 THEN
        LexErr 62, ""   ' a constant name expected
    ELSEIF CBk(2) <> TEQ THEN
        LexErr 108, ""   ' a constant expression expected
    ELSEIF NCB = 3 AND CBk(3) = TINT AND (SuffixType(CBs$(1)) = 0 OR SuffixType(CBs$(1)) = TYINT) THEN
        ' (NAME = integer: most of them)
        LxConstSet CBv(1), TYINT, CBv(3), ""
    ELSE
        CBp = 3
        LxConstVal CBv(1), CBs$(1)
    END IF
    FOR i = 1 TO NCB
        CBs$(i) = ""
    NEXT i
    NCB = 0
    CErr = 0
END SUB

' error n of the line being read (s$: its {s})
SEGMENT LXEND
SUB LexErr (n, s$)
    TokFile$ = LxFile$
    TokLine = LxLineNo
    TokText$ = LxLine$
    ErrRec n, 0, 0, s$
END SUB

SEGMENT

FUNCTION IsLetter (c)
    IsLetter = (c >= 65 AND c <= 90) OR (c >= 97 AND c <= 122) OR c = 95
END FUNCTION

FUNCTION IsDigit (c)
    IsDigit = c >= 48 AND c <= 57
END FUNCTION

FUNCTION LxC ()
    LxC = ASC(LxLine$, LxPos)
END FUNCTION

' where the comment starts (' or a REM statement), LEN + 1 for none
FUNCTION CommentAt (l$)
    DIM p, n, c, q, st
    n = LEN(l$)
    p = 1
    st = 1
    DO WHILE p <= n
        c = ASC(l$, p)
        IF c = 34 THEN
            q = INSTR(p + 1, l$, CHR$(34))
            IF q = 0 THEN EXIT DO
            p = q + 1
            st = 0
        ELSEIF c = 39 THEN
            CommentAt = p
            EXIT FUNCTION
        ELSEIF c = 58 THEN
            st = 1
            p = p + 1
        ELSEIF c = 32 OR c = 9 OR (st = 1 AND IsDigit(c)) THEN
            p = p + 1
        ELSEIF st = 1 AND UCASE$(MID$(l$, p, 3)) = "REM" AND NOT IsLetter(ASC(l$, p + 3)) AND NOT IsDigit(ASC(l$, p + 3)) THEN
            CommentAt = p
            EXIT FUNCTION
        ELSE
            st = 0
            p = p + 1
        END IF
    LOOP
    CommentAt = n + 1
END FUNCTION

' a number: an integer (TINT) or the text of a real (TSNG, TDBL)
SUB LexNumber ()
    DIM s, digits$, ty, c, v, d, big, nsig, i, suf
    s = LxPos
    ty = 0
    DO WHILE IsDigit(LxC)
        LxPos = LxPos + 1
    LOOP
    IF LxC = 46 THEN
        ty = TYSNG
        LxPos = LxPos + 1
        DO WHILE IsDigit(LxC)
            LxPos = LxPos + 1
        LOOP
    END IF
    digits$ = MID$(LxLine$, s, LxPos - s)
    c = LxC
    IF c = 69 OR c = 101 OR c = 68 OR c = 100 THEN
        d = ASC(LxLine$, LxPos + 1)
        IF IsDigit(d) OR ((d = 43 OR d = 45) AND IsDigit(ASC(LxLine$, LxPos + 2))) THEN
            IF c = 68 OR c = 100 THEN ty = TYDBL ELSE IF ty = 0 THEN ty = TYSNG
            digits$ = digits$ + "E"
            LxPos = LxPos + 1
            IF d = 43 OR d = 45 THEN
                digits$ = digits$ + CHR$(d)
                LxPos = LxPos + 1
            END IF
            s = LxPos
            DO WHILE IsDigit(LxC)
                LxPos = LxPos + 1
            LOOP
            digits$ = digits$ + MID$(LxLine$, s, LxPos - s)
        END IF
    END IF
    ' a suffix: ! DOUBLE, # SINGLE (kept SINGLE, however many digits), % INTEGER
    c = LxC
    suf = 0
    IF c = 33 THEN
        ty = TYDBL
        LxPos = LxPos + 1
    ELSEIF c = 35 THEN
        ty = TYSNG
        suf = 1
        LxPos = LxPos + 1
    ELSEIF c = 37 THEN
        IF ty <> 0 THEN LexErr 2, ""   ' an integer with a decimal point
        ty = TYINT
        LxPos = LxPos + 1
    END IF
    IF ty = 0 OR ty = TYINT THEN
        ' an integer, if it fits (32768 is taken as -32768: for -32768)
        v = 0
        big = 0
        FOR i = 1 TO LEN(digits$)
            d = ASC(digits$, i) - 48
            IF v > 3276 OR (v = 3276 AND d > 8) THEN big = 1
            IF big = 0 THEN
                IF v = 3276 AND d = 8 THEN v = -32768 ELSE v = v * 10 + d
            END IF
        NEXT i
        IF big = 0 THEN
            TB TINT
            TW v
            EXIT SUB
        END IF
        IF ty = TYINT THEN LexErr 3, ""   ' integer too large
        ty = TYSNG
    END IF
    ' more than 7 significant digits: a DOUBLE
    IF ty = TYSNG AND suf = 0 THEN
        nsig = 0
        FOR i = 1 TO LEN(digits$)
            c = ASC(digits$, i)
            IF c = 69 THEN EXIT FOR
            IF IsDigit(c) AND (nsig > 0 OR c <> 48) THEN nsig = nsig + 1
        NEXT i
        IF nsig > 7 THEN ty = TYDBL
    END IF
    IF ty = TYDBL THEN TB TDBL ELSE TB TSNG
    TS digits$
END SUB

' &H, &O, &B numbers: 16 bits
' &H, &O, &B and a digit of that base next: a number (else & is the
' operator: a&b, a & h)
FUNCTION RadixAhead ()
    DIM r, d
    r = INSTR("HhOoBb", CHR$(ASC(LxLine$, LxPos + 1)))
    IF r = 0 OR ASC(LxLine$, LxPos + 1) = 0 THEN EXIT FUNCTION
    d = ASC(LxLine$, LxPos + 2)
    IF r <= 2 THEN
        RadixAhead = IsDigit(d) OR (d >= 65 AND d <= 70) OR (d >= 97 AND d <= 102)
    ELSEIF r <= 4 THEN
        RadixAhead = d >= 48 AND d <= 55
    ELSE
        RadixAhead = d = 48 OR d = 49
    END IF
END FUNCTION

SUB LexRadix ()
    DIM base, c, v, d, n
    c = ASC(LxLine$, LxPos + 1)
    IF c = 72 OR c = 104 THEN
        base = 16
    ELSEIF c = 79 OR c = 111 THEN
        base = 8
    ELSE
        base = 2
    END IF
    LxPos = LxPos + 2
    DO
        c = LxC
        IF IsDigit(c) THEN
            d = c - 48
        ELSEIF c >= 65 AND c <= 70 THEN
            d = c - 55
        ELSEIF c >= 97 AND c <= 102 THEN
            d = c - 87
        ELSE
            EXIT DO
        END IF
        IF d >= base THEN EXIT DO
        ' v * base + d in 16 bits, without overflow
        IF base = 16 THEN
            v = ((v AND &HFFF) * 16) OR d
        ELSEIF base = 8 THEN
            v = ((v AND &H1FFF) * 8) OR d
        ELSE
            v = ((v AND &H3FFF) * 2) OR d
        END IF
        n = n + 1
        LxPos = LxPos + 1
    LOOP
    IF n = 0 THEN LexErr 4, ""   ' a number expected after &
    IF LxC = 37 THEN LxPos = LxPos + 1
    TB TINT
    TW v
END SUB

' a name (first: at a statement's start): a CONST's value (LxPut), or TIDENT and the name
SUB LxIdent (w$, first)
    DIM pb, po, i, c, decl
    LxHashes w$
    i = NmFind(LxHash, LxH2)
    IF i > 0 THEN
        IF NmProc(i) < 0 THEN c = -NmProc(i)
    END IF
    IF LxCMode AND LxWant = 1 THEN
        ' a CONST's name: its name only
        IF c > 0 THEN
            LexErr 24, w$   ' {s} declared twice
        ELSEIF i > 0 THEN
            IF NmUse(i) > 0 THEN LexErr 119, w$   ' {s} is used before its CONST
        END IF
        IF i = 0 THEN i = NmAt
        TB TIDENT
        TS w$
        CBv(NCB) = i
        LxWant = 0
        EXIT SUB
    END IF
    IF c > 0 THEN
        ' a CONST's name: its value; its name means nothing else
        SELECT CASE LxLead
        CASE KSUB, KFUNCTION, KPRIVATE, KDECLARE
            decl = 1
        CASE KDIM, KREDIM, KSTATIC, KSHARED, KCOMMON
            IF LxParen = 0 THEN decl = 1
        END SELECT
        IF decl THEN
            LexErr 24, w$   ' {s} declared twice
        ELSEIF first <> 0 OR LxNoLab <> 0 THEN
            LexErr 30, w$   ' {s} is a constant
        ELSE
            SELECT CASE LxPrevK
            CASE KLET, KFOR, KNEXT, KREAD, KINPUT, KSWAP, KCALL, KERASE
                LexErr 30, w$   ' {s} is a constant
            END SELECT
        END IF
        LxPut c
        EXIT SUB
    END IF
    pb = LxPB
    po = LxPO
    TB TIDENT
    TS w$
    IF LxCMode = 0 THEN LxName w$, 1
    IF LxWant = 2 THEN LxCand LxDB, LxDO
    LxWant = 0
END SUB

' the tokens of one line (comments already cut off)
SUB LexTokens ()
    DIM c, s, w$, k, d, first, q, i
    first = 1
    DO
        DO WHILE LxPos <= LxLen
            c = LxC
            IF c <> 32 AND c <> 9 THEN EXIT DO
            LxPos = LxPos + 1
        LOOP
        IF LxPos > LxLen THEN EXIT DO
        c = LxC
        IF first <> 0 THEN
            ' a statement starts
            IF LxStmtTok > LxMaxStmt THEN LxMaxStmt = LxStmtTok
            IF LxHdrPar > LxMaxPar THEN LxMaxPar = LxHdrPar
            IF LxCdDecl > 0 THEN CdPar(LxCdDecl) = LxHdrPar
            LxCdDecl = 0
            LxWant = 0
            LxStmtTok = 0
            LxHdrPar = 0
            LxLead = 0
            LxParen = 0
            LxDecl = 0
            LxNoLab = 0
        END IF
        IF first = 1 AND IsDigit(c) THEN
            ' a line number
            s = LxPos
            DO WHILE IsDigit(LxC)
                LxPos = LxPos + 1
            LOOP
            w$ = MID$(LxLine$, s, LxPos - s)
            DO WHILE LEN(w$) > 1 AND ASC(w$, 1) = 48
                w$ = MID$(w$, 2)
            LOOP
            TB TLABEL
            TS w$
            LxName w$, 2
            first = 1
        ELSEIF IsLetter(c) THEN
            s = LxPos
            DO
                LxPos = LxPos + 1
                c = LxC
            LOOP WHILE IsLetter(c) OR IsDigit(c)
            w$ = UCASE$(MID$(LxLine$, s, LxPos - s))
            ' a keyword followed by $ % ! ~ is a name (STRING$, INPUT$); a #
            ' after one is a file's number (PRINT#1)
            IF c = 36 OR c = 37 OR c = 33 OR c = 126 THEN k = 0 ELSE k = KwCode(w$)
            IF k = 0 THEN
                ' its type suffix: % INTEGER, # SINGLE, ! DOUBLE, $ STRING, ~ BYTE
                IF c = 37 OR c = 33 OR c = 35 OR c = 36 OR c = 126 THEN
                    w$ = w$ + CHR$(c)
                    LxPos = LxPos + 1
                END IF
                ' NAME: at the start of a statement is a label
                IF first = 1 AND LxC = 58 AND SuffixType(w$) = 0 THEN
                    LxPos = LxPos + 1
                    LxHashes w$
                    i = NmFind(LxHash, LxH2)
                    IF i > 0 THEN
                        IF NmProc(i) < 0 THEN LexErr 24, w$   ' {s} declared twice
                    END IF
                    TB TLABEL
                    TS w$
                    LxName w$, 2
                    first = 1
                ELSE
                    LxIdent w$, first
                    first = 0
                END IF
            ELSEIF k = KDATA THEN
                ' DATA: the rest of the line as it is
                TB k
                TB TSTR
                TS LTRIM$(MID$(LxLine$, LxPos))
                LxStrBytes LxLen - LxPos + 1
                LxPos = LxLen + 1
            ELSE
                IF k = KSUB OR k = KFUNCTION THEN
                    IF first <> 0 OR LxLead = KPRIVATE THEN ProcMark 1
                    IF first = 0 AND LxLead = KEND THEN ProcMark 0
                END IF
                IF first <> 0 THEN
                    LxLead = k
                    IF k = KCONST THEN
                        ' (its tokens kept, not written: LxConstOne)
                        LxCMode = 1
                        NCB = 0
                        LxWant = 1
                    END IF
                    IF LxProc = 0 AND k = KDECLARE THEN
                        LxWant = 2
                        LxDB = LxPB
                        LxDO = LxPO
                    END IF
                    SELECT CASE k
                    CASE KDECLARE, KCOMMON, KDEFINT, KDEFSNG, KDEFDBL, KDEFSTR, KOPTION, KSEGMENT
                        LxDecl = 1
                    END SELECT
                END IF
                SELECT CASE k
                CASE KIF, KELSEIF, KELSE, KFOR, KNEXT, KDO, KLOOP, KWHILE, KWEND, KSELECT, KCASE, KEXIT, KGOTO, KGOSUB, KRETURN, KON, KAND, KOR, KUNTIL
                    IF LxProc THEN LxCtl = LxCtl + 1 ELSE LxBodyCtl = LxBodyCtl + 1
                END SELECT
                IF LxCMode = 0 OR k <> KCONST THEN TB k
                SELECT CASE k
                CASE KGOTO, KGOSUB, KRESTORE, KRESUME, KRETURN
                    LxNoLab = 1
                END SELECT
                first = 0
                IF k = KTHEN OR k = KELSE THEN first = 2
            END IF
        ELSEIF IsDigit(c) OR (c = 46 AND IsDigit(ASC(LxLine$, LxPos + 1))) THEN
            LexNumber
            first = 0
        ELSEIF c = 34 THEN
            q = INSTR(LxPos + 1, LxLine$, CHR$(34))
            IF q = 0 THEN q = LxLen + 1
            TB TSTR
            TS MID$(LxLine$, LxPos + 1, q - LxPos - 1)
            LxStrBytes q - LxPos - 1
            LxPos = q + 1
            first = 0
        ELSEIF c = 38 AND RadixAhead THEN
            LexRadix
            first = 0
        ELSE
            LxPos = LxPos + 1
            d = LxC
            SELECT CASE c
            CASE 61
                IF d = 60 THEN
                    TB TLE
                    LxPos = LxPos + 1
                ELSEIF d = 62 THEN
                    TB TGE
                    LxPos = LxPos + 1
                ELSE
                    TB TEQ
                END IF
            CASE 60
                IF d = 62 THEN
                    TB TNE
                    LxPos = LxPos + 1
                ELSEIF d = 61 THEN
                    TB TLE
                    LxPos = LxPos + 1
                ELSE
                    TB TLT
                END IF
            CASE 62
                IF d = 61 THEN
                    TB TGE
                    LxPos = LxPos + 1
                ELSEIF d = 60 THEN
                    TB TNE
                    LxPos = LxPos + 1
                ELSE
                    TB TGT
                END IF
            CASE 43: TB TPLUS
            CASE 45: TB TMINUS
            CASE 42: TB TMUL
            CASE 47: TB TDIV
            CASE 92: TB TIDIV
            CASE 94: TB TPOW
            CASE 40
                TB TLPAR
                LxParen = LxParen + 1
            CASE 41
                TB TRPAR
                LxParen = LxParen - 1
            CASE 44
                IF LxCMode <> 0 AND LxParen = 0 THEN
                    ' (the next CONST of the statement)
                    LxConstOne
                    LxWant = 1
                ELSE
                    TB TCOMMA
                END IF
            CASE 59: TB TSEMI
            CASE 35: TB THASH
            CASE 38: TB TAMP
            CASE 124: TB TBAR
            CASE 63: TB KPRINT
            CASE 58
                ' (a label is only at the start of a line; a CONST statement ends)
                IF LxCMode THEN
                    LxConstOne
                    LxCMode = 0
                ELSE
                    TB TCOLON
                END IF
                first = 3
            CASE ELSE
                LexErr 5, CHR$(c)   ' unexpected character {s}
            END SELECT
            IF c <> 58 THEN first = 0
        END IF
    LOOP
    IF LxCMode THEN
        LxConstOne
        LxCMode = 0
    END IF
END SUB

' one logical line
SUB LexLine (l$)
    DIM e, t$, q, f$
    e = CommentAt(l$)
    t$ = RTRIM$(LTRIM$(LEFT$(l$, e - 1)))
    IF t$ = "" THEN EXIT SUB
    IF UCASE$(LEFT$(t$, 8)) = "#INCLUDE" THEN
        q = INSTR(t$, CHR$(34))
        f$ = ""
        IF q > 0 THEN f$ = MID$(t$, q + 1, INSTR(q + 1, t$ + CHR$(34), CHR$(34)) - q - 1)
        IF f$ = "" THEN
            LexErr 6, ""   ' #INCLUDE "FILE" expected
        ELSE
            LexInclude f$
        END IF
        EXIT SUB
    END IF
    TB TLINE
    TW LxLineNo
    TS t$
    IF LxProc THEN LxLines = LxLines + 1 ELSE LxBodyLines = LxBodyLines + 1
    LxLine$ = t$
    LxPos = 1
    LxLen = LEN(t$)
    LexTokens
END SUB

' the lines of one file (#INCLUDE files nest: LexInclude)
SUB LexLines (f$, ch)
    DIM l$, more$, n
    OPEN f$ FOR INPUT AS #ch
    LxFile$ = f$
    TB TFILE
    TS f$
    LxLineNo = 0
    ' (MAXERR errors: no more -- ErrRec)
    DO WHILE NOT EOF(ch) AND ErrCount < MAXERR
        LINE INPUT #ch, l$
        LxLineNo = LxLineNo + 1
        ' a line ending in " _" goes on in the next one
        n = 0
        DO WHILE RIGHT$(RTRIM$(l$), 2) = " _" AND NOT EOF(ch)
            l$ = RTRIM$(l$)
            LINE INPUT #ch, more$
            n = n + 1
            l$ = LEFT$(l$, LEN(l$) - 1) + LTRIM$(more$)
        LOOP
        LxLine$ = l$
        LexLine l$
        LxLineNo = LxLineNo + n
    LOOP
    CLOSE #ch
END SUB

SUB LexInclude (f$)
    DIM saveline, savefile$, g$
    IF LxDepth >= 3 THEN
        LexErr 7, ""   ' #INCLUDE files nest too deep
        EXIT SUB
    END IF
    ' FILE.BAS or FILE.TEXT, beside the source first (its volume and
    ' sub-volume), then as named
    g$ = UCASE$(f$)
    IF INSTR(g$, ":") = 0 AND LEFT$(g$, 1) <> "/" THEN
        g$ = FindSource$(g$, DirOf$(SrcName$))
    ELSE
        g$ = FindSource$(g$, "")
    END IF
    IF NOT FileExists(g$) THEN
        LexErr 8, g$   ' no file {s}
        EXIT SUB
    END IF
    saveline = LxLineNo
    savefile$ = LxFile$
    LxDepth = LxDepth + 1
    LexLines g$, CHINC + LxDepth - 1
    LxDepth = LxDepth - 1
    LxLineNo = saveline
    LxFile$ = savefile$
    TB TFILE
    TS savefile$
END SUB

' the token file: its header (THWORDS words: room for it first, written
' at the end, when the counts are known), then the tokens
SUB LexFile (f$)
    DIM i
    IF FileExists(TokName$) THEN KILL TokName$
    OPEN TokName$ FOR BINARY AS #CHTOK
    LxPB = 0
    LxPO = 0
    FOR i = 1 TO THWORDS
        TW 0
    NEXT i
    NmCap = 256
    REDIM NmHash(NmCap), NmH2(NmCap), NmGlob(NmCap) AS BYTE, NmProc(NmCap), NmNext(NmCap), NmUse(NmCap) AS BYTE
    CdCap = 128
    REDIM CdNm(CdCap), CdBsH(CdCap), CdH2(CdCap), CdB(CdCap) AS BYTE, CdO(CdCap), CdPar(CdCap)
    ' (BC's modules have about 300 CONSTs: not grown while they are read)
    CnCap = 384
    REDIM CnTy(CnCap) AS BYTE, CnVal(CnCap), CnTxt$(CnCap)
    LxDepth = 0
    LexLines f$, CHSRC
    TB TEOF
    ProcMark 0
    IF LxStmtTok > LxMaxStmt THEN LxMaxStmt = LxStmtTok
    IF LxHdrPar > LxMaxPar THEN LxMaxPar = LxHdrPar
    IF LxCdDecl > 0 THEN CdPar(LxCdDecl) = LxHdrPar
    LxUnused
    ' (the module's body: one more procedure)
    IF 3 * LxBodyCode + LxBodyStrB > LxMaxCode THEN LxMaxCode = 3 * LxBodyCode + LxBodyStrB
    IF LxBodyCtl > LxMaxCtl THEN LxMaxCtl = LxBodyCtl
    IF LxBodyLines > LxMaxLines THEN LxMaxLines = LxBodyLines
    SEEK #CHTOK, 1
    TW TOKMAGIC
    TW LxGlob
    TW LxMaxLoc
    TW LxParams
    ' (the CONSTs are the lexer's: none for BCGEN)
    TW 0
    TW LxMaxCode
    TW LxMaxCtl
    TW LxMaxStmt
    TW LxMaxPar
    TW LxMaxLines
    CLOSE #CHTOK
    ERASE NmHash, NmH2, NmGlob, NmProc, NmNext, NmUse, CdNm, CdBsH, CdH2, CdB, CdO, CdPar, CnTy, CnVal, CnTxt$
END SUB

' ---- BCLEX, the program: pass 1 of the job's compile step, then BCGEN

ReadJob
StepNames
ErrCount = 0
IF NOT FileExists(SrcName$) THEN
    SayLn "BC: no file " + SrcName$
    PhaseDone 0
END IF
IF OptQuiet = 0 THEN SayLn "Compiling " + SrcName$
TokLine = 0
TokText$ = ""
MemNote "start"
LexFile SrcName$
MemNote "lexed"
IF ErrCount > 0 THEN CompileFailed
ChainTo "BCGEN", ""
