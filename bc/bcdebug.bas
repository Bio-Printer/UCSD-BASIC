' BCDEBUG -- where a program's run-time error was.  The library's _RTERR
' (lib/rtwhere.bas) says the error, then chains here with
'   BCDEBUG unit block S#,P#,I# S#,P#,I# ...
' the code file's unit and first block, and the procedures' frames from
' the innermost out: each one's segment, procedure and offset (I#, after
' the call).  BCDEBUG reads the line tables BCLINK puts after the code
' file's segments (bclink.bas: WriteLines), finds the first frame that is
' not the library's, and says
'   FILE line N, in NAME (S# s, P# p, I# i):
'   the line
' (the line read from the source file, beside the code file first when its
' name has no volume).  No line tables (linked by an older BC), or no
' frame of the program's own among those given: S#, P#, I# of the first.  It ends with the exit status 1.
DEFINT A-Z

CONST LTMAGIC = 17474

' the command line, where its next number is; the code file's unit, where
' the tables start (block), one of their blocks read (Blk, its number
' BlkNo); where the next byte is read (block WB, byte WI)
DIM SHARED Cmd$, CPos, Unit, Base, Blk(255), BlkNo, WB, WI

' (0 at the end; what is between the numbers does not matter)
FUNCTION CmdNum ()
    DIM v, c
    DO WHILE CPos <= LEN(Cmd$)
        c = ASC(Cmd$, CPos)
        IF c >= 48 AND c <= 57 THEN EXIT DO
        CPos = CPos + 1
    LOOP
    DO WHILE CPos <= LEN(Cmd$)
        c = ASC(Cmd$, CPos)
        IF c < 48 OR c > 57 THEN EXIT DO
        v = v * 10 + c - 48
        CPos = CPos + 1
    LOOP
    CmdNum = v
END FUNCTION

FUNCTION NumS$ (v)
    NumS$ = LTRIM$(STR$(v))
END FUNCTION

' the tables' word w next
SUB WSeek (w)
    WB = Base + w \ 256
    WI = (w MOD 256) * 2
END SUB

' their next byte (255, the end of a line table, when it cannot be read)
FUNCTION WByte ()
    DIM v
    IF WB <> BlkNo THEN
        CSP 5, Unit, VARPTR(Blk(0)), 0, 512, WB, 0
        BlkNo = WB
        IF CSP%(34) <> 0 THEN BlkNo = -1
    END IF
    IF BlkNo < 0 THEN
        WByte = 255
        EXIT FUNCTION
    END IF
    v = Blk(WI \ 2)
    IF WI AND 1 THEN v = ((v AND &HFF00) \ 256) AND 255 ELSE v = v AND 255
    WI = WI + 1
    IF WI = 512 THEN
        WI = 0
        WB = WB + 1
    END IF
    WByte = v
END FUNCTION

FUNCTION WWord ()
    DIM lo
    lo = WByte
    WWord = lo OR WByte * 256
END FUNCTION

FUNCTION WStr$ ()
    DIM n, i, s$
    n = WByte
    FOR i = 1 TO n
        s$ = s$ + CHR$(WByte)
    NEXT i
    WStr$ = s$
END FUNCTION

' a record read over: 0 at the end of the records
FUNCTION SkipRec ()
    DIM n, i, d, x
    n = WByte
    IF n = 0 OR n = 255 THEN EXIT FUNCTION
    FOR i = 1 TO n
        x = WByte
    NEXT i
    DO
        d = WByte
        IF d = 255 THEN EXIT DO
        IF d = 253 THEN n = 4 ELSE n = 1
        FOR i = 1 TO n
            x = WByte
        NEXT i
    LOOP
    SkipRec = -1
END FUNCTION

' line ln of the source file f$, without its indentation: 0 if the file
' cannot be read
FUNCTION SayLine (f$, ln)
    DIM i, l$
    ON ERROR RESUME NEXT
    OPEN f$ FOR INPUT AS #1
    IF ERR <> 0 THEN EXIT FUNCTION
    ON ERROR GOTO 0
    FOR i = 1 TO ln
        IF EOF(1) THEN EXIT FOR
        LINE INPUT #1, l$
    NEXT i
    CLOSE #1
    IF i > ln THEN PRINT LTRIM$(l$)
    SayLine = -1
END FUNCTION

' ---- BCDEBUG, the program

DIM ok, rs, s, p, i, k, r, s0, p0, i0, d, off, ln, fl, bl, bf, nm$, f$
Cmd$ = COMMAND$
CPos = 1
Unit = CmdNum
Base = CmdNum
IF Unit = 0 THEN
    PRINT "BCDEBUG: a program's run-time error runs it (BCDEBUG unit block S#,P#,I# ...)"
    SYSTEM 1
END IF
BlkNo = -1
' block 0's last words: where the tables are (bclink.bas: WriteLines)
WSeek 254
ok = WWord = LTMAGIC
Base = Base + WWord
IF ok THEN
    WSeek 0
    rs = WWord
END IF
' the frames: the first with a record (not the library's)
DO
    s = CmdNum
    IF s = 0 THEN EXIT DO
    p = CmdNum
    i = CmdNum
    IF s0 = 0 THEN
        s0 = s
        p0 = p
        i0 = i
    END IF
    IF ok THEN
        WSeek s
        k = WWord
        IF k > 0 THEN
            WSeek k
            IF p <= WWord THEN
                WSeek k + p
                r = WWord
            END IF
        END IF
    END IF
    IF r <> 0 OR NOT ok THEN EXIT DO
LOOP
IF r = 0 THEN
    IF s0 = 0 THEN SYSTEM 1
    IF ok THEN
        PRINT "in the library: S# "; NumS$(s0); ", P# "; NumS$(p0); ", I# "; NumS$(i0); " (its calls too deep to follow)"
    ELSE
        PRINT "S# "; NumS$(s0); ", P# "; NumS$(p0); ", I# "; NumS$(i0); " (the code file has no line tables)"
    END IF
    SYSTEM 1
END IF
' the record: its name; its line, the last whose code starts before I#
' (which is after the call)
WSeek rs
FOR k = 1 TO r - 1
    d = SkipRec
NEXT k
nm$ = WStr$
DO
    d = WByte
    IF d = 255 THEN EXIT DO
    IF d = 254 THEN
        fl = WByte
    ELSE
        IF d = 253 THEN
            off = WWord
            ln = WWord
        ELSE
            off = off + d
            ln = ln + WByte
        END IF
        IF off < i THEN
            bl = ln
            bf = fl
        END IF
    END IF
LOOP
' its file's name: after the records
DO WHILE SkipRec
LOOP
IF bf > 0 AND bf <= WByte THEN
    FOR k = 1 TO bf
        f$ = WStr$
    NEXT k
END IF
IF bl > 0 AND f$ <> "" THEN
    PRINT f$; " line "; NumS$(bl); ", in "; nm$; " (S# "; NumS$(s); ", P# "; NumS$(p); ", I# "; NumS$(i); "):"
    k = 0
    IF INSTR(f$, ":") = 0 THEN k = SayLine("#" + NumS$(Unit) + ":" + f$, bl)
    IF k = 0 THEN k = SayLine(f$, bl)
ELSE
    PRINT "in "; nm$; " (S# "; NumS$(s); ", P# "; NumS$(p); ", I# "; NumS$(i); ")"
END IF
SYSTEM 1
