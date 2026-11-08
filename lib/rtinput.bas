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
' rubs out.  With <NAME on the command line, a line of that file
SUB _CONLINE ()
    DIM c, n
    n = 0
    IF _REDIR AND 2 THEN
        ' (redirected: a line of the file, not echoed; its end: error 62)
        c = _FGETC(CHRIN)
        IF c < 0 THEN _IOERR 62
        DO WHILE c >= 0 AND c <> 13
            IF c <> 10 AND n < 250 THEN
                n = n + 1
                POKEB _INBUF + n, c
            END IF
            c = _FGETC(CHRIN)
        LOOP
        POKEB _INBUF, n
        EXIT SUB
    END IF
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
DECLARE FUNCTION _FLINEN (ch, max)

' LINE INPUT into a LENGTH string of max characters: from a file up to
' max (the console's line is 255 at most)
FUNCTION _LINPUTN (ch, prompt, max)
    IF ch <> 0 THEN _LINPUTN = _FLINEN(ch, max) ELSE _LINPUTN = _LINPUT(ch, prompt)
END FUNCTION

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

FUNCTION _INFD! ()
    DIM t
    t = _TTOP
    _INFD! = _VAL!(_INFS)
    _TTOP = t
END FUNCTION

FUNCTION _INFI ()
    DIM d!, t
    t = _TTOP
    d! = _VAL!(_INFS)
    _TTOP = t
    _INFI = d!
END FUNCTION

' INKEY$: a key that is waiting, or ""
FUNCTION _INKEY ()
    DIM t, e, k
    _CONFLUSH
    k = CSP%(35, 2)
    IF k = 0 THEN
        ' the native P-Code engine (the emulator, the ucsd-pico firmware) answers UNITBUSY "not
        ' busy" always, and counts the keys waiting in SYSCOM^.EXPANSION[2] once EXPANSION[1]
        ' asks for it (PX_KEYS_AHEAD, 25609; it answers 25610): the first INKEY$ asks (and is
        ' ""), later ones read the count.  (Home, End, PgUp ... then come as one code each;
        ' _HALT puts the keys back.)  A key mode the program set (25605..25608) is left alone.
        e = PEEK(OSVAR(1) + 38)
        IF e < 25605 OR e > 25610 THEN
            POKE OSVAR(1) + 38, 25609
        ELSEIF e = 25610 THEN
            k = PEEK(OSVAR(1) + 40)
        END IF
    END IF
    IF k <> 0 THEN
        t = _TALLOC(1)
        POKEB t + 1, _CONRAW
        _INKEY = t
    END IF
END FUNCTION

' ---- SETPIN, PIN(), PIN() =: the RP2040's GPIO pins (MMBasic's), through the ucsd-pico
' firmware (UCSD-Pascal-on-RP2040 port/Gpio.h): TIME (CSP 9) with 25614 and the request
' op * 16384 + option * 4096 + arg * 256 + pin answers the status and the value.  The firmware
' is asked once whether it is there (its machine information: 25613, &H7C00 -> &H5250).
FUNCTION _PINREQ (op, opt, arg, p)
    STATIC fw
    DIM hi, lo
    IF fw = 0 THEN
        hi = 25613
        lo = &H7C00
        CSP 9, VARPTR(hi), VARPTR(lo)
        IF hi = &H5250 THEN fw = 1 ELSE fw = -1
    END IF
    IF fw < 0 THEN _RTERR 71
    IF p < 0 OR p > 255 OR arg < 0 OR arg > 15 OR opt < 0 OR opt > 3 THEN _RTERR 5
    hi = 25614
    lo = op * 16384 + opt * 4096 + arg * 256 + p
    CSP 9, VARPTR(hi), VARPTR(lo)
    IF hi = 4 THEN _RTERR 70
    IF hi <> 0 THEN _RTERR 5
    _PINREQ = lo
END FUNCTION

' SETPIN pin, cfg [, option]: cfg OFF 0, AIN 1, DIN 2, DOUT 3; option PULLUP 1, PULLDOWN 2
SUB _SETPIN (p, cfg, opt)
    DIM x
    x = _PINREQ(0, opt, cfg, p)
END SUB

' PIN(pin): a DIN pin's level, a DOUT pin's, an AIN pin's millivolts
FUNCTION _PIN (p)
    _PIN = _PINREQ(2, 0, 0, p)
END FUNCTION

' PIN(pin) = value: a DOUT pin's level (0, or 1 for any other)
SUB _PINSET (p, v)
    DIM x
    IF v <> 0 THEN v = 1
    x = _PINREQ(1, 0, v, p)
END SUB

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

' COMMAND$: the command line Tiny-C's shell gave, without the program's
' name (RTCORE's _ARGS took it at the start); else ""
FUNCTION _CMD ()
    _CMD = _STMP(_CMDLINE)
END FUNCTION

