' B2UTIL -- linked into every program of the compiler (B2, B2LEX, B2SYN ...,
' BCLIST, BCLINK): messages, file names, and the job file through which
' they hand the work on to each other (CHAIN)
#INCLUDE "B2COM"

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
' ---- errors: B2LEX's and B2NAME's are numbers (their texts are B2ERR's),
' kept with where they were until the step ends -- the 10th ends it
' (MAXERR: more would scroll the first off the screen): B2LEX reads no more
' lines, B2NAME's GetTok gives TEOF, and the passes, back at the top, see
' ErrCount; then the program chains to B2ERR, which says them all
' (CompileFailed: from the top, where the stack is short).  n: the
' message (n < 0: a fatal error, the end at once), a: a number in it, t:
' a token, s$: a string (its text's {a}, {t} or {k}, {s}).

DIM SHARED ErN(), ErA(), ErT(), ErL(), ErF$(), ErX$(), ErS$()

SUB ErrRec (n, a, t, s$)
    DIM i
    IF ErrCount >= MAXERR THEN EXIT SUB
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
    PRINT "B2: "; msg$
    PhaseDone 0
END SUB

' ---- types by a name's suffix

' the type a name's suffix gives, 0 for none
' the type a name's suffix says: % INTEGER, # SINGLE, ! DOUBLE, $ STRING,
' ~ BYTE (0: no suffix)
FUNCTION SuffixType (n$)
    SELECT CASE ASC(n$, LEN(n$))
    CASE 37: SuffixType = TYINT
    CASE 35: SuffixType = TYSNG
    CASE 33: SuffixType = TYDBL
    CASE 36: SuffixType = TYSTR
    CASE 126: SuffixType = TYBYTE
    END SELECT
END FUNCTION

FUNCTION BaseName$ (n$)
    IF SuffixType(n$) THEN BaseName$ = LEFT$(n$, LEN(n$) - 1) ELSE BaseName$ = n$
END FUNCTION

FUNCTION TypeChar$ (ty)
    SELECT CASE ty
    CASE TYINT: TypeChar$ = "%"
    CASE TYSNG: TypeChar$ = "#"
    CASE TYDBL: TypeChar$ = "!"
    CASE TYSTR: TypeChar$ = "$"
    CASE TYBYTE: TypeChar$ = "~"
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
' (B2LEX's names, B2NAME's tables; BCLINK's double: LinkGrown); NGrown
' counts them (B2NAME -M says how often its tables grew)
FUNCTION Grown (cap, max)
    DIM n
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
        SayLn "B2: this program is a part of B2: run B2"
        SYSTEM 1
    END IF
    OPEN JobName$ FOR INPUT AS #CHJOB
    LINE INPUT #CHJOB, JobHome$
    LINE INPUT #CHJOB, JobBlk$
    LINE INPUT #CHJOB, l$
    JobFlags = VAL(l$)
    LINE INPUT #CHJOB, JobCur$
    CLOSE #CHJOB
    IF JobFlags AND JFQUIET THEN OptQuiet = 1
    IF JobFlags AND JFMEM THEN OptMem = 1
    IF JobFlags AND JFKEEP THEN OptKeep = 1
END SUB

SEGMENT

' CHAIN to the program p$ of the compiler (args$ its command line); it
' cannot be found: a message, and the end with status 1.  Where the driver
' found it (JobBlk$): "@unit,block P$" -- the library's CHAIN runs it with
' no file opened, no directory read (memory a pass may not have left)
SUB ChainTo (p$, args$)
    DIM c$, k, b$
    c$ = JobHome$ + p$
    k = INSTR(JobBlk$, " " + p$ + "=")
    IF k > 0 THEN
        b$ = MID$(JobBlk$, k + LEN(p$) + 2)
        b$ = LEFT$(b$, INSTR(b$ + " ", " ") - 1)
        c$ = "@" + MID$(JobHome$, 2, LEN(JobHome$) - 2) + "," + b$ + " " + p$
    END IF
    IF args$ <> "" THEN c$ = c$ + " " + args$
    CLOSE
    ON ERROR RESUME NEXT
    CHAIN c$
    ON ERROR GOTO 0
    SayLn "B2: cannot run " + JobHome$ + p$ + ".CODE"
    SYSTEM 1
END SUB

' a step done (ok) or failed: back to the driver, for the next one
SUB PhaseDone (ok)
    IF ok THEN ChainTo "B2", "-Z 0" ELSE ChainTo "B2", "-Z 1"
END SUB

SEGMENT RTSELDOM

' a compile step's files: "C lst NAME"
SUB StepNames ()
    DIM n$, p
    p = INSTR(3, JobCur$, " ")
    OptList = VAL(MID$(JobCur$, 3, p - 3))
    n$ = MID$(JobCur$, p + 1)
    ' (the names #DEFINEd by -D: after the file's name)
    p = INSTR(n$, " ")
    IF p > 0 THEN
        Defines$ = MID$(n$, p + 1)
        n$ = LEFT$(n$, p - 1)
    END IF
    SrcName$ = SourceOf$(n$)
    ModName$ = ModOf$(n$)
    ObjName$ = DirOf$(n$) + ModName$ + ".OBJ"
    IF OptList THEN LstName$ = ListOf$(n$) ELSE LstName$ = ""
    TokFile$ = SrcName$
END SUB

' a compile failed: no object, no token file
SUB CompileFailed ()
    ' the errors, for B2ERR: their count, then seven lines each (n, a, t,
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
    ChainTo "B2ERR", ""
END SUB

' ---- B2ERR's: the step failed (the errors said); its files go
SUB StepFailed ()
    DIM i
    IF OptKeep = 0 THEN
        FOR i = 0 TO 7
            IF FileExists(PassFile$(i)) THEN KILL PassFile$(i)
        NEXT i
    END IF
    IF FileExists(SymName$) THEN KILL SymName$
    IF FileExists(DatName$) THEN KILL DatName$
    IF FileExists(ObjName$) THEN KILL ObjName$
    IF FileExists(":B2TEMP.LNK") THEN KILL ":B2TEMP.LNK"
    PhaseDone 0
END SUB

' ... done
SUB CompileDone ()
    IF OptQuiet = 0 THEN SayLn "  " + ObjName$
    IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words"
    PhaseDone -1
END SUB

' the file pass n writes (0 B2LEX's tokens, 1 B2CONST's): with -K NAME.Wn
' (B2DUMP shows it) in BASIC2:/MAP/Wn, BASIC2:/MAP or beside the source
' (AuxDir$), else a temporary one on the prefix volume
FUNCTION PassFile$ (n)
    IF OptKeep THEN
        IF JobFlags AND JFWDIRS THEN
            PassFile$ = "BASIC2:/MAP/W" + IStr$(n) + "/" + LEFT$(ModName$, 10) + ".W" + IStr$(n)
        ELSE
            PassFile$ = AuxDir$(SrcName$) + LEFT$(ModName$, 10) + ".W" + IStr$(n)
        END IF
    ELSE
        PassFile$ = ":B2TEMP.W" + IStr$(n)
    END IF
END FUNCTION

' where -K's NAME.Wn and -MAP's NAME.MAP go: BASIC2:/MAP/ when the volume
' BASIC2: has the sub-volume MAP (the driver looked: JFMAPDIR), else beside
' the file f$ they are made of
FUNCTION AuxDir$ (f$)
    IF JobFlags AND JFMAPDIR THEN AuxDir$ = "BASIC2:/MAP/" ELSE AuxDir$ = DirOf$(f$)
END FUNCTION

' f$ named by its volume's name, not its unit's number: VOL:NAME for
' #5:NAME, *NAME (the boot volume's: the system's SYVID, its global words
' 63..66) and NAME or :NAME (the prefix's, DKVID: 59..62), VOL:/A/NAME for
' one in a sub-volume.  The host: f$.
FUNCTION FullName$ (f$)
    DIM d(255), k, v$, r$, a, i, n, c
    FullName$ = f$
    IF OSVAR(1) = 0 THEN EXIT FUNCTION
    k = INSTR(f$, ":")
    r$ = UCASE$(MID$(f$, k + 1))
    IF k > 0 THEN v$ = UCASE$(LEFT$(f$, k - 1))
    IF v$ = "" AND LEFT$(r$, 1) = "*" THEN
        v$ = "*"
        r$ = MID$(r$, 2)
    END IF
    IF v$ = "*" THEN
        a = OSADDR(63)
    ELSEIF v$ = "" THEN
        a = OSADDR(59)
    ELSEIF LEFT$(v$, 1) = "#" THEN
        ' (the unit's directory: the volume's name at its byte 6)
        CSP 5, VAL(MID$(v$, 2)), VARPTR(d(0)), 0, 512, 2, 0
        IF CSP%(34) <> 0 THEN EXIT FUNCTION
        a = VARPTR(d(0)) + 6
    END IF
    IF a <> 0 THEN
        v$ = ""
        n = PEEK(a) AND 255
        IF n > 7 THEN EXIT FUNCTION
        FOR i = 1 TO n
            c = PEEK(a + (i AND &HFFFE))
            IF i AND 1 THEN c = (c \ 256) AND 255 ELSE c = c AND 255
            v$ = v$ + CHR$(c)
        NEXT i
    END IF
    IF v$ = "" THEN EXIT FUNCTION
    IF INSTR(r$, "/") > 0 AND LEFT$(r$, 1) <> "/" THEN r$ = "/" + r$
    FullName$ = v$ + ":" + r$
END FUNCTION

' the header's word THSRC + i for the path p$ (B2LEX's, B2CONST's)
FUNCTION PathWord (p$, i)
    DIM a, b
    IF i = 0 THEN
        a = LEN(p$)
        IF a > 2 * (WHWORDS - THSRC - 1) THEN a = 2 * (WHWORDS - THSRC - 1)
        PathWord = a
        EXIT FUNCTION
    END IF
    IF 2 * i - 1 <= LEN(p$) THEN a = ASC(p$, 2 * i - 1)
    IF 2 * i <= LEN(p$) THEN b = ASC(p$, 2 * i) AND 127
    PathWord = a + 256 * b
END FUNCTION

SEGMENT

' ---- every program's start

' the temporary files: on the prefix volume (:), not on the shell's path
TokName$ = ":B2TEMP.TOK"
SymName$ = ":B2TEMP.SYM"
LTmpName$ = ":B2TEMP.LST"
LCodName$ = ":B2TEMP.LCD"
DatName$ = ":B2TEMP.DAT"
JobName$ = ":B2TEMP.JOB"
ErrName$ = ":B2TEMP.ERR"
