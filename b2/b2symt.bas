' B2SYMT -- the symbol table (B2DECL and B2NAME): BC's, the names as
' strings.  B2DECL writes the module's symbols to :B2TEMP.SYM (SymSave),
' B2NAME reads them (SymLoad) and adds each procedure's own.  Also the
' token reader of the two passes (GetTok: B2IO's records, TFILE skipped)
' and what reads a declaration (DeclType, ParseParams, DefLetters).
#INCLUDE "B2COM"
#INCLUDE "B2REC"
#INCLUDE "B2SYM"

' ---- the token reader

SUB GetTok ()
    DO
        NextRec
        IF Rk <> TFILE THEN EXIT DO
    LOOP
END SUB

' the end of a statement: the next one, a line, a label, the end
FUNCTION AtEnd ()
    AtEnd = Tok = RSTMT OR Tok = TLINE OR Tok = TEOF OR Tok = TLABEL OR Tok = CEND
END FUNCTION

SUB SkipStmt ()
    DO WHILE NOT AtEnd
        GetTok
    LOOP
END SUB

SUB Expect (t)
    IF Tok = t THEN
        GetTok
    ELSE
        ErrRec 1, t, Tok, ""   ' {k} expected, not {t}
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
    DO WHILE NSL > 0
        IF SLx(NSL) <= keep THEN EXIT DO
        NSL = NSL - 1
    LOOP
END SUB

' the symbol tables made as large as the counts say (the module's and
' one procedure's names; the parameters: all of them, one line's again)
SUB SymTables (nsym, npar)
    SymCap = Capped(nsym, MAXSYM)
    ParCap = Capped(npar, MAXPAR)
    REDIM SName$(SymCap), SKind(SymCap) AS BYTE, SType(SymCap) AS BYTE, SCls(SymCap) AS BYTE
    REDIM SOff(SymCap), SFlags(SymCap) AS BYTE, SScope(SymCap) AS BYTE, SNext(SymCap)
    REDIM SAux(SymCap), SAux2(SymCap), SSeg(SymCap) AS BYTE, HashHead(HSIZE)
    REDIM PType(ParCap) AS BYTE, PFlg(ParCap) AS BYTE
    SLCap = 16
    PLCap = 16
    REDIM SLx(SLCap), SLv(SLCap), PLx(PLCap), PLv(PLCap)
    NSL = 0
    NPL = 0
    REDIM SegName$(MAXSEG), DefType(25), ParName$(30), ParFlags(30)
END SUB

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

' ---- declarations

' DEFINT A-C, X ... (the token after the keyword is current)
SUB DefLetters (ty)
    DIM a, b
    DO
        IF Tok <> TIDENT THEN
            ErrNo 12   ' a letter expected
            EXIT SUB
        END IF
        a = ASC(TokS$, 1) - 65
        b = a
        GetTok
        IF Tok = TMINUS THEN
            GetTok
            IF Tok = TIDENT THEN b = ASC(TokS$, 1) - 65
            GetTok
        END IF
        IF a >= 0 AND b <= 25 AND a <= b THEN
            FOR a = a TO b
                DefType(a) = ty
            NEXT a
        END IF
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

FUNCTION DefKw (k)
    SELECT CASE k
    CASE KDEFINT: DefKw = TYINT
    CASE KDEFSNG: DefKw = TYSNG
    CASE KDEFDBL: DefKw = TYDBL
    CASE KDEFSTR: DefKw = TYSTR
    END SELECT
END FUNCTION

SUB ResetDefs ()
    DIM i
    FOR i = 0 TO 25
        DefType(i) = TYSNG
    NEXT i
END SUB

' a declared name and its type: "N" with SFAS for AS type (and for a name
' with no suffix), else N with its suffix.  Returns the type; the name is
' left in DeclName$, the flags in DeclFlags.
FUNCTION DeclType (n$, isproc)
    DIM ty
    DeclName$ = n$
    DeclFlags = 0
    DeclLen = 0
    ty = NameType(n$)
    IF Tok = KAS THEN
        GetTok
        IF SuffixType(n$) THEN ErrNo 13   ' a name with a type suffix declared AS a type
        ty = ParseType
        DeclFlags = SFAS
    ELSEIF SuffixType(n$) = 0 THEN
        IF isproc THEN
            DeclFlags = SFAS
        ELSE
            DeclName$ = n$ + TypeChar$(ty)
        END IF
    END IF
    ' a string's LENGTH n: its characters at most (n a number)
    IF Tok = TIDENT AND isproc = 0 THEN
        IF TokS$ = "LENGTH" THEN
            GetTok
            IF ty <> TYSTR THEN ErrNo 125   ' LENGTH: a string's only
            IF Tok <> TINT THEN
                ErrNo 126   ' LENGTH: a number from 1 to 32000 expected
            ELSEIF TokV < 1 OR TokV > 32000 THEN
                ErrNo 126   ' LENGTH: a number from 1 to 32000 expected
            ELSE
                IF ty = TYSTR THEN DeclLen = TokV
                GetTok
            END IF
        END IF
    END IF
    DeclType = ty
END FUNCTION

' the parameter list of a SUB or FUNCTION (the "(" is current or absent):
' the types go into PType/PFlg from NPar + 1, the names into ParName$.
' Returns the number of parameters.
FUNCTION ParseParams ()
    DIM n, fl, ty, nm$
    IF Tok <> TLPAR THEN EXIT FUNCTION
    GetTok
    IF Tok = TRPAR THEN
        GetTok
        EXIT FUNCTION
    END IF
    DO
        fl = 0
        IF Tok = KBYREF THEN
            fl = PFBYREF
            GetTok
        ELSEIF Tok = KBYVAL THEN
            GetTok
        END IF
        IF Tok <> TIDENT THEN
            ErrNo 14   ' a parameter name expected
            EXIT DO
        END IF
        nm$ = TokS$
        GetTok
        IF Tok = TLPAR THEN
            GetTok
            Expect TRPAR
            fl = PFARRAY
        END IF
        ty = DeclType(nm$, 0)
        n = n + 1
        IF NPar + n > ParCap THEN
            IF ParCap >= MAXPAR THEN FatalRec 15, ""   ' too many parameters
            ParCap = Grown(ParCap, MAXPAR)
            REDIM PRESERVE PType(ParCap) AS BYTE, PFlg(ParCap) AS BYTE
        END IF
        PType(NPar + n) = ty
        PFlg(NPar + n) = fl
        SetParLen NPar + n, DeclLen
        IF n <= 30 THEN
            ParName$(n) = DeclName$
            ParFlags(n) = DeclFlags
        END IF
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
    Expect TRPAR
    IF n > 30 THEN ErrNo 16   ' more than 30 parameters
    ParseParams = n
END FUNCTION

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

' the linker's name of a symbol (the library's names as they are)
FUNCTION LinkName$ (s)
    DIM n$
    IF s = 0 THEN EXIT FUNCTION
    n$ = SName$(s)
    IF (SFlags(s) AND SFRUNTIME) <> 0 OR ASC(n$, 1) = 95 THEN
        LinkName$ = BaseName$(n$)
        EXIT FUNCTION
    END IF
    IF SKind(s) = SKSUB THEN
        n$ = BaseName$(n$)
    ELSE
        n$ = BaseName$(n$) + TypeChar$(SType(s))
    END IF
    IF SFlags(s) AND SFPRIVATE THEN n$ = ModName$ + "'" + n$
    LinkName$ = n$
END FUNCTION

' ---- the symbol file (B2DECL writes it, B2NAME reads it)

SUB SymPutS (s$)
    DIM n AS BYTE
    n = LEN(s$)
    PUT #CHSYM, , n
    IF n > 0 THEN PUT #CHSYM, , s$
END SUB

SUB SymPutB (v)
    DIM b AS BYTE
    b = v AND 255
    PUT #CHSYM, , b
END SUB

FUNCTION SymGetB ()
    DIM b AS BYTE
    GET #CHSYM, , b
    SymGetB = b
END FUNCTION

FUNCTION SymGetS$ ()
    DIM n AS BYTE, s$
    GET #CHSYM, , n
    IF n > 0 THEN
        s$ = SPACE$(n)
        GET #CHSYM, , s$
    END IF
    SymGetS$ = s$
END FUNCTION

SUB SymSave ()
    DIM i
    IF FileExists(SymName$) THEN KILL SymName$
    OPEN SymName$ FOR BINARY AS #CHSYM
    PUT #CHSYM, , NSym
    PUT #CHSYM, , NPar
    PUT #CHSYM, , NSegName
    PUT #CHSYM, , StaticWords
    PUT #CHSYM, , NData
    PUT #CHSYM, , OptExplicit
    FOR i = 1 TO NSym
        SymPutS SName$(i)
        SymPutB SKind(i)
        SymPutB SType(i)
        SymPutB SCls(i)
        SymPutB SFlags(i)
        SymPutB SSeg(i)
        PUT #CHSYM, , SOff(i)
        PUT #CHSYM, , SAux(i)
        PUT #CHSYM, , SAux2(i)
    NEXT i
    FOR i = 1 TO NPar
        SymPutB PType(i)
        SymPutB PFlg(i)
    NEXT i
    FOR i = 2 TO NSegName
        SymPutS SegName$(i)
    NEXT i
    ' (the LENGTHs: symbols', parameters')
    PUT #CHSYM, , NSL
    FOR i = 1 TO NSL
        PUT #CHSYM, , SLx(i)
        PUT #CHSYM, , SLv(i)
    NEXT i
    PUT #CHSYM, , NPL
    FOR i = 1 TO NPL
        PUT #CHSYM, , PLx(i)
        PUT #CHSYM, , PLv(i)
    NEXT i
    CLOSE #CHSYM
END SUB

' (extra: room for the procedures' own names; xpar: parameters)
SUB SymLoad (extra, xpar)
    DIM i, n, np, ns, h, sw, nd, oe
    OPEN SymName$ FOR BINARY AS #CHSYM
    GET #CHSYM, , n
    GET #CHSYM, , np
    GET #CHSYM, , ns
    GET #CHSYM, , sw
    GET #CHSYM, , nd
    GET #CHSYM, , oe
    SymTables n + extra, np + xpar
    InitSyms
    StaticWords = sw
    NData = nd
    OptExplicit = oe
    FOR i = 1 TO n
        h = AddSym(SymGetS$, SymGetB, 0)
        SType(h) = SymGetB
        SCls(h) = SymGetB
        SFlags(h) = SymGetB
        SSeg(h) = SymGetB
        GET #CHSYM, , SOff(h)
        GET #CHSYM, , SAux(h)
        GET #CHSYM, , SAux2(h)
    NEXT i
    NPar = np
    FOR i = 1 TO np
        PType(i) = SymGetB
        PFlg(i) = SymGetB
    NEXT i
    NSegName = ns
    FOR i = 2 TO ns
        SegName$(i) = SymGetS$
    NEXT i
    GET #CHSYM, , n
    FOR i = 1 TO n
        GET #CHSYM, , h
        GET #CHSYM, , np
        SetSymLen h, np
    NEXT i
    GET #CHSYM, , n
    FOR i = 1 TO n
        GET #CHSYM, , h
        GET #CHSYM, , np
        SetParLen h, np
    NEXT i
    CLOSE #CHSYM
    NModSym = NSym
END SUB

' ---- the LENGTHs (few symbols and parameters have one: a list)

FUNCTION SymLen (s)
    DIM i
    FOR i = NSL TO 1 STEP -1
        IF SLx(i) = s THEN
            SymLen = SLv(i)
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

' (the symbols are added in order: a new one's after all the others)
SUB SetSymLen (s, n)
    DIM i
    FOR i = NSL TO 1 STEP -1
        IF SLx(i) = s THEN
            SLv(i) = n
            EXIT SUB
        END IF
    NEXT i
    IF n = 0 THEN EXIT SUB
    IF NSL >= SLCap THEN
        SLCap = SLCap + 16
        REDIM PRESERVE SLx(SLCap), SLv(SLCap)
    END IF
    NSL = NSL + 1
    SLx(NSL) = s
    SLv(NSL) = n
END SUB

FUNCTION ParLen (p)
    DIM i
    FOR i = NPL TO 1 STEP -1
        IF PLx(i) = p THEN
            ParLen = PLv(i)
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

SUB SetParLen (p, n)
    DIM i
    FOR i = NPL TO 1 STEP -1
        IF PLx(i) = p THEN
            PLv(i) = n
            EXIT SUB
        END IF
    NEXT i
    IF n = 0 THEN EXIT SUB
    IF NPL >= PLCap THEN
        PLCap = PLCap + 16
        REDIM PRESERVE PLx(PLCap), PLv(PLCap)
    END IF
    NPL = NPL + 1
    PLx(NPL) = p
    PLv(NPL) = n
END SUB
