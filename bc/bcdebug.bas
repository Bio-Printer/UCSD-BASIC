' BCDEBUG -- where a program's run-time error was.  The library's _RTERR
' (lib/rtwhere.bas) says the error, then chains here with
'   BCDEBUG unit block S#,P#,I# S#,P#,I# ...
' the code file's unit and first block, and the procedures' frames from
' the innermost out: each one's segment, procedure and offset (I#, after
' the call).  BCDEBUG finds the code file's name in the unit's directory
' (and in the sub-volumes' on the way: Tiny-C's, data files holding a
' volume), reads NAME.MAP beside it (BCLINK -MAP) for the first frame
' that has lines there (the library's have none), and says
'   FILE line N, in NAME (S# s, P# p, I# i):
'   the line
' (the line read from the source file, beside the code file first when its
' name has no volume).  Without the map: each frame's numbers,
' s=S#,p=P#,i=I#.  It ends with the exit status 1.
DEFINT A-Z

CONST CHMAP = 1, CHSRC = 2, MAXF = 20

' the command line, where its next number is; the code file's unit, its
' path ("#u:" or "#u:/A/B/") and name; a directory read (DirBuf); the frames
DIM SHARED Cmd$, CPos, Unit, Path$, Prog$, DirBuf(1023)
DIM SHARED NFr, FrS(MAXF), FrP(MAXF), FrI(MAXF)
' what LookUp found: the procedure's name, the line's file and number
DIM SHARED FoundNm$, FoundF$, FoundLn

' the command line's next number (0 at its end; what is between numbers
' does not matter)
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

' the number at the start of s$ (after blanks)
FUNCTION LeadNum (s$)
    DIM j, c, v
    FOR j = 1 TO LEN(s$)
        c = ASC(s$, j)
        IF c >= 48 AND c <= 57 THEN
            v = v * 10 + c - 48
        ELSEIF c <> 32 OR v > 0 THEN
            EXIT FOR
        END IF
    NEXT j
    LeadNum = v
END FUNCTION

FUNCTION NumS$ (v)
    NumS$ = LTRIM$(STR$(v))
END FUNCTION

' the directory's byte o, word o (even)
FUNCTION DByte (o)
    DIM v
    v = DirBuf(o \ 2)
    IF o AND 1 THEN DByte = ((v AND &HFF00) \ 256) AND 255 ELSE DByte = v AND 255
END FUNCTION

FUNCTION DWord (o)
    DWord = DirBuf(o \ 2)
END FUNCTION

' the code file that starts at block blk of the unit: its name (Prog$) and
' path (Path$); 0 if it is not found
FUNCTION FindProg (blk)
    DIM base, depth, n, i, e, f, l, k, nm$
    Path$ = "#" + NumS$(Unit) + ":"
    FOR depth = 1 TO 4
        CSP 5, Unit, VARPTR(DirBuf(0)), 0, 2048, base + 2, 0
        IF CSP%(34) <> 0 THEN EXIT FUNCTION
        n = DWord(16)
        IF n > 77 THEN n = 77
        FOR i = 1 TO n
            e = 26 * i
            f = base + DWord(e)
            l = base + DWord(e + 2)
            IF blk >= f AND blk < l THEN EXIT FOR
        NEXT i
        IF i > n THEN EXIT FUNCTION
        nm$ = ""
        FOR k = 1 TO DByte(e + 6)
            nm$ = nm$ + CHR$(DByte(e + 6 + k))
        NEXT k
        IF f = blk THEN
            Prog$ = nm$
            FindProg = -1
            EXIT FUNCTION
        END IF
        ' (in a sub-volume: a data file)
        IF (DWord(e + 4) AND 15) <> 5 THEN EXIT FUNCTION
        IF RIGHT$(Path$, 1) = ":" THEN Path$ = Path$ + "/"
        Path$ = Path$ + nm$ + "/"
        base = f
    NEXT depth
END FUNCTION

' NAME.MAP's name (NAME.CODE's)
FUNCTION MapName$ ()
    IF RIGHT$(Prog$, 5) = ".CODE" THEN MapName$ = LEFT$(Prog$, LEN(Prog$) - 5) + ".MAP" ELSE MapName$ = Prog$ + ".MAP"
END FUNCTION

' the frame S# s, P# p, I# i in the map: 1 its line found (FoundNm$,
' FoundF$, FoundLn), 0 no line (the library's), -1 no map
FUNCTION LookUp (s, p, i)
    DIM l$, inseg, inproc, f$, j, c, a, b, part, k
    ON ERROR RESUME NEXT
    OPEN Path$ + MapName$ FOR INPUT AS #CHMAP
    IF ERR <> 0 THEN
        LookUp = -1
        EXIT FUNCTION
    END IF
    ON ERROR GOTO 0
    FoundLn = 0
    DO WHILE NOT EOF(CHMAP)
        LINE INPUT #CHMAP, l$
        IF LEFT$(l$, 3) = "S# " THEN
            IF inproc THEN EXIT DO
            inseg = LeadNum(MID$(l$, 4)) = s
        ELSEIF inseg AND LEFT$(l$, 5) = "  P# " THEN
            IF inproc THEN EXIT DO
            IF LeadNum(MID$(l$, 6)) = p THEN
                inproc = 1
                ' "  P#   3  NAME, 116 bytes"
                l$ = MID$(l$, 11)
                k = LEN(l$)
                DO WHILE k > 1
                    IF MID$(l$, k, 2) = ", " THEN EXIT DO
                    k = k - 1
                LOOP
                FoundNm$ = LEFT$(l$, k - 1)
                ' ("the main program (NAME'BODY)")
                IF LEFT$(FoundNm$, 17) = "the main program " THEN FoundNm$ = "the main program"
            END IF
        ELSEIF inproc THEN
            IF LEFT$(l$, 9) = "    FILE " THEN
                f$ = MID$(l$, 10)
            ELSE
                ' "I#:N I#:N ...": the last line whose code starts before i
                part = 0
                a = 0
                b = 0
                FOR j = 1 TO LEN(l$) + 1
                    IF j <= LEN(l$) THEN c = ASC(l$, j) ELSE c = 32
                    IF c >= 48 AND c <= 57 THEN
                        IF part = 0 THEN a = a * 10 + c - 48 ELSE b = b * 10 + c - 48
                    ELSEIF c = 58 THEN
                        part = 1
                    ELSEIF part = 1 THEN
                        IF a < i THEN
                            FoundLn = b
                            FoundF$ = f$
                        END IF
                        part = 0
                        a = 0
                        b = 0
                    END IF
                NEXT j
            END IF
        END IF
    LOOP
    CLOSE #CHMAP
    IF FoundLn > 0 THEN LookUp = 1
END FUNCTION

' line ln of the source file f$, without its indentation: 0 if the file
' cannot be read
FUNCTION SayLine (f$, ln)
    DIM i, l$
    ON ERROR RESUME NEXT
    OPEN f$ FOR INPUT AS #CHSRC
    IF ERR <> 0 THEN EXIT FUNCTION
    ON ERROR GOTO 0
    FOR i = 1 TO ln
        IF EOF(CHSRC) THEN EXIT FOR
        LINE INPUT #CHSRC, l$
    NEXT i
    CLOSE #CHSRC
    IF i > ln THEN PRINT LTRIM$(l$)
    SayLine = -1
END FUNCTION

' every frame's numbers, and why there is no more (why$)
SUB SayFrames (why$)
    DIM k
    FOR k = 1 TO NFr
        PRINT "s="; NumS$(FrS(k)); ",p="; NumS$(FrP(k)); ",i="; NumS$(FrI(k)); " ";
    NEXT k
    PRINT "("; why$; ")"
END SUB

' ---- BCDEBUG, the program

DIM blk, s, k, r
Cmd$ = COMMAND$
CPos = 1
Unit = CmdNum
blk = CmdNum
IF Unit = 0 THEN
    PRINT "BCDEBUG: a program's run-time error runs it (BCDEBUG unit block S#,P#,I# ...)"
    SYSTEM 1
END IF
DO WHILE NFr < MAXF
    s = CmdNum
    IF s = 0 THEN EXIT DO
    NFr = NFr + 1
    FrS(NFr) = s
    FrP(NFr) = CmdNum
    FrI(NFr) = CmdNum
LOOP
IF NOT FindProg(blk) THEN
    SayFrames "the code file not found"
    SYSTEM 1
END IF
' the first frame with lines in the map
FOR k = 1 TO NFr
    r = LookUp(FrS(k), FrP(k), FrI(k))
    IF r <> 0 THEN EXIT FOR
NEXT k
IF r = -1 THEN
    SayFrames "no " + MapName$ + ": link with -MAP"
ELSEIF r = 0 THEN
    SayFrames "not in " + MapName$
ELSE
    PRINT FoundF$; " line "; NumS$(FoundLn); ", in "; FoundNm$; " (S# "; NumS$(FrS(k)); ", P# "; NumS$(FrP(k)); ", I# "; NumS$(FrI(k)); "):"
    r = 0
    IF INSTR(FoundF$, ":") = 0 THEN r = SayLine(Path$ + FoundF$, FoundLn)
    IF r = 0 THEN r = SayLine(FoundF$, FoundLn)
END IF
SYSTEM 1
