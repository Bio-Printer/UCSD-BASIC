' B2LEX -- pass 1: the source (and its #INCLUDE files) into tokens
'
' Its lines only: #INCLUDE, #DEFINE, #IFDEF ..., the comments, the
' characters.  What needs the module's names -- the CONSTs, the DECLAREs
' never used, the header's counts -- is B2CONST's, the pass after, so that
' its tables are not in memory when an #INCLUDE file is opened here.
'
' Comments (' and REM) are dropped.  Each source line with tokens starts
' with TLINE: its number and its text (for messages and the listing);
' TFILE names the file the lines come from.  A line ending in " _" goes
' on in the next one.  Numbers are converted here: TINT holds the value,
' TSNG and TDBL the text of a real (digits, ".", "E", exponent).
#INCLUDE "B2COM"

DIM SHARED LxDepth, LxLine$, LxPos, LxLen, LxLineNo, LxFile$

' What the header says (for B2CONST's tables): the names written (at most
' 768), the CONSTs, the module's DECLAREs; LxInConst: a CONST statement is
' being read (its names are counted), LxParen its ( depth
DIM SHARED LxNames, LxConsts, LxDecls, LxInConst, LxParen

' #DEFINE, #IFDEF ... (LexDirective): the names defined (" A B "), the #IFDEFs open
' (PpN), each one's lines compiled or not (PpOn), the lines of the one outside it
' compiled (PpAct: 1 for none), #ELSE seen (PpElse)
DIM SHARED PpDefs$, PpN, PpOn(8), PpAct(8), PpElse(8)

' ---- the token file (plain: B2CONST does what needs the names)

SUB TB (v)
    DIM b AS BYTE
    b = v
    PUT #CHOUT, , b
END SUB

SUB TW (v)
    PUT #CHOUT, , v
END SUB

SUB TS (s$)
    TB LEN(s$)
    IF LEN(s$) > 0 THEN PUT #CHOUT, , s$
END SUB

' a name: TIDENT (counted)
SUB LexName (w$)
    TB TIDENT
    TS w$
    IF LxNames < 768 THEN LxNames = LxNames + 1
    IF LxInConst = 1 AND LxParen = 0 THEN
        LxConsts = LxConsts + 1
        LxInConst = 2
    END IF
END SUB

' error n of the line being read (s$: its {s})
SUB LexErr (n, s$)
    TokFile$ = LxFile$
    TokLine = LxLineNo
    TokText$ = LxLine$
    ErrRec n, 0, 0, s$
END SUB


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


' the tokens of one line (comments already cut off): first is 1 at the
' line's start (a number or NAME: there is a label), 2 after THEN and
' ELSE, 3 after a colon
SUB LexTokens ()
    DIM c, s, w$, k, d, first, q
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
            LxInConst = 0
            LxParen = 0
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
                    TB TLABEL
                    TS w$
                    first = 1
                ELSE
                    LexName w$
                    first = 0
                END IF
            ELSEIF k = KDATA THEN
                ' DATA: the rest of the line as it is
                TB k
                TB TSTR
                TS LTRIM$(MID$(LxLine$, LxPos))
                LxPos = LxLen + 1
            ELSE
                IF first <> 0 THEN
                    IF k = KCONST THEN LxInConst = 1
                    IF k = KDECLARE THEN LxDecls = LxDecls + 1
                END IF
                TB k
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
                TB TCOMMA
                ' (the next CONST of the statement)
                IF LxInConst = 2 AND LxParen = 0 THEN LxInConst = 1
            CASE 59: TB TSEMI
            CASE 35: TB THASH
            CASE 38: TB TAMP
            CASE 124: TB TBAR
            CASE 63: TB KPRINT
            CASE 58
                TB TCOLON
                first = 3
            CASE ELSE
                LexErr 5, CHR$(c)   ' unexpected character {s}
            END SELECT
            IF c <> 58 THEN first = 0
        END IF
    LOOP
END SUB

' #DEFINE NAME, #UNDEF NAME, #IFDEF NAME, #IFNDEF NAME, #ELSE, #ENDIF: -1
' (done), 0 if t$ is not one of them
FUNCTION LexDirective (t$)
    DIM w$, n$, p, ison
    p = INSTR(t$ + " ", " ")
    w$ = UCASE$(LEFT$(t$, p - 1))
    n$ = UCASE$(LTRIM$(MID$(t$, p)))
    p = INSTR(n$ + " ", " ")
    n$ = LEFT$(n$, p - 1)
    SELECT CASE w$
    CASE "#DEFINE", "#UNDEF"
        IF PpAct(PpN) = 0 THEN
        ELSEIF n$ = "" THEN
            LexErr 120, w$   ' a name expected after {s}
        ELSE
            p = INSTR(PpDefs$, " " + n$ + " ")
            IF p > 0 THEN PpDefs$ = LEFT$(PpDefs$, p) + MID$(PpDefs$, p + LEN(n$) + 2)
            IF w$ = "#DEFINE" THEN PpDefs$ = PpDefs$ + n$ + " "
        END IF
    CASE "#IFDEF", "#IFNDEF"
        IF n$ = "" AND PpAct(PpN) THEN LexErr 120, w$   ' a name expected after {s}
        ison = INSTR(PpDefs$, " " + n$ + " ") > 0
        IF w$ = "#IFNDEF" THEN ison = NOT ison
        IF PpN >= 8 THEN
            LexErr 121, ""   ' #IFDEF nested more than 8 deep
        ELSE
            PpN = PpN + 1
            PpOn(PpN) = ison
            PpElse(PpN) = 0
            IF PpAct(PpN - 1) AND ison THEN PpAct(PpN) = 1 ELSE PpAct(PpN) = 0
        END IF
    CASE "#ELSE"
        IF PpN = 0 THEN
            LexErr 122, w$   ' {s} without #IFDEF
        ELSEIF PpElse(PpN) THEN
            LexErr 123, ""   ' #ELSE twice
        ELSE
            PpElse(PpN) = 1
            PpOn(PpN) = NOT PpOn(PpN)
            IF PpAct(PpN - 1) AND PpOn(PpN) THEN PpAct(PpN) = 1 ELSE PpAct(PpN) = 0
        END IF
    CASE "#ENDIF"
        IF PpN = 0 THEN LexErr 122, w$ ELSE PpN = PpN - 1   ' {s} without #IFDEF
    CASE ELSE
        EXIT FUNCTION
    END SELECT
    LexDirective = -1
END FUNCTION

' one logical line
SUB LexLine (l$)
    DIM e, t$, q, f$
    e = CommentAt(l$)
    t$ = RTRIM$(LTRIM$(LEFT$(l$, e - 1)))
    IF t$ = "" THEN EXIT SUB
    IF LEFT$(t$, 1) = "#" THEN
        IF LexDirective(t$) THEN EXIT SUB
    END IF
    ' (the lines of an #IFDEF ... not compiled)
    IF PpAct(PpN) = 0 THEN EXIT SUB
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

' the token file: its header (WHWORDS words: room for it first, written
' at the end, when the counts are known), then the tokens
SUB LexFile (f$)
    DIM i
    IF FileExists(TokName$) THEN KILL TokName$
    OPEN TokName$ FOR BINARY AS #CHOUT
    FOR i = 1 TO WHWORDS
        TW 0
    NEXT i
    LxDepth = 0
    ' (-D's names, and B2: the compiler is B2)
    PpDefs$ = " B2 "
    FOR i = 1 TO LEN(Defines$)
        IF MID$(Defines$, i, 1) = "," THEN PpDefs$ = PpDefs$ + " " ELSE PpDefs$ = PpDefs$ + MID$(Defines$, i, 1)
    NEXT i
    PpDefs$ = PpDefs$ + " "
    PpN = 0
    PpAct(0) = 1
    LexLines f$, CHSRC
    IF PpN > 0 THEN LexErr 124, ""   ' #ENDIF expected
    TB TEOF
    ' (B2CONST's counts: names, DECLAREs, CONSTs)
    SEEK #CHOUT, 1
    TW TOKMAGIC
    TW LxNames
    TW 0
    TW LxDecls
    TW LxConsts
    CLOSE #CHOUT
END SUB

' ---- B2LEX, the program: pass 1 of the job's compile step, then B2CONST

ReadJob
StepNames
ErrCount = 0
IF NOT FileExists(SrcName$) THEN
    SayLn "B2: no file " + SrcName$
    PhaseDone 0
END IF
IF OptQuiet = 0 THEN SayLn "Compiling " + SrcName$
TokLine = 0
TokText$ = ""
MemNote "start"
TokName$ = PassFile$(0)
LexFile SrcName$
MemNote "lexed"
IF ErrCount > 0 THEN CompileFailed
ChainTo "B2CONST", ""
