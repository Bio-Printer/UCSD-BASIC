' RTNUM -- the run-time library: reals and doubles (text, VAL, rounding,
' RND, TIMER)
#INCLUDE "RTCOM"

' a double as text in the style of BASIC: prec significant digits, no
' leading 0 before the point, E+nn; a blank before one that is not negative
FUNCTION _FMTD (d#, prec)
    DIM b, n, i, c, o, t, neg
    b = _SCRATCH
    CSP 133, d#, 103, prec, b
    ' (a C string): copied, 0.5 -> .5, e -> E
    n = 0
    DO WHILE PEEKB(b + n) <> 0 AND n < 40
        n = n + 1
    LOOP
    t = _TALLOC(n + 1)
    o = 0
    neg = PEEKB(b) = 45
    IF NOT neg THEN
        o = 1
        POKEB t + 1, 32
    END IF
    FOR i = 0 TO n - 1
        c = PEEKB(b + i)
        IF c = 48 AND PEEKB(b + i + 1) = 46 AND (i = 0 OR (i = 1 AND neg)) THEN
            ' the 0 of 0.5
        ELSE
            IF c = 101 THEN c = 69
            o = o + 1
            POKEB t + o, c
        END IF
    NEXT i
    POKEB t, o
    _FMTD = t
END FUNCTION

FUNCTION _STRS (x!)
    _STRS = _FMTD(x!, 7)
END FUNCTION

FUNCTION _STRD (x#)
    _STRD = _FMTD(x#, 15)
END FUNCTION

SUB _PSNG (ch, x!)
    _PSTR ch, _FMTD(x!, 7)
    _PSPC ch, 1
END SUB

SUB _PDBL (ch, x#)
    _PSTR ch, _FMTD(x#, 15)
    _PSPC ch, 1
END SUB



' VAL: the number at the start of s (blanks skipped; &H hexadecimal; D as E)
FUNCTION _VAL# (s)
    DIM b, n, i, c, j, r#, v, d, k
    n = _SLEN(s)
    i = 1
    DO WHILE i <= n
        IF PEEKB(s + i) <> 32 THEN EXIT DO
        i = i + 1
    LOOP
    IF i < n THEN
        IF PEEKB(s + i) = 38 AND (PEEKB(s + i + 1) OR 32) = 104 THEN
            v = 0
            FOR k = i + 2 TO n
                c = PEEKB(s + k) OR 32
                IF c >= 48 AND c <= 57 THEN
                    d = c - 48
                ELSEIF c >= 97 AND c <= 102 THEN
                    d = c - 87
                ELSE
                    EXIT FOR
                END IF
                v = ((v AND &HFFF) * 16) OR d
            NEXT k
            _VAL# = v
            EXIT FUNCTION
        END IF
    END IF
    b = _SCRATCH
    j = 0
    DO WHILE i <= n AND j < 70
        c = PEEKB(s + i)
        IF c = 68 OR c = 100 THEN c = 69
        POKEB b + j, c
        j = j + 1
        i = i + 1
    LOOP
    POKEB b + j, 0
    n = CSP%(135, b, VARPTR(r#))
    _VAL# = r#
END FUNCTION

' CINT of a double: rounded, half away from 0
FUNCTION _DCINT (d#)
    IF d# >= 0 THEN d# = d# + .5# ELSE d# = d# - .5#
    IF d# >= 32768# OR d# <= -32769# THEN _RTERR 6
    _DCINT = CSP%(109, d#)
END FUNCTION

FUNCTION _FIXD# (d#)
    IF d# >= 0 THEN _FIXD# = CSP#(124, d#) ELSE _FIXD# = CSP#(125, d#)
END FUNCTION

FUNCTION _FIXS! (x!)
    _FIXS! = _FIXD#(x!)
END FUNCTION

FUNCTION _INTS! (x!)
    DIM d#
    d# = x!
    _INTS! = CSP#(124, d#)
END FUNCTION

FUNCTION _SGNI (v)
    IF v > 0 THEN _SGNI = 1 ELSE IF v < 0 THEN _SGNI = -1
END FUNCTION

FUNCTION _SGNS (x!)
    IF x! > 0 THEN _SGNS = 1 ELSE IF x! < 0 THEN _SGNS = -1
END FUNCTION

FUNCTION _SGND (x#)
    IF x# > 0 THEN _SGND = 1 ELSE IF x# < 0 THEN _SGND = -1
END FUNCTION

FUNCTION _TANS! (x!)
    DIM d#
    d# = x!
    _TANS! = CSP#(115, d#)
END FUNCTION

' RND: the next of the generator, 0 <= RND < 1
FUNCTION _RND! ()
    _SEED# = CSP#(127, _SEED# * 16598013# + 12820163#, 16777216#)
    _RND! = _SEED# / 16777216#
END FUNCTION

SUB _RANDOMIZE (n)
    _SEED# = n + 32768#
END SUB

' TIMER: seconds (the P-machine's clock counts 60ths)
FUNCTION _TIMER! ()
    DIM hi, lo, d#
    CSP 9, VARPTR(hi), VARPTR(lo)
    d# = hi * 65536# + lo
    IF lo < 0 THEN d# = d# + 65536#
    _TIMER! = d# / 60
END FUNCTION

' FRE(x): the words free; FRE(-1): the fewest there have been
FUNCTION _FRE (x)
    DIM m
    m = CSP%(40)
    IF m < _MINFREE OR _MINFREE = 0 THEN _MINFREE = m
    IF x = -1 THEN _FRE = _MINFREE ELSE _FRE = m
END FUNCTION
