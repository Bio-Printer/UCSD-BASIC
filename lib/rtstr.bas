' RTSTR -- the run-time library: string functions (each returns a new
' temporary, or 0 for "")
#INCLUDE "RTCOM"

' a temporary copy of n characters of s from character st (1..)
FUNCTION _SUBSTR (s, st, n)
    DIM t
    IF n <= 0 THEN EXIT FUNCTION
    t = _TALLOC(n)
    CSP 2, s + st, 0, t + 1, 0, n
    _SUBSTR = t
END FUNCTION

FUNCTION _ASC (s, p)
    IF p < 1 OR p > _SLEN(s) THEN EXIT FUNCTION
    _ASC = PEEKB(s + p)
END FUNCTION

FUNCTION _CHR (c)
    DIM t
    t = _TALLOC(1)
    POKEB t + 1, c AND 255
    _CHR = t
END FUNCTION

FUNCTION _MID (s, st, n)
    DIM l
    IF st < 1 OR n < 0 THEN _RTERR 5
    l = _SLEN(s)
    IF st > l THEN EXIT FUNCTION
    IF n > l - st + 1 THEN n = l - st + 1
    _MID = _SUBSTR(s, st, n)
END FUNCTION

FUNCTION _LEFT (s, n)
    DIM l
    IF n < 0 THEN _RTERR 5
    l = _SLEN(s)
    IF n > l THEN n = l
    _LEFT = _SUBSTR(s, 1, n)
END FUNCTION

FUNCTION _RIGHT (s, n)
    DIM l
    IF n < 0 THEN _RTERR 5
    l = _SLEN(s)
    IF n > l THEN n = l
    _RIGHT = _SUBSTR(s, l - n + 1, n)
END FUNCTION

FUNCTION _INSTR (st, a, b)
    DIM la, lb, i, j, ok
    IF st < 1 THEN _RTERR 5
    la = _SLEN(a)
    lb = _SLEN(b)
    IF st > la THEN
        IF lb = 0 AND st = la + 1 THEN _INSTR = st
        EXIT FUNCTION
    END IF
    IF lb = 0 THEN
        _INSTR = st
        EXIT FUNCTION
    END IF
    FOR i = st - 1 TO la - lb
        ok = -1
        FOR j = 1 TO lb
            IF PEEKB(a + i + j) <> PEEKB(b + j) THEN
                ok = 0
                EXIT FOR
            END IF
        NEXT j
        IF ok THEN
            _INSTR = i + 1
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

' upper (up = 1) or lower case
FUNCTION _CASE (s, up)
    DIM t, i, c, n
    n = _SLEN(s)
    t = _SUBSTR(s, 1, n)
    FOR i = 1 TO n
        c = PEEKB(t + i)
        IF up THEN
            IF c >= 97 AND c <= 122 THEN POKEB t + i, c - 32
        ELSE
            IF c >= 65 AND c <= 90 THEN POKEB t + i, c + 32
        END IF
    NEXT i
    _CASE = t
END FUNCTION

FUNCTION _UCASE (s)
    _UCASE = _CASE(s, 1)
END FUNCTION

FUNCTION _LCASE (s)
    _LCASE = _CASE(s, 0)
END FUNCTION

FUNCTION _LTRIM (s)
    DIM i, n
    n = _SLEN(s)
    i = 1
    DO WHILE i <= n
        IF PEEKB(s + i) <> 32 THEN EXIT DO
        i = i + 1
    LOOP
    _LTRIM = _SUBSTR(s, i, n - i + 1)
END FUNCTION

FUNCTION _RTRIM (s)
    DIM n
    n = _SLEN(s)
    DO WHILE n > 0
        IF PEEKB(s + n) <> 32 THEN EXIT DO
        n = n - 1
    LOOP
    _RTRIM = _SUBSTR(s, 1, n)
END FUNCTION

FUNCTION _TRIM (s)
    _TRIM = _LTRIM(_RTRIM(s))
END FUNCTION

FUNCTION _STRNG (n, c)
    DIM t
    IF n < 0 THEN _RTERR 5
    IF n = 0 THEN EXIT FUNCTION
    t = _TALLOC(n)
    CSP 10, t + 1, 0, n, c AND 255
    _STRNG = t
END FUNCTION

FUNCTION _SPACE (n)
    _SPACE = _STRNG(n, 32)
END FUNCTION

FUNCTION _STRI (v)
    _STRI = _ISTR(v, 1)
END FUNCTION

' HEX$: 16 bits, no leading zeros
FUNCTION _HEX (v)
    DIM b, i, d, t
    b = _SCRATCH + 40
    DO
        d = v AND 15
        IF d < 10 THEN POKEB b - i, 48 + d ELSE POKEB b - i, 55 + d
        i = i + 1
        v = (v AND &HFFF0) \ 16
        IF v < 0 THEN v = v + 4096
    LOOP WHILE v <> 0
    t = _TALLOC(i)
    CSP 2, b - i + 1, 0, t + 1, 0, i
    _HEX = t
END FUNCTION

' MID$(s$, st, n) = v$: in the variable's own block
SUB _MIDSET (slot, st, n, v)
    DIM s, l, lv, i
    s = PEEK(slot)
    l = _SLEN(s)
    IF st < 1 OR st > l THEN _RTERR 5
    IF NOT _OWNED(s) THEN
        ' (a parameter's temporary): a block of its own first
        POKE slot, 0
        _SASG slot, s
        s = PEEK(slot)
    END IF
    lv = _SLEN(v)
    FOR i = 0 TO n - 1
        IF i >= lv OR st + i > l THEN EXIT FOR
        POKEB s + st + i, PEEKB(v + 1 + i)
    NEXT i
END SUB

' SWAP of two numbers: their n bytes
SUB _SWAP (a, b, n)
    DIM i, t
    FOR i = 0 TO n - 1
        t = PEEKB(a + i)
        POKEB a + i, PEEKB(b + i)
        POKEB b + i, t
    NEXT i
END SUB

SUB _SSWAP (a, b)
    DIM x, y, t
    x = PEEK(a)
    y = PEEK(b)
    IF (x = 0 OR _OWNED(x)) AND (y = 0 OR _OWNED(y)) THEN
        POKE a, y
        POKE b, x
        EXIT SUB
    END IF
    t = _STMP(x)
    _SASG a, y
    _SASG b, t
END SUB

' MKI$ MKS$ MKD$ and CVI CVS CVD: the bytes of a number
FUNCTION _MKN (addr, n)
    DIM t
    t = _TALLOC(n)
    CSP 2, addr, 0, t + 1, 0, n
    _MKN = t
END FUNCTION

FUNCTION _MKI (v)
    _MKI = _MKN(VARPTR(v), 2)
END FUNCTION

FUNCTION _MKS (x#)
    _MKS = _MKN(VARPTR(x#), 4)
END FUNCTION

FUNCTION _MKD (x!)
    _MKD = _MKN(VARPTR(x!), 8)
END FUNCTION

SUB _CVN (s, addr, n)
    DIM l
    CSP 10, addr, 0, n, 0
    l = _SLEN(s)
    IF l > n THEN l = n
    IF l > 0 THEN CSP 2, s + 1, 0, addr, 0, l
END SUB

FUNCTION _CVI (s)
    DIM v
    _CVN s, VARPTR(v), 2
    _CVI = v
END FUNCTION

FUNCTION _CVS# (s)
    DIM x#
    _CVN s, VARPTR(x#), 4
    _CVS# = x#
END FUNCTION

FUNCTION _CVD! (s)
    DIM x!
    _CVN s, VARPTR(x!), 8
    _CVD! = x!
END FUNCTION
