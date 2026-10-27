' BCUTIL -- linked into every program of the compiler (BC, BCLEX, BCGEN,
' BCLIST, BCLINK): messages, file names, and the job file through which
' they hand the work on to each other (CHAIN)
#INCLUDE "BCCOM"

' ---- messages

SUB Say (s$)
    PRINT s$;
END SUB

SUB SayLn (s$)
    PRINT s$
END SUB

FUNCTION IStr$ (n)
    IStr$ = LTRIM$(STR$(n))
END FUNCTION

FUNCTION UpStr$ (s$)
    UpStr$ = UCASE$(s$)
END FUNCTION

' an error in the source: where, what, and the line
' ---- errors: BCLEX's and BCGEN's are numbers (their texts are BCERR's),
' kept with where they were until the step ends -- the 10th ends it at
' once (MAXERR: more would scroll the first off the screen); then the
' program chains to BCERR, which says them all (CompileFailed).  n: the
' message (n < 0: a fatal error, the end at once), a: a number in it, t:
' a token, s$: a string (its text's {a}, {t} or {k}, {s}).

DIM SHARED ErN(), ErA(), ErT(), ErL(), ErF$(), ErX$(), ErS$()

SUB ErrRec (n, a, t, s$)
    DIM i
    ErrCount = ErrCount + 1
    i = ErrCount
    IF i = 1 THEN REDIM ErN(MAXERR), ErA(MAXERR), ErT(MAXERR), ErL(MAXERR), ErF$(MAXERR), ErX$(MAXERR), ErS$(MAXERR)
    ErN(i) = n
    ErA(i) = a
    ErT(i) = t
    IF Tok = TLINE THEN
        ' (the statement ended: it was on the line before)
        ErL(i) = PrevLine
        ErF$(i) = PrevFile$
        ErX$(i) = PrevText$
    ELSE
        ErL(i) = TokLine
        ErF$(i) = LineFile$
        IF LineFile$ = "" THEN ErF$(i) = TokFile$
        ErX$(i) = TokText$
    END IF
    ErS$(i) = s$
    IF i >= MAXERR THEN CompileFailed
END SUB

SUB ErrNo (n)
    ErrRec n, 0, 0, ""
END SUB

' an error after which the step cannot go on
SUB FatalRec (n, s$)
    ErrRec -n, 0, 0, s$
    CompileFailed
END SUB

SUB Fatal (msg$)
    PRINT "BC: "; msg$
    PhaseDone 0
END SUB

' ---- types by a name's suffix

' the type a name's suffix gives, 0 for none
FUNCTION SuffixType (n$)
    SELECT CASE ASC(n$, LEN(n$))
    CASE 37: SuffixType = TYINT
    CASE 33: SuffixType = TYSNG
    CASE 35: SuffixType = TYDBL
    CASE 36: SuffixType = TYSTR
    END SELECT
END FUNCTION

FUNCTION BaseName$ (n$)
    IF SuffixType(n$) THEN BaseName$ = LEFT$(n$, LEN(n$) - 1) ELSE BaseName$ = n$
END FUNCTION

FUNCTION TypeChar$ (ty)
    SELECT CASE ty
    CASE TYINT: TypeChar$ = "%"
    CASE TYSNG: TypeChar$ = "!"
    CASE TYDBL: TypeChar$ = "#"
    CASE TYSTR: TypeChar$ = "$"
    CASE TYBYTE: TypeChar$ = "%"
    END SELECT
END FUNCTION

' ---- files

FUNCTION FileExists (f$)
    ON ERROR RESUME NEXT
    OPEN f$ FOR INPUT AS #CHLTMP
    IF ERR = 0 THEN
        CLOSE #CHLTMP
        FileExists = -1
    END IF
    ON ERROR GOTO 0
END FUNCTION

' (the names of files, the job file, the end of a step: seldom, in the
' library's segment RTSELDOM; MemNote, and the CHAIN to the next program,
' which ends every program, a Fatal error deep in GEN too, in the main one)
SEGMENT RTSELDOM

' NAME with the suffix suf$ unless it has one (a dot after its volume and
' sub-volumes)
FUNCTION WithSuffix$ (f$, suf$)
    DIM i, c
    FOR i = LEN(f$) TO 1 STEP -1
        c = ASC(f$, i)
        IF c = 46 THEN
            WithSuffix$ = f$
            EXIT FUNCTION
        END IF
        IF c = 58 OR c = 47 OR c = 92 THEN EXIT FOR
    NEXT i
    WithSuffix$ = f$ + suf$
END FUNCTION

' where a file is: its volume and sub-volumes ("#5:" of "#5:FOO.BAS",
' "BASIC:/SRC/" of "BASIC:/SRC/BC.BAS"), "" for none
FUNCTION DirOf$ (f$)
    DIM i, c
    FOR i = LEN(f$) TO 1 STEP -1
        c = ASC(f$, i)
        IF c = 58 OR c = 47 OR c = 92 THEN
            DirOf$ = LEFT$(f$, i)
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

' FOO of VOL:FOO.BAS (and of VOL:/A/FOO.BAS)
FUNCTION ModOf$ (f$)
    DIM s$, i
    s$ = MID$(f$, LEN(DirOf$(f$)) + 1)
    i = INSTR(s$, ".")
    IF i > 0 THEN s$ = LEFT$(s$, i - 1)
    ModOf$ = UCASE$(s$)
END FUNCTION

' the source file of NAME: NAME, NAME.BAS or NAME.TEXT
FUNCTION SourceOf$ (n$)
    SourceOf$ = FindSource$(n$, "")
END FUNCTION

' a BASIC source file: NAME as named when it has a suffix, else NAME.BAS
' or NAME.TEXT; in dir$ first when dir$ is not "".  The first name tried
' when there is none.
FUNCTION FindSource$ (n$, dir$)
    DIM i, c$
    FOR i = 1 TO 2
        IF WithSuffix$(n$, ".X") = n$ THEN
            c$ = n$
        ELSEIF i = 1 THEN
            c$ = n$ + ".BAS"
        ELSE
            c$ = n$ + ".TEXT"
        END IF
        IF dir$ <> "" THEN
            IF FileExists(dir$ + c$) THEN
                FindSource$ = dir$ + c$
                EXIT FUNCTION
            END IF
        END IF
        IF FileExists(c$) THEN
            FindSource$ = c$
            EXIT FUNCTION
        END IF
    NEXT i
    IF WithSuffix$(n$, ".X") = n$ THEN FindSource$ = n$ ELSE FindSource$ = n$ + ".BAS"
END FUNCTION

' the listing file: NAME.LST (the name cut so that it fits in 15), a file
' of lines that end in CR, not a UCSD text file
FUNCTION ListOf$ (n$)
    DIM m$
    m$ = ModOf$(n$)
    IF LEN(m$) > 11 THEN m$ = LEFT$(m$, 11)
    ListOf$ = DirOf$(n$) + m$ + ".LST"
END FUNCTION

SEGMENT

' n, max at most (a table's size)
FUNCTION Capped (n, max)
    IF n > max OR n < 0 THEN Capped = max ELSE Capped = n
END FUNCTION

' a table's new size when cap entries were too few: 100 more, max at most
' (BCLEX's names, BCGEN's tables; BCLINK's double: LinkGrown); NGrown
' counts them (BCGEN -M says how often its tables grew)
FUNCTION Grown (cap, max)
    DIM n
    NGrown = NGrown + 1
    n = cap + 100
    IF n > max THEN n = max
    Grown = n
END FUNCTION

SUB MemNote (w$)
    IF OptMem THEN SayLn "  [" + w$ + ": " + IStr$(FRE(0)) + " free, least " + IStr$(FRE(-1)) + "]"
END SUB

SEGMENT RTSELDOM

' ---- the job (BC writes it; the other programs read it, do the step and
' chain on)

' the job's first lines: where the programs are, the options, the step
SUB ReadJob ()
    DIM l$
    IF NOT FileExists(JobName$) THEN
        SayLn "BC: this program is a part of BC: run BC"
        SYSTEM 1
    END IF
    OPEN JobName$ FOR INPUT AS #CHJOB
    LINE INPUT #CHJOB, JobHome$
    LINE INPUT #CHJOB, l$
    JobFlags = VAL(l$)
    LINE INPUT #CHJOB, JobCur$
    CLOSE #CHJOB
    IF JobFlags AND JFQUIET THEN OptQuiet = 1
    IF JobFlags AND JFMEM THEN OptMem = 1
END SUB

SEGMENT

' CHAIN to the program p$ of the compiler (args$ its command line); it
' cannot be found: a message, and the end with status 1
SUB ChainTo (p$, args$)
    DIM c$
    c$ = JobHome$ + p$
    IF args$ <> "" THEN c$ = c$ + " " + args$
    CLOSE
    ON ERROR RESUME NEXT
    CHAIN c$
    ON ERROR GOTO 0
    SayLn "BC: cannot run " + JobHome$ + p$ + ".CODE"
    SYSTEM 1
END SUB

' a step done (ok) or failed: back to the driver, for the next one
SUB PhaseDone (ok)
    IF ok THEN ChainTo "BC", "-Z 0" ELSE ChainTo "BC", "-Z 1"
END SUB

SEGMENT RTSELDOM

' a compile step's files: "C lst NAME"
SUB StepNames ()
    DIM n$, p
    p = INSTR(3, JobCur$, " ")
    OptList = VAL(MID$(JobCur$, 3, p - 3))
    n$ = MID$(JobCur$, p + 1)
    SrcName$ = SourceOf$(n$)
    ModName$ = ModOf$(n$)
    ObjName$ = DirOf$(n$) + ModName$ + ".OBJ"
    IF OptList THEN LstName$ = ListOf$(n$) ELSE LstName$ = ""
    TokFile$ = SrcName$
END SUB

' a compile failed: no object, no token file
SUB CompileFailed ()
    ' the errors, for BCERR: their count, then seven lines each (n, a, t,
    ' the line's number, the file, the line's text, the string)
    DIM i, n
    n = ErrCount
    IF n > MAXERR THEN n = MAXERR
    OPEN ErrName$ FOR OUTPUT AS #CHJOB
    PRINT #CHJOB, IStr$(ErrCount)
    FOR i = 1 TO n
        PRINT #CHJOB, IStr$(ErN(i))
        PRINT #CHJOB, IStr$(ErA(i))
        PRINT #CHJOB, IStr$(ErT(i))
        PRINT #CHJOB, IStr$(ErL(i))
        PRINT #CHJOB, ErF$(i)
        PRINT #CHJOB, ErX$(i)
        PRINT #CHJOB, ErS$(i)
    NEXT i
    CLOSE #CHJOB
    ChainTo "BCERR", ""
END SUB

' ---- BCERR's: the step failed (the errors said); its files go
SUB StepFailed ()
    IF FileExists(TokName$) THEN KILL TokName$
    IF FileExists(ObjName$) THEN KILL ObjName$
    PhaseDone 0
END SUB

' ... done
SUB CompileDone ()
    IF OptQuiet = 0 THEN SayLn "  " + ObjName$
    IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words"
    PhaseDone -1
END SUB

' ---- every program's start

DIM SegName$(MAXSEG), DefType(25), ParName$(30), ParFlags(30)
' the temporary files: on the prefix volume (:), not on the shell's path
TokName$ = ":BCTEMP.TOK"
LTmpName$ = ":BCTEMP.LST"
LCodName$ = ":BCTEMP.LCD"
DatName$ = ":BCTEMP.DAT"
JobName$ = ":BCTEMP.JOB"
ErrName$ = ":BCTEMP.ERR"
