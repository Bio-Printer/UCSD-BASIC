' BCEMIT -- pass 3: the P-code emitter
'
' A procedure's code goes, as it is made, to the stream :BCTEMP.ASM for
' BCASM (pass 4, bcasm.bas: BCGENCOM's AMxxx records): its bytes, its
' jumps and labels by number, its relocations by name, its lines.  At its
' end (EndProc) the exit code is added and the entry code (zeroing the
' locals, saving the string-temporaries mark) is made last, for BCASM to put
' in front; BCASM resolves the jumps (a jump of more than 127 bytes
' forward, or any backward one, goes through the procedure's jump table),
' adds the attribute words and writes the procedure to the object file as
' a P record.  Here are only the counts: PC (the code's bytes, for the
' alignment of LDC and XJP words), NLab, NFix, NRel (each one's most, MAX
' constants: a procedure too large is said here, at its line).
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"


DIM SHARED GsRet(100), ProcKeep, StmBuf(254) AS BYTE, NStmBuf

' ---- the stream (CHASM): the code's bytes kept in StmBuf until a record

SUB StmFlush ()
    DIM i, b AS BYTE
    IF NStmBuf = 0 THEN EXIT SUB
    b = AMBYTES
    PUT #CHASM, , b
    b = NStmBuf
    PUT #CHASM, , b
    FOR i = 0 TO NStmBuf - 1
        b = StmBuf(i)
        PUT #CHASM, , b
    NEXT i
    NStmBuf = 0
END SUB

SUB StmByte (v)
    DIM b AS BYTE
    b = v AND 255
    PUT #CHASM, , b
END SUB

' a record k (the bytes before it first)
SUB StmRec (k)
    StmFlush
    StmByte k
END SUB

SUB StmWord (w)
    PUT #CHASM, , w
END SUB

SUB StmStr (s$)
    StmByte LEN(s$)
    IF LEN(s$) > 0 THEN PUT #CHASM, , s$
END SUB

' ---- bytes

' n more bytes of code
SUB PcAdd (n)
    IF PC >= MAXCODE - 40 THEN
        ErrNo 110   ' procedure too large: split it
        PC = 0
    END IF
    PC = PC + n
END SUB

SUB OB (b)
    PcAdd 1
    IF NStmBuf >= 255 THEN StmFlush
    StmBuf(NStmBuf) = b AND 255
    NStmBuf = NStmBuf + 1
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
        ErrNo 111   ' procedure too large (labels): split it
        NLab = 0
    END IF
    NewLabel = NLab
    NLab = NLab + 1
END FUNCTION

' (BCASM drops a UJP to this very label just before it)
SUB SetLabel (l)
    StmRec AMLABEL
    StmWord l
END SUB

SUB MoreFix ()
    IF NFix >= MAXFIX THEN
        ErrNo 112   ' procedure too large (jumps): split it
        NFix = 0
    END IF
    NFix = NFix + 1
END SUB

SUB Jump (op, l)
    MoreFix
    StmRec AMJUMP
    StmByte op
    StmWord l
    PcAdd 2
END SUB

' a word of a case table: self-relative, the target is its address - it
SUB CaseWord (l)
    MoreFix
    StmRec AMCASE
    StmWord l
    PcAdd 2
END SUB

' ---- relocations and the names they refer to

SUB Reloc (ty, sym)
    IF NRel >= MAXREL THEN
        ErrNo 113   ' procedure too large (calls): split it
        NRel = 0
    END IF
    StmRec AMREL
    StmByte ty
    StmStr LinkName$(sym)
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

SEGMENT RTSELDOM
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

SEGMENT
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
    n$ = SymName$(s)
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

' ---- the object file's records other than the procedures' (BCASM
' writes them)

SUB ObjByte (b)
    StmRec AMOBJB
    StmByte b
END SUB

SUB ObjWord (w)
    StmRec AMOBJW
    StmWord w
END SUB

SUB ObjStr (s$)
    StmRec AMOBJS
    StmStr s$
END SUB

' ---- the line table and the listing's statement records (BCASM's)

' the pending record dropped (a procedure skipped: no code of its own)
SUB ListDrop ()
    StmRec AMDROP
END SUB

' a line starts (Tok is its TLINE): where its code starts, into the line
' table (a file's name there without its volume and path: the same
' wherever it was compiled; BCDEBUG looks beside the code file first), and
' its record for the listing
SUB ListLine ()
    DIM n$, k
    IF LineFile$ <> LnCurF$ THEN
        LnCurF$ = LineFile$
        n$ = LineFile$
        FOR k = LEN(n$) TO 1 STEP -1
            IF MID$(n$, k, 1) = ":" OR MID$(n$, k, 1) = "/" THEN EXIT FOR
        NEXT k
        StmRec AMFILE
        StmStr MID$(n$, k + 1)
    END IF
    StmRec AMLINE
    StmWord TokLine
    IF OptList THEN StmStr TokText$
END SUB

' ---- procedures

' a procedure starts: s its symbol (0 for the module's body); the
' parameters' frame words are laid out by the caller (NParamWords)
SUB BeginProc (s)
    StmRec AMBEGIN
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
    LnCurF$ = ""
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

SEGMENT STMTA
' a GOSUB's return point: its number (RETURN goes back through a table)
FUNCTION GosubSite (l)
    IF NGosub >= 100 THEN
        ErrNo 114   ' more than 100 GOSUBs in one procedure
        EXIT FUNCTION
    END IF
    IF NGosub = 0 THEN GosubOff = NewLocal(1)
    NGosub = NGosub + 1
    GsRet(NGosub) = l
    GosubSite = NGosub
END FUNCTION

SEGMENT RTSELDOM
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
        StmRec AMALIAS
        StmWord RetLab
        StmWord ExitLab
    END IF
END SUB

' the entry code, for BCASM to put in front of the procedure's code (an
' even number of bytes: the LDC and XJP words stay aligned)
SUB GenEntry ()
    DIM save, bytes
    StmRec AMENTRY
    save = PC
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
    StmRec AMENTRYEND
END SUB

' the procedure's end: for BCASM its frame and its name (and where, for an
' error it finds: the end, as ErrRec says it)
SUB EndProc ()
    DIM flags, nm$, sg$, s
    ' every label used is defined
    FOR s = ProcKeep + 1 TO NSym
        IF SKind(s) = SKLABEL AND (SFlags(s) AND SFSETLAB) = 0 THEN
            ErrRec 115, 0, 0, MID$(SymName$(s), 2)   ' label {s} not defined
        END IF
    NEXT s
    IF OptList THEN StmRec AMLEXIT
    GenExit
    GenEntry
    IF PC > HiPC THEN HiPC = PC
    IF NFix > HiFix THEN HiFix = NFix
    IF NLab > HiLab THEN HiLab = NLab
    IF NRel > HiRel THEN HiRel = NRel
    IF NSym > HiSym THEN HiSym = NSym
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
    StmRec AMEND
    StmWord ExitLab
    StmWord MaxLocal
    StmWord NParamWords
    StmByte ResWords
    StmByte flags
    StmStr nm$
    StmStr sg$
    IF Tok = TLINE THEN
        StmWord PrevLine
        StmStr PrevFile$
        StmStr PrevText$
    ELSE
        StmWord TokLine
        IF LineFile$ = "" THEN StmStr TokFile$ ELSE StmStr LineFile$
        StmStr TokText$
    END IF
    IF ProcSym > 0 THEN PopSyms ProcKeep
END SUB
