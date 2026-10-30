' BCERR -- the compile step's errors: BCLEX and BCGEN (and the procedures
' they share) keep each error as a number, a number in it, a token and a
' string, and where it was (BCUTIL's ErrRec); when the step ends they
' write them to :BCTEMP.ERR and chain here (CompileFailed).  BCERR has the
' texts (MsgText$: {s} the string, {a} the number, {t} the token's name,
' {k} the name of the token the number is), says each error as
'   FILE line N: the text
'     the line
' and "N error(s): no NAME.OBJ" (a fatal error, a negative number: "BC:
' the text", and no more), removes the step's files and chains to BC with
' the failure.  Only an error brings it into memory: BCGEN holds no text.
#INCLUDE "BCCOM"

' the texts of errors 1 to 40
FUNCTION MsgA$ (n)
    DIM t$
    SELECT CASE n
    CASE 1: t$ = "{k} expected, not {t}"
    CASE 2: t$ = "an integer with a decimal point"
    CASE 3: t$ = "integer too large"
    CASE 4: t$ = "a number expected after &"
    CASE 5: t$ = "unexpected character {s}"
    CASE 6: t$ = "#INCLUDE " + CHR$(34) + "FILE" + CHR$(34) + " expected"
    CASE 7: t$ = "#INCLUDE files nest too deep"
    CASE 8: t$ = "no file {s}"
    CASE 9: t$ = "too many names"
    CASE 10: t$ = "too many segments"
    CASE 11: t$ = "a type expected (INTEGER, SINGLE, DOUBLE, STRING, BYTE)"
    CASE 12: t$ = "a letter expected"
    CASE 13: t$ = "a name with a type suffix declared AS a type"
    CASE 14: t$ = "a parameter name expected"
    CASE 15: t$ = "too many parameters"
    CASE 16: t$ = "more than 30 parameters"
    CASE 17: t$ = "a procedure name expected"
    CASE 18: t$ = "a SUB name with a type suffix"
    CASE 19: t$ = "{s}: not as declared before"
    CASE 20: t$ = "{s} defined twice"
    CASE 21: t$ = "{s} is already the name of something else"
    CASE 22: t$ = ") expected"
    CASE 23: t$ = "a variable name expected"
    CASE 24: t$ = "{s} declared twice"
    CASE 25: t$ = "SUB or FUNCTION expected"
    CASE 26: t$ = "the end of the statement expected, not {t}"
    CASE 27: t$ = "type mismatch: a string as a condition"
    CASE 28: t$ = "a variable expected"
    CASE 29: t$ = "{s} is an array: an index expected"
    CASE 30: t$ = "{s} is a constant"
    CASE 31: t$ = "{s}: no such array (DIM it first)"
    CASE 32: t$ = "a label expected"
    CASE 33: t$ = "label {s} defined twice"
    CASE 34: t$ = "blocks nested too deep"
    CASE 35: t$ = "END IF expected"
    CASE 36: t$ = "a FOR variable expected"
    CASE 37: t$ = "FOR needs a numeric variable"
    CASE 38: t$ = "FOR loops nested more than 30 deep"
    CASE 39: t$ = "NEXT expected"
    CASE 40: t$ = "LOOP expected"
    END SELECT
    MsgA$ = t$
END FUNCTION

' the texts of errors 41 to 80
FUNCTION MsgB$ (n)
    DIM t$
    SELECT CASE n
    CASE 41: t$ = "WEND expected"
    CASE 42: t$ = "a comparison expected after IS"
    CASE 43: t$ = "END SELECT expected"
    CASE 44: t$ = "CONTINUE FOR, DO or WHILE expected"
    CASE 45: t$ = "EXIT {t} outside a procedure"
    CASE 46: t$ = "FOR, DO, WHILE, SELECT, SUB or FUNCTION expected"
    CASE 47: t$ = "not inside such a block"
    CASE 48: t$ = "CONTINUE SELECT?"
    CASE 49: t$ = "RETURN with a value outside a FUNCTION"
    CASE 50: t$ = "only ON ERROR GOTO 0 and ON ERROR RESUME NEXT"
    CASE 51: t$ = "GOTO or GOSUB expected"
    CASE 52: t$ = "more than 50 labels"
    CASE 53: t$ = ", expected"
    CASE 54: t$ = "PRINT USING is not supported"
    CASE 55: t$ = "LINE INPUT needs a string variable"
    CASE 56: t$ = "INPUT, OUTPUT, APPEND, BINARY or RANDOM expected"
    CASE 57: t$ = "DIM SHARED inside a procedure"
    CASE 58: t$ = "{s} is not an array"
    CASE 59: t$ = "{s}: the wrong number of dimensions"
    CASE 60: t$ = "STATIC arrays are not supported"
    CASE 61: t$ = "no module variable {s}"
    CASE 62: t$ = "a constant name expected"
    CASE 63: t$ = "too many string and real constants"
    CASE 64: t$ = "RESTORE without DATA"
    CASE 65: t$ = "no such label"
    CASE 66: t$ = "SWAP needs two variables of one type"
    CASE 67: t$ = "{s}: {a} argument(s) expected"
    CASE 68: t$ = "MID$ needs a string variable"
    CASE 69: t$ = "{s}: a constant expected"
    CASE 70: t$ = "= expected after the function's name"
    CASE 71: t$ = "LINE INPUT expected"
    CASE 72: t$ = "SHARED outside a procedure"
    CASE 73: t$ = "no array {s}"
    CASE 74: t$ = "an array name expected"
    CASE 75: t$ = "a SUB name expected"
    CASE 76: t$ = "no SUB {s}"
    CASE 77: t$ = "a statement expected, not {t}"
    CASE 78: t$ = "a SUB or FUNCTION inside a procedure (END SUB missing?)"
    CASE 79: t$ = "internal: {s} not declared"
    CASE 80: t$ = "END FUNCTION expected"
    END SELECT
    MsgB$ = t$
END FUNCTION

' the texts of errors 81 to 117
FUNCTION MsgC$ (n)
    DIM t$
    SELECT CASE n
    CASE 81: t$ = "END SUB expected"
    CASE 82: t$ = "{t} without its block"
    CASE 83: t$ = "not BCLEX's token file: {s}"
    CASE 84: t$ = "expression too complex"
    CASE 85: t$ = "type mismatch"
    CASE 86: t$ = "& needs strings, INTEGERs or BYTEs"
    CASE 87: t$ = "{s} not declared (OPTION EXPLICIT)"
    CASE 88: t$ = "real constant too large"
    CASE 89: t$ = "VARPTR needs a variable"
    CASE 90: t$ = "{s}: an argument expected"
    CASE 91: t$ = "{s}: arguments expected"
    CASE 92: t$ = "FRE: one argument expected"
    CASE 93: t$ = "{s}: one argument expected"
    CASE 94: t$ = "OSVAR: a constant expected"
    CASE 95: t$ = "OSADDR: a constant expected"
    CASE 96: t$ = "{s}: two arguments expected"
    CASE 97: t$ = "INSTR: arguments expected"
    CASE 98: t$ = "STR$: one argument expected"
    CASE 99: t$ = "SADD: one argument expected"
    CASE 100: t$ = "{s}: a constant first"
    CASE 101: t$ = "{s}: a comparison as an argument"
    CASE 102: t$ = "an index expected"
    CASE 103: t$ = "{s}: the wrong number of indexes"
    CASE 104: t$ = "an array expected as argument {a} of {s}"
    CASE 105: t$ = "{s} is a SUB, not a FUNCTION"
    CASE 106: t$ = "{s}: no such array or function"
    CASE 107: t$ = "an expression expected, not {t}"
    CASE 108: t$ = "a constant expression expected"
    CASE 109: t$ = "argument {a} of {s}: an array of another type"
    CASE 110: t$ = "procedure too large: split it"
    CASE 111: t$ = "procedure too large (labels): split it"
    CASE 112: t$ = "procedure too large (jumps): split it"
    CASE 113: t$ = "procedure too large (calls): split it"
    CASE 114: t$ = "more than 100 GOSUBs in one procedure"
    CASE 115: t$ = "label {s} not defined"
    CASE 116: t$ = "internal: a label not set"
    CASE 117: t$ = "procedure too large (more than 60 long jumps): split it"
    CASE 118: t$ = "| needs INTEGERs or BYTEs"
    CASE 119: t$ = "{s} is used before its CONST"
    END SELECT
    MsgC$ = t$
END FUNCTION

FUNCTION MsgText$ (n)
    IF n <= 40 THEN
        MsgText$ = MsgA$(n)
    ELSEIF n <= 80 THEN
        MsgText$ = MsgB$(n)
    ELSE
        MsgText$ = MsgC$(n)
    END IF
END FUNCTION

' t$ with what {w$} stands for: v$
FUNCTION Fill$ (t$, w$, v$)
    DIM p
    p = INSTR(t$, w$)
    IF p = 0 THEN
        Fill$ = t$
    ELSE
        Fill$ = LEFT$(t$, p - 1) + v$ + MID$(t$, p + LEN(w$))
    END IF
END FUNCTION

' ---- BCERR, the program

DIM count, i, n, a, t, l, l$, f$, x$, s$, m$, p
ReadJob
StepNames
OPEN ErrName$ FOR INPUT AS #CHJOB
LINE INPUT #CHJOB, l$
count = VAL(l$)
n = count
IF n > MAXERR THEN n = MAXERR
FOR i = 1 TO n
    LINE INPUT #CHJOB, l$
    p = VAL(l$)
    LINE INPUT #CHJOB, l$
    a = VAL(l$)
    LINE INPUT #CHJOB, l$
    t = VAL(l$)
    LINE INPUT #CHJOB, l$
    l = VAL(l$)
    LINE INPUT #CHJOB, f$
    LINE INPUT #CHJOB, x$
    LINE INPUT #CHJOB, s$
    m$ = MsgText$(ABS(p))
    m$ = Fill$(m$, "{s}", s$)
    m$ = Fill$(m$, "{a}", IStr$(a))
    m$ = Fill$(m$, "{t}", KwName$(t))
    m$ = Fill$(m$, "{k}", KwName$(a))
    IF p < 0 THEN
        PRINT "BC: "; m$
        EXIT FOR
    END IF
    PRINT f$; " line "; IStr$(l); ": "; m$
    IF x$ <> "" THEN PRINT "  "; x$
NEXT i
CLOSE #CHJOB
KILL ErrName$
IF p >= 0 THEN SayLn IStr$(count) + " error(s): no " + ObjName$
StepFailed
