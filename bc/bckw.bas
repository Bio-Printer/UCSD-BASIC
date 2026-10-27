' BCKW -- the keywords: the lexer's table (BCLEX) and their names in
' messages (BCGEN)
#INCLUDE "BCCOM"

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
        tb$ = "RESUME   SEEK     USING    CHAIN    "
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
