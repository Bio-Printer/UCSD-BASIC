' BCEMIT -- pass 3: the P-code emitter and the object file
'
' A procedure's code is made in Code() from offset 0.  At its end
' (EndProc) the exit code is added, the entry code (zeroing the locals,
' saving the string-temporaries mark) is put in front of it, jumps are
' resolved (a jump of more than 127 bytes forward, or any backward one,
' goes through the procedure's jump table), the attribute words are added
' and the procedure is written to the object file as a P record.
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"
SEGMENT GEN


DIM SHARED LongLab(60), PendPC, PendLine, PendText$, PendSet
DIM SHARED GsRet(100), ProcKeep

' ---- bytes

SUB OB (b)
    IF PC >= MAXCODE - 40 THEN
        ErrMsg "procedure too large: split it"
        PC = 0
    END IF
    Code(PC) = b AND 255
    PC = PC + 1
END SUB

SUB OW (w)
    OB w AND 255
    OB (w AND &HFF00) \ 256
END SUB

SUB OBig (v)
    IF v >= 0 AND v < 128 THEN
        OB v
    ELSE
        OB 128 OR ((v AND &H7F00) \ 256)
        OB v AND 255
    END IF
END SUB

SUB OpBig (op, v)
    OB op
    OBig v
END SUB

SUB Ldc (v)
    IF v >= 0 AND v < 128 THEN
        OB v
    ELSEIF v < 0 AND v > -128 THEN
        OB -v
        OB ONGI
    ELSE
        OB OLDCI
        OW v
    END IF
END SUB

SUB Ldl (off)
    IF off >= 1 AND off <= 16 THEN OB &HD7 + off ELSE OpBig OLDL, off
END SUB

SUB Stl (off)
    OpBig OSTL, off
END SUB

SUB Lla (off)
    OpBig OLLA, off
END SUB

SUB EmitCsp (n)
    OB OCSP
    OB n
END SUB

SUB Ind0 ()
    OB OSIND0
END SUB

' take n words off the stack: FJP to the next instruction pops one
SUB DropWords (n)
    DIM i
    FOR i = 1 TO n
        OB OFJP
        OB 0
    NEXT i
END SUB

' ---- labels and jumps

FUNCTION NewLabel ()
    IF NLab >= MAXLAB THEN
        ErrMsg "procedure too large (labels): split it"
        NLab = 0
    END IF
    LabPos(NLab) = -1
    NewLabel = NLab
    NLab = NLab + 1
END FUNCTION

SUB SetLabel (l)
    DIM i
    ' a UJP to this very label just before it: drop it
    IF NFix > 0 AND PC >= 2 THEN
        IF FixPos(NFix - 1) = PC - 1 AND FixLab(NFix - 1) = l AND Code(PC - 2) = OUJP THEN
            NFix = NFix - 1
            PC = PC - 2
            FOR i = 0 TO NLab - 1
                IF LabPos(i) = PC + 2 THEN LabPos(i) = PC
            NEXT i
            IF PendSet AND PendPC = PC + 2 THEN PendPC = PC
        END IF
    END IF
    LabPos(l) = PC
END SUB

SUB Jump (op, l)
    OB op
    IF NFix >= MAXFIX THEN
        ErrMsg "procedure too large (jumps): split it"
        NFix = 0
    END IF
    FixPos(NFix) = PC
    FixLab(NFix) = l
    NFix = NFix + 1
    OB 0
END SUB

' a word of a case table: self-relative, the target is its address - it
SUB CaseWord (l)
    IF NFix >= MAXFIX THEN
        ErrMsg "procedure too large (jumps): split it"
        NFix = 0
    END IF
    FixPos(NFix) = PC
    FixLab(NFix) = -2 - l
    NFix = NFix + 1
    OW 0
END SUB

' ---- relocations and the names they refer to

SUB Reloc (ty, sym)
    IF NRel >= MAXREL THEN
        ErrMsg "procedure too large (calls): split it"
        NRel = 0
    END IF
    RelPos(NRel) = PC
    RelType(NRel) = ty
    RelSym(NRel) = sym
    NRel = NRel + 1
END SUB

' a run-time library procedure (or variable): its symbol
FUNCTION RtSym (n$)
    DIM s
    s = FindSym(n$)
    IF s = 0 THEN
        s = AddSym(n$, SKFUNC, TYVOID)
        SFlags(s) = SFRUNTIME
    END IF
    RtSym = s
END FUNCTION

FUNCTION RtVar (n$)
    DIM s
    s = FindSym(n$)
    IF s = 0 THEN
        s = AddSym(n$, SKVAR, TYINT)
        SCls(s) = SCCOMMON
        SFlags(s) = SFRUNTIME
    END IF
    RtVar = s
END FUNCTION

' a global variable's load, store or address: op with a 2-byte operand the
' linker fills in (a module static: its offset in the module's block; a
' COMMON variable: the offset in it)
SUB GlobOp (op, s, add)
    DIM v
    OB op
    IF SCls(s) = SCCOMMON THEN
        Reloc RGNAME, s
        v = add
    ELSE
        Reloc RGSTAT, 0
        v = SOff(s) + add
    END IF
    OB 128 OR ((v AND &H7F00) \ 256)
    OB v AND 255
END SUB

SUB CallSym (s)
    Reloc RCALL, s
    OB OCXP
    OB 0
    OB 0
    SFlags(s) = SFlags(s) OR SFUSED
END SUB

SUB CallRt (n$)
    CallSym RtSym(n$)
END SUB

FUNCTION LinkName$ (s)
    DIM n$
    IF s = 0 THEN EXIT FUNCTION
    n$ = SName$(s)
    IF (SFlags(s) AND SFRUNTIME) <> 0 OR ASC(n$, 1) = 95 THEN
        ' the run-time library's names: as they are (no type suffix)
        LinkName$ = BaseName$(n$)
        EXIT FUNCTION
    END IF
    IF SKind(s) = SKSUB THEN
        n$ = BaseName$(n$)
    ELSE
        n$ = BaseName$(n$) + TypeChar$(SType(s))
    END IF
    IF SFlags(s) AND SFPRIVATE THEN n$ = ModName$ + "'" + n$
    LinkName$ = n$
END FUNCTION

' ---- the frame

FUNCTION NewLocal (words)
    CurLocal = CurLocal + words
    IF CurLocal > MaxLocal THEN MaxLocal = CurLocal
    NewLocal = CurLocal - words + 1
END FUNCTION

' after a statement that made string temporaries: give them back
SUB TempReset ()
    IF TempUsed = 0 THEN EXIT SUB
    Ldl MarkOff
    GlobOp OSRO, RtVar("_TTOP"), 0
    TempUsed = 0
    UsedMark = 1
END SUB

' ---- the object file

SUB ObjByte (b)
    DIM x AS BYTE
    x = b AND 255
    PUT #CHOBJ, , x
END SUB

SUB ObjWord (w)
    PUT #CHOBJ, , w
END SUB

SUB ObjStr (s$)
    ObjByte LEN(s$)
    IF LEN(s$) > 0 THEN PUT #CHOBJ, , s$
END SUB

' ---- the listing's statement records (written one behind: see SetLabel)

SUB ListFlush ()
    IF PendSet THEN
        PRINT #CHLREC, IStr$(PendPC); " "; IStr$(PendLine)
        PRINT #CHLREC, PendText$
        PendSet = 0
    END IF
END SUB

' the listing of a procedure, for LIST (after pass 3, the GEN segment
' gone: it and LIST do not fit into the code space together): its
' statements' records end with a *; its code goes to LCodName$ -- its name,
' "PC entry-bytes jump-table-entries code-end relocations", its bytes in hex
' (32 a line), each relocation "position kind name"
SUB ListSave (nm$)
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
        IF RelType(i) = RGSTAT THEN s$ = "" ELSE s$ = LinkName$(RelSym(i))
        PRINT #CHLCOD, IStr$(RelPos(i)); " "; IStr$(RelType(i)); " "; s$
    NEXT i
END SUB

' the pending record dropped (a procedure skipped: no code of its own)
SUB ListDrop ()
    IF PendSet AND PendPC = PC THEN PendSet = 0
END SUB

SUB ListLine ()
    IF OptList = 0 THEN EXIT SUB
    ListFlush
    PendPC = PC
    PendLine = TokLine
    PendText$ = TokText$
    PendSet = 1
END SUB

' ---- procedures

' a procedure starts: s its symbol (0 for the module's body); the
' parameters' frame words are laid out by the caller (NParamWords)
SUB BeginProc (s)
    ProcSym = s
    PC = 0
    NLab = 0
    NFix = 0
    NRel = 0
    NeedZero = 0
    UsedMark = 0
    TempUsed = 0
    NGosub = 0
    NCtl = 0
    NFor = 0
    PendNext = 0
    PendSet = 0
    ProcKeep = NSym
    CurLocal = NParamWords
    MaxLocal = NParamWords
    ExitLab = NewLabel
    RetLab = NewLabel
    MarkOff = NewLocal(1)
    GosubOff = 0
    ResultOff = 0
    IF s > 0 THEN
        IF SKind(s) = SKFUNC THEN
            ResultOff = NewLocal(TypeWords(SType(s)))
            NeedZero = 1
        END IF
    END IF
END SUB

' a GOSUB's return point: its number (RETURN goes back through a table)
FUNCTION GosubSite (l)
    IF NGosub >= 100 THEN
        ErrMsg "more than 100 GOSUBs in one procedure"
        EXIT FUNCTION
    END IF
    IF NGosub = 0 THEN GosubOff = NewLocal(1)
    NGosub = NGosub + 1
    GsRet(NGosub) = l
    GosubSite = NGosub
END FUNCTION

' the exit code: the result, the strings and arrays given back
SUB GenExit ()
    DIM s, i, ty
    SetLabel ExitLab
    IF UsedMark THEN
        TempUsed = 1
        TempReset
    END IF
    ' the strings and arrays given back first: the result's words are
    ' the parameters' place
    FOR s = ProcKeep + 1 TO NSym
        IF SKind(s) = SKVAR AND SType(s) = TYSTR AND (SCls(s) = SCLOCAL OR SCls(s) = SCPARAM) AND SOff(s) <> ResultOff THEN
            Lla SOff(s)
            CallRt "_SFREE"
        ELSEIF SKind(s) = SKARRAY AND SCls(s) = SCLOCAL THEN
            Lla SOff(s)
            CallRt "_AFREE"
        END IF
    NEXT s
    IF ResultOff > 0 THEN
        ty = SType(ProcSym)
        IF ty = TYSTR THEN
            Lla ResultOff
            CallRt "_SRET"
            Stl 1
        ELSEIF ResWords = 1 THEN
            Ldl ResultOff
            Stl 1
        ELSE
            Lla 1
            Lla ResultOff
            OB OLDM
            OB ResWords
            OB OSTM
            OB ResWords
        END IF
    END IF
    IF NGosub > 0 THEN
        Ldl GosubOff
        GlobOp OSRO, RtVar("_GSSP"), 0
    END IF
    OB ORNP
    OB ResWords
    ' RETURN (from a GOSUB): the return point's number, then a case table
    IF NGosub > 0 THEN
        SetLabel RetLab
        OB 0
        CallRt "_GSPOP"
        OB OXJP
        IF PC AND 1 THEN OB 0
        OW 1
        OW NGosub
        Jump OUJP, ExitLab
        FOR i = 1 TO NGosub
            CaseWord GsRet(i)
        NEXT i
    ELSE
        LabPos(RetLab) = LabPos(ExitLab)
    END IF
END SUB

' the entry code, in front of the procedure's code (an even number of
' bytes: the LDC and XJP words stay aligned)
SUB GenEntry ()
    DIM pro(24) AS BYTE, np, i, d, save, bytes, nrel0, r
    save = PC
    nrel0 = NRel
    ' made at the end of the code, then moved to the front
    bytes = (MaxLocal - NParamWords) * 2
    IF NeedZero AND bytes > 0 THEN
        Lla NParamWords + 1
        OB 0
        Ldc bytes
        OB 0
        EmitCsp 10
    END IF
    IF UsedMark THEN
        GlobOp OLDO, RtVar("_TTOP"), 0
        Stl MarkOff
    END IF
    IF NGosub > 0 THEN
        GlobOp OLDO, RtVar("_GSSP"), 0
        Stl GosubOff
    END IF
    IF (PC - save) AND 1 THEN OB ONOP
    np = PC - save
    FOR i = 0 TO np - 1
        pro(i) = Code(save + i)
    NEXT i
    PC = save
    IF np = 0 THEN EXIT SUB
    ' move the code up by np bytes
    FOR i = PC - 1 TO 0 STEP -1
        Code(i + np) = Code(i)
    NEXT i
    FOR i = 0 TO np - 1
        Code(i) = pro(i)
    NEXT i
    PC = PC + np
    FOR i = 0 TO NLab - 1
        IF LabPos(i) >= 0 THEN LabPos(i) = LabPos(i) + np
    NEXT i
    FOR i = 0 TO NFix - 1
        FixPos(i) = FixPos(i) + np
    NEXT i
    FOR i = 0 TO nrel0 - 1
        RelPos(i) = RelPos(i) + np
    NEXT i
    ' the entry code's own relocations: they were made at save
    FOR i = nrel0 TO NRel - 1
        RelPos(i) = RelPos(i) - save
    NEXT i
    EntryBytes = np
END SUB

' the jumps, the jump table and the attributes; write the P record
SUB EndProc ()
    DIM i, k, t, pos, off, jtab, exitpos, flags, nm$, sg$, s, kind
    ' every label used is defined
    FOR s = ProcKeep + 1 TO NSym
        IF SKind(s) = SKLABEL AND (SFlags(s) AND SFSETLAB) = 0 THEN
            ErrMsg "label " + MID$(SName$(s), 2) + " not defined"
        END IF
    NEXT s
    IF OptList THEN
        ListFlush
        PendPC = PC
        PendLine = 0
        PendText$ = "(exit)"
        PendSet = 1
        ListFlush
    END IF
    GenExit
    EntryBytes = 0
    GenEntry
    exitpos = LabPos(ExitLab)
    IF PC > HiPC THEN HiPC = PC
    IF NFix > HiFix THEN HiFix = NFix
    IF NLab > HiLab THEN HiLab = NLab
    IF NRel > HiRel THEN HiRel = NRel
    IF NSym > HiSym THEN HiSym = NSym
    NLong = 0
    FOR i = 0 TO NFix - 1
        IF FixLab(i) >= 0 THEN
            pos = FixPos(i)
            t = LabPos(FixLab(i))
            IF t < 0 THEN
                ErrMsg "internal: a label not set"
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
                        ErrMsg "procedure too large (more than 60 long jumps): split it"
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
    IF PC AND 1 THEN OB 0
    jtab = PC + 2 * NLong + 8
    FOR k = NLong - 1 TO 0 STEP -1
        pos = jtab - 10 - 2 * k
        OW pos - LongLab(k)
    NEXT k
    OW (MaxLocal - NParamWords) * 2
    OW NParamWords * 2
    OW jtab - 4 - exitpos
    OW jtab - 2
    OB 0
    OB 1
    ' the case tables
    FOR i = 0 TO NFix - 1
        IF FixLab(i) <= -2 THEN
            pos = FixPos(i)
            t = LabPos(-2 - FixLab(i))
            Code(pos) = (pos - t) AND 255
            Code(pos + 1) = ((pos - t) AND &HFF00) \ 256
        END IF
    NEXT i
    ' the P record
    IF ProcSym = 0 THEN
        flags = 1
        nm$ = ModName$ + "'BODY"
        sg$ = ""
    ELSE
        flags = 0
        IF SFlags(ProcSym) AND SFPRIVATE THEN flags = 2
        nm$ = LinkName$(ProcSym)
        sg$ = SegName$(SSeg(ProcSym))
    END IF
    IF ErrCount = 0 THEN
        ObjByte 80
        ObjByte flags
        ObjStr nm$
        ObjStr sg$
        ObjWord NParamWords * 2
        ObjByte ResWords
        ObjWord PC
        ObjWord jtab
        FOR i = 0 TO PC - 1
            ObjByte Code(i)
        NEXT i
        ObjWord NRel
        FOR i = 0 TO NRel - 1
            ObjWord RelPos(i)
            ObjByte RelType(i)
            ObjStr LinkName$(RelSym(i))
        NEXT i
    END IF
    IF OptList THEN ListSave nm$
    IF ProcSym > 0 THEN PopSyms ProcKeep
END SUB
