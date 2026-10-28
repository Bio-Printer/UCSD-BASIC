' RTWHERE -- where a run-time error was: _RTERR calls _RTWHERE, which
' follows the procedures' frames out from _RTERR's and chains to BCDEBUG
' (bc/bcdebug.bas) with them: "BCDEBUG unit block S#,P#,I# S#,P#,I# ...",
' the code file's unit and first block, then each frame's caller, the
' innermost first, as many as the command line holds (the operating
' system's prompt line: 80 characters with the shell's path).  BCDEBUG
' finds the first that is not the library's in NAME.MAP (BCLINK -MAP)
' and says the source's line.  No BCDEBUG: the numbers are said here, as
' s=S#,p=P#,i=I# each.  In the segment RTSELDOM.
#INCLUDE "RTCOM"

DECLARE FUNCTION _XOR (a, b)

CONST PXRUN = 25601, PXCHILD = 25602, PXARGS = 25604

SEGMENT RTSELDOM

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
    ' (the command line: BCDEBUG, then these, 80 characters at most)
    lim = 80 - 7
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
    ' BCDEBUG: beside the program, on the prefix, the boot disk, BASIC:
    _WCAT a, b
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
        _WCAT c, SADD("BCDEBUG.CODE")
        _WRUN c, a
    NEXT k
    ' (no BCDEBUG) each frame's numbers: s=S#,p=P#,i=I#, the innermost first
    _WSAY b
    _PNL 0
END SUB

' the code file c (a Pascal string: a title for FOPEN) run with the command
' line BCDEBUG and a: this program ends (Tiny-C's pexec protocol, as
' RTCHAIN's _CHAIN, without its search of the paths, the shell's path and
' its check of the code file); back if there is no such code file
SUB _WRUN (c, a)
    DIM fib, u, first, kind, pl, k, sum, i, e
    fib = _MALLOC(80)
    OSCALL 3, fib, 0, -1
    OSCALL 5, fib, c, 1, 0
    IF CSP%(34) = 0 THEN
        u = PEEK(fib + 14)
        first = PEEK(fib + 32)
        kind = PEEK(fib + 36) AND 15
        OSCALL 6, fib, 0
    END IF
    _MFREE fib
    IF kind <> 2 THEN EXIT SUB
    pl = OSADDR(70)
    CSP 2, SADD("BCDEBUG") + 1, 0, pl + 1, 0, 7
    CSP 2, a + 1, 0, pl + 8, 0, PEEKB(a)
    k = 7 + PEEKB(a)
    POKEB pl, k
    sum = k
    FOR i = 1 TO k
        sum = sum * 3 + PEEKB(pl + i)
    NEXT i
    e = OSVAR(1) + 36
    POKE e + 12, PXARGS
    POKE e + 14, _XOR(sum, &H5A5A)
    POKE e + 2, u
    POKE e + 4, first
    IF PEEK(e) <> PXCHILD THEN POKE e + 6, 0
    POKE e, PXRUN
    _HALT 0
END SUB

' the frames' numbers (" 1,3,73 1,2,30") said as "s=1,p=3,i=73 s=1,p=2,i=30"
SUB _WSAY (b)
    DIM i, c, k, d
    d = 1
    FOR i = 1 TO PEEKB(b)
        c = PEEKB(b + i)
        IF c >= 48 AND c <= 57 THEN
            IF d THEN
                SELECT CASE k
                CASE 0: _CONPUT 115
                CASE 1: _CONPUT 112
                CASE ELSE: _CONPUT 105
                END SELECT
                _CONPUT 61
                k = (k + 1) MOD 3
            END IF
            d = 0
        ELSE
            IF i > 1 THEN _CONPUT c
            d = 1
        END IF
        IF c >= 48 AND c <= 57 THEN _CONPUT c
    NEXT i
END SUB
