' RTFILE -- the run-time library: files
'
' OPEN f$ FOR INPUT / OUTPUT / APPEND / BINARY / RANDOM AS #n.  A name
' ending in .TEXT is a UCSD text file (2 header blocks, 1K pages, a line
' never crosses a page, DLE blank compression read); any other file is its
' bytes (lines end with CR).  The operating system's FINIT, FOPEN, FCLOSE
' and FBLOCKIO (CXP 0,3 / 5 / 6 / 28) do the disk work; the buffering is
' here.  CONSOLE: is the console.  A file in a sub-volume (VOL:/A/NAME) is
' RTSUBV's.
#INCLUDE "RTCOM"

' the entry of channel ch (1..15; 16, 17 the redirections')
FUNCTION _FENTRY (ch)
    IF ch < 1 OR ch > CHRIN THEN _RTERR 52
    _FENTRY = _FTAB + ch * 32
END FUNCTION

' an open channel's entry, or a run-time error
FUNCTION _FOPENED (ch)
    DIM e
    e = _FENTRY(ch)
    IF PEEK(e + FFL) = 0 THEN _RTERR 52
    _FOPENED = e
END FUNCTION

FUNCTION _FREEF ()
    DIM ch
    FOR ch = 1 TO 15
        IF PEEK(_FTAB + ch * 32 + FFL) = 0 THEN
            _FREEF = ch
            EXIT FUNCTION
        END IF
    NEXT ch
    _RTERR 67
END FUNCTION

' FBLOCKIO: n blocks from block b into / out of the buffer
FUNCTION _BLOCKIO (e, nblocks, b, rd)
    DIM n
    IF PEEK(e + FSVU) THEN
        _BLOCKIO = _SVIO(e, nblocks, b, rd)
        EXIT FUNCTION
    END IF
    n = OSCALL%(28, PEEK(e + FFIB), PEEK(e + FBUF), 0, nblocks, b, rd, 0, 0)
    IF CSP%(34) <> 0 THEN POKE e + FFL, PEEK(e + FFL) OR FERR
    _BLOCKIO = n
END FUNCTION

FUNCTION _FLUSHBUF (e)
    DIM n, fl, p
    fl = PEEK(e + FFL)
    IF (fl AND FDIRTY) = 0 THEN EXIT FUNCTION
    POKE e + FFL, fl AND NOT FDIRTY
    IF fl AND FTEXT THEN
        p = PEEK(e + FPOS)
        CSP 10, PEEK(e + FBUF) + p, 0, 1024 - p, 0
        n = _BLOCKIO(e, 2, PEEK(e + FBLK), 0)
        IF n = 2 THEN EXIT FUNCTION
    ELSE
        n = _BLOCKIO(e, 1, PEEK(e + FBLK), 0)
        IF n = 1 THEN EXIT FUNCTION
    END IF
    POKE e + FFL, PEEK(e + FFL) OR FERR
    _FLUSHBUF = -1
END FUNCTION

' a byte file's block b into the buffer
FUNCTION _LOADBLK (e, b)
    DIM n
    IF PEEK(e + FBLK) = b THEN EXIT FUNCTION
    IF _FLUSHBUF(e) THEN
        _LOADBLK = -1
        EXIT FUNCTION
    END IF
    POKE e + FBLK, b
    POKE e + FLEN, 0
    IF PEEK(e + FFL) AND FREAD THEN
        n = _BLOCKIO(e, 1, b, 1)
        IF n > 0 THEN POKE e + FLEN, 512
    END IF
    IF PEEK(e + FLEN) = 0 THEN CSP 10, PEEK(e + FBUF), 0, 512, 0
END FUNCTION

' (OPEN and the names it takes: in the segment RTSELDOM, RTSUBV's)
SEGMENT RTSELDOM

' a UCSD text file: "x.TEXT", or "x.BAS" (a BASIC source)?
FUNCTION _ISTEXT (name)
    DIM n, i, c, t, k, m
    n = PEEKB(name)
    FOR k = 1 TO 2
        IF k = 1 THEN t = SADD(".TEXT") ELSE t = SADD(".BAS")
        m = PEEKB(t)
        IF n > m THEN
            FOR i = 1 TO m
                c = PEEKB(name + n - m + i)
                IF c >= 97 AND c <= 122 THEN c = c - 32
                IF c <> PEEKB(t + i) THEN EXIT FOR
            NEXT i
            IF i > m THEN
                _ISTEXT = -1
                EXIT FUNCTION
            END IF
        END IF
    NEXT k
END FUNCTION

' the title FOPEN takes: upper case, at most 30 characters; a / after the
' volume (VOL:/NAME, /NAME) left out
FUNCTION _TITLE (name)
    DIM n, i, c, t, k
    t = _SCRATCH
    n = PEEKB(name)
    k = 0
    FOR i = 1 TO n
        c = PEEKB(name + i)
        IF c >= 97 AND c <= 122 THEN c = c - 32
        IF c = 47 OR c = 92 THEN
            IF k = 0 THEN
                c = -1
            ELSEIF PEEKB(t + k) = 58 THEN
                c = -1
            END IF
        END IF
        IF c >= 0 AND k < 30 THEN
            k = k + 1
            POKEB t + k, c
        END IF
    NEXT i
    ' the size, [n] or [*] (_FNAME took it off the name)
    IF PEEKB(_SIZESPEC) THEN
        CSP 2, _SIZESPEC + 1, 0, t + k + 1, 0, PEEKB(_SIZESPEC)
        k = k + PEEKB(_SIZESPEC)
    END IF
    POKEB t, k
    _TITLE = t
END FUNCTION

FUNCTION _SAMEAS (name, w)
    DIM n, i, c
    n = PEEKB(name)
    IF n <> PEEKB(w) THEN EXIT FUNCTION
    FOR i = 1 TO n
        c = PEEKB(name + i)
        IF c >= 97 AND c <= 122 THEN c = c - 32
        IF c <> PEEKB(w + i) THEN EXIT FUNCTION
    NEXT i
    _SAMEAS = -1
END FUNCTION

' the name a file is opened by, in _PATHBUF: a name without a volume on
' the shell's path (CD, Tiny-C's shell) has that path and a / before it;
' a size at its end, [n] or [*] (the operating system's: n blocks, half the
' largest free area), goes to _SIZESPEC
FUNCTION _FNAME (name)
    DIM n, k, c, b, i
    POKEB _SIZESPEC, 0
    IF name = 0 THEN EXIT FUNCTION
    b = _PATHBUF
    k = 0
    n = PEEKB(name)
    IF n > 0 AND _SVPWD <> 0 THEN
        c = PEEKB(name + 1)
        IF c <> 47 AND c <> 92 AND c <> 35 AND c <> 42 THEN
            FOR i = 1 TO n
                IF PEEKB(name + i) = 58 THEN EXIT FOR
            NEXT i
            IF i > n THEN
                k = PEEKB(_SVPWD)
                CSP 2, _SVPWD + 1, 0, b + 1, 0, k
                c = PEEKB(b + k)
                IF c <> 47 AND c <> 58 THEN
                    k = k + 1
                    POKEB b + k, 47
                END IF
            END IF
        END IF
    END IF
    ' the size
    IF n > 2 THEN
        IF PEEKB(name + n) = 93 THEN
            FOR i = n - 1 TO 1 STEP -1
                IF PEEKB(name + i) = 91 THEN EXIT FOR
            NEXT i
            IF i >= 1 AND n - i + 1 <= 7 THEN
                CSP 2, name + i, 0, _SIZESPEC + 1, 0, n - i + 1
                POKEB _SIZESPEC, n - i + 1
                n = i - 1
            END IF
        END IF
    END IF
    IF k + n > 126 THEN n = 126 - k
    IF n > 0 THEN CSP 2, name + 1, 0, b + k + 1, 0, n
    POKEB b, k + n
    _FNAME = b
END FUNCTION

' mode 1 INPUT, 2 OUTPUT, 3 APPEND, 4 BINARY, 5 RANDOM
SUB _OPEN (name, mode, ch, reclen)
    DIM e, fl, old, ok, n, bsz, fib, buf, p
    _ERRCODE = 0
    ' (ch < 0: the library's own, -CHROUT or -CHRIN)
    IF ch > 15 THEN _RTERR 52
    e = _FENTRY(ABS(ch))
    IF PEEK(e + FFL) THEN
        _IOERR 55
        EXIT SUB
    END IF
    IF name = 0 THEN
        _IOERR 53
        EXIT SUB
    END IF
    CSP 10, e, 0, 32, 0
    POKE e + FUNG, -1
    POKE e + FBLK, -1
    name = _FNAME(name)
    IF _SAMEAS(name, SADD("CONSOLE:")) THEN
        POKE e + FFL, FCON OR FREAD OR FWRITE
        EXIT SUB
    END IF
    SELECT CASE mode
    CASE 1: fl = FREAD
    CASE 2, 3: fl = FWRITE
    CASE ELSE: fl = FREAD OR FWRITE
    END SELECT
    IF mode <= 3 AND _ISTEXT(name) THEN fl = fl OR FTEXT
    ' a byte file read as lines: the zeros that fill its last block end it
    IF mode = 1 AND (fl AND FTEXT) = 0 THEN fl = fl OR FZEND
    bsz = 512
    IF (fl AND FTEXT) <> 0 AND (fl AND FWRITE) <> 0 THEN bsz = 1024
    POKE e + FBSZ, bsz
    buf = _MALLOC(bsz)
    POKE e + FBUF, buf
    ' in a sub-volume?
    fib = _MALLOC(24)
    POKE e + FFIB, fib
    n = _SVOPEN(e, name, mode)
    IF n = 0 THEN
        _MFREE fib
        fib = _MALLOC(80)
        POKE e + FFIB, fib
        ' (a Pascal boolean: 1, not BASIC's -1 -- SYSTEM.C takes only 1 as
        ' true)
        IF mode <> 2 THEN old = 1 ELSE old = 0
        OSCALL 3, fib, 0, -1
        OSCALL 5, fib, _TITLE(name), old, 0
        ok = CSP%(34) = 0
    ELSE
        IF n = 1 THEN old = 1 ELSE old = 0
        ok = n > 0
    END IF
    IF NOT ok AND mode >= 4 AND n = 0 THEN
        ' BINARY, RANDOM: a new file
        old = 0
        OSCALL 3, fib, 0, -1
        OSCALL 5, fib, _TITLE(name), 0, 0
        ok = CSP%(34) = 0
    END IF
    IF NOT ok THEN
        _MFREE buf
        _MFREE fib
        POKE e + FFL, 0
        _IOERR 53
        EXIT SUB
    END IF
    IF old = 0 THEN fl = fl OR FNEW
    POKE e + FFL, fl
    IF fl AND FTEXT THEN
        IF old = 0 THEN
            CSP 10, buf, 0, 1024, 0
            n = _BLOCKIO(e, 2, 0, 0)
        END IF
        POKE e + FBLK, 2
        POKE e + FPOS, 0
        POKE e + FLEN, 0
        IF mode = 3 THEN
            ' APPEND: the last page and the end of its text
            DO
                n = _BLOCKIO(e, 2, PEEK(e + FBLK), 1)
                IF n < 2 THEN EXIT DO
                POKE e + FBLK, PEEK(e + FBLK) + 2
            LOOP
            IF PEEK(e + FBLK) > 2 THEN
                POKE e + FBLK, PEEK(e + FBLK) - 2
                n = _BLOCKIO(e, 2, PEEK(e + FBLK), 1)
                p = 0
                DO WHILE p < 1024
                    IF PEEKB(buf + p) = 0 THEN EXIT DO
                    p = p + 1
                LOOP
                POKE e + FPOS, p
                POKE e + FLST, p
            ELSE
                CSP 10, buf, 0, 1024, 0
            END IF
            POKE e + FFL, (PEEK(e + FFL) OR FDIRTY) AND NOT FREAD
        ELSEIF fl AND FREAD THEN
            POKE e + FBLK, 2 - bsz \ 512
        END IF
    ELSEIF mode = 3 THEN
        n = 0
        DO WHILE _BLOCKIO(e, 1, n, 1) = 1
            n = n + 1
        LOOP
        POKE e + FBLK, -1
        p = _LOADBLK(e, n)
        POKE e + FPOS, 0
    END IF
END SUB

' the shell's redirections (_ARGS took them): the console's output to
' _REDNAME (mode 3: appended; a file not there yet made), its input from
' _REDNAME + 82; a file that cannot be opened: its name, and the end
SUB _REDOPEN ()
    DIM m, f
    _ERRTRAP = -1
    IF _REDIR AND 1 THEN
        IF _REDIR AND 4 THEN m = 3 ELSE m = 2
        _OPEN _REDNAME, m, -CHROUT, 0
        IF _ERRCODE <> 0 AND m = 3 THEN _OPEN _REDNAME, 2, -CHROUT, 0
        IF _ERRCODE <> 0 THEN f = _REDNAME
    END IF
    IF (_REDIR AND 2) <> 0 AND f = 0 THEN
        _OPEN _REDNAME + 82, 1, -CHRIN, 0
        IF _ERRCODE <> 0 THEN f = _REDNAME + 82
    END IF
    _ERRTRAP = 0
    _ERRCODE = 0
    IF f THEN
        _REDCLOSE
        _PSTR 0, f
        _PSTR 0, SADD(": cannot open it")
        _PNL 0
        _HALT 1
    END IF
END SUB


' KILL name
SUB _KILL (name)
    DIM fib, r
    _ERRCODE = 0
    name = _FNAME(name)
    POKEB _SIZESPEC, 0
    r = _SVKILL(name)
    IF r < 0 THEN _IOERR 53
    IF r THEN EXIT SUB
    fib = _MALLOC(80)
    OSCALL 3, fib, 0, -1
    OSCALL 5, fib, _TITLE(name), 1, 0
    IF CSP%(34) <> 0 THEN
        _MFREE fib
        _IOERR 53
        EXIT SUB
    END IF
    OSCALL 6, fib, 2
    _MFREE fib
END SUB

SEGMENT

SUB _CLOSE1 (ch)
    DIM e, fl, r
    e = _FTAB + ch * 32
    fl = PEEK(e + FFL)
    IF fl = 0 THEN EXIT SUB
    IF (fl AND FCON) = 0 THEN
        r = _FLUSHBUF(e)
        IF PEEK(e + FSVU) THEN
            IF _SVCLOSE(e) THEN r = -1
        ELSE
            ' a new text file is of the kind text whatever its name (X.BAS):
            ' FCLOSE enters the FIB's header, kind and all
            IF (fl AND FNEW) <> 0 AND (fl AND FTEXT) <> 0 THEN POKE PEEK(e + FFIB) + 36, (PEEK(PEEK(e + FFIB) + 36) AND &HFFF0) OR 3
            IF fl AND FNEW THEN OSCALL 6, PEEK(e + FFIB), 1 ELSE OSCALL 6, PEEK(e + FFIB), 0
            IF CSP%(34) <> 0 THEN r = -1
        END IF
        _MFREE PEEK(e + FBUF)
        _MFREE PEEK(e + FFIB)
        ' (closed before the error: _RTERR closes every file)
        POKE e + FFL, 0
        IF r THEN _IOERR 61
    END IF
    POKE e + FFL, 0
END SUB

' CLOSE #ch; ch 0: every file
SUB _CLOSE (ch)
    DIM i
    IF ch = 0 THEN
        FOR i = 1 TO 15
            _CLOSE1 i
        NEXT i
    ELSE
        IF ch < 1 OR ch > 15 THEN _RTERR 52
        _CLOSE1 ch
    END IF
END SUB

' ---- reading

' a text file's next character: -1 at the end
FUNCTION _TGETC (e)
    DIM c, n, d, pos
    DO
        d = PEEK(e + FDLE)
        IF d > 0 THEN
            POKE e + FDLE, d - 1
            _TGETC = 32
            EXIT FUNCTION
        END IF
        pos = PEEK(e + FPOS)
        IF pos >= PEEK(e + FLEN) THEN
            IF PEEK(e + FFL) AND FEOF THEN
                _TGETC = -1
                EXIT FUNCTION
            END IF
            n = PEEK(e + FBSZ) \ 512
            POKE e + FBLK, PEEK(e + FBLK) + n
            n = _BLOCKIO(e, n, PEEK(e + FBLK), 1)
            IF n <= 0 THEN
                POKE e + FFL, PEEK(e + FFL) OR FEOF
                POKE e + FLEN, 0
                _TGETC = -1
                EXIT FUNCTION
            END IF
            POKE e + FLEN, n * 512
            POKE e + FPOS, 0
            pos = 0
        END IF
        c = PEEKB(PEEK(e + FBUF) + pos)
        POKE e + FPOS, pos + 1
        IF d < 0 THEN
            ' the count after a DLE
            POKE e + FDLE, c - 32
        ELSEIF c = 0 THEN
            ' the rest of the page is padding
            POKE e + FPOS, PEEK(e + FLEN)
        ELSEIF c = 16 THEN
            POKE e + FDLE, -1
        ELSE
            _TGETC = c
            EXIT FUNCTION
        END IF
    LOOP
END FUNCTION

' a byte file's next byte: -1 at the end
FUNCTION _RGETC (e)
    DIM b, pos
    pos = PEEK(e + FPOS)
    IF PEEK(e + FBLK) < 0 OR pos >= 512 THEN
        b = PEEK(e + FBLK)
        IF b < 0 THEN b = 0 ELSE IF pos >= 512 THEN b = b + 1
        IF _LOADBLK(e, b) THEN
            _RGETC = -1
            EXIT FUNCTION
        END IF
        IF pos >= 512 THEN
            pos = 0
            POKE e + FPOS, 0
        END IF
        IF PEEK(e + FLEN) = 0 THEN
            POKE e + FFL, PEEK(e + FFL) OR FEOF
            _RGETC = -1
            EXIT FUNCTION
        END IF
    END IF
    b = PEEKB(PEEK(e + FBUF) + pos)
    IF b = 0 AND (PEEK(e + FFL) AND FZEND) <> 0 THEN
        POKE e + FFL, PEEK(e + FFL) OR FEOF
        _RGETC = -1
        EXIT FUNCTION
    END IF
    _RGETC = b
    POKE e + FPOS, pos + 1
END FUNCTION

' the next character of channel ch (-1 at the end)
FUNCTION _FGETC (ch)
    DIM e, c, fl
    e = _FOPENED(ch)
    c = PEEK(e + FUNG)
    IF c >= 0 THEN
        POKE e + FUNG, -1
        _FGETC = c
        EXIT FUNCTION
    END IF
    fl = PEEK(e + FFL)
    IF fl AND FCON THEN
        _FGETC = _CONGETC
        EXIT FUNCTION
    END IF
    IF (fl AND FREAD) = 0 THEN _IOERR 54
    IF fl AND FTEXT THEN _FGETC = _TGETC(e) ELSE _FGETC = _RGETC(e)
END FUNCTION

FUNCTION _EOF (ch)
    DIM e, c
    e = _FOPENED(ch)
    IF PEEK(e + FUNG) >= 0 THEN EXIT FUNCTION
    IF PEEK(e + FFL) AND FCON THEN EXIT FUNCTION
    c = _FGETC(ch)
    IF c < 0 THEN _EOF = -1 ELSE POKE e + FUNG, c
END FUNCTION

' LINE INPUT #ch: the next line (a temporary), without its CR
FUNCTION _FLINE (ch)
    DIM c, n, b, t, e
    e = _FOPENED(ch)
    b = _INBUF
    c = _FGETC(ch)
    IF c < 0 THEN _IOERR 62
    DO WHILE c >= 0 AND c <> 13
        IF c <> 10 AND n < 255 THEN
            n = n + 1
            POKEB b + n, c
        END IF
        c = _FGETC(ch)
    LOOP
    t = _TALLOC(n)
    IF n THEN CSP 2, b + 1, 0, t + 1, 0, n
    _FLINE = t
END FUNCTION

' ---- writing

' a text page is full: write it, the unfinished line begins the next one
FUNCTION _TPAGE (e)
    DIM b, l, n, pos, lbuf
    b = PEEK(e + FBUF)
    pos = PEEK(e + FPOS)
    l = PEEK(e + FLST)
    IF l = 0 THEN l = pos
    n = pos - l
    IF n > 0 THEN
        lbuf = _MALLOC(n)
        CSP 2, b + l, 0, lbuf, 0, n
    END IF
    POKE e + FPOS, l
    POKE e + FFL, PEEK(e + FFL) OR FDIRTY
    IF _FLUSHBUF(e) THEN
        IF n > 0 THEN _MFREE lbuf
        _TPAGE = -1
        EXIT FUNCTION
    END IF
    IF n > 0 THEN
        CSP 2, lbuf, 0, b, 0, n
        _MFREE lbuf
    END IF
    POKE e + FBLK, PEEK(e + FBLK) + 2
    POKE e + FPOS, n
    POKE e + FLST, 0
END FUNCTION

SUB _FPUTC (ch, c)
    DIM e, fl, pos, b
    e = _FOPENED(ch)
    fl = PEEK(e + FFL)
    IF fl AND FCON THEN
        _CONPUT c
        EXIT SUB
    END IF
    IF (fl AND FWRITE) = 0 THEN
        _IOERR 54
        EXIT SUB
    END IF
    IF c = 13 THEN POKE e + FCOL, 0 ELSE POKE e + FCOL, PEEK(e + FCOL) + 1
    IF fl AND FTEXT THEN
        IF PEEK(e + FPOS) >= 1023 THEN
            IF _TPAGE(e) THEN
                _IOERR 61
                EXIT SUB
            END IF
        END IF
        pos = PEEK(e + FPOS)
        POKEB PEEK(e + FBUF) + pos, c
        POKE e + FPOS, pos + 1
        IF c = 13 THEN POKE e + FLST, pos + 1
        POKE e + FFL, PEEK(e + FFL) OR FDIRTY
        EXIT SUB
    END IF
    pos = PEEK(e + FPOS)
    IF PEEK(e + FBLK) < 0 OR pos >= 512 THEN
        b = PEEK(e + FBLK)
        IF b < 0 THEN b = 0 ELSE IF pos >= 512 THEN b = b + 1
        IF _LOADBLK(e, b) THEN
            _IOERR 61
            EXIT SUB
        END IF
        IF pos >= 512 THEN pos = 0
    END IF
    POKEB PEEK(e + FBUF) + pos, c
    POKE e + FPOS, pos + 1
    IF pos + 1 > PEEK(e + FLEN) THEN POKE e + FLEN, pos + 1
    POKE e + FFL, PEEK(e + FFL) OR FDIRTY
END SUB

' ---- GET and PUT: bytes

SUB _GETR (addr, ch, n)
    DIM i, c
    FOR i = 0 TO n - 1
        c = _FGETC(ch)
        IF c < 0 THEN c = 0
        POKEB addr + i, c
    NEXT i
END SUB

SUB _PUTR (addr, ch, n)
    DIM i
    FOR i = 0 TO n - 1
        _FPUTC ch, PEEKB(addr + i)
    NEXT i
END SUB

FUNCTION _GETS (ch, n)
    DIM t
    IF n = 0 THEN EXIT FUNCTION
    t = _TALLOC(n)
    _GETR t + 1, ch, n
    _GETS = t
END FUNCTION

SUB _PUTS (ch, s)
    IF s THEN _PUTR s + 1, ch, PEEKB(s)
END SUB

' SEEK #ch, pos (from 1): a byte file's position
SUB _SEEK (ch, pos#)
    DIM e, b, o, d!
    e = _FOPENED(ch)
    IF PEEK(e + FFL) AND FTEXT THEN _IOERR 54
    d! = pos# - 1
    b = CSP%(109, d! / 512)
    o = CSP%(109, d! - b * 512!)
    IF _LOADBLK(e, b) THEN _IOERR 61
    POKE e + FPOS, o
    POKE e + FUNG, -1
    POKE e + FFL, PEEK(e + FFL) AND NOT FEOF
END SUB

FUNCTION _LOF (ch)
    DIM e
    e = _FOPENED(ch)
    _LOF = 0
END FUNCTION

