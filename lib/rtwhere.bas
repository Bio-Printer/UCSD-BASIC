' RTWHERE -- where a run-time error was: _RTERR calls _RTWHERE, which
' follows the procedures' frames out from _RTERR's and chains to BCDEBUG
' (bc/bcdebug.bas) with them: "BCDEBUG unit block S#,P#,I# S#,P#,I# ...",
' the code file's unit and first block, then each frame's caller, the
' innermost first, as many as the command line holds (the operating
' system's prompt line: 80 characters with the shell's path).  BCDEBUG
' finds the first that is not the library's in the line tables BCLINK puts
' after the code file's segments and says the source's line.  No BCDEBUG:
' the numbers are said here.  A segment of its own, in memory only after
' an error.
#INCLUDE "RTCOM"

DECLARE SUB _CHAIN (cmd)

SEGMENT RTWHERE

' a word of the code: in the Harvard layout the code is not in the data
' space, and unit 64 reads it (in the other layouts a bad unit: PEEK)
FUNCTION _CODEW (a)
    DIM w
    CSP 5, 64, VARPTR(w), 0, 2, a, 0
    IF CSP%(34) <> 0 THEN w = PEEK(a)
    _CODEW = w
END FUNCTION

' the Pascal string s after the one at c
SUB _WCAT (c, s)
    CSP 2, s + 1, 0, c + PEEKB(c) + 1, 0, PEEKB(s)
    POKEB c, PEEKB(c) + PEEKB(s)
END SUB

' ... the number v (after the character sep: 0 none)
SUB _WNUM (c, v, sep)
    DIM t
    IF sep THEN
        POKEB c, PEEKB(c) + 1
        POKEB c + PEEKB(c), sep
    END IF
    t = _TTOP
    _WCAT c, _ISTR(v, 0)
    _TTOP = t
END SUB

' f is _RTERR's frame (its mark stack control word: word 1 the frame of its
' caller, 2 the caller's procedure's attributes (JTAB), 3 its segment
' (SEGP), 4 where it goes on (IPC))
SUB _RTWHERE (f)
    DIM sy, a, b, c, s, p, jt, ipc, lim, k
    sy = OSVAR(1)
    a = _MALLOC(100)
    b = _MALLOC(100)
    c = _MALLOC(100)
    POKEB b, 0
    ' the code file: its unit, and its segment 1's block less 1 (block 0)
    POKEB a, 0
    _WNUM a, PEEK(sy + 102), 32
    _WNUM a, PEEK(sy + 104) - 1, 32
    ' (room for the longest name, BASIC:BCDEBUG, and the shell's path)
    lim = 80 - 13
    IF _SVPWD THEN lim = lim - 1 - PEEKB(_SVPWD)
    DO
        jt = PEEK(f + 4)
        s = _CODEW(PEEK(f + 6)) AND 255
        p = _CODEW(jt) AND 255
        ' (the startup procedure: no further)
        IF s = 1 AND p = 1 THEN EXIT DO
        ipc = PEEK(f + 8) - ((jt - 2) - _CODEW(jt - 2))
        POKEB c, 0
        _WNUM c, s, 32
        _WNUM c, p, 44
        _WNUM c, ipc, 44
        IF PEEKB(a) + PEEKB(b) + PEEKB(c) > lim THEN EXIT DO
        _WCAT b, c
        f = PEEK(f + 2)
    LOOP
    ' BCDEBUG: beside the program, on the prefix (or the shell's path), the
    ' boot disk, BASIC:
    FOR k = 1 TO 4
        POKEB c, 0
        SELECT CASE k
        CASE 1
            _WCAT c, SADD("#")
            _WNUM c, PEEK(sy + 102), 0
            _WCAT c, SADD(":")
        CASE 3
            _WCAT c, SADD("*")
        CASE 4
            _WCAT c, SADD("BASIC:")
        END SELECT
        _WCAT c, SADD("BCDEBUG")
        _WCAT c, a
        _WCAT c, b
        _CHAIN c
    NEXT k
    ' (no BCDEBUG) S#,P#,I# of each frame: the innermost first
    _PSTR 0, SADD("S#,P#,I# from the innermost call out:")
    _PSTR 0, b
    _PNL 0
END SUB
