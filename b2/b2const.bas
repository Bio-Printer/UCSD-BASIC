' B2CONST -- pass 1b: the names (BC's lexer did this as it read)
'
' Reads B2LEX's tokens and writes them again for B2SYN, with what needs
' the module's names: the CONSTs are worked out here and their values
' written where their names come (B2SYN and the passes after never see a
' CONST); each DECLARE the module never uses is marked (TSKIP, written
' into the file with SEEK at the end); and the header's counts -- the
' names at the module's level and in its largest procedure, the
' parameters, the code, the longest statement and procedure -- are made,
' for the next passes' tables (docs/DESIGN.md section 3: the same as BC's).
' A pass of its own, so that its tables are not in memory when B2LEX opens
' an #INCLUDE file (the library's RTSELDOM, and two files open, is the
' lexer's peak); this pass opens nothing while it works.
#INCLUDE "B2COM"
#INCLUDE "B2REC"


' What the token file's header says (WHWORDS, BCCOM): the names declared or
' used at the module's level and the procedures' names (LxGlob), and, of
' each procedure (the module's body as one), the names in it (a name in
' the table NmHash remembers whether it was counted at the module's level,
' NmGlob, and the procedure it was last counted for, NmProc), the code's
' tokens and its
' strings' bytes, the keywords that make labels and jumps; the parameters
' of SUB, FUNCTION and DECLARE lines (and the most of one line), the tokens
' of the longest statement, the lines of the longest procedure (B2NAME's
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
' value is written (LxPut: TINT, TSNG, TDBL, TSTR), and B2NAME never sees a CONST.  Each
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
    PUT #CHOUT, , b
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


' (the end's: a segment of its own)
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
            SEEK #CHOUT, CdB(c) * 512# + CdO(c) + 1
            LxParams = LxParams - CdPar(c)
            PUT #CHOUT, , b
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
    PUT #CHOUT, , v
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
    IF LEN(s$) > 0 THEN PUT #CHOUT, , s$
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


' an error at the line being read (at a TLINE: the line before, which a
' CONST statement it ends was on -- ErrRec)
SUB LexErr (n, s$)
    ErrRec n, 0, 0, s$
END SUB

' a statement starts: the counts of the one before
SUB StmtStart ()
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
END SUB

' a keyword k of the statement (first: it starts it)
SUB ConstKw (k, first)
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
END SUB

' the tokens, B2LEX's, to the end (BC's lexer's LexTokens without the
' characters: first is 1 at a line's start, 2 after THEN and ELSE, 3
' after a colon)
SUB ConstPass ()
    DIM first, k
    first = 1
    DO
        NextRec
        k = Rk
        IF k = TEOF THEN EXIT DO
        IF (k = TLINE OR k = TFILE) AND LxCMode <> 0 THEN
            ' (a line ends a CONST statement)
            LxConstOne
            LxCMode = 0
        END IF
        IF k = TLINE THEN
            first = 1
            TB TLINE
            TW RW1
            TS RS$
            IF LxProc THEN LxLines = LxLines + 1 ELSE LxBodyLines = LxBodyLines + 1
        ELSEIF k = TFILE THEN
            TB TFILE
            TS RS$
        ELSE
            IF first <> 0 THEN StmtStart
            SELECT CASE k
            CASE TLABEL
                ' a line number or a label
                LxHashes RS$
                IF NmFind(LxHash, LxH2) > 0 THEN
                    IF NmProc(NmFind(LxHash, LxH2)) < 0 THEN LexErr 24, RS$   ' {s} declared twice
                END IF
                TB TLABEL
                TS RS$
                LxName RS$, 2
                first = 1
            CASE TIDENT
                LxIdent RS$, first
                first = 0
            CASE TINT
                TB TINT
                TW RW1
                first = 0
            CASE TSNG, TDBL
                TB k
                TS RS$
                first = 0
            CASE TSTR
                TB TSTR
                TS RS$
                LxStrBytes LEN(RS$)
                first = 0
            CASE KDATA
                ' (the rest of the line, a TSTR, as it is)
                ConstKw k, first
                first = 0
            CASE 1 TO 99
                ConstKw k, first
                first = 0
                IF k = KTHEN OR k = KELSE THEN first = 2
            CASE TLPAR
                TB TLPAR
                LxParen = LxParen + 1
                first = 0
            CASE TRPAR
                TB TRPAR
                LxParen = LxParen - 1
                first = 0
            CASE TCOMMA
                IF LxCMode <> 0 AND LxParen = 0 THEN
                    ' (the next CONST of the statement)
                    LxConstOne
                    LxWant = 1
                ELSE
                    TB TCOMMA
                END IF
                first = 0
            CASE TCOLON
                ' (a CONST statement ends)
                IF LxCMode THEN
                    LxConstOne
                    LxCMode = 0
                ELSE
                    TB TCOLON
                END IF
                first = 3
            CASE ELSE
                TB k
                first = 0
            END SELECT
        END IF
    LOOP
    IF LxCMode THEN
        LxConstOne
        LxCMode = 0
    END IF
END SUB

' ---- B2CONST, the program: pass 1b of the job's compile step, then B2SYN

DIM i
ReadJob
StepNames
ErrCount = 0
InName$ = PassFile$(0)
OutName$ = PassFile$(1)
InOpen InName$
' (the names' table: B2LEX counted the module's names, at most so many)
NmCap = Capped(InHead(THGLOB) + 16, 2000)
REDIM NmHash(NmCap), NmH2(NmCap), NmGlob(NmCap) AS BYTE, NmProc(NmCap), NmNext(NmCap), NmUse(NmCap) AS BYTE
CdCap = Capped(InHead(THPARAMS) + 8, 1000)
REDIM CdNm(CdCap), CdBsH(CdCap), CdH2(CdCap), CdB(CdCap) AS BYTE, CdO(CdCap), CdPar(CdCap)
CnCap = Capped(InHead(THCONSTS) + 8, 1000)
REDIM CnTy(CnCap) AS BYTE, CnVal(CnCap), CnTxt$(CnCap)
IF OptMem THEN SayLn "  [names " + IStr$(NmCap) + ", DECLAREs " + IStr$(CdCap) + ", CONSTs " + IStr$(CnCap) + "]"
IF FileExists(OutName$) THEN KILL OutName$
OPEN OutName$ FOR BINARY AS #CHOUT
LxPB = 0
LxPO = 0
FOR i = 1 TO WHWORDS
    TW 0
NEXT i
MemNote "tables"
ConstPass
ProcMark 0
IF LxStmtTok > LxMaxStmt THEN LxMaxStmt = LxStmtTok
IF LxHdrPar > LxMaxPar THEN LxMaxPar = LxHdrPar
IF LxCdDecl > 0 THEN CdPar(LxCdDecl) = LxHdrPar
TB TEOF
LxUnused
' (the module's body: one more procedure)
IF 3 * LxBodyCode + LxBodyStrB > LxMaxCode THEN LxMaxCode = 3 * LxBodyCode + LxBodyStrB
IF LxBodyCtl > LxMaxCtl THEN LxMaxCtl = LxBodyCtl
IF LxBodyLines > LxMaxLines THEN LxMaxLines = LxBodyLines
SEEK #CHOUT, 1
TW TOKMAGIC
TW LxGlob
TW LxMaxLoc
TW LxParams
' (the CONSTs are this pass's: none for the passes after)
TW 0
TW LxMaxCode
TW LxMaxCtl
TW LxMaxStmt
TW LxMaxPar
TW LxMaxLines
CLOSE #CHOUT
CLOSE #CHIN
IF OptMem THEN SayLn "  [names " + IStr$(NNm) + ", CONSTs " + IStr$(NCn) + "]"
ERASE NmHash, NmH2, NmGlob, NmProc, NmNext, NmUse, CdNm, CdBsH, CdH2, CdB, CdO, CdPar, CnTy, CnVal, CnTxt$
IF ErrCount > 0 THEN CompileFailed
IF OptKeep = 0 THEN KILL InName$
IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words (B2CONST)"
ChainTo "B2SYN", ""
