' RTINPUT -- the run-time library: the console's input, INPUT, LINE INPUT,
' INKEY$, CLS, LOCATE, COMMAND$
#INCLUDE "RTCOM"

FUNCTION _CONRAW ()
    DIM c
    _CONFLUSH
    CSP 5, 2, VARPTR(c), 0, 1, 0, 0
    _CONRAW = c AND 255
END FUNCTION

SUB _ECHO (c)
    DIM b
    b = c
    CSP 6, 1, VARPTR(b), 0, 1, 0, 0
END SUB

' a line typed at the console into _INBUF (a Pascal string); backspace
' rubs out
SUB _CONLINE ()
    DIM c, n
    n = 0
    DO
        c = _CONRAW
        IF c = 8 OR c = 127 THEN
            IF n > 0 THEN
                n = n - 1
                _ECHO 8
                _ECHO 32
                _ECHO 8
            END IF
        ELSEIF c = 13 OR c = 10 THEN
            _ECHO 13
            EXIT DO
        ELSEIF c >= 32 AND n < 250 THEN
            n = n + 1
            POKEB _INBUF + n, c
            _ECHO c
        END IF
    LOOP
    POKEB _INBUF, n
    _CONCOL = 0
END SUB

' the console as a file (CONSOLE:): its next character
FUNCTION _CONGETC ()
    STATIC inpos
    IF inpos = 0 THEN
        _CONLINE
        inpos = 1
    END IF
    IF inpos > PEEKB(_INBUF) THEN
        inpos = 0
        _CONGETC = 13
    ELSE
        _CONGETC = PEEKB(_INBUF + inpos)
        inpos = inpos + 1
    END IF
END FUNCTION

FUNCTION _LINPUT (ch, prompt)
    DIM t, n
    IF ch <> 0 THEN
        _LINPUT = _FLINE(ch)
        EXIT FUNCTION
    END IF
    _PSTR 0, prompt
    _CONLINE
    n = PEEKB(_INBUF)
    IF n = 0 THEN EXIT FUNCTION
    t = _TALLOC(n)
    CSP 2, _INBUF + 1, 0, t + 1, 0, n
    _LINPUT = t
END FUNCTION

DECLARE FUNCTION _FLINE (ch)

' INPUT: the line, then each variable takes the next field
SUB _INPUT (ch, prompt, qm)
    DIM t, n
    IF ch = 0 THEN
        _PSTR 0, prompt
        IF qm THEN _PSTR 0, SADD("? ")
        _CONLINE
    ELSE
        t = _FLINE(ch)
        n = _SLEN(t)
        POKEB _INBUF, n
        IF n THEN CSP 2, t + 1, 0, _INBUF + 1, 0, n
    END IF
    _INPOS = 1
END SUB

' the next field of the INPUT line: up to a comma; "quoted" kept whole
FUNCTION _INFS ()
    DIM n, s, e, t
    n = PEEKB(_INBUF)
    DO WHILE _INPOS <= n
        IF PEEKB(_INBUF + _INPOS) <> 32 THEN EXIT DO
        _INPOS = _INPOS + 1
    LOOP
    IF _INPOS <= n AND PEEKB(_INBUF + _INPOS) = 34 THEN
        s = _INPOS + 1
        e = s
        DO WHILE e <= n
            IF PEEKB(_INBUF + e) = 34 THEN EXIT DO
            e = e + 1
        LOOP
        _INPOS = e + 1
        DO WHILE _INPOS <= n
            IF PEEKB(_INBUF + _INPOS) = 44 THEN EXIT DO
            _INPOS = _INPOS + 1
        LOOP
    ELSE
        s = _INPOS
        DO WHILE _INPOS <= n
            IF PEEKB(_INBUF + _INPOS) = 44 THEN EXIT DO
            _INPOS = _INPOS + 1
        LOOP
        e = _INPOS
        DO WHILE e > s
            IF PEEKB(_INBUF + e - 1) <> 32 THEN EXIT DO
            e = e - 1
        LOOP
    END IF
    _INPOS = _INPOS + 1
    IF e > s THEN
        t = _TALLOC(e - s)
        CSP 2, _INBUF + s, 0, t + 1, 0, e - s
        _INFS = t
    END IF
END FUNCTION

FUNCTION _INFD# ()
    DIM t
    t = _TTOP
    _INFD# = _VAL#(_INFS)
    _TTOP = t
END FUNCTION

FUNCTION _INFI ()
    DIM d#, t
    t = _TTOP
    d# = _VAL#(_INFS)
    _TTOP = t
    _INFI = d#
END FUNCTION

' INKEY$: a key that is waiting, or ""
FUNCTION _INKEY ()
    DIM t
    _CONFLUSH
    IF CSP%(35, 2) <> 0 THEN
        t = _TALLOC(1)
        POKEB t + 1, _CONRAW
        _INKEY = t
    END IF
END FUNCTION

SUB _CLS ()
    _CONFLUSH
    OSCALL 37
    _CONCOL = 0
END SUB

' LOCATE row, column (from 1)
SUB _LOCATE (r, c)
    _CONFLUSH
    IF r < 1 THEN r = 1
    IF c < 1 THEN c = 1
    OSCALL 29, c - 1, r - 1
    _CONCOL = c - 1
END SUB

' COMMAND$: the command line Tiny-C's shell gave (pexec), without the
' program's name: kept by the operating system in its prompt line PL while SYSCOM's expansion words
' say so; else ""
FUNCTION _CMD ()
    STATIC got, cline
    DIM e, pl, n, sum, i, t
    IF got = 0 THEN
        ' the first time: taken while this is the program pexec started
        ' (EXPANSION[0] = PX_CHILD) and PL holds its line (EXPANSION[6] =
        ' PX_ARGS, [7] its checksum)
        got = 1
        e = OSVAR(1) + 36
        pl = OSADDR(70)
        n = PEEKB(pl)
        IF PEEK(e) = 25602 AND PEEK(e + 12) = 25604 AND n <= 80 THEN
            sum = n
            FOR i = 1 TO n
                sum = sum * 3 + PEEKB(pl + i)
            NEXT i
            IF PEEK(e + 14) = _XOR(sum, &H5A5A) THEN
                POKE e + 12, 0
                ' the shell's path after the arguments: not wanted here
                FOR i = 1 TO n
                    IF PEEKB(pl + i) = 30 THEN
                        n = i - 1
                        EXIT FOR
                    END IF
                NEXT i
                ' the first word is the program's name: not part of COMMAND$
                i = 1
                DO WHILE i <= n
                    IF PEEKB(pl + i) <> 32 THEN EXIT DO
                    i = i + 1
                LOOP
                DO WHILE i <= n
                    IF PEEKB(pl + i) = 32 THEN EXIT DO
                    i = i + 1
                LOOP
                DO WHILE i <= n
                    IF PEEKB(pl + i) <> 32 THEN EXIT DO
                    i = i + 1
                LOOP
                n = n - i + 1
                IF n > 0 THEN
                    cline = _MALLOC(n + 1)
                    CSP 2, pl + i, 0, cline + 1, 0, n
                    POKEB cline, n
                END IF
            END IF
        END IF
    END IF
    _CMD = _STMP(cline)
END FUNCTION

DECLARE FUNCTION _XOR (a, b)
