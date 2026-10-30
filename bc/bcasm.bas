' BCASM -- pass 4 of a compile: the procedures pass 3 made, assembled into
' the object file
'
' BCGEN (pass 3) writes each procedure's code to the stream :BCTEMP.ASM as
' it makes it (BCEMIT; the records are BCGENCOM's AMxxx): its bytes, its
' jumps, case words and labels by number, its relocations by name, its
' lines; the entry code, made last, between AMENTRY and AMENTRYEND; at
' AMEND its frame and its name.  BCASM does with them what BCGEN did in
' memory: the procedure in Code() from offset 0 (a UJP to the label right
' after it dropped), the entry code moved to the front, the jumps resolved
' (one of more than 127 bytes forward, or any backward one, through the
' procedure's jump table), the attribute words, the P record; and the
' listing's records.  So neither the code nor its tables are in BCGEN's
' memory (docs/DESIGN.md sections 5 and 10).
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"

' the long jumps' targets; the listing's statement record (written one
' behind: AsSetLabel may move it); the highest label known; where the
' entry code started, and the relocations before it
DIM SHARED LongLab(60), PendPC, PendLine, PendText$, PendSet, LabHi, ESave, ERel0

' ---- the stream

FUNCTION AsB ()
    DIM b AS BYTE
    GET #CHASM, , b
    AsB = b
END FUNCTION

FUNCTION AsW ()
    DIM w
    GET #CHASM, , w
    AsW = w
END FUNCTION

FUNCTION AsS$ ()
    DIM n AS BYTE, s$
    GET #CHASM, , n
    IF n > 0 THEN
        s$ = SPACE$(n)
        GET #CHASM, , s$
    END IF
    AsS$ = s$
END FUNCTION

' ---- the procedure's code

SUB AsOB (b)
    IF PC >= MAXCODE - 40 THEN
        ErrNo 110   ' procedure too large: split it
        PC = 0
    END IF
    Code(PC) = b AND 255
    PC = PC + 1
END SUB

SUB AsOW (w)
    AsOB w AND 255
    AsOB (w AND &HFF00) \ 256
END SUB

' label l known (not set: -1)
SUB AsLab (l)
    DO WHILE LabHi < l
        LabHi = LabHi + 1
        LabPos(LabHi) = -1
    LOOP
END SUB

SUB AsSetLabel (l)
    DIM i
    AsLab l
    ' a UJP to this very label just before it: dropped
    IF NFix > 0 AND PC >= 2 THEN
        IF FixPos(NFix - 1) = PC - 1 AND FixLab(NFix - 1) = l AND Code(PC - 2) = OUJP THEN
            NFix = NFix - 1
            PC = PC - 2
            FOR i = 0 TO LabHi
                IF LabPos(i) = PC + 2 THEN LabPos(i) = PC
            NEXT i
            IF PendSet AND PendPC = PC + 2 THEN PendPC = PC
        END IF
    END IF
    LabPos(l) = PC
END SUB

SUB AsJump (op, l)
    AsLab l
    AsOB op
    FixPos(NFix) = PC
    FixLab(NFix) = l
    NFix = NFix + 1
    AsOB 0
END SUB

' a word of a case table: self-relative, the target is its address - it
SUB AsCase (l)
    AsLab l
    FixPos(NFix) = PC
    FixLab(NFix) = -2 - l
    NFix = NFix + 1
    AsOW 0
END SUB

SUB AsReloc (ty, n$)
    RelPos(NRel) = PC
    RelType(NRel) = ty
    RelName$(NRel) = n$
    NRel = NRel + 1
END SUB

SUB AsLineAt (pc, l)
    IF NLn >= LnCap THEN
        LnCap = Grown(LnCap, 32000)
        REDIM PRESERVE LnPC(LnCap), LnNo(LnCap)
    END IF
    LnPC(NLn) = pc
    LnNo(NLn) = l
    NLn = NLn + 1
END SUB

' the lines' file is n$ now (its name without volume and path): a file
' change in the line table
SUB AsFile (n$)
    DIM f
    f = 1
    DO WHILE f <= NLnFile
        IF LnFile$(f) = n$ THEN EXIT DO
        f = f + 1
    LOOP
    IF f > NLnFile AND NLnFile < MAXLNF THEN
        NLnFile = f
        LnFile$(f) = n$
    END IF
    IF f <= NLnFile THEN AsLineAt -1, f
END SUB

' the entry code made (since ESave): moved in front of the procedure's code
SUB AsEntry ()
    DIM pro(24) AS BYTE, np, i
    np = PC - ESave
    FOR i = 0 TO np - 1
        pro(i) = Code(ESave + i)
    NEXT i
    PC = ESave
    IF np = 0 THEN EXIT SUB
    ' move the code up by np bytes
    FOR i = PC - 1 TO 0 STEP -1
        Code(i + np) = Code(i)
    NEXT i
    FOR i = 0 TO np - 1
        Code(i) = pro(i)
    NEXT i
    PC = PC + np
    FOR i = 0 TO LabHi
        IF LabPos(i) >= 0 THEN LabPos(i) = LabPos(i) + np
    NEXT i
    FOR i = 0 TO NFix - 1
        FixPos(i) = FixPos(i) + np
    NEXT i
    FOR i = 0 TO ERel0 - 1
        RelPos(i) = RelPos(i) + np
    NEXT i
    ' the entry code's own relocations: they were made at ESave
    FOR i = ERel0 TO NRel - 1
        RelPos(i) = RelPos(i) - ESave
    NEXT i
    EntryBytes = np
END SUB

' ---- the object file

SUB AsObjByte (b)
    DIM x AS BYTE
    x = b AND 255
    PUT #CHOBJ, , x
END SUB

SUB AsObjWord (w)
    PUT #CHOBJ, , w
END SUB

SUB AsObjStr (s$)
    AsObjByte LEN(s$)
    IF LEN(s$) > 0 THEN PUT #CHOBJ, , s$
END SUB

' ---- the listing's records

SUB AsFlush ()
    IF PendSet THEN
        PRINT #CHLREC, IStr$(PendPC); " "; IStr$(PendLine)
        PRINT #CHLREC, PendText$
        PendSet = 0
    END IF
END SUB

' the listing of a procedure, for LIST: its statements' records end with a
' *; its code goes to LCodName$ -- its name, "PC entry-bytes
' jump-table-entries code-end relocations", its bytes in hex (32 a line),
' each relocation "position kind name"
SUB AsListSave (nm$)
    DIM i, s$
    PRINT #CHLREC, "*"
    PRINT #CHLCOD, nm$
    PRINT #CHLCOD, IStr$(PC); " "; IStr$(EntryBytes); " "; IStr$(NLong); " "; IStr$(CodeEndPos); " "; IStr$(NRel)
    FOR i = 0 TO PC - 1
        s$ = s$ + RIGHT$("0" + HEX$(Code(i)), 2)
        IF LEN(s$) = 64 OR i = PC - 1 THEN
            PRINT #CHLCOD, s$
            s$ = ""
        END IF
    NEXT i
    FOR i = 0 TO NRel - 1
        IF RelType(i) = RGSTAT THEN s$ = "" ELSE s$ = RelName$(i)
        PRINT #CHLCOD, IStr$(RelPos(i)); " "; IStr$(RelType(i)); " "; s$
    NEXT i
END SUB

' ---- a procedure's end (AMEND): the jumps, the jump table and the
' attributes; the P record

SUB AsEnd ()
    DIM i, k, t, pos, off, jtab, exitpos, flags, nm$, sg$, exitlab
    exitlab = AsW
    MaxLocal = AsW
    NParamWords = AsW
    ResWords = AsB
    flags = AsB
    nm$ = AsS$
    sg$ = AsS$
    ' (where, for an error: the procedure's end)
    Tok = 0
    TokLine = AsW
    LineFile$ = AsS$
    TokText$ = AsS$
    AsLab exitlab
    exitpos = LabPos(exitlab)
    NLong = 0
    FOR i = 0 TO NFix - 1
        IF FixLab(i) >= 0 THEN
            pos = FixPos(i)
            t = LabPos(FixLab(i))
            IF t < 0 THEN
                ErrNo 116   ' internal: a label not set
                t = 0
            END IF
            off = t - (pos + 1)
            IF off >= 0 AND off <= 127 THEN
                Code(pos) = off
            ELSE
                k = 0
                DO WHILE k < NLong
                    IF LongLab(k) = t THEN EXIT DO
                    k = k + 1
                LOOP
                IF k = NLong THEN
                    IF NLong >= 60 THEN
                        ErrNo 117   ' procedure too large (more than 60 long jumps): split it
                        k = 0
                    ELSE
                        LongLab(NLong) = t
                        NLong = NLong + 1
                    END IF
                END IF
                Code(pos) = (256 - 10 - 2 * k) AND 255
            END IF
        END IF
    NEXT i
    CodeEndPos = PC
    IF PC AND 1 THEN AsOB 0
    jtab = PC + 2 * NLong + 8
    FOR k = NLong - 1 TO 0 STEP -1
        pos = jtab - 10 - 2 * k
        AsOW pos - LongLab(k)
    NEXT k
    AsOW (MaxLocal - NParamWords) * 2
    AsOW NParamWords * 2
    AsOW jtab - 4 - exitpos
    AsOW jtab - 2
    AsOB 0
    AsOB 1
    ' the case tables
    FOR i = 0 TO NFix - 1
        IF FixLab(i) <= -2 THEN
            pos = FixPos(i)
            AsLab -2 - FixLab(i)
            t = LabPos(-2 - FixLab(i))
            Code(pos) = (pos - t) AND 255
            Code(pos + 1) = ((pos - t) AND &HFF00) \ 256
        END IF
    NEXT i
    IF ErrCount = 0 THEN
        AsObjByte 80
        AsObjByte flags
        AsObjStr nm$
        AsObjStr sg$
        AsObjWord NParamWords * 2
        AsObjByte ResWords
        AsObjWord PC
        AsObjWord jtab
        FOR i = 0 TO PC - 1
            AsObjByte Code(i)
        NEXT i
        AsObjWord NRel
        FOR i = 0 TO NRel - 1
            AsObjWord RelPos(i)
            AsObjByte RelType(i)
            AsObjStr RelName$(i)
        NEXT i
        ' the line table: (where a line's code starts, the line), a file
        ' change -1 and the file's name (the entry code before them all)
        AsObjWord NLn
        FOR i = 0 TO NLn - 1
            IF LnPC(i) < 0 THEN
                AsObjWord -1
                AsObjStr LnFile$(LnNo(i))
            ELSE
                AsObjWord LnPC(i) + EntryBytes
                AsObjWord LnNo(i)
            END IF
        NEXT i
    END IF
    IF OptList THEN AsListSave nm$
END SUB

' ---- the stream's records, to its end

SUB AsPass ()
    DIM k, n, i, l, m, t$
    DO
        k = AsB
        SELECT CASE k
        CASE AMBYTES
            n = AsB
            FOR i = 1 TO n
                AsOB AsB
            NEXT i
        CASE AMJUMP
            k = AsB
            AsJump k, AsW
        CASE AMCASE
            AsCase AsW
        CASE AMLABEL
            AsSetLabel AsW
        CASE AMALIAS
            l = AsW
            m = AsW
            AsLab l
            AsLab m
            LabPos(l) = LabPos(m)
        CASE AMREL
            k = AsB
            AsReloc k, AsS$
        CASE AMFILE
            AsFile AsS$
        CASE AMLINE
            l = AsW
            AsLineAt PC, l
            IF OptList THEN
                t$ = AsS$
                AsFlush
                PendPC = PC
                PendLine = l
                PendText$ = t$
                PendSet = 1
            END IF
        CASE AMDROP
            IF PendSet AND PendPC = PC THEN PendSet = 0
        CASE AMBEGIN
            PC = 0
            NFix = 0
            NRel = 0
            NLn = 0
            LabHi = -1
            PendSet = 0
        CASE AMLEXIT
            AsFlush
            PendPC = PC
            PendLine = 0
            PendText$ = "(exit)"
            PendSet = 1
            AsFlush
        CASE AMENTRY
            ESave = PC
            ERel0 = NRel
            EntryBytes = 0
        CASE AMENTRYEND
            AsEntry
        CASE AMEND
            AsEnd
        CASE AMOBJB
            AsObjByte AsB
        CASE AMOBJW
            AsObjWord AsW
        CASE AMOBJS
            AsObjStr AsS$
        CASE AMSIZE
            LnCap = AsW
            REDIM LnPC(LnCap), LnNo(LnCap)
        CASE ELSE
            ' (AMEOF)
            EXIT DO
        END SELECT
    LOOP
END SUB

' ---- BCASM, the program: pass 4 of the job's compile step, then BCLIST
' for a listing

ReadJob
StepNames
ErrCount = 0
Tok = 0
TokLine = 0
TokText$ = ""
LnCap = 100
REDIM Code(MAXCODE) AS BYTE, LabPos(MAXLAB), FixPos(MAXFIX), FixLab(MAXFIX)
REDIM RelPos(MAXREL), RelType(MAXREL) AS BYTE, RelName$(MAXREL), LnFile$(MAXLNF)
REDIM LnPC(LnCap), LnNo(LnCap)
NLnFile = 0
MemNote "tables"
OPEN AsmName$ FOR BINARY AS #CHASM
' a new file takes the largest free area: with the listing's records
' written at the same time, the object takes half of it ([*]), the
' statements half of the rest
IF OptList THEN OPEN ObjName$ + "[*]" FOR OUTPUT AS #CHOBJ ELSE OPEN ObjName$ FOR OUTPUT AS #CHOBJ
PUT #CHOBJ, , "BCOB"
AsObjByte 77
AsObjStr ModName$
IF OptList THEN
    OPEN LTmpName$ + "[*]" FOR OUTPUT AS #CHLREC
    OPEN LCodName$ FOR OUTPUT AS #CHLCOD
END IF
AsPass
CLOSE #CHASM
CLOSE #CHOBJ
IF OptList THEN
    CLOSE #CHLREC
    CLOSE #CHLCOD
END IF
KILL AsmName$
IF ErrCount > 0 THEN CompileFailed
IF OptList THEN ChainTo "BCLIST", ""
CompileDone
