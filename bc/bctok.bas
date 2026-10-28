' BCTOK -- the token file (written by BCLEX, read by passes 2 and 3) and
' the symbol table: BCGEN's
#INCLUDE "BCCOM"

' ---- the token file

' (its header: THWORDS words, BCLEX's counts, into TokHead(THxxx))
SUB OpenTok ()
    DIM i
    REDIM TokHead(THWORDS)
    OPEN TokName$ FOR BINARY AS #CHTOK
    FOR i = 0 TO THWORDS - 1
        GET #CHTOK, , TokHead(i)
    NEXT i
    TokLine = 0
    TokText$ = ""
    TokFile$ = SrcName$
    GetTok
END SUB

FUNCTION TokStr$ ()
    DIM n AS BYTE, s$
    GET #CHTOK, , n
    IF n > 0 THEN
        s$ = SPACE$(n)
        GET #CHTOK, , s$
    END IF
    TokStr$ = s$
END FUNCTION

SUB GetTok ()
    DIM b AS BYTE, v
    TokNewLine = 0
    ' (MAXERR errors: the end, for the passes to end -- ErrRec)
    IF ErrCount >= MAXERR THEN
        Tok = TEOF
        EXIT SUB
    END IF
    DO
        GET #CHTOK, , b
        Tok = b
        SELECT CASE Tok
        CASE TIDENT, TSTR, TSNG, TDBL, TLABEL
            TokS$ = TokStr$
            EXIT SUB
        CASE TINT
            GET #CHTOK, , v
            TokV = v
            EXIT SUB
        CASE TLINE
            GET #CHTOK, , v
            PrevLine = TokLine
            PrevText$ = TokText$
            PrevFile$ = LineFile$
            LineFile$ = TokFile$
            TokLine = v
            TokText$ = TokStr$
            TokNewLine = 1
            EXIT SUB
        CASE TFILE
            TokFile$ = TokStr$
        CASE 0
            Tok = TEOF
            EXIT SUB
        CASE ELSE
            EXIT SUB
        END SELECT
    LOOP
END SUB

' the end of a statement: a colon, a new line or the end
FUNCTION AtEnd ()
    AtEnd = Tok = TCOLON OR Tok = TLINE OR Tok = TEOF OR Tok = KELSE
END FUNCTION

SUB SkipStmt ()
    DO WHILE Tok <> TCOLON AND Tok <> TLINE AND Tok <> TEOF
        GetTok
    LOOP
END SUB

FUNCTION IsTok (t)
    IF Tok = t THEN
        GetTok
        IsTok = -1
    END IF
END FUNCTION

' the token t next (else error 1: "t expected, not ...")
SUB Expect (t)
    IF Tok = t THEN
        GetTok
    ELSE
        ErrRec 1, t, Tok, ""
    END IF
END SUB

' ---- the symbol table

SUB InitSyms ()
    DIM i
    NSym = 0
    NPar = 0
    NSegName = 1
    SegName$(1) = ""
    CurSeg = 1
    FOR i = 0 TO HSIZE - 1
        HashHead(i) = 0
    NEXT i
    FOR i = 0 TO 25
        DefType(i) = TYSNG
    NEXT i
    StaticWords = 0
END SUB

FUNCTION HashName (n$)
    DIM h, i
    FOR i = 1 TO LEN(n$)
        h = (h * 5 + ASC(n$, i)) AND 4095
    NEXT i
    HashName = h MOD HSIZE
END FUNCTION

' the type of a name: its suffix, or the DEFtype of its first letter
FUNCTION NameType (n$)
    DIM t, c, i
    t = SuffixType(n$)
    IF t = 0 THEN
        ' the first letter (after the _ of the library's names)
        i = 1
        DO WHILE ASC(n$, i) = 95
            i = i + 1
        LOOP
        c = ASC(n$, i)
        IF c >= 65 AND c <= 90 THEN t = DefType(c - 65) ELSE t = TYSNG
    END IF
    NameType = t
END FUNCTION

' the newest symbol of exactly this name, 0 if none
FUNCTION FindSym (n$)
    DIM i
    i = HashHead(HashName(n$))
    DO WHILE i > 0
        IF SName$(i) = n$ THEN
            FindSym = i
            EXIT FUNCTION
        END IF
        i = SNext(i)
    LOOP
END FUNCTION

' a procedure: by its name as written, or a name declared AS type without
' its suffix (FUNCTION F AS STRING called as F$)
FUNCTION FindProc (n$)
    DIM i, t
    i = FindSym(n$)
    IF i = 0 THEN
        t = SuffixType(n$)
        IF t THEN
            i = FindSym(BaseName$(n$))
            IF i > 0 THEN
                IF SType(i) <> t OR (SFlags(i) AND SFAS) = 0 THEN i = 0
            END IF
        END IF
    END IF
    IF i > 0 THEN
        IF SKind(i) <> SKSUB AND SKind(i) <> SKFUNC THEN i = 0
    END IF
    FindProc = i
END FUNCTION

FUNCTION AddSym (n$, kind, ty)
    DIM h
    IF NSym >= SymCap THEN
        IF SymCap >= MAXSYM THEN FatalRec 9, ""   ' too many names
        SymCap = Grown(SymCap, MAXSYM)
        REDIM PRESERVE SName$(SymCap), SKind(SymCap) AS BYTE, SType(SymCap) AS BYTE, SCls(SymCap) AS BYTE
        REDIM PRESERVE SOff(SymCap), SFlags(SymCap) AS BYTE, SScope(SymCap) AS BYTE, SNext(SymCap)
        REDIM PRESERVE SAux(SymCap), SAux2(SymCap), SSeg(SymCap) AS BYTE
    END IF
    NSym = NSym + 1
    SName$(NSym) = n$
    SKind(NSym) = kind
    SType(NSym) = ty
    SCls(NSym) = 0
    SOff(NSym) = 0
    SFlags(NSym) = 0
    SScope(NSym) = 0
    SAux(NSym) = 0
    SAux2(NSym) = 0
    SSeg(NSym) = 0
    h = HashName(n$)
    SNext(NSym) = HashHead(h)
    HashHead(h) = NSym
    AddSym = NSym
END FUNCTION

' forget the symbols after keep (the newest: each is the head of its chain)
SUB PopSyms (keep)
    DIM i, h
    FOR i = NSym TO keep + 1 STEP -1
        h = HashName(SName$(i))
        HashHead(h) = SNext(i)
        SName$(i) = ""
    NEXT i
    NSym = keep
END SUB

FUNCTION SegIndex (n$)
    DIM i
    FOR i = 1 TO NSegName
        IF SegName$(i) = n$ THEN
            SegIndex = i
            EXIT FUNCTION
        END IF
    NEXT i
    IF NSegName >= MAXSEG THEN
        ErrNo 10   ' too many segments
        SegIndex = 1
        EXIT FUNCTION
    END IF
    NSegName = NSegName + 1
    SegName$(NSegName) = n$
    SegIndex = NSegName
END FUNCTION

' AS type: the type after AS (the token after it is current)
FUNCTION ParseType ()
    SELECT CASE Tok
    CASE KINTEGER: ParseType = TYINT
    CASE KSINGLE, KREAL: ParseType = TYSNG
    CASE KDOUBLE: ParseType = TYDBL
    CASE KSTRING: ParseType = TYSTR
    CASE KBYTE: ParseType = TYBYTE
    CASE ELSE
        ErrNo 11   ' a type expected (INTEGER, SINGLE, DOUBLE, STRING, BYTE)
        ParseType = TYINT
        EXIT FUNCTION
    END SELECT
    GetTok
END FUNCTION
