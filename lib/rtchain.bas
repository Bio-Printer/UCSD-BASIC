' RTCHAIN -- the run-time library: CHAIN "[VOL:]PROGRAM [options]"
'
' The program ends and the other one runs in its place, with the rest of
' the line as its COMMAND$.  Nothing of this one stays in memory: the other
' program has all of it.  It is Tiny-C's pexec protocol (BIGGY's operating
' systems: SYSTEM.PASCAL 1.10 and later, SYSTEM.C): SYSCOM's EXPANSION[0] =
' PX_RUN, [1] and [2] the unit and first block of the code file to run; the
' command line in the prompt line PL (with the shell's path after a byte 30,
' as the shell gives it), EXPANSION[6] = PX_ARGS and [7] its checksum.  When
' the program chained to ends, GETCMD starts the code file of EXPANSION[3]
' and [4]: a program started by the shell (EXPANSION[0] = PX_CHILD) leaves
' them as they are, so the shell comes back after the last program of the
' chain; else they are made no code file (unit 0) and the Command: prompt
' comes.
#INCLUDE "RTCOM"

DECLARE FUNCTION _SVPATH (e, name, d)
DECLARE FUNCTION _SVFIND (d, nm)
DECLARE FUNCTION _FNAME (name)
DECLARE FUNCTION _TITLE (name)
DECLARE FUNCTION _XOR (a, b)

CONST PXRUN = 25601, PXCHILD = 25602, PXARGS = 25604, PXPATHSEP = 30

SEGMENT RTSELDOM

' CHAIN cmd: an error if it cannot be done (53: no such code file, or not
' a linked one; 64: no name, or the line too long for PL, 80 characters
' with the shell's path)
SUB _CHAIN (cmd)
    DIM n, i, k, s, nm, u, first, kind, fib, d, e, r, pl, sum, w, t
    _ERRCODE = 0
    t = _TTOP
    ' the line without the blanks around it; its first word the program
    n = PEEKB(cmd)
    s = 1
    DO WHILE s <= n
        IF PEEKB(cmd + s) <> 32 THEN EXIT DO
        s = s + 1
    LOOP
    DO WHILE n >= s
        IF PEEKB(cmd + n) <> 32 THEN EXIT DO
        n = n - 1
    LOOP
    k = s
    DO WHILE k <= n
        IF PEEKB(cmd + k) = 32 THEN EXIT DO
        k = k + 1
    LOOP
    w = k - s
    IF w = 0 OR w > 60 THEN
        _TTOP = t
        _IOERR 64
        EXIT SUB
    END IF
    ' its code file: NAME.CODE, or NAME. as it is (as X(ecute takes it)
    nm = _TALLOC(w + 5)
    CSP 2, cmd + s, 0, nm + 1, 0, w
    IF PEEKB(nm + w) = 46 THEN
        POKEB nm, w - 1
    ELSE
        CSP 2, SADD(".CODE") + 1, 0, nm + w + 1, 0, 5
        POKEB nm, w + 5
    END IF
    ' where it is: in a sub-volume (a path, or the shell's path), or by the
    ' operating system
    nm = _FNAME(nm)
    kind = 0
    d = _MALLOC(2048)
    e = _MALLOC(32)
    CSP 10, e, 0, 32, 0
    POKE e + FFIB, _MALLOC(24)
    r = _SVPATH(e, nm, d)
    IF r = 1 THEN
        i = _SVFIND(d, PEEK(e + FFIB))
        IF i > 0 THEN
            u = PEEK(e + FSVU)
            first = PEEK(e + FSVB) + PEEK(d + 26 * i)
            kind = PEEK(d + 26 * i + 4) AND 15
        END IF
    ELSEIF r = 0 THEN
        fib = _MALLOC(80)
        OSCALL 3, fib, 0, -1
        OSCALL 5, fib, _TITLE(nm), 1, 0
        IF CSP%(34) = 0 THEN
            u = PEEK(fib + 14)
            first = PEEK(fib + 32)
            kind = PEEK(fib + 36) AND 15
            OSCALL 6, fib, 0
        END IF
        _MFREE fib
    END IF
    _MFREE PEEK(e + FFIB)
    _MFREE e
    ' a code file, linked (its block 0: SEGKIND at word 96, each 0; a code
    ' file older than I.5 has other values there, and is linked too)
    IF kind = 2 THEN
        CSP 5, u, d, 0, 512, first, 0
        IF CSP%(34) <> 0 THEN kind = 0
    END IF
    IF kind = 2 THEN
        r = 1
        FOR i = 0 TO 15
            k = PEEK(d + 192 + 2 * i)
            IF k < 0 OR k > 4 THEN r = 2
            IF k <> 0 AND r = 1 THEN r = 0
        NEXT i
        IF r = 0 THEN kind = 0
    END IF
    _MFREE d
    IF kind <> 2 THEN
        _TTOP = t
        _IOERR 53
        EXIT SUB
    END IF
    ' the command line, and the shell's path after it
    k = n - s + 1
    IF _SVPWD THEN k = k + 1 + PEEKB(_SVPWD)
    IF k > 80 THEN
        _TTOP = t
        _IOERR 64
        EXIT SUB
    END IF
    pl = OSADDR(70)
    CSP 2, cmd + s, 0, pl + 1, 0, n - s + 1
    IF _SVPWD THEN
        POKEB pl + n - s + 2, PXPATHSEP
        CSP 2, _SVPWD + 1, 0, pl + n - s + 3, 0, PEEKB(_SVPWD)
    END IF
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
    _TTOP = t
    ' this program ends (its files closed); GETCMD starts the other one
    _HALT 0
END SUB
