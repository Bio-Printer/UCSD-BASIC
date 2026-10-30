' BCKW -- the keywords: the lexer's table (BCLEX) and their names in
' messages (BCERR)
#INCLUDE "BCCOM"

' (KwCode's copy of the table, made at its first call)
DIM SHARED KwT$(3)

' ---- keywords (the lexer's table: codes 1..NKEYWORD, 9 characters each),
' and their names for messages

' (a segment of its own: called once, before the lexer opens a file)
SEGMENT KWTAB
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
        tb$ = "RESUME   SEEK     USING    CHAIN    "
    END SELECT
    KwTable$ = tb$
END FUNCTION

SEGMENT

FUNCTION KwName$ (k)
    DIM t$, e$, j
    j = k
    IF j > TMEND AND j <= TMEND + NKEYWORD THEN
        ' (the end of a block: END IF, END SELECT ...)
        e$ = "END "
        j = j - TMEND
    END IF
    IF j >= 1 AND j <= NKEYWORD THEN
        t$ = KwTable$((j - 1) \ 27)
        KwName$ = e$ + RTRIM$(MID$(t$, ((j - 1) MOD 27) * 9 + 1, 9))
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
    CASE TBAR: KwName$ = "|"
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
    IF KwT$(0) = "" THEN
        FOR part = 0 TO 3
            KwT$(part) = KwTable$(part)
        NEXT part
    END IF
    pad$ = LEFT$(w$ + "         ", 9)
    FOR part = 0 TO 3
        t$ = KwT$(part)
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
