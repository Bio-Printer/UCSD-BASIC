' RTWHERE -- where a run-time error was: the statement's line, its file and
' text, the procedure, and the P-System's S#, P#, I# (_RTERR calls
' _RTWHERE).  The procedures' frames are followed from _RTERR's out to the
' first one that is not the library's; the line tables BCLINK puts after
' the code file's segments (bclink.bas: WriteLines) give its name and the
' line its code is in.  All in a segment of its own, RTWHERE: in memory only
' after an error (in RTSELDOM it would take that segment's memory at every
' OPEN).
#INCLUDE "RTCOM"

CONST LTMAGIC = 17474

' the code file's unit and the tables' first block; one block of them read
' (_WBUF, its number _WBLK); where the next byte is read (block _WB, byte
' _WI)
DIM SHARED _WUNIT, _WBASE, _WBUF, _WBLK, _WB, _WI

SEGMENT RTWHERE

' a word of the code: in the Harvard layout the code is not in the data
' space, and unit 64 reads it (in the other layouts a bad unit: PEEK)
FUNCTION _CODEW (a)
    DIM w
    CSP 5, 64, VARPTR(w), 0, 2, a, 0
    IF CSP%(34) <> 0 THEN w = PEEK(a)
    _CODEW = w
END FUNCTION

' the tables' word w next
SUB _WSEEK (w)
    _WB = _WBASE + w \ 256
    _WI = (w MOD 256) * 2
END SUB

' their next byte (255, the end of a line table, when it cannot be read)
FUNCTION _WBYTE ()
    IF _WB <> _WBLK THEN
        CSP 5, _WUNIT, _WBUF, 0, 512, _WB, 0
        _WBLK = _WB
        IF CSP%(34) <> 0 THEN _WBLK = -1
    END IF
    IF _WBLK < 0 THEN
        _WBYTE = 255
        EXIT FUNCTION
    END IF
    _WBYTE = PEEKB(_WBUF + _WI)
    _WI = _WI + 1
    IF _WI = 512 THEN
        _WI = 0
        _WB = _WB + 1
    END IF
END FUNCTION

FUNCTION _WWORD ()
    DIM lo
    lo = _WBYTE
    _WWORD = lo OR _WBYTE * 256
END FUNCTION

' the next n bytes of the tables onto the console, or into the string s
SUB _WSTR (n, s)
    DIM i, c
    FOR i = 1 TO n
        c = _WBYTE
        IF s THEN POKEB s + i, c ELSE _CONPUT c
    NEXT i
    IF s THEN POKEB s, n
END SUB

' line ln of the source file f (a Pascal string) onto the console, without
' its indentation, if the file can be read: -1 if it could
FUNCTION _WLINE (f, ln)
    DIM e, buf, b, i, c, n, dle, lead
    _OPEN f, 1, 15, 0
    IF _ERRCODE <> 0 THEN EXIT FUNCTION
    e = _FTAB + 15 * 32
    IF (PEEK(e + FFL) AND FTEXT) = 0 THEN
        _CLOSE 15
        EXIT FUNCTION
    END IF
    _WLINE = -1
    buf = PEEK(e + FBUF)
    n = 1
    b = 2
    lead = 1
    DO WHILE n <= ln
        IF _BLOCKIO(e, 1, b, 1) < 1 THEN EXIT DO
        FOR i = 0 TO 511
            c = PEEKB(buf + i)
            IF dle THEN
                dle = 0
            ELSEIF c = 16 THEN
                dle = 1
            ELSEIF c = 13 THEN
                n = n + 1
                IF n > ln THEN EXIT FOR
            ELSEIF n = ln AND c <> 0 AND c <> 10 AND (c <> 32 OR lead = 0) THEN
                _CONPUT c
                lead = 0
            END IF
        NEXT i
        b = b + 1
    LOOP
    IF lead = 0 THEN _PNL 0
    _CLOSE 15
END FUNCTION

' where the error was: f is _RTERR's frame (its mark stack control word:
' word 1 the frame of its caller, 2 the caller's procedure's attributes
' (JTAB), 3 its segment (SEGP), 4 where it goes on (IPC)).  Says
'   FILE line N, in NAME (S# s, P# p, I# i):
'   the line
' or, without the tables, S#, P#, I# of _RTERR's caller.
SUB _RTWHERE (f)
    DIM sy, s, p, ipc, jt, r, k, ok, depth, nf, fw, hw, off, ln, fl, bl, bf, d, pn, fn, s0, p0, i0
    sy = OSVAR(1)
    ' the code file: its unit, and its segment 1's block (block 1 of the file)
    _WUNIT = PEEK(sy + 102)
    _WBASE = PEEK(sy + 104) - 1
    _WBUF = _MALLOC(512)
    pn = _MALLOC(256)
    fn = _MALLOC(256)
    POKEB pn, 0
    POKEB fn, 0
    _WBLK = -1
    ' block 0's last words: where the tables and their header are
    _WSEEK 253
    hw = _WWORD
    ok = _WWORD = LTMAGIC
    _WBASE = _WBASE + _WWORD
    IF ok THEN
        _WSEEK hw
        nf = _WWORD
        fw = _WWORD
    END IF
    ' the frames, out to the first that is not the library's (a procedure
    ' with a line table)
    DO
        jt = PEEK(f + 4)
        s = _CODEW(PEEK(f + 6)) AND 255
        p = _CODEW(jt) AND 255
        ipc = PEEK(f + 8) - ((jt - 2) - _CODEW(jt - 2))
        IF depth = 0 THEN
            s0 = s
            p0 = p
            i0 = ipc
        END IF
        r = 0
        IF ok THEN
            _WSEEK hw + 2 + s
            k = _WWORD
            IF k > 0 THEN
                _WSEEK k
                IF p <= _WWORD THEN
                    _WSEEK k + p
                    r = _WWORD
                END IF
            END IF
        END IF
        IF r <> 0 OR NOT ok OR (s = 1 AND p = 1) OR depth > 200 THEN EXIT DO
        f = PEEK(f + 2)
        depth = depth + 1
    LOOP
    IF r = 0 THEN
        s = s0
        p = p0
        ipc = i0
    ELSE
        ' its name; its line: the last whose code starts before IPC (which
        ' is after the call)
        _WSEEK r
        _WSTR _WBYTE, pn
        DO
            d = _WBYTE
            IF d = 255 THEN EXIT DO
            IF d = 254 THEN
                fl = _WBYTE
            ELSE
                IF d = 253 THEN
                    off = _WWORD
                    ln = _WWORD
                ELSE
                    off = off + d
                    ln = ln + _WBYTE
                END IF
                IF off < ipc THEN
                    bl = ln
                    bf = fl
                END IF
            END IF
        LOOP
        IF bf > 0 AND bf <= nf THEN
            _WSEEK fw
            FOR k = 1 TO bf
                _WSTR _WBYTE, fn
            NEXT k
        END IF
    END IF
    IF bl > 0 AND PEEKB(fn) > 0 THEN
        _PSTR 0, fn
        _PSTR 0, SADD(" line ")
        _PSTR 0, _ISTR(bl, 0)
        _PSTR 0, SADD(", ")
    END IF
    IF r THEN
        _PSTR 0, SADD("in ")
        _PSTR 0, pn
        _PSTR 0, SADD(" (")
    END IF
    _PSTR 0, SADD("S# ")
    _PSTR 0, _ISTR(s, 0)
    _PSTR 0, SADD(", P# ")
    _PSTR 0, _ISTR(p, 0)
    _PSTR 0, SADD(", I# ")
    _PSTR 0, _ISTR(ipc, 0)
    IF r THEN _PSTR 0, SADD(")")
    IF bl > 0 AND PEEKB(fn) > 0 THEN
        _PSTR 0, SADD(":")
        _PNL 0
        ' the file: beside the code file when its name has no volume
        k = 0
        FOR d = 1 TO PEEKB(fn)
            IF PEEKB(fn + d) = 58 THEN k = 1
        NEXT d
        IF k = 0 THEN
            k = _ISTR(_WUNIT, 0)
            POKEB pn + 1, 35
            CSP 2, k + 1, 0, pn + 2, 0, PEEKB(k)
            POKEB pn + PEEKB(k) + 2, 58
            CSP 2, fn + 1, 0, pn + PEEKB(k) + 3, 0, PEEKB(fn)
            POKEB pn, PEEKB(k) + 2 + PEEKB(fn)
            IF NOT _WLINE(pn, bl) THEN k = 0
        END IF
        IF k = 0 THEN k = _WLINE(fn, bl)
    ELSE
        _PNL 0
    END IF
END SUB
