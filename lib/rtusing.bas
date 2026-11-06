' RTUSING -- the run-time library: PRINT USING and USING$ (QuickBASIC's
' format)
'
' _USTART fmt$ takes the format (a copy: the statement's temporaries go
' after each item); each item then _UNUM x! or _USTR s$: the format's
' text up to its next field goes into the line being made (_UOUT), then the
' item in that field (after its last field the format starts again);
' _UEND: the text up to the next field, and the line (a temporary).
'   numbers  # a digit, . the point, , (before the point) thousands
'            separated, + first or last: the sign, - last: a minus,
'            $$ a $ before the digits, ** the blanks before them *, **$
'            both, ^^^^ (or ^^^^^) an exponent; too large for its field:
'            % before the number
'   strings  ! the first character, & all of it, \  \ as many as the
'            field is wide (2 and the blanks between)
'   _c       the character c as it is; every other character as it is
' In the segment RTUSING: in memory only while a line is made.
#INCLUDE "RTCOM"

DECLARE FUNCTION _SCAT (a, b)
DECLARE FUNCTION _CHR (c)
DECLARE FUNCTION _SUBSTR (s, st, n)
DECLARE FUNCTION _STRNG (n, c)
DECLARE SUB _SFREE (slot)

' the format (a slot: a variable's own block), the next character of it,
' the line made (a slot), whether the format has a field
DIM SHARED _UFMT, _UPOS, _UOUT, _UANY

SEGMENT RTUSING

' the format's character at i
FUNCTION _UCH (i)
    IF i < 1 OR i > _SLEN(_UFMT) THEN EXIT FUNCTION
    _UCH = PEEKB(_SDAT(_UFMT) + i)
END FUNCTION

' s$ (a temporary or any string) after the line
SUB _UADD (s)
    _SASGN VARPTR(_UOUT), _SCAT(_UOUT, s), 32000
END SUB

SUB _UADDC (c)
    _UADD _CHR(c)
END SUB

' n characters c after the line
SUB _UADDN (n, c)
    IF n > 0 THEN _UADD _STRNG(n, c)
END SUB

' the kind of field at i: 0 none, 1 a number's, 2 a string's
FUNCTION _UFIELD (i)
    DIM c, d, j
    c = _UCH(i)
    d = _UCH(i + 1)
    SELECT CASE c
    CASE 35
        _UFIELD = 1
    CASE 46
        IF d = 35 THEN _UFIELD = 1
    CASE 43
        IF d = 35 OR d = 36 OR d = 42 OR (d = 46 AND _UCH(i + 2) = 35) THEN _UFIELD = 1
    CASE 36
        IF d = 36 THEN _UFIELD = 1
    CASE 42
        IF d = 42 THEN _UFIELD = 1
    CASE 33, 38
        _UFIELD = 2
    CASE 92
        j = i + 1
        DO WHILE _UCH(j) = 32
            j = j + 1
        LOOP
        IF _UCH(j) = 92 THEN _UFIELD = 2
    END SELECT
END FUNCTION

' the format's text up to its next field into the line; at its end, from
' its start again (want: a field is needed) -- 0 if it has none
FUNCTION _ULIT (want)
    DIM c, n, wrapped
    n = _SLEN(_UFMT)
    DO
        IF _UPOS > n THEN
            IF want = 0 OR wrapped OR _UANY = 0 THEN EXIT FUNCTION
            _UPOS = 1
            wrapped = 1
        END IF
        IF _UFIELD(_UPOS) THEN
            _ULIT = _UFIELD(_UPOS)
            _UANY = 1
            EXIT FUNCTION
        END IF
        c = _UCH(_UPOS)
        IF c = 95 AND _UPOS < n THEN
            _UPOS = _UPOS + 1
            c = _UCH(_UPOS)
        END IF
        _UADDC c
        _UPOS = _UPOS + 1
    LOOP
END FUNCTION

SUB _USTART (fmt)
    DIM i
    _SASGN VARPTR(_UFMT), fmt, 32000
    _SFREE VARPTR(_UOUT)
    _UPOS = 1
    _UANY = 0
    FOR i = 1 TO _SLEN(_UFMT)
        IF _UFIELD(i) THEN _UANY = 1
    NEXT i
    IF _UANY = 0 THEN _RTERR 5
END SUB

' a string in the next field
SUB _USTR (s)
    DIM c, j, w, n
    IF _ULIT(1) <> 2 THEN _RTERR 13
    c = _UCH(_UPOS)
    n = _SLEN(s)
    IF c = 33 THEN
        IF n > 0 THEN _UADD _SUBSTR(s, 1, 1) ELSE _UADDC 32
        _UPOS = _UPOS + 1
    ELSEIF c = 38 THEN
        _UADD s
        _UPOS = _UPOS + 1
    ELSE
        j = _UPOS + 1
        DO WHILE _UCH(j) = 32
            j = j + 1
        LOOP
        w = j - _UPOS + 1
        IF n >= w THEN
            _UADD _SUBSTR(s, 1, w)
        ELSE
            _UADD s
            _UADDN w - n, 32
        END IF
        _UPOS = j + 1
    END IF
END SUB

' the text CSP 133 makes of d! (fmt 101 e, 102 f; prec digits): a temporary
FUNCTION _UTXT (d!, fmt, prec)
    DIM b, n, t
    b = _SCRATCH
    CSP 133, d!, fmt, prec, b
    n = 0
    DO WHILE PEEKB(b + n) <> 0 AND n < 40
        n = n + 1
    LOOP
    t = _TALLOC(n)
    IF n THEN CSP 2, b, 0, t + 1, 0, n
    _UTXT = t
END FUNCTION

' x! (0 or more) rounded to k decimals, a half up (BASIC's: C's text of
' 9.25 is 9.2, a half to even); not one too large for it to matter
FUNCTION _URND! (x!, k)
    DIM f!
    f! = 10! ^ k
    IF x! * f! < 1E+15! THEN _URND! = INT(x! * f! + .5!) / f! ELSE _URND! = x!
END FUNCTION

' a number in the next field
SUB _UNUM (x!)
    DIM p, c, signlead, signtrail, stars, dollar, ndig, comma, dec, expo, neg
    DIM ip, t, i, k, e, m!, w, body, lead, fill
    IF _ULIT(1) <> 1 THEN _RTERR 13
    p = _UPOS
    ' the field: [+] [** | $$ | **$] #,# [. #] [^^^^] [+ | -]
    IF _UCH(p) = 43 THEN
        signlead = 1
        p = p + 1
    END IF
    IF _UCH(p) = 42 AND _UCH(p + 1) = 42 THEN
        stars = 1
        ndig = 2
        p = p + 2
        IF _UCH(p) = 36 THEN
            dollar = 1
            p = p + 1
        END IF
    ELSEIF _UCH(p) = 36 AND _UCH(p + 1) = 36 THEN
        dollar = 1
        ndig = 1
        p = p + 2
    END IF
    DO
        c = _UCH(p)
        IF c = 35 THEN
            ndig = ndig + 1
        ELSEIF c = 44 THEN
            comma = 1
            ndig = ndig + 1
        ELSE
            EXIT DO
        END IF
        p = p + 1
    LOOP
    dec = -1
    IF _UCH(p) = 46 THEN
        dec = 0
        p = p + 1
        DO WHILE _UCH(p) = 35
            dec = dec + 1
            p = p + 1
        LOOP
    END IF
    IF _UCH(p) = 94 AND _UCH(p + 1) = 94 AND _UCH(p + 2) = 94 AND _UCH(p + 3) = 94 THEN
        expo = 2
        p = p + 4
        IF _UCH(p) = 94 THEN
            expo = 3
            p = p + 1
        END IF
    END IF
    IF signlead = 0 THEN
        IF _UCH(p) = 43 THEN
            signtrail = 1
            p = p + 1
        ELSEIF _UCH(p) = 45 THEN
            signtrail = 2
            p = p + 1
        END IF
    END IF
    _UPOS = p
    neg = x! < 0
    IF neg THEN x! = -x!
    k = dec
    IF k < 0 THEN k = 0
    IF expo THEN
        ' the digits before the point: those of the field (one for the
        ' sign without + or -)
        ip = ndig
        IF signlead = 0 AND signtrail = 0 AND ip > 1 THEN ip = ip - 1
        IF ip < 1 THEN ip = 1
        e = 0
        IF x! <> 0 THEN
            e = INT(LOG(x!) / LOG(10!)) - ip + 1
            m! = x! / 10! ^ e
            IF m! >= 10! ^ ip THEN
                m! = m! / 10!
                e = e + 1
            END IF
            IF m! < 10! ^ (ip - 1) THEN
                m! = m! * 10!
                e = e - 1
            END IF
        END IF
        m! = _URND!(m!, k)
        t = _UTXT(m!, 102, k)
        ' (rounding made it a digit longer)
        IF _SLEN(t) - k + (k > 0) > ip THEN
            m! = m! / 10!
            e = e + 1
            t = _UTXT(m!, 102, k)
        END IF
        IF dec = 0 THEN t = _SCAT(t, SADD("."))
        IF e < 0 THEN t = _SCAT(t, SADD("E-")) ELSE t = _SCAT(t, SADD("E+"))
        e = ABS(e)
        IF expo = 3 THEN t = _SCAT(t, _CHR(48 + (e \ 100) MOD 10))
        t = _SCAT(t, _CHR(48 + (e \ 10) MOD 10))
        t = _SCAT(t, _CHR(48 + e MOD 10))
    ELSE
        t = _UTXT(_URND!(x!, k), 102, k)
        IF dec = 0 THEN t = _SCAT(t, SADD("."))
        ' (the point's place: the digits before it)
        ip = _SLEN(t)
        IF dec >= 0 THEN ip = ip - dec - 1
        ' 0.5 in a field with no digits before the point: .5
        IF ip = 1 AND ndig = 0 AND _UCH2(t, 1) = 48 THEN
            t = _SUBSTR(t, 2, _SLEN(t) - 1)
            ip = 0
        END IF
        IF comma AND ip > 3 THEN
            ' the thousands separated
            body = _SUBSTR(t, 1, ip)
            t = _SUBSTR(t, ip + 1, _SLEN(t) - ip)
            i = ip
            DO WHILE i > 3
                t = _SCAT(_SCAT(SADD(","), _SUBSTR(body, i - 2, 3)), t)
                i = i - 3
            LOOP
            t = _SCAT(_SUBSTR(body, 1, i), t)
        END IF
    END IF
    ' the sign
    IF signlead THEN
        IF neg THEN lead = 45 ELSE lead = 43
    ELSEIF neg AND signtrail = 0 THEN
        lead = 45
    END IF
    IF lead THEN t = _SCAT(_CHR(lead), t)
    IF dollar THEN t = _SCAT(SADD("$"), t)
    ' the field's width before the point (and the point, the decimals, the
    ' exponent): the number padded to it, or too large: %
    w = ndig + signlead + dollar
    IF dec >= 0 THEN w = w + dec + 1
    IF expo THEN w = w + expo + 2
    fill = 32
    IF stars THEN fill = 42
    IF _SLEN(t) > w THEN
        _UADDC 37
    ELSE
        _UADDN w - _SLEN(t), fill
    END IF
    _UADD t
    IF signtrail = 1 THEN
        IF neg THEN _UADDC 45 ELSE _UADDC 43
    ELSEIF signtrail = 2 THEN
        IF neg THEN _UADDC 45 ELSE _UADDC 32
    END IF
END SUB

' the i-th character of the string t
FUNCTION _UCH2 (t, i)
    IF i >= 1 AND i <= _SLEN(t) THEN _UCH2 = PEEKB(_SDAT(t) + i)
END FUNCTION

' the end: the format's text up to its next field; the line (a temporary)
FUNCTION _UEND ()
    DIM k
    k = _ULIT(0)
    _UEND = _STMP(_UOUT)
    _SFREE VARPTR(_UOUT)
END FUNCTION
