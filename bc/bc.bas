' BC -- the BASIC compiler for the UCSD P-System: the driver
'
' BC compiles BASIC sources (NAME.TEXT) into object files (NAME.OBJ) and
' links object files and the library BASLIB.OBJ into a code file
' (NAME.CODE).  Commands, at the "Compile what file?" prompt or as the
' command line:
'   NAME            compile NAME.TEXT and link NAME.CODE
'   -C NAME         compile only: NAME.OBJ
'   -S NAME         compile with a listing (the BASIC statements and the
'                   P-code made for them) in NAME.LST.TEXT; -S -C NAME too
'   -L OUT=A,B,...  link A.OBJ, B.OBJ ... (and BASLIB.OBJ) into OUT.CODE
'   -J LIB=A,B,...  join object files into one library LIB.OBJ
'   @FILE           the commands in FILE.TEXT, one or more a line
'   -Q              fewer messages
' This module is the resident part: the driver, messages, the token reader
' and the symbol table, used by every pass.
#INCLUDE "BCCOM"

' ---- messages

SUB Say (s$)
    PRINT s$;
END SUB

SUB SayLn (s$)
    PRINT s$
END SUB

FUNCTION IStr$ (n)
    IStr$ = LTRIM$(STR$(n))
END FUNCTION

FUNCTION UpStr$ (s$)
    UpStr$ = UCASE$(s$)
END FUNCTION

' an error in the source: where, what, and the line
SUB ErrMsg (msg$)
    ErrCount = ErrCount + 1
    IF ErrCount > 30 THEN EXIT SUB
    PRINT TokFile$; " line "; IStr$(TokLine); ": "; msg$
    IF TokText$ <> "" THEN PRINT "  "; TokText$
END SUB

SUB Fatal (msg$)
    PRINT "BC: "; msg$
    CLOSE
    END
END SUB

' ---- keywords (the lexer's table: codes 1..NKEYWORD, 9 characters each)

FUNCTION KwTable$ (part)
    DIM tb$
    SELECT CASE part
    CASE 0
        tb$ = "PRINT    INPUT    LET      IF       THEN     ELSE     ELSEIF   END      "
        tb$ = tb$ + "FOR      TO       STEP     NEXT     WHILE    WEND     DO       LOOP     "
        tb$ = tb$ + "UNTIL    EXIT     GOTO     GOSUB    RETURN   ON       SUB      FUNCTION "
        tb$ = tb$ + "CALL     DIM      REDIM    "
    CASE 1
        tb$ = "SHARED   COMMON   AS       INTEGER  SINGLE   DOUBLE   STRING   BYTE     "
        tb$ = tb$ + "CONST    DECLARE  DEFINT   DEFSNG   DEFDBL   DEFSTR   SELECT   CASE     "
        tb$ = tb$ + "IS       OPEN     CLOSE    OUTPUT   APPEND   BINARY   RANDOM   LINE     "
        tb$ = tb$ + "GET      PUT      KILL     "
    CASE 2
        tb$ = "STOP     SYSTEM   AND      OR       XOR      NOT      MOD      BYREF    "
        tb$ = tb$ + "BYVAL    STATIC   SEGMENT  PRIVATE  SWAP     ERASE    DATA     READ     "
        tb$ = tb$ + "RESTORE  CONTINUE RANDOMIZEOPTION   EXPLICIT REAL     CLS      LOCATE   "
        tb$ = tb$ + "WRITE    PRESERVE ERROR    "
    CASE ELSE
        tb$ = "RESUME   SEEK     USING    "
    END SELECT
    KwTable$ = tb$
END FUNCTION

FUNCTION KwName$ (k)
    DIM t$
    IF k >= 1 AND k <= NKEYWORD THEN
        t$ = KwTable$((k - 1) \ 27)
        KwName$ = RTRIM$(MID$(t$, ((k - 1) MOD 27) * 9 + 1, 9))
        EXIT FUNCTION
    END IF
    SELECT CASE k
    CASE TEQ: KwName$ = "="
    CASE TNE: KwName$ = "<>"
    CASE TLT: KwName$ = "<"
    CASE TGT: KwName$ = ">"
    CASE TLE: KwName$ = "<="
    CASE TGE: KwName$ = ">="
    CASE TPLUS: KwName$ = "+"
    CASE TMINUS: KwName$ = "-"
    CASE TMUL: KwName$ = "*"
    CASE TDIV: KwName$ = "/"
    CASE TIDIV: KwName$ = "\"
    CASE TPOW: KwName$ = "^"
    CASE TLPAR: KwName$ = "("
    CASE TRPAR: KwName$ = ")"
    CASE TCOMMA: KwName$ = ","
    CASE TSEMI: KwName$ = ";"
    CASE THASH: KwName$ = "#"
    CASE TAMP: KwName$ = "&"
    CASE TCOLON: KwName$ = ":"
    CASE TIDENT: KwName$ = "a name"
    CASE TINT, TSNG, TDBL: KwName$ = "a number"
    CASE TSTR: KwName$ = "a string"
    CASE TLINE: KwName$ = "the end of the line"
    CASE TEOF: KwName$ = "the end of the file"
    CASE ELSE: KwName$ = "?"
    END SELECT
END FUNCTION

' the keyword code of an upper-case word, 0 if it is not one
FUNCTION KwCode (w$)
    DIM part, p, t$, pad$
    IF LEN(w$) > 9 OR LEN(w$) < 2 THEN EXIT FUNCTION
    pad$ = LEFT$(w$ + "         ", 9)
    FOR part = 0 TO 3
        t$ = KwTable$(part)
        p = INSTR(t$, pad$)
        DO WHILE p > 0
            IF (p - 1) MOD 9 = 0 THEN
                KwCode = part * 27 + (p - 1) \ 9 + 1
                EXIT FUNCTION
            END IF
            p = INSTR(p + 1, t$, pad$)
        LOOP
    NEXT part
END FUNCTION

' ---- the token file (written by the lexer, read by passes 2 and 3)

SUB OpenTok ()
    OPEN TokName$ FOR BINARY AS #CHTOK
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

SUB Expect (t, what$)
    IF Tok = t THEN
        GetTok
    ELSE
        ErrMsg what$ + " expected, not " + KwName$(Tok)
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

' the type a name's suffix gives, 0 for none
FUNCTION SuffixType (n$)
    SELECT CASE ASC(n$, LEN(n$))
    CASE 37: SuffixType = TYINT
    CASE 33: SuffixType = TYSNG
    CASE 35: SuffixType = TYDBL
    CASE 36: SuffixType = TYSTR
    END SELECT
END FUNCTION

FUNCTION BaseName$ (n$)
    IF SuffixType(n$) THEN BaseName$ = LEFT$(n$, LEN(n$) - 1) ELSE BaseName$ = n$
END FUNCTION

FUNCTION TypeChar$ (ty)
    SELECT CASE ty
    CASE TYINT: TypeChar$ = "%"
    CASE TYSNG: TypeChar$ = "!"
    CASE TYDBL: TypeChar$ = "#"
    CASE TYSTR: TypeChar$ = "$"
    CASE TYBYTE: TypeChar$ = "%"
    END SELECT
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
    IF NSym >= MAXSYM THEN Fatal "too many names"
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
        ErrMsg "too many segments"
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
        ErrMsg "a type expected (INTEGER, SINGLE, DOUBLE, STRING, BYTE)"
        ParseType = TYINT
        EXIT FUNCTION
    END SELECT
    GetTok
END FUNCTION

' ---- files

FUNCTION FileExists (f$)
    ON ERROR RESUME NEXT
    OPEN f$ FOR INPUT AS #CHLTMP
    IF ERR = 0 THEN
        CLOSE #CHLTMP
        FileExists = -1
    END IF
    ON ERROR GOTO 0
END FUNCTION

' NAME with the suffix suf$ unless it has one (a dot after its volume)
FUNCTION WithSuffix$ (f$, suf$)
    DIM i, c
    FOR i = LEN(f$) TO 1 STEP -1
        c = ASC(f$, i)
        IF c = 46 THEN
            WithSuffix$ = f$
            EXIT FUNCTION
        END IF
        IF c = 58 THEN EXIT FOR
    NEXT i
    WithSuffix$ = f$ + suf$
END FUNCTION

' the volume part of a file name ("#5:" of "#5:FOO.TEXT"), "" for none
FUNCTION VolOf$ (f$)
    DIM i
    i = INSTR(f$, ":")
    IF i > 0 THEN VolOf$ = LEFT$(f$, i)
END FUNCTION

' FOO of VOL:FOO.TEXT
FUNCTION ModOf$ (f$)
    DIM s$, i
    s$ = MID$(f$, LEN(VolOf$(f$)) + 1)
    i = INSTR(s$, ".")
    IF i > 0 THEN s$ = LEFT$(s$, i - 1)
    ModOf$ = UCASE$(s$)
END FUNCTION

' the source file of NAME: NAME, NAME.TEXT or NAME.BAS, on its volume
FUNCTION SourceOf$ (n$)
    DIM f$
    f$ = WithSuffix$(n$, ".TEXT")
    IF NOT FileExists(f$) AND f$ <> n$ THEN
        IF FileExists(n$ + ".BAS") THEN f$ = n$ + ".BAS"
    END IF
    SourceOf$ = f$
END FUNCTION

' the listing file: NAME.LST.TEXT (the name cut so that it fits in 15)
FUNCTION ListOf$ (n$)
    DIM m$
    m$ = ModOf$(n$)
    IF LEN(m$) > 6 THEN m$ = LEFT$(m$, 6)
    ListOf$ = VolOf$(n$) + m$ + ".LST.TEXT"
END FUNCTION

' ---- compiling one file

SUB MemNote (w$)
    IF OptMem THEN SayLn "  [" + w$ + ": " + IStr$(FRE(0)) + " free, least " + IStr$(FRE(-1)) + "]"
END SUB

FUNCTION Compile (n$, lst)
    SrcName$ = SourceOf$(n$)
    ModName$ = ModOf$(n$)
    ObjName$ = VolOf$(n$) + ModName$ + ".OBJ"
    OptList = lst
    IF lst THEN LstName$ = ListOf$(n$) ELSE LstName$ = ""
    ErrCount = 0
    IF NOT FileExists(SrcName$) THEN
        SayLn "BC: no file " + SrcName$
        EXIT FUNCTION
    END IF
    IF OptQuiet = 0 THEN SayLn "Compiling " + SrcName$
    TokFile$ = SrcName$
    TokLine = 0
    TokText$ = ""
    MemNote "start"
    LexFile SrcName$
    MemNote "lexed"
    ' the symbol table: only while the module is compiled (the linker
    ' gets its memory)
    REDIM SName$(MAXSYM), SKind(MAXSYM) AS BYTE, SType(MAXSYM) AS BYTE, SCls(MAXSYM) AS BYTE
    REDIM SOff(MAXSYM), SFlags(MAXSYM) AS BYTE, SScope(MAXSYM) AS BYTE, SNext(MAXSYM)
    REDIM SAux(MAXSYM), SAux2(MAXSYM), SSeg(MAXSYM) AS BYTE, HashHead(HSIZE)
    REDIM PType(MAXPAR) AS BYTE, PFlg(MAXPAR) AS BYTE
    MemNote "symbols"
    IF ErrCount = 0 THEN
        InitSyms
        DeclPass
    END IF
    MemNote "declared"
    IF ErrCount = 0 THEN GenPass
    ERASE SName$, SKind, SType, SCls, SOff, SFlags, SScope, SNext, SAux, SAux2, SSeg
    ERASE HashHead, PType, PFlg
    KILL TokName$
    IF ErrCount > 0 THEN
        SayLn IStr$(ErrCount) + " error(s): no " + ObjName$
        IF FileExists(ObjName$) THEN KILL ObjName$
        EXIT FUNCTION
    END IF
    IF OptQuiet = 0 THEN SayLn "  " + ObjName$
    IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words"
    Compile = -1
END FUNCTION

' ---- commands

DIM SHARED CmdLine$, CmdPos

' the next word of the command line ("" at its end)
FUNCTION NextWord$ ()
    DIM s, c
    DO WHILE CmdPos <= LEN(CmdLine$)
        c = ASC(CmdLine$, CmdPos)
        IF c <> 32 AND c <> 9 AND c <> 44 THEN EXIT DO
        CmdPos = CmdPos + 1
    LOOP
    s = CmdPos
    DO WHILE CmdPos <= LEN(CmdLine$)
        c = ASC(CmdLine$, CmdPos)
        IF c = 32 OR c = 9 THEN EXIT DO
        CmdPos = CmdPos + 1
    LOOP
    NextWord$ = MID$(CmdLine$, s, CmdPos - s)
END FUNCTION

' -L OUT=A,B: the code file and the object files
FUNCTION DoLink (spec$)
    DIM e, out$, objs$
    e = INSTR(spec$, "=")
    IF e = 0 THEN
        out$ = spec$
        objs$ = spec$
    ELSE
        out$ = LEFT$(spec$, e - 1)
        objs$ = MID$(spec$, e + 1)
    END IF
    out$ = WithSuffix$(out$, ".CODE")
    DoLink = LinkProg(out$, objs$)
END FUNCTION

FUNCTION DoJoin (spec$)
    DIM e
    e = INSTR(spec$, "=")
    IF e = 0 THEN
        SayLn "BC: -J LIB=A,B,..."
        EXIT FUNCTION
    END IF
    DoJoin = JoinLib(WithSuffix$(LEFT$(spec$, e - 1), ".OBJ"), MID$(spec$, e + 1))
END FUNCTION

' @FILE: each line of FILE.TEXT is a command line
FUNCTION RunBatch (f$)
    DIM l$, ok, n, i, lines$(200)
    f$ = WithSuffix$(f$, ".TEXT")
    IF NOT FileExists(f$) THEN
        SayLn "BC: no file " + f$
        EXIT FUNCTION
    END IF
    ' read it all first: the commands open files of their own
    OPEN f$ FOR INPUT AS #CHBAT
    DO WHILE NOT EOF(CHBAT) AND n < 200
        LINE INPUT #CHBAT, l$
        n = n + 1
        lines$(n) = l$
    LOOP
    CLOSE #CHBAT
    ok = -1
    FOR i = 1 TO n
        l$ = LTRIM$(lines$(i))
        IF l$ <> "" AND LEFT$(l$, 1) <> "'" THEN
            IF NOT RunCmds(l$) THEN
                ok = 0
                EXIT FOR
            END IF
        END IF
    NEXT i
    RunBatch = ok
END FUNCTION

' one command line: options and names, run in turn; the first failure stops
FUNCTION RunCmds (l$)
    DIM w$, cmd$, ok, lst, conly, savel$, savep
    savel$ = CmdLine$
    savep = CmdPos
    CmdLine$ = l$
    CmdPos = 1
    ok = -1
    DO
        w$ = UCASE$(NextWord$)
        IF w$ = "" THEN EXIT DO
        IF w$ = "-S" THEN
            lst = 1
        ELSEIF w$ = "-C" THEN
            conly = 1
        ELSEIF w$ = "-Q" THEN
            OptQuiet = 1
        ELSEIF w$ = "-M" THEN
            OptMem = 1
        ELSEIF w$ = "-L" THEN
            ok = DoLink(UCASE$(NextWord$))
        ELSEIF w$ = "-J" THEN
            ok = DoJoin(UCASE$(NextWord$))
        ELSEIF LEFT$(w$, 1) = "@" THEN
            ok = RunBatch(MID$(w$, 2))
        ELSEIF LEFT$(w$, 1) = "-" THEN
            SayLn "BC: unknown option " + w$
            ok = 0
        ELSE
            ok = Compile(w$, lst)
            IF ok AND conly = 0 THEN ok = DoLink(VolOf$(w$) + ModOf$(w$))
            lst = 0
            conly = 0
        END IF
        IF NOT ok THEN EXIT DO
    LOOP
    CmdLine$ = savel$
    CmdPos = savep
    RunCmds = ok
END FUNCTION

' ---- the main program

DIM SegName$(MAXSEG), DefType(25), ParName$(30), ParFlags(30)

DIM cmd$, l$, r
TokName$ = "BCTEMP.TOK"
LTmpName$ = "BCTEMP.LST"
cmd$ = COMMAND$
IF cmd$ <> "" THEN
    IF NOT RunCmds(cmd$) THEN SYSTEM 1
    SYSTEM 0
END IF
PRINT "BC -- BASIC compiler for the UCSD P-System"
DO
    PRINT "Compile what file? ";
    LINE INPUT l$
    l$ = LTRIM$(RTRIM$(l$))
    IF l$ = "" THEN EXIT DO
    r = RunCmds(l$)
LOOP
END
