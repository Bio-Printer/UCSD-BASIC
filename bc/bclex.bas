' BCLEX -- pass 1: the source (and its #INCLUDE files) into tokens
'
' Comments (' and REM) are dropped.  Each source line with tokens starts
' with TLINE: its number and its text (for messages and the listing);
' TFILE names the file the lines come from.  A line ending in " _" goes
' on in the next one.  Numbers are converted here: TINT holds the value,
' TSNG and TDBL the text of a real (digits, ".", "E", exponent).
#INCLUDE "BCCOM"
SEGMENT LEX

DIM SHARED LxDepth, LxLine$, LxPos, LxLen, LxLineNo, LxFile$

SUB TB (v)
    DIM b AS BYTE
    b = v
    PUT #CHTOK, , b
END SUB

SUB TW (v)
    PUT #CHTOK, , v
END SUB

SUB TS (s$)
    TB LEN(s$)
    IF LEN(s$) > 0 THEN PUT #CHTOK, , s$
END SUB

SUB LexErr (msg$)
    TokFile$ = LxFile$
    TokLine = LxLineNo
    TokText$ = LxLine$
    ErrMsg msg$
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
    DIM s, digits$, ty, c, v, d, big, nsig, i
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
    c = LxC
    IF c = 35 THEN
        ty = TYDBL
        LxPos = LxPos + 1
    ELSEIF c = 33 THEN
        ty = TYSNG
        LxPos = LxPos + 1
    ELSEIF c = 37 THEN
        IF ty <> 0 THEN LexErr "an integer with a decimal point"
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
        IF ty = TYINT THEN LexErr "integer too large"
        ty = TYSNG
    END IF
    ' more than 7 significant digits: a DOUBLE
    IF ty = TYSNG THEN
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
    IF n = 0 THEN LexErr "a number expected after &"
    IF LxC = 37 THEN LxPos = LxPos + 1
    TB TINT
    TW v
END SUB

' the tokens of one line (comments already cut off)
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
            ' a keyword followed by $ % ! is a name (STRING$, INPUT$)
            IF c = 36 OR c = 37 OR c = 33 THEN k = 0 ELSE k = KwCode(w$)
            IF k = 0 THEN
                IF c = 37 OR c = 33 OR c = 35 OR c = 36 THEN
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
                    TB TIDENT
                    TS w$
                    first = 0
                END IF
            ELSE
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
        ELSEIF c = 38 AND INSTR("HhOoBb", CHR$(ASC(LxLine$, LxPos + 1))) > 0 AND ASC(LxLine$, LxPos + 1) <> 0 THEN
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
            CASE 40: TB TLPAR
            CASE 41: TB TRPAR
            CASE 44: TB TCOMMA
            CASE 59: TB TSEMI
            CASE 35: TB THASH
            CASE 38: TB TAMP
            CASE 63: TB KPRINT
            CASE 58
                TB TCOLON
                first = 1
            CASE ELSE
                LexErr "unexpected character " + CHR$(c)
            END SELECT
            IF c <> 58 THEN first = 0
        END IF
    LOOP
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
            LexErr "#INCLUDE " + CHR$(34) + "FILE" + CHR$(34) + " expected"
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
    DO WHILE NOT EOF(ch)
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
        LexErr "#INCLUDE files nest too deep"
        EXIT SUB
    END IF
    g$ = WithSuffix$(UCASE$(f$), ".TEXT")
    IF NOT FileExists(g$) THEN
        ' beside the source: the source's volume
        IF INSTR(g$, ":") = 0 AND INSTR(SrcName$, ":") > 0 THEN
            g$ = LEFT$(SrcName$, INSTR(SrcName$, ":")) + g$
        END IF
    END IF
    IF NOT FileExists(g$) THEN
        LexErr "no file " + g$
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

SUB LexFile (f$)
    OPEN TokName$ FOR OUTPUT AS #CHTOK
    LxDepth = 0
    LexLines f$, CHSRC
    TB TEOF
    CLOSE #CHTOK
END SUB
