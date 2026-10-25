' RTDATA -- the run-time library: DATA, READ, RESTORE; WRITE's strings
'
' Each module's body gives its DATA statements (their text, as written)
' to the list here when it starts; READ takes the next item (a quoted
' string, or the text up to the next comma, without blanks around it).
#INCLUDE "RTCOM"

COMMON SHARED _DLIST, _DCOUNT, _DCAP, _DSTMT, _DPOS

' the number the next module's first DATA statement gets
FUNCTION _DMARK ()
    _DMARK = _DCOUNT
END FUNCTION

SUB _DATA (s)
    DIM nl
    IF _DCOUNT >= _DCAP THEN
        nl = _MALLOC((_DCAP + 16) * 2)
        IF _DCAP THEN
            CSP 2, _DLIST, 0, nl, 0, _DCAP * 2
            _MFREE _DLIST
        END IF
        _DLIST = nl
        _DCAP = _DCAP + 16
    END IF
    POKE _DLIST + _DCOUNT * 2, s
    _DCOUNT = _DCOUNT + 1
END SUB

SUB _RESTORE (k)
    _DSTMT = k
    _DPOS = 0
END SUB

' the next item (a temporary)
FUNCTION _READ ()
    DIM s, n, b, e, t
    DO
        IF _DSTMT >= _DCOUNT THEN _RTERR 4
        s = PEEK(_DLIST + _DSTMT * 2)
        n = PEEKB(s)
        IF _DPOS = 0 THEN _DPOS = 1
        IF _DPOS <= n + 1 THEN EXIT DO
        _DSTMT = _DSTMT + 1
        _DPOS = 0
    LOOP
    DO WHILE _DPOS <= n
        IF PEEKB(s + _DPOS) <> 32 THEN EXIT DO
        _DPOS = _DPOS + 1
    LOOP
    IF _DPOS <= n AND PEEKB(s + _DPOS) = 34 THEN
        b = _DPOS + 1
        e = b
        DO WHILE e <= n
            IF PEEKB(s + e) = 34 THEN EXIT DO
            e = e + 1
        LOOP
        _DPOS = e + 1
        DO WHILE _DPOS <= n
            IF PEEKB(s + _DPOS) = 44 THEN EXIT DO
            _DPOS = _DPOS + 1
        LOOP
    ELSE
        b = _DPOS
        DO WHILE _DPOS <= n
            IF PEEKB(s + _DPOS) = 44 THEN EXIT DO
            _DPOS = _DPOS + 1
        LOOP
        e = _DPOS
        DO WHILE e > b
            IF PEEKB(s + e - 1) <> 32 THEN EXIT DO
            e = e - 1
        LOOP
    END IF
    ' past the comma; after the last item, the next statement
    _DPOS = _DPOS + 1
    IF _DPOS > n + 1 THEN
        _DSTMT = _DSTMT + 1
        _DPOS = 0
    END IF
    IF e > b THEN
        t = _TALLOC(e - b)
        CSP 2, s + b, 0, t + 1, 0, e - b
        _READ = t
    END IF
END FUNCTION

' WRITE: a string in quotes
SUB _WQSTR (ch, s)
    _PSTR ch, SADD(CHR$(34))
    _PSTR ch, s
    _PSTR ch, SADD(CHR$(34))
END SUB
