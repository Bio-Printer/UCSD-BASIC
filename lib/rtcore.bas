' RTCORE -- the run-time library: start and end, errors, the heap, the
' string temporaries, string assignment, the console's output, PRINT,
' integer division, GOSUB
#INCLUDE "RTCOM"

CONST ARENA = 2048, GSMAX = 50, RESERVE = 500

' ---- unsigned comparison: a < b as 0..65535
FUNCTION _ULT (a, b)
    _ULT = (a + &H8000) < (b + &H8000)
END FUNCTION

' a block straight from the P-machine's heap (NEW), not to be given back
FUNCTION _NEWBLK (words)
    DIM np
    IF CSP%(40) < words + RESERVE THEN _RTERR 7
    CSP 1, VARPTR(np), words
    _NEWBLK = np
END FUNCTION

' ---- the start: the blocks the library keeps, then the heap's start
SUB _RTINIT ()
    DIM i
    _TBASE = _NEWBLK(ARENA \ 2)
    _TTOP = _TBASE
    _TEND = _TBASE + ARENA
    _GSBASE = _NEWBLK(GSMAX)
    _GSSP = 0
    _FREETAB = _NEWBLK(34)
    CSP 10, _FREETAB, 0, 68, 0
    _CONBUF = _NEWBLK(41)
    _INBUF = _NEWBLK(129)
    _FTAB = _NEWBLK(256)
    CSP 10, _FTAB, 0, 512, 0
    _ABUF = _NEWBLK(9)
    _AIXB = _NEWBLK(9)
    _SCRATCH = _NEWBLK(41)
    _SEED# = 327680
    ' everything above this is the heap of the program's strings and arrays
    i = _NEWBLK(1)
    _HEAPLO = i
    _HEAPTOP = i + 2
END SUB

' ---- the end
SUB _HALT (code)
    _CLOSE 0
    _CONFLUSH
    CSP 4, 1, 1
END SUB

' ---- errors
SUB _ERRTEXT (code)
    DIM m
    SELECT CASE code
    CASE 3: m = SADD("RETURN without GOSUB")
    CASE 5: m = SADD("Illegal function call")
    CASE 6: m = SADD("Overflow")
    CASE 7: m = SADD("Out of memory")
    CASE 9: m = SADD("Subscript out of range")
    CASE 10: m = SADD("Array already dimensioned")
    CASE 11: m = SADD("Division by zero")
    CASE 13: m = SADD("Type mismatch")
    CASE 14: m = SADD("Out of string space")
    CASE 15: m = SADD("String too long")
    CASE 16: m = SADD("GOSUB nesting too deep")
    CASE 52: m = SADD("Bad file number")
    CASE 53: m = SADD("File not found")
    CASE 54: m = SADD("Bad file mode")
    CASE 55: m = SADD("File already open")
    CASE 57: m = SADD("Device I/O error")
    CASE 61: m = SADD("Disk full")
    CASE 62: m = SADD("Input past end of file")
    CASE 67: m = SADD("Too many files")
    CASE ELSE: m = SADD("Error")
    END SELECT
    _PSTR 0, m
END SUB

SUB _RTERR (code)
    _CONFLUSH
    _CONPUT 13
    _PSTR 0, SADD("Run-time error ")
    _PSTR 0, _ISTR(code, 0)
    _PSTR 0, SADD(": ")
    _ERRTEXT code
    _CONPUT 13
    _CONFLUSH
    _CLOSE 0
    CSP 4, 1, 1
END SUB

' an I/O error: ERR with ON ERROR RESUME NEXT, else the program stops
SUB _IOERR (code)
    IF _ERRTRAP THEN
        _ERRCODE = code
    ELSE
        _RTERR code
    END IF
END SUB

SUB _ONERR (onoff)
    _ERRTRAP = onoff
    _ERRCODE = 0
END SUB

FUNCTION _ERRNO ()
    _ERRNO = _ERRCODE
END FUNCTION

' ---- the heap: blocks of up to 132 words in lists by size (multiples of 4
' words), bigger ones in one list (best fit).  The word before a block
' holds its size in words (with that word); a free block's first word links.

FUNCTION _MALLOC (nbytes)
    DIM w, c, p, prev, best, bprev, np
    w = (nbytes + 1) \ 2 + 1
    IF w <= 132 THEN
        w = ((w + 3) \ 4) * 4
        c = _FREETAB + (w \ 4) * 2
        p = PEEK(c)
        IF p THEN
            POKE c, PEEK(p)
            _MALLOC = p
            EXIT FUNCTION
        END IF
    ELSE
        p = _BIGFREE
        DO WHILE p
            IF PEEK(p - 2) >= w THEN
                IF best = 0 THEN
                    best = p
                    bprev = prev
                ELSEIF PEEK(p - 2) < PEEK(best - 2) THEN
                    best = p
                    bprev = prev
                END IF
            END IF
            prev = p
            p = PEEK(p)
        LOOP
        IF best THEN
            IF bprev THEN POKE bprev, PEEK(best) ELSE _BIGFREE = PEEK(best)
            _MALLOC = best
            EXIT FUNCTION
        END IF
    END IF
    np = _NEWBLK(w)
    POKE np, w
    _HEAPTOP = np + w * 2
    _MALLOC = np + 2
END FUNCTION

SUB _MFREE (p)
    DIM w, c
    IF p = 0 THEN EXIT SUB
    w = PEEK(p - 2)
    IF w <= 132 THEN
        c = _FREETAB + (w \ 4) * 2
        POKE p, PEEK(c)
        POKE c, p
    ELSE
        POKE p, _BIGFREE
        _BIGFREE = p
    END IF
END SUB

' does p point at a string block a variable owns (on the heap)
FUNCTION _OWNED (p)
    IF p = 0 THEN EXIT FUNCTION
    IF _ULT(p, _HEAPLO) THEN EXIT FUNCTION
    _OWNED = _ULT(p, _HEAPTOP)
END FUNCTION

' ---- string temporaries

' room for a string of n characters in the arena (the length byte set)
FUNCTION _TALLOC (n)
    DIM t
    IF n > 255 THEN _RTERR 15
    t = _TTOP
    _TTOP = t + ((n + 2) AND &HFFFE)
    IF _ULT(_TEND, _TTOP) THEN
        _TTOP = t
        _RTERR 14
    END IF
    POKEB t, n
    _TALLOC = t
END FUNCTION

' a copy of string p in the arena (a BYVAL argument)
FUNCTION _STMP (p)
    DIM n, t
    IF p = 0 THEN EXIT FUNCTION
    n = PEEKB(p)
    IF n = 0 THEN EXIT FUNCTION
    t = _TALLOC(n)
    CSP 2, p + 1, 0, t + 1, 0, n
    _STMP = t
END FUNCTION

FUNCTION _SLEN (p)
    IF p THEN _SLEN = PEEKB(p)
END FUNCTION

' ---- string variables

' slot := v (a copy in the variable's own block)
SUB _SASG (slot, v)
    DIM n, old, cap, nw
    IF v THEN n = PEEKB(v)
    old = PEEK(slot)
    IF old = v AND _OWNED(old) THEN EXIT SUB
    IF _OWNED(old) THEN
        cap = (PEEK(old - 2) - 1) * 2 - 1
        IF cap >= n THEN
            IF n = 0 THEN
                _MFREE old
                POKE slot, 0
                EXIT SUB
            END IF
            CSP 2, v + 1, 0, old + 1, 0, n
            POKEB old, n
            EXIT SUB
        END IF
    END IF
    nw = 0
    IF n > 0 THEN
        ' a little room to grow: strings that are added to
        IF old <> 0 AND n < 200 THEN nw = _MALLOC(n + 1 + n \ 2) ELSE nw = _MALLOC(n + 1)
        CSP 2, v + 1, 0, nw + 1, 0, n
        POKEB nw, n
    END IF
    IF _OWNED(old) THEN _MFREE old
    POKE slot, nw
END SUB

SUB _SFREE (slot)
    DIM v
    v = PEEK(slot)
    IF _OWNED(v) THEN _MFREE v
    POKE slot, 0
END SUB

' a FUNCTION's string result: a temporary, the variable given back
FUNCTION _SRET (slot)
    DIM v
    v = PEEK(slot)
    _SRET = _STMP(v)
    IF _OWNED(v) THEN _MFREE v
    POKE slot, 0
END FUNCTION

FUNCTION _SCAT (a, b)
    DIM la, lb, t
    IF a THEN la = PEEKB(a)
    IF b THEN lb = PEEKB(b)
    IF la + lb > 255 THEN _RTERR 15
    t = _TALLOC(la + lb)
    IF la THEN CSP 2, a + 1, 0, t + 1, 0, la
    IF lb THEN CSP 2, b + 1, 0, t + 1 + la, 0, lb
    _SCAT = t
END FUNCTION

' -1, 0, 1 as a < b, a = b, a > b
FUNCTION _SCMP (a, b)
    DIM la, lb, n, i, ca, cb
    IF a THEN la = PEEKB(a)
    IF b THEN lb = PEEKB(b)
    n = la
    IF lb < n THEN n = lb
    FOR i = 1 TO n
        ca = PEEKB(a + i)
        cb = PEEKB(b + i)
        IF ca <> cb THEN
            IF ca < cb THEN _SCMP = -1 ELSE _SCMP = 1
            EXIT FUNCTION
        END IF
    NEXT i
    IF la < lb THEN
        _SCMP = -1
    ELSEIF la > lb THEN
        _SCMP = 1
    END IF
END FUNCTION

' ---- integers

' a / b of 0..65535
FUNCTION _UDIV (a, b)
    DIM q, r
    IF b < 0 THEN
        IF _ULT(a, b) THEN _UDIV = 0 ELSE _UDIV = 1
        EXIT FUNCTION
    END IF
    IF a >= 0 THEN
        _UDIV = DVI%(a, b)
        EXIT FUNCTION
    END IF
    q = DVI%(DVI%(a AND 32767, 2) + 16384, b)
    q = q + q
    r = a - q * b
    IF NOT _ULT(r, b) THEN q = q + 1
    _UDIV = q
END FUNCTION

' \ : rounded toward 0
FUNCTION _DIVI (a, b)
    DIM neg, q
    IF b = 0 THEN _RTERR 11
    IF a < 0 THEN
        a = -a
        neg = 1
    END IF
    IF b < 0 THEN
        b = -b
        neg = 1 - neg
    END IF
    q = _UDIV(a, b)
    IF neg THEN _DIVI = -q ELSE _DIVI = q
END FUNCTION

' MOD: the sign of a
FUNCTION _MODI (a, b)
    _MODI = a - _DIVI(a, b) * b
END FUNCTION

FUNCTION _XOR (a, b)
    _XOR = (a OR b) AND NOT (a AND b)
END FUNCTION

' an integer as text: lead 1 = a blank before one that is not negative
FUNCTION _ISTR (v, lead)
    DIM b, i, n, neg, d, t
    b = _SCRATCH + 40
    i = 0
    neg = v < 0
    DO
        d = v - _DIVI(v, 10) * 10
        IF d < 0 THEN d = -d
        POKEB b - i, 48 + d
        i = i + 1
        v = _DIVI(v, 10)
    LOOP WHILE v <> 0
    IF neg THEN
        POKEB b - i, 45
        i = i + 1
    ELSEIF lead THEN
        POKEB b - i, 32
        i = i + 1
    END IF
    t = _TALLOC(i)
    CSP 2, b - i + 1, 0, t + 1, 0, i
    _ISTR = t
END FUNCTION

' ---- GOSUB / RETURN: the return points' numbers
SUB _GSPUSH (k)
    IF _GSSP >= GSMAX THEN _RTERR 16
    POKE _GSBASE + _GSSP * 2, k
    _GSSP = _GSSP + 1
END SUB

FUNCTION _GSPOP ()
    IF _GSSP <= 0 THEN _RTERR 3
    _GSSP = _GSSP - 1
    _GSPOP = PEEK(_GSBASE + _GSSP * 2)
END FUNCTION

' ---- the console's output: a line at a time (UNITWRITE to unit 1)
SUB _CONFLUSH ()
    IF _CONLEN > 0 THEN
        CSP 6, 1, _CONBUF, 0, _CONLEN, 0, 0
        _CONLEN = 0
    END IF
END SUB

SUB _CONPUT (c)
    POKEB _CONBUF + _CONLEN, c
    _CONLEN = _CONLEN + 1
    IF c = 13 THEN
        _CONCOL = 0
        _CONFLUSH
    ELSE
        _CONCOL = _CONCOL + 1
        IF _CONLEN >= 80 THEN _CONFLUSH
    END IF
END SUB

' ---- PRINT: ch 0 is the console
SUB _PSTR (ch, s)
    DIM i, n
    IF s = 0 THEN EXIT SUB
    n = PEEKB(s)
    IF ch = 0 THEN
        FOR i = 1 TO n
            _CONPUT PEEKB(s + i)
        NEXT i
    ELSE
        FOR i = 1 TO n
            _FPUTC ch, PEEKB(s + i)
        NEXT i
    END IF
END SUB

SUB _PNL (ch)
    IF ch = 0 THEN _CONPUT 13 ELSE _FPUTC ch, 13
END SUB

SUB _PINT (ch, v)
    _PSTR ch, _ISTR(v, 1)
    IF ch = 0 THEN _CONPUT 32 ELSE _FPUTC ch, 32
END SUB

' the column (from 0) of the console or a file
FUNCTION _COL (ch)
    IF ch = 0 THEN _COL = _CONCOL ELSE _COL = PEEK(_FENTRY(ch) + FCOL)
END FUNCTION

FUNCTION _POS (x)
    _POS = _CONCOL + 1
END FUNCTION

SUB _PSPC (ch, n)
    DIM i
    FOR i = 1 TO n
        IF ch = 0 THEN _CONPUT 32 ELSE _FPUTC ch, 32
    NEXT i
END SUB

SUB _PCOMMA (ch)
    DO
        _PSPC ch, 1
    LOOP WHILE _COL(ch) MOD 14 <> 0
END SUB

' TAB(n): to column n (from 1), on the next line if it is passed
SUB _PTAB (ch, n)
    IF _COL(ch) >= n - 1 THEN _PNL ch
    DO WHILE _COL(ch) < n - 1
        _PSPC ch, 1
    LOOP
END SUB
