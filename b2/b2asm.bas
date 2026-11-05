' B2ASM -- pass 8 of a compile: the procedures the passes made, assembled
' into the object file (BC's BCASM, docs/B2DESIGN.md)
'
' The code records of B2STMT's file: bytes (CBYTES), jumps, case words and
' labels by number, relocations by name, lines (TLINE, TFILE); the
' templates the passes left to it: CALIGN (a 0 at an odd byte: an LDC's
' and XJP's words), CTEMP (the string work area's mark put back: LDL
' mark, SRO _TTOP), CGOSUB (a GOSUB's return point), CFREE (a local to give
' back at the exit); CBEGIN ... CEND a procedure with its frame.  At CEND
' the exit code is made (the frees, the result, RETURN's case table) and
' the entry code (zeroing, the marks) put in front, the jumps resolved (one
' of more than 127 bytes forward, or any backward one, through the
' procedure's jump table), the attribute words, the P record; and the
' listing's records.  Every other record (the statements' marks, the
' compiled blocks' brackets) is passed over.  The tables are as large as
' the header says the largest procedure needs.
#INCLUDE "B2COM"
#INCLUDE "B2REC"
#INCLUDE "B2OPS"

' the long jumps' targets; the listing's statement record (written one
' behind: AsSetLabel may move it); the highest label known; where the
' entry code started, and the relocations before it
DIM SHARED LongLab(60), PendPC, PendLine, PendText$, PendSet, LabHi, ESave, ERel0
' the procedure's code and its tables (BC's BCGENCOM), its GOSUBs' return
' points, the locals to give back, the CTEMPs seen (UsedMark), its line
' table's files
DIM SHARED Code() AS BYTE, PC, CodeCap, LabPos(), LabCap, FixPos(), FixLab(), NFix, FixCap
DIM SHARED RelPos(), RelType() AS BYTE, RelName$(), NRel, RelCap, EntryBytes, CodeEndPos, NLong
DIM SHARED LnPC(), LnNo(), NLn, LnCap, LnFile$(MAXLNF), NLnFile
DIM SHARED GsRet(100), NGosub, FrK(), FrO(), NFr, FrCap, UsedMark, AsDone

' ---- the procedure's code

SUB AsOB (b)
    IF PC >= CodeCap - 2 THEN
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
    IF l >= LabCap THEN
        ErrNo 111   ' procedure too large (labels): split it
        l = 0
    END IF
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
    IF NFix >= FixCap THEN
        ErrNo 112   ' procedure too large (jumps): split it
        NFix = 0
    END IF
    AsOB op
    FixPos(NFix) = PC
    FixLab(NFix) = l
    NFix = NFix + 1
    AsOB 0
END SUB

' a word of a case table: self-relative, the target is its address - it
SUB AsCase (l)
    AsLab l
    IF NFix >= FixCap THEN
        ErrNo 112   ' procedure too large (jumps): split it
        NFix = 0
    END IF
    FixPos(NFix) = PC
    FixLab(NFix) = -2 - l
    NFix = NFix + 1
    AsOW 0
END SUB

SUB AsReloc (ty, n$)
    IF NRel >= RelCap THEN
        ErrNo 113   ' procedure too large (calls): split it
        NRel = 0
    END IF
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
    exitlab = 0
    flags = CbFlags
    nm$ = CbName$
    sg$ = CbSeg$
    ' (where, for an error: the procedure's end)
    Tok = 0
    TokLine = RW1
    LineFile$ = RS$
    TokText$ = RS2$
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
    AsOW (CbLocal - CbPw) * 2
    AsOW CbPw * 2
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
        AsObjWord CbPw * 2
        AsObjByte CbRw
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

' ---- the templates: code B2ASM makes itself

SUB AsBig (v)
    IF v >= 0 AND v < 128 THEN
        AsOB v
    ELSE
        AsOB 128 OR ((v AND &H7F00) \ 256)
        AsOB v AND 255
    END IF
END SUB

SUB AsLdc (v)
    IF v >= 0 AND v < 128 THEN
        AsOB v
    ELSEIF v < 0 AND v > -128 THEN
        AsOB -v
        AsOB ONGI
    ELSE
        AsOB OLDCI
        AsOW v
    END IF
END SUB

SUB AsLdl (off)
    IF off >= 1 AND off <= 16 THEN
        AsOB &HD7 + off
    ELSE
        AsOB OLDL
        AsBig off
    END IF
END SUB

SUB AsStl (off)
    AsOB OSTL
    AsBig off
END SUB

SUB AsLla (off)
    AsOB OLLA
    AsBig off
END SUB

' a library variable's load or store (_TTOP, _GSSP: COMMON)
SUB AsGlob (op, n$)
    AsOB op
    AsReloc RGNAME, n$
    AsOB 128
    AsOB 0
END SUB

SUB AsCall (n$)
    AsReloc RCALL, n$
    AsOB OCXP
    AsOB 0
    AsOB 0
END SUB

' CTEMP: the string temporaries given back
SUB AsTemp ()
    AsLdl CbMark
    AsGlob OSRO, "_TTOP"
    UsedMark = 1
END SUB

' the exit code: the strings and arrays given back, the result, GOSUB's
' stack pointer; RETURN (from a GOSUB): the return point's number, a case
' table
SUB AsExit (gsoff)
    DIM i
    AsSetLabel 0
    IF UsedMark THEN AsTemp
    ' (the strings and arrays first: the result's words are the parameters' place)
    FOR i = 1 TO NFr
        AsLla FrO(i)
        IF FrK(i) = 1 THEN AsCall "_SFREE" ELSE AsCall "_AFREE"
    NEXT i
    IF CbResOff > 0 THEN
        IF CbResTy = TYSTR THEN
            AsLla CbResOff
            AsCall "_SRET"
            AsStl 1
        ELSEIF CbRw = 1 THEN
            AsLdl CbResOff
            AsStl 1
        ELSE
            AsLla 1
            AsLla CbResOff
            AsOB OLDM
            AsOB CbRw
            AsOB OSTM
            AsOB CbRw
        END IF
    END IF
    IF NGosub > 0 THEN
        AsLdl gsoff
        AsGlob OSRO, "_GSSP"
    END IF
    AsOB ORNP
    AsOB CbRw
    IF NGosub > 0 THEN
        AsSetLabel 1
        AsOB 0
        AsCall "_GSPOP"
        AsOB OXJP
        IF PC AND 1 THEN AsOB 0
        AsOW 1
        AsOW NGosub
        AsJump OUJP, 0
        FOR i = 1 TO NGosub
            AsCase GsRet(i)
        NEXT i
    ELSE
        AsLab 1
        LabPos(1) = LabPos(0)
    END IF
END SUB

' the entry code, put in front of the procedure's code (an even number of
' bytes: the LDC and XJP words stay aligned)
SUB AsEntryCode (gsoff)
    DIM bytes
    ESave = PC
    ERel0 = NRel
    EntryBytes = 0
    bytes = (CbLocal - CbPw) * 2
    IF CbZero AND bytes > 0 THEN
        AsLla CbPw + 1
        AsOB 0
        AsLdc bytes
        AsOB 0
        AsOB OCSP
        AsOB 10
    END IF
    IF UsedMark THEN
        AsGlob OLDO, "_TTOP"
        AsStl CbMark
    END IF
    IF NGosub > 0 THEN
        AsGlob OLDO, "_GSSP"
        AsStl gsoff
    END IF
    IF (PC - ESave) AND 1 THEN AsOB ONOP
    AsEntry
END SUB

' a procedure's end (CEND read): the exit code, the entry code, the rest
SUB AsProcEnd ()
    DIM gsoff
    ' (GOSUB's stack pointer: a local of its own, after all the others)
    IF NGosub > 0 THEN
        CbLocal = CbLocal + 1
        gsoff = CbLocal
    END IF
    IF OptList THEN
        AsFlush
        PendPC = PC
        PendLine = 0
        PendText$ = "(exit)"
        PendSet = 1
        AsFlush
    END IF
    AsExit gsoff
    AsEntryCode gsoff
    AsEnd
END SUB

' ---- the records, to the end

SUB AsPass ()
    DIM i, n$, k
    DO
        NextRec
        SELECT CASE Rk
        CASE TEOF
            EXIT DO
        CASE CBYTES
            FOR i = 0 TO RB1 - 1
                AsOB InBuf(i)
            NEXT i
        CASE CJUMP
            AsJump RB1, RW1
        CASE CCASE
            AsCase RW1
        CASE CLABEL
            AsSetLabel RW1
        CASE CALIAS
            AsLab RW1
            AsLab RW2
            LabPos(RW1) = LabPos(RW2)
        CASE CREL
            AsReloc RB1, RS$
        CASE CALIGN
            IF PC AND 1 THEN AsOB 0
        CASE CTEMP
            AsTemp
        CASE CGOSUB
            IF NGosub < 100 THEN
                NGosub = NGosub + 1
                GsRet(NGosub) = RW1
            END IF
        CASE CFREE
            IF NFr < FrCap THEN
                NFr = NFr + 1
                FrK(NFr) = RB1
                FrO(NFr) = RW1
            END IF
        CASE TFILE
            ' (its name without volume and path: the same wherever it was
            ' compiled; B2DEBUG looks beside the code file first)
            n$ = RS$
            FOR k = LEN(n$) TO 1 STEP -1
                IF MID$(n$, k, 1) = ":" OR MID$(n$, k, 1) = "/" THEN EXIT FOR
            NEXT k
            AsFile MID$(n$, k + 1)
        CASE TLINE
            AsLineAt PC, RW1
            IF OptList THEN
                AsFlush
                PendPC = PC
                PendLine = RW1
                PendText$ = RS$
                PendSet = 1
            END IF
        CASE CBEGIN
            PC = 0
            NFix = 0
            NRel = 0
            NLn = 0
            LabHi = -1
            PendSet = 0
            NGosub = 0
            NFr = 0
            UsedMark = 0
        CASE CEND
            AsProcEnd
        CASE COBJB
            AsObjByte RB1
        CASE COBJW
            AsObjWord RW1
        CASE COBJS
            AsObjStr RS$
        END SELECT
    LOOP
END SUB

' ---- B2ASM, the program: pass 8 of the job's compile step, then B2LIST
' for a listing

ReadJob
StepNames
ErrCount = 0
Tok = 0
TokLine = 0
TokText$ = ""
InOpen PassFile$(7)
' (the largest procedure's: B2IO counted what the passes wrote)
' (and the jump table: 2 bytes a long jump, 60 at most; the attribute words)
IF InHead(WHJUMPS) > 60 THEN CodeCap = 120 ELSE CodeCap = 2 * InHead(WHJUMPS)
CodeCap = Capped(InHead(WHCODE) + CodeCap + 32, 32000)
LabCap = InHead(WHLABS) + 4
FixCap = InHead(WHJUMPS) + 104
RelCap = InHead(WHRELS) + 8
FrCap = RelCap
LnCap = InHead(THLINES) + 8
REDIM Code(CodeCap) AS BYTE, LabPos(LabCap), FixPos(FixCap), FixLab(FixCap)
REDIM RelPos(RelCap), RelType(RelCap) AS BYTE, RelName$(RelCap)
REDIM LnPC(LnCap), LnNo(LnCap), FrK(FrCap), FrO(FrCap)
NLnFile = 0
IF OptMem THEN SayLn "  [code " + IStr$(CodeCap) + ", labels " + IStr$(LabCap) + ", jumps " + IStr$(FixCap) + ", calls " + IStr$(RelCap) + ", lines " + IStr$(LnCap) + "]"
MemNote "tables"
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
CLOSE #CHIN
CLOSE #CHOBJ
IF OptList THEN
    CLOSE #CHLREC
    CLOSE #CHLCOD
END IF
IF OptKeep = 0 THEN KILL PassFile$(7)
IF ErrCount > 0 THEN CompileFailed
IF OptList THEN ChainTo "B2LIST", ""
CompileDone
