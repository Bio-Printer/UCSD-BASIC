' PI -- Archimedes' method with DOUBLEs: Tiny-C's PI.C (and PASCAL-C's
' PI.TEXT) in BASIC.
' Polygons with 6, 12, 24, ... sides inside and around a circle of
' diameter 1: their perimeters are a lower and an upper bound for pi.
' Doubling the sides:
'     upper' = 2 * upper * lower / (upper + lower)   (harmonic mean)
'     lower' = SQR(upper' * lower)                   (geometric mean)
' Each step makes the gap about 4 times smaller (0.6 digits); both bounds
' close in on pi until they agree to 15 significant digits.
' BASIC has no PRINT USING: Fixed$ writes a number with a given number of
' decimals, by whole-number DOUBLE arithmetic (exact below 2^52).
DEFINT A-Z
CONST REF = "3.14159265358979"      ' pi, 15 significant digits
DIM SHARED two52#

' x# rounded to a whole number (x# below 2^52)
FUNCTION Whole# (x#)
    Whole# = (x# + two52#) - two52#
END FUNCTION

' x# (not negative) with dec decimals, right-aligned in w columns
FUNCTION Fixed$ (x#, dec, w)
    DIM y#, q#, s$, n
    y# = x#
    FOR n = 1 TO dec
        y# = y# * 10
    NEXT n
    y# = Whole#(y#)
    ' the digits, the last one first, until the whole part is done
    n = 0
    DO
        ' y# \ 10 (Whole# only of 0 and more: below 2^52 its steps are halves)
        IF y# >= 10 THEN q# = Whole#(y# / 10 - 0.45) ELSE q# = 0
        s$ = CHR$(48 + CINT(y# - 10 * q#)) + s$
        y# = q#
        n = n + 1
        IF n = dec THEN s$ = "." + s$
    LOOP UNTIL n > dec AND y# = 0
    IF LEN(s$) < w THEN s$ = SPACE$(w - LEN(s$)) + s$
    Fixed$ = s$
END FUNCTION

' how many leading digits of x#, to 14 decimals, agree with pi
FUNCTION Digits (x#)
    DIM s$, i, n
    s$ = Fixed$(x#, 14, 0)
    FOR i = 1 TO LEN(REF)
        IF MID$(s$, i, 1) <> MID$(REF, i, 1) THEN EXIT FOR
        IF MID$(REF, i, 1) <> "." THEN n = n + 1
    NEXT i
    Digits = n
END FUNCTION

DIM upper#, lower#, sides#, i
two52# = 4503599627370496#
upper# = 2 * SQR(3#)                ' the hexagon around the circle
lower# = 3                          ' the hexagon inside it
sides# = 6
PRINT "Pi by Archimedes' method (polygons around and inside a circle)"
PRINT
PRINT "step       sides  lower bound        upper bound        digits"
FOR i = 0 TO 30
    PRINT RIGHT$("   " + LTRIM$(STR$(i)), 4); " "; Fixed$(sides#, 0, 11); "  ";
    PRINT Fixed$(lower#, 15, 0); "  "; Fixed$(upper#, 15, 0); "  ";
    PRINT RIGHT$(" " + LTRIM$(STR$(Digits(lower#))), 2); " ";
    PRINT RIGHT$(" " + LTRIM$(STR$(Digits(upper#))), 2)
    IF Digits(lower#) >= 15 AND Digits(upper#) >= 15 THEN EXIT FOR
    upper# = 2 * upper# * lower# / (upper# + lower#)
    lower# = SQR(upper# * lower#)
    sides# = sides# * 2
NEXT i
PRINT
PRINT "pi = "; Fixed$((lower# + upper#) / 2, 14, 0); " (ATN: "; Fixed$(4 * ATN(1#), 14, 0); ")"
