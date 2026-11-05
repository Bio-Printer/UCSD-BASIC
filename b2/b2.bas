' B2 -- the second BASIC compiler for the UCSD P-System: the driver
'
' B2 compiles BASIC sources (NAME.BAS, text files) into object files
' (NAME.OBJ) and links object files and the library BASLIB.OBJ into a code
' file (NAME.CODE).  Commands, at the "Compile what file?" prompt or as the
' command line:
'   NAME            compile NAME.BAS (or NAME.TEXT) and link NAME.CODE
'   -C NAME         compile only: NAME.OBJ
'   -S NAME         compile with a listing (the BASIC statements and the
'                   P-code made for them) in NAME.LST; -S -C NAME too
'   -L OUT=A,B,...  link A.OBJ, B.OBJ ... (and BASLIB.OBJ) into OUT.CODE
'   -J LIB=A,B,...  join object files into one library LIB.OBJ
'   -MAP            with each link, NAME.MAP (B2DEBUG says a run-time
'                   error's line from it)
'   -D A,B          the compiles after it: A and B #DEFINEd
'   -K              keep each pass's file, NAME.W2 ... (B2DUMP shows them)
'   @FILE           the commands in FILE.TEXT, one or more a line
'   -Q              fewer messages;  -M  each pass's memory
' The compiler is many programs, each in memory alone (CHAIN,
' docs/B2DESIGN.md): this one, the driver, turns a command line (batch
' files and all) into steps, puts them into the job file and chains to the
' program of the first: B2LEX for a compile (its passes chain on to B2SYN,
' B2DECL ... B2ASM, B2LIST), B2LINK for a link; after errors a pass chains
' to B2ERR, which says them.  The last of them chains to B2 -Z (with 0, or
' 1 for a failure), which runs the next step, and at the end asks for the
' next command, or ends with that status when it was given its commands
' as its command line.
#INCLUDE "B2COM"

DIM SHARED CmdLine$, CmdPos, Steps$(MAXSTEP), NSteps
' -MAP: the links after it, in its command line, its batch file and the batch files that
' one names, write NAME.MAP (their steps M, not L); a batch file's -MAP ends with it.
' -D: the names #DEFINEd for the compiles after it, so too
DIM SHARED MapOn, DefOn$

' the next word of the command line ("" at its end)
FUNCTION NextWord$ ()
    DIM s, c
    DO WHILE CmdPos <= LEN(CmdLine$)
        c = ASC(CmdLine$, CmdPos)
        IF c <> 32 AND c <> 9 AND c <> 44 THEN EXIT DO
        CmdPos = CmdPos + 1
    LOOP
    s = CmdPos
    DO WHILE CmdPos <= LEN(CmdLine$)
        c = ASC(CmdLine$, CmdPos)
        IF c = 32 OR c = 9 THEN EXIT DO
        CmdPos = CmdPos + 1
    LOOP
    NextWord$ = MID$(CmdLine$, s, CmdPos - s)
END FUNCTION

' a step at the end of the queue
FUNCTION AddStep (s$)
    IF NSteps >= MAXSTEP THEN
        SayLn "B2: too many commands at once"
        EXIT FUNCTION
    END IF
    NSteps = NSteps + 1
    Steps$(NSteps) = s$
    AddStep = -1
END FUNCTION

' @FILE: each line of FILE.TEXT is a command line
FUNCTION AddBatch (f$)
    DIM l$, ok, n, i, lines$(200), savemap, savedef$
    savemap = MapOn
    savedef$ = DefOn$
    f$ = WithSuffix$(f$, ".TEXT")
    IF NOT FileExists(f$) THEN
        SayLn "B2: no file " + f$
        EXIT FUNCTION
    END IF
    ' read it all first: its lines may name more batch files
    OPEN f$ FOR INPUT AS #CHBAT
    DO WHILE NOT EOF(CHBAT) AND n < 200
        LINE INPUT #CHBAT, l$
        n = n + 1
        lines$(n) = l$
    LOOP
    CLOSE #CHBAT
    ok = -1
    FOR i = 1 TO n
        l$ = LTRIM$(lines$(i))
        IF l$ <> "" AND LEFT$(l$, 1) <> "'" THEN
            IF NOT AddCmds(l$) THEN
                ok = 0
                EXIT FOR
            END IF
        END IF
    NEXT i
    MapOn = savemap
    DefOn$ = savedef$
    AddBatch = ok
END FUNCTION

' one command line: its options and names, as steps -- C lst name (a
' compile), L OUT=A,B (a link; M OUT=A,B with its map), J LIB=A,B (a join);
' 0 if it has a mistake
FUNCTION AddCmds (l$)
    DIM w$, ok, lst, conly, savel$, savep
    savel$ = CmdLine$
    savep = CmdPos
    CmdLine$ = l$
    CmdPos = 1
    ok = -1
    DO
        w$ = UCASE$(NextWord$)
        IF w$ = "" THEN EXIT DO
        IF w$ = "-S" THEN
            lst = 1
        ELSEIF w$ = "-C" THEN
            conly = 1
        ELSEIF w$ = "-Q" THEN
            JobFlags = JobFlags OR JFQUIET
        ELSEIF w$ = "-M" THEN
            JobFlags = JobFlags OR JFMEM
        ELSEIF w$ = "-MAP" THEN
            MapOn = 1
        ELSEIF w$ = "-K" THEN
            JobFlags = JobFlags OR JFKEEP
        ELSEIF w$ = "-D" THEN
            DefOn$ = UCASE$(NextWord$)
        ELSEIF w$ = "-L" THEN
            ok = AddStep(MID$("LM", MapOn + 1, 1) + " " + UCASE$(NextWord$))
        ELSEIF w$ = "-J" THEN
            ok = AddStep("J " + UCASE$(NextWord$))
        ELSEIF LEFT$(w$, 1) = "@" THEN
            ok = AddBatch(MID$(w$, 2))
        ELSEIF LEFT$(w$, 1) = "-" THEN
            SayLn "B2: unknown option " + w$
            ok = 0
        ELSE
            IF DefOn$ <> "" THEN ok = AddStep("C " + IStr$(lst) + " " + w$ + " " + DefOn$) ELSE ok = AddStep("C " + IStr$(lst) + " " + w$)
            IF ok AND conly = 0 THEN ok = AddStep(MID$("LM", MapOn + 1, 1) + " " + DirOf$(w$) + ModOf$(w$))
            lst = 0
            conly = 0
        END IF
        IF NOT ok THEN EXIT DO
    LOOP
    CmdLine$ = savel$
    CmdPos = savep
    AddCmds = ok
END FUNCTION

' the job file: where the programs are, the options, the step being done,
' the steps after it
SUB WriteJob ()
    DIM i
    OPEN JobName$ FOR OUTPUT AS #CHJOB
    PRINT #CHJOB, JobHome$
    PRINT #CHJOB, JobBlk$
    PRINT #CHJOB, IStr$(JobFlags)
    PRINT #CHJOB, JobCur$
    FOR i = 1 TO NSteps
        PRINT #CHJOB, Steps$(i)
    NEXT i
    CLOSE #CHJOB
END SUB

' ... read back (BC -Z): the steps still to be done
SUB ReadSteps ()
    DIM l$
    NSteps = 0
    IF NOT FileExists(JobName$) THEN EXIT SUB
    OPEN JobName$ FOR INPUT AS #CHJOB
    LINE INPUT #CHJOB, l$
    LINE INPUT #CHJOB, l$
    LINE INPUT #CHJOB, l$
    JobFlags = VAL(l$)
    LINE INPUT #CHJOB, l$
    DO WHILE NOT EOF(CHJOB) AND NSteps < MAXSTEP
        LINE INPUT #CHJOB, l$
        IF l$ <> "" THEN
            NSteps = NSteps + 1
            Steps$(NSteps) = l$
        END IF
    LOOP
    CLOSE #CHJOB
END SUB

' the next step: the job file without it, and its program run (CHAIN)
SUB RunStep ()
    DIM i
    JobCur$ = Steps$(1)
    FOR i = 2 TO NSteps
        Steps$(i - 1) = Steps$(i)
    NEXT i
    NSteps = NSteps - 1
    WriteJob
    IF LEFT$(JobCur$, 1) = "C" THEN ChainTo "B2LEX", "" ELSE ChainTo "B2LINK", ""
END SUB

' the first block of each of the compiler's programs (B2xxx.CODE, at the
' top of the unit B2's code file is on: JobHome$), " B2LEX=123 ...", for
' ChainTo (the host: none -- PEEK and CSP are nothing there)
SUB FindBlocks (u)
    DIM d(1023), n, i, e, k, l, nm$, c
    JobBlk$ = ""
    CSP 5, u, VARPTR(d(0)), 0, 2048, 2, 0
    IF CSP%(34) <> 0 THEN EXIT SUB
    n = d(8)
    IF n > 77 THEN n = 77
    FOR i = 1 TO n
        e = 13 * i
        l = d(e + 3) AND 255
        nm$ = ""
        FOR k = 1 TO l
            IF (k AND 1) = 1 THEN c = (d(e + 3 + k \ 2) AND &HFF00) \ 256 ELSE c = d(e + 3 + k \ 2) AND 255
            nm$ = nm$ + CHR$(c)
        NEXT k
        ' (B2.CODE ... B2DEBUG.CODE: letters after B2 -- not BUILD's B2LEX2.CODE)
        IF LEFT$(nm$, 2) = "B2" AND RIGHT$(nm$, 5) = ".CODE" THEN
            nm$ = LEFT$(nm$, LEN(nm$) - 5)
            c = 1
            FOR k = 3 TO LEN(nm$)
                IF ASC(nm$, k) < 65 OR ASC(nm$, k) > 90 THEN c = 0
            NEXT k
            IF c AND LEN(JobBlk$) < 240 THEN JobBlk$ = JobBlk$ + " " + nm$ + "=" + IStr$(d(e))
        END IF
    NEXT i
END SUB

' ---- the main program

DIM cmd$, l$, failed
' the other programs are beside this one: on the unit its code file is on
' (SYSCOM^.SEGTABLE[1].CODEUNIT)
JobHome$ = "#" + IStr$(PEEK(OSVAR(1) + 102)) + ":"
FindBlocks PEEK(OSVAR(1) + 102)
cmd$ = COMMAND$
IF LEFT$(cmd$, 3) = "-Z " THEN
    ' a step is done: the next one, or (after a failure) none of the rest
    ReadSteps
    IF VAL(MID$(cmd$, 4)) <> 0 THEN
        failed = 1
        NSteps = 0
    END IF
ELSEIF cmd$ <> "" THEN
    IF NOT AddCmds(cmd$) THEN SYSTEM 1
ELSE
    JobFlags = JFASK
    PRINT "B2 -- BASIC compiler for the UCSD P-System"
END IF
IF JobFlags AND JFQUIET THEN OptQuiet = 1
DO
    IF NSteps > 0 THEN RunStep
    IF FileExists(JobName$) THEN KILL JobName$
    IF (JobFlags AND JFASK) = 0 THEN SYSTEM failed
    PRINT "Compile what file? ";
    LINE INPUT l$
    l$ = LTRIM$(RTRIM$(l$))
    IF l$ = "" THEN EXIT DO
    failed = 0
    JobFlags = JFASK
    IF NOT AddCmds(l$) THEN NSteps = 0
LOOP
END
