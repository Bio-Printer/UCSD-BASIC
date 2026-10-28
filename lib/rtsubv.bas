' RTSUBV -- the run-time library: files in sub-volumes
'
' A sub-volume is a data file that holds a volume of its own (Tiny-C's
' shell makes one with MKDIR): its blocks 2..5 are a directory, its block
' numbers counted from the file's first block.  A path names a file in
' one: VOL:/A/NAME or VOL:A/NAME (A a sub-volume on VOL:), VOL:/A/B/NAME
' (B inside A), /A/NAME or A/NAME on the prefix volume; \ is taken as /.
' The operating system finds the first sub-volume (FOPEN: VOL:A, so #5:
' and * work as for any file) and tells its unit and first block; the
' rest is UNITREAD and UNITWRITE at the blocks the directories give.  A
' file written gets the largest free area of its sub-volume (or half of
' what another file being written there has not used yet), and its
' directory entry when it is closed.
'
' The open file's channel entry: FSVU its unit, FSVB the sub-volume's
' first block, FSVF the file's first block, FSVR the blocks it may use,
' FSVH the blocks it has; FFIB points to its record: the name (16 bytes),
' the blocks it had when opened, its kind.
#INCLUDE "RTCOM"

' (the library's segment RTSELDOM: what a program does seldom -- OPEN and
' the sub-volumes, CHAIN, the command line at the start; RTFILE, RTCHAIN and
' RTCORE put those there too)
SEGMENT RTSELDOM

' the directory of the sub-volume at block base of unit u into d (2048
' bytes): 0 if there is none
FUNCTION _SVDIR (u, base, d)
    DIM n
    CSP 5, u, d, 0, 2048, base + 2, 0
    IF CSP%(34) <> 0 THEN EXIT FUNCTION
    IF PEEK(d) <> 0 OR PEEK(d + 2) <> 6 OR PEEK(d + 14) < 6 THEN EXIT FUNCTION
    n = PEEKB(d + 6)
    IF n < 1 OR n > 7 THEN EXIT FUNCTION
    n = PEEK(d + 16)
    IF n < 0 OR n > 77 THEN EXIT FUNCTION
    _SVDIR = -1
END FUNCTION

' the entry of d named nm (upper case), 0 for none
FUNCTION _SVFIND (d, nm)
    DIM i, k, n, ent, c
    n = PEEKB(nm)
    FOR i = 1 TO PEEK(d + 16)
        ent = d + 26 * i
        IF PEEKB(ent + 6) = n THEN
            FOR k = 1 TO n
                c = PEEKB(ent + 6 + k)
                IF c >= 97 AND c <= 122 THEN c = c - 32
                IF c <> PEEKB(nm + k) THEN EXIT FOR
            NEXT k
            IF k > n THEN
                _SVFIND = i
                EXIT FUNCTION
            END IF
        END IF
    NEXT i
END FUNCTION

' does name end with suf (upper case)?
FUNCTION _SVSUF (name, suf)
    DIM n, m, i, c
    n = PEEKB(name)
    m = PEEKB(suf)
    IF n < m THEN EXIT FUNCTION
    FOR i = 1 TO m
        c = PEEKB(name + n - m + i)
        IF c >= 97 AND c <= 122 THEN c = c - 32
        IF c <> PEEKB(suf + i) THEN EXIT FUNCTION
    NEXT i
    _SVSUF = -1
END FUNCTION

' Where the file name is: 0 when it is not in a sub-volume, -1 when a
' volume or sub-volume on the way is not there, 1: its sub-volume's
' directory in d, its unit and first block in the entry e, its name in
' e's record
FUNCTION _SVPATH (e, name, d)
    DIM p, n, i, c, k, s, fib, u, base, j, ent
    n = PEEKB(name)
    IF n > 99 THEN n = 99
    p = _MALLOC(100)
    ' upper case, \ as /; c: after the volume's colon
    c = 0
    FOR i = 1 TO n
        k = PEEKB(name + i)
        IF k >= 97 AND k <= 122 THEN k = k - 32
        IF k = 92 THEN k = 47
        IF k = 58 THEN c = i
        POKEB p + i, k
    NEXT i
    i = c + 1
    DO WHILE i <= n
        IF PEEKB(p + i) <> 47 THEN EXIT DO
        i = i + 1
    LOOP
    ' a / after the first name: a path
    FOR k = i TO n
        IF PEEKB(p + k) = 47 THEN EXIT FOR
    NEXT k
    IF k > n THEN
        _MFREE p
        EXIT FUNCTION
    END IF
    _SVPATH = -1
    IF c + k - i > 30 THEN
        _MFREE p
        EXIT FUNCTION
    END IF
    ' the first sub-volume, VOL:A, by the operating system
    s = _SCRATCH
    FOR j = 1 TO c
        POKEB s + j, PEEKB(p + j)
    NEXT j
    FOR j = i TO k - 1
        POKEB s + c + j - i + 1, PEEKB(p + j)
    NEXT j
    POKEB s, c + k - i
    fib = _MALLOC(80)
    OSCALL 3, fib, 0, -1
    OSCALL 5, fib, s, 1, 0
    IF CSP%(34) <> 0 THEN
        _MFREE fib
        _MFREE p
        EXIT FUNCTION
    END IF
    u = PEEK(fib + 14)
    base = PEEK(fib + 32)
    OSCALL 6, fib, 0
    _MFREE fib
    ' the names after it: sub-volumes, the last the file
    DO
        IF NOT _SVDIR(u, base, d) THEN
            _MFREE p
            EXIT FUNCTION
        END IF
        DO WHILE k <= n
            IF PEEKB(p + k) <> 47 THEN EXIT DO
            k = k + 1
        LOOP
        i = k
        DO WHILE k <= n
            IF PEEKB(p + k) = 47 THEN EXIT DO
            k = k + 1
        LOOP
        ' the name, into the record
        IF k - i < 1 OR k - i > 15 THEN
            _MFREE p
            EXIT FUNCTION
        END IF
        s = PEEK(e + FFIB)
        FOR j = i TO k - 1
            POKEB s + j - i + 1, PEEKB(p + j)
        NEXT j
        POKEB s, k - i
        IF k > n THEN EXIT DO
        IF k - i <> 1 OR PEEKB(s + 1) <> 46 THEN
            ' (. is where the path is)
            j = _SVFIND(d, s)
            IF j = 0 THEN
                _MFREE p
                EXIT FUNCTION
            END IF
            ent = d + 26 * j
            IF (PEEK(ent + 4) AND 15) <> 5 THEN
                _MFREE p
                EXIT FUNCTION
            END IF
            base = base + PEEK(ent)
        END IF
    LOOP
    _MFREE p
    POKE e + FSVU, u
    POKE e + FSVB, base
    _SVPATH = 1
END FUNCTION

' the best place for a new file in d: the largest free area, or the larger
' half of what a file being written in one has left.  Its first block (in
' the sub-volume) into the record's word 20, the blocks it has the result
FUNCTION _SVROOM (e, d)
    DIM n, k, last, gs, ge, av, ast, avic, avs, ch, o, f, rs, re, best, rec, victim, vs
    rec = PEEK(e + FFIB)
    n = PEEK(d + 16)
    last = PEEK(d + 2)
    FOR k = 1 TO n + 1
        gs = last
        IF k <= n THEN
            ge = PEEK(d + 26 * k)
            last = PEEK(d + 26 * k + 2)
        ELSE
            ge = PEEK(d + 14)
        END IF
        av = ge - gs
        ast = gs
        avic = 0
        FOR ch = 1 TO CHRIN
            o = _FTAB + ch * 32
            IF o <> e AND (PEEK(o + FFL) AND FWRITE) <> 0 AND PEEK(o + FSVU) = PEEK(e + FSVU) AND PEEK(o + FSVB) = PEEK(e + FSVB) THEN
                f = PEEK(o + FSVF) - PEEK(o + FSVB)
                IF f >= gs AND f < ge THEN
                    IF avic = 0 THEN av = 0
                    rs = f + PEEK(o + FSVH)
                    re = f + PEEK(o + FSVR)
                    IF (re - rs) \ 2 > av THEN
                        av = (re - rs) \ 2
                        ast = re - av
                        avic = o
                        avs = ast - f
                    END IF
                END IF
            END IF
        NEXT ch
        IF av > best THEN
            best = av
            POKE rec + 20, ast
            victim = avic
            vs = avs
        END IF
    NEXT k
    IF best > 0 AND victim <> 0 THEN POKE victim + FSVR, vs
    _SVROOM = best
END FUNCTION

' OPEN of a file in a sub-volume (mode as _OPEN's): 0 not one, -1 it
' cannot be, 1 an old file, 2 a new one
FUNCTION _SVOPEN (e, name, mode)
    DIM d, r, i, n, ent, a, rec, k
    d = _MALLOC(2048)
    r = _SVPATH(e, name, d)
    rec = PEEK(e + FFIB)
    IF r = 1 THEN
        n = PEEK(d + 16)
        i = _SVFIND(d, rec)
        IF i > 0 AND mode <> 2 THEN
            ent = d + 26 * i
            a = PEEK(ent)
            POKE e + FSVF, PEEK(e + FSVB) + a
            POKE e + FSVH, PEEK(ent + 2) - a
            POKE rec + 16, PEEK(ent + 2) - a
            POKE rec + 18, PEEK(ent + 4) AND 15
            IF i < n THEN POKE e + FSVR, PEEK(ent + 26) - a ELSE POKE e + FSVR, PEEK(d + 14) - a
        ELSEIF mode <= 3 AND mode <> 2 THEN
            r = -1
        ELSE
            k = _SVROOM(e, d)
            IF k = 0 OR n >= 77 THEN
                r = -1
            ELSE
                POKE e + FSVF, PEEK(e + FSVB) + PEEK(rec + 20)
                POKE e + FSVR, k
                POKE e + FSVH, 0
                POKE rec + 16, 0
                k = 5
                IF _SVSUF(rec, SADD(".TEXT")) OR _SVSUF(rec, SADD(".BAS")) THEN k = 3
                IF _SVSUF(rec, SADD(".CODE")) THEN k = 2
                POKE rec + 18, k
                r = 2
            END IF
        END IF
    END IF
    _MFREE d
    _SVOPEN = r
END FUNCTION

' n blocks from the file's block b into / out of its buffer: the blocks
' done
FUNCTION _SVIO (e, nblocks, b, rd)
    DIM n
    IF rd THEN n = PEEK(e + FSVH) - b ELSE n = PEEK(e + FSVR) - b
    IF n > nblocks THEN n = nblocks
    IF n <= 0 OR b < 0 THEN EXIT FUNCTION
    IF rd THEN
        CSP 5, PEEK(e + FSVU), PEEK(e + FBUF), 0, n * 512, PEEK(e + FSVF) + b, 0
    ELSE
        CSP 6, PEEK(e + FSVU), PEEK(e + FBUF), 0, n * 512, PEEK(e + FSVF) + b, 0
    END IF
    IF CSP%(34) <> 0 THEN
        POKE e + FFL, PEEK(e + FFL) OR FERR
        EXIT FUNCTION
    END IF
    IF rd = 0 AND b + n > PEEK(e + FSVH) THEN POKE e + FSVH, b + n
    _SVIO = n
END FUNCTION

' CLOSE: the directory entry of a file new or of a new length; -1 if it
' cannot be written.  A new file that could not be written whole is not
' kept (an old one of its name stays).
FUNCTION _SVCLOSE (e)
    DIM d, rec, u, base, first, i, n, j, ent, date
    rec = PEEK(e + FFIB)
    IF (PEEK(e + FFL) AND FNEW) = 0 AND PEEK(e + FSVH) = PEEK(rec + 16) THEN EXIT FUNCTION
    _SVCLOSE = -1
    IF (PEEK(e + FFL) AND FNEW) <> 0 AND (PEEK(e + FFL) AND FERR) <> 0 THEN EXIT FUNCTION
    u = PEEK(e + FSVU)
    base = PEEK(e + FSVB)
    d = _MALLOC(2048)
    ' today: the boot disk's date
    CSP 5, PEEK(OSVAR(1) + 4), d, 0, 512, 2, 0
    IF CSP%(34) = 0 THEN date = PEEK(d + 20)
    IF NOT _SVDIR(u, base, d) THEN
        _MFREE d
        EXIT FUNCTION
    END IF
    first = PEEK(e + FSVF) - base
    i = _SVFIND(d, rec)
    n = PEEK(d + 16)
    IF PEEK(e + FFL) AND FNEW THEN
        IF i > 0 THEN
            ' the old file of that name goes
            IF i < n THEN CSP 2, d + 26 * (i + 1), 0, d + 26 * i, 0, (n - i) * 26
            n = n - 1
        END IF
        j = 1
        DO WHILE j <= n
            IF PEEK(d + 26 * j) >= first THEN EXIT DO
            j = j + 1
        LOOP
        ' the area must still be free
        IF j <= n THEN
            IF PEEK(d + 26 * j) < first + PEEK(e + FSVH) THEN j = -1
        END IF
        IF j > 1 THEN
            IF PEEK(d + 26 * (j - 1) + 2) > first THEN j = -1
        END IF
        IF j < 0 OR n >= 77 THEN
            _MFREE d
            EXIT FUNCTION
        END IF
        IF j <= n THEN CSP 3, d + 26 * j, 0, d + 26 * (j + 1), 0, (n - j + 1) * 26
        n = n + 1
        ent = d + 26 * j
        CSP 10, ent, 0, 26, 0
        POKE ent, first
        POKE ent + 4, PEEK(rec + 18)
        CSP 2, rec, 0, ent + 6, 0, PEEKB(rec) + 1
        POKE d + 16, n
    ELSE
        IF i = 0 THEN
            _MFREE d
            EXIT FUNCTION
        END IF
        ent = d + 26 * i
    END IF
    POKE ent + 2, first + PEEK(e + FSVH)
    POKE ent + 22, 512
    POKE ent + 24, date
    CSP 6, u, d, 0, 2048, base + 2, 0
    IF CSP%(34) = 0 THEN _SVCLOSE = 0
    _MFREE d
END FUNCTION

' KILL of a file in a sub-volume: 0 not one, -1 it cannot be, 1 done
FUNCTION _SVKILL (name)
    DIM e, d, r, i, n
    e = _MALLOC(32)
    CSP 10, e, 0, 32, 0
    POKE e + FFIB, _MALLOC(24)
    d = _MALLOC(2048)
    r = _SVPATH(e, name, d)
    IF r = 1 THEN
        i = _SVFIND(d, PEEK(e + FFIB))
        n = PEEK(d + 16)
        IF i = 0 THEN
            r = -1
        ELSE
            IF i < n THEN CSP 2, d + 26 * (i + 1), 0, d + 26 * i, 0, (n - i) * 26
            POKE d + 16, n - 1
            CSP 6, PEEK(e + FSVU), d, 0, 2048, PEEK(e + FSVB) + 2, 0
            IF CSP%(34) <> 0 THEN r = -1
        END IF
    END IF
    _MFREE d
    _MFREE PEEK(e + FFIB)
    _MFREE e
    _SVKILL = r
END FUNCTION
