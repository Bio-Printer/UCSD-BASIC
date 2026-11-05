' B2IO -- the intermediate files (docs/B2DESIGN.md section 3): a pass
' reads the records of the one before (NextRec: the kind into Rk, its
' operands into RB1.., RW1.., RS$, RS2$, RPT()/RPF(), InBuf(), CBxxx) and
' writes its own (PutRec copies the record just read; WRec, WB, WW, WS
' write one; OB collects code bytes into CBYTES records).  The writer
' counts, per procedure (CBEGIN ... CEND), the code's bytes (at most), the
' labels, the jumps, the relocations and the largest compiled block, and
' writes the most of each into the header when the file is closed: the
' next passes make their tables that large.  A CBEGIN's frame and label
' counts are written again at its CEND (SEEK back): what this pass added.
#INCLUDE "B2COM"

' the writer's counts in the procedure being written; where the compiled
' block being written started; the CBEGIN's fields when it was written
DIM SHARED PcEst, NJmp, NRelW, BlkPos, Cb0Local, Cb0Lab, Cb0Zero, IoMade

' ---- reading

SUB InOpen (n$)
    DIM i
    InName$ = n$
    OPEN n$ FOR BINARY AS #CHIN
    IF IoMade = 0 THEN
        REDIM InHead(WHWORDS), OutHead(WHWORDS), RPT(31) AS BYTE, RPF(31) AS BYTE
        REDIM InBuf(255) AS BYTE, OutBuf(255) AS BYTE
        IoMade = 1
    END IF
    ' (B2LEX's counts go on to the next pass; the others are this pass's)
    FOR i = 0 TO WHWORDS - 1
        GET #CHIN, , InHead(i)
        IF i < WHCODE THEN OutHead(i) = InHead(i)
    NEXT i
    IF InHead(THMAGIC) <> TOKMAGIC THEN FatalRec 83, n$   ' not B2's file: {s}
    InPend = 0
    TokLine = 0
    TokText$ = ""
    TokFile$ = SrcName$
    LineFile$ = SrcName$
END SUB

FUNCTION RdB ()
    DIM b AS BYTE
    GET #CHIN, , b
    RdB = b
END FUNCTION

FUNCTION RdW ()
    DIM w
    GET #CHIN, , w
    RdW = w
END FUNCTION

FUNCTION RdS$ ()
    DIM n AS BYTE, s$
    GET #CHIN, , n
    IF n > 0 THEN
        s$ = SPACE$(n)
        GET #CHIN, , s$
    END IF
    RdS$ = s$
END FUNCTION

' the next record's kind, not read yet (NextRec reads it)
FUNCTION PeekRec ()
    IF InPend = 0 THEN
        InPendK = RdB
        IF InPendK = 0 THEN InPendK = TEOF
        InPend = 1
    END IF
    PeekRec = InPendK
END FUNCTION

' the next record: Rk and its operands (Tok is Rk, for errors' place)
SUB NextRec ()
    DIM i
    IF InPend THEN
        Rk = InPendK
        InPend = 0
    ELSE
        Rk = RdB
        IF Rk = 0 THEN Rk = TEOF
    END IF
    Tok = Rk
    IF Rk < 128 THEN EXIT SUB
    SELECT CASE Rk
    CASE TIDENT, TSNG, TDBL, TSTR, TLABEL, RLREF
        RS$ = RdS$
        TokS$ = RS$
    CASE TINT, RLAB, CLABEL, CCASE, CGOSUB, COBJW
        RW1 = RdW
        TokV = RW1
    CASE TLINE
        RW1 = RdW
        RS$ = RdS$
        PrevLine = TokLine
        PrevText$ = TokText$
        PrevFile$ = LineFile$
        LineFile$ = TokFile$
        TokLine = RW1
        TokText$ = RS$
    CASE TFILE
        RS$ = RdS$
        TokFile$ = RS$
    CASE RSTMT, RX, RLV, RMARK, COBJB
        RB1 = RdB
    CASE RVAR
        RB1 = RdB
        RB2 = RdB
        RB3 = RdB
        RW1 = RdW
        RW2 = RdB
        RS$ = RdS$
    CASE RCALL
        RB1 = RdB
        RB2 = RdB
        RS$ = RdS$
        RNP = RdB
        FOR i = 1 TO RNP
            RPT(i) = RdB
            RPF(i) = RdB
        NEXT i
        RS2$ = RdS$
    CASE RBUILT
        RB1 = RdB
        RS$ = RdS$
    CASE RXC
        RB1 = RdB
        RB2 = RdB
        RW1 = RdW
    CASE RLVC
        RB1 = RdB
        RB2 = RdB
    CASE CBYTES
        RB1 = RdB
        FOR i = 0 TO RB1 - 1
            InBuf(i) = RdB
        NEXT i
    CASE CJUMP, CFREE
        RB1 = RdB
        RW1 = RdW
    CASE CALIAS
        RW1 = RdW
        RW2 = RdW
    CASE CREL
        RB1 = RdB
        RS$ = RdS$
    CASE COBJS
        RS$ = RdS$
    CASE CBEGIN
        CbKind = RdW
        CbPw = RdW
        CbRw = RdW
        CbResOff = RdW
        CbResTy = RdW
        CbMark = RdW
        CbLocal = RdW
        CbLab = RdW
        CbZero = RdW
        CbFlags = RdW
        CbName$ = RdS$
        CbSeg$ = RdS$
        InProc = CbKind = 0
    CASE CEND
        RW1 = RdW
        RS$ = RdS$
        RS2$ = RdS$
    END SELECT
END SUB

' ---- writing

SUB OutOpen (n$)
    DIM i
    OutName$ = n$
    IF FileExists(n$) THEN KILL n$
    OPEN n$ FOR BINARY AS #CHOUT
    OutPos = 0
    NOutBuf = 0
    FOR i = 0 TO WHWORDS - 1
        WW 0
    NEXT i
    FOR i = WHCODE TO WHBLK
        OutHead(i) = 0
    NEXT i
END SUB

' the header (p: the pass) and the end
SUB OutClose (p)
    DIM i
    OB1Flush
    WB TEOF
    OutHead(WHPASS) = p
    SEEK #CHOUT, 1
    FOR i = 0 TO WHWORDS - 1
        PUT #CHOUT, , OutHead(i)
    NEXT i
    CLOSE #CHOUT
END SUB

SUB WB (v)
    DIM b AS BYTE
    b = v AND 255
    PUT #CHOUT, , b
    OutPos = OutPos + 1
END SUB

SUB WW (w)
    PUT #CHOUT, , w
    OutPos = OutPos + 2
END SUB

SUB WS (s$)
    WB LEN(s$)
    IF LEN(s$) > 0 THEN PUT #CHOUT, , s$
    OutPos = OutPos + LEN(s$)
END SUB

' the code bytes collected: a CBYTES record
SUB OB1Flush ()
    DIM i
    IF NOutBuf = 0 THEN EXIT SUB
    WB CBYTES
    WB NOutBuf
    FOR i = 0 TO NOutBuf - 1
        WB OutBuf(i)
    NEXT i
    NOutBuf = 0
END SUB

' a record k starts (the code bytes before it first); what it adds to the
' procedure's code, jumps and relocations is counted
SUB WRec (k)
    OB1Flush
    WB k
    SELECT CASE k
    CASE CJUMP, CCASE
        NJmp = NJmp + 1
        PcEst = PcEst + 2
    CASE CREL
        NRelW = NRelW + 1
    CASE CALIGN
        PcEst = PcEst + 1
    CASE CTEMP
        ' (B2ASM's: LDL m, SRO _TTOP)
        PcEst = PcEst + 6
        NRelW = NRelW + 1
    CASE CFREE
        ' (LLA n, CXP _SFREE)
        PcEst = PcEst + 6
        NRelW = NRelW + 1
    CASE CGOSUB
        ' (the return table's word)
        PcEst = PcEst + 2
        NJmp = NJmp + 1
    CASE RXC, RLVC
        BlkPos = OutPos
    CASE RXCE, RLVCE
        IF OutPos - BlkPos > OutHead(WHBLK) THEN OutHead(WHBLK) = OutPos - BlkPos
    END SELECT
END SUB

' a byte of code
SUB OB (b)
    IF NOutBuf >= 255 THEN OB1Flush
    OutBuf(NOutBuf) = b AND 255
    NOutBuf = NOutBuf + 1
    PcEst = PcEst + 1
END SUB

' a procedure starts: its CBEGIN with the fields CBxxx (written again at
' its CEND with what was added)
SUB WBegin ()
    WRec CBEGIN
    CbPos = OutPos
    WW CbKind
    WW CbPw
    WW CbRw
    WW CbResOff
    WW CbResTy
    WW CbMark
    WW CbLocal
    WW CbLab
    WW CbZero
    WW CbFlags
    WS CbName$
    WS CbSeg$
    Cb0Local = CbLocal
    Cb0Lab = CbLab
    Cb0Zero = CbZero
    PcEst = 0
    NJmp = 0
    NRelW = 0
    InProc = CbKind = 0
END SUB

' ... its end (line, file, text: where, for an error B2ASM finds)
SUB WEndProc (l, f$, t$)
    DIM e
    OB1Flush
    IF CbLocal <> Cb0Local OR CbLab <> Cb0Lab OR CbZero <> Cb0Zero THEN
        e = OutPos
        SEEK #CHOUT, CbPos + 13
        PUT #CHOUT, , CbLocal
        PUT #CHOUT, , CbLab
        PUT #CHOUT, , CbZero
        SEEK #CHOUT, e + 1
    END IF
    WRec CEND
    WW l
    WS f$
    WS t$
    ' (the entry and exit code, B2ASM's: at most 48 bytes, 6 relocations
    ' and 2 jumps besides those counted)
    IF PcEst + 48 > OutHead(WHCODE) THEN OutHead(WHCODE) = PcEst + 48
    IF CbLab + 2 > OutHead(WHLABS) THEN OutHead(WHLABS) = CbLab + 2
    IF NJmp + 2 > OutHead(WHJUMPS) THEN OutHead(WHJUMPS) = NJmp + 2
    IF NRelW + 6 > OutHead(WHRELS) THEN OutHead(WHRELS) = NRelW + 6
END SUB

' the record just read, written as it was
SUB PutRec ()
    DIM i
    IF Rk = CBEGIN THEN
        WBegin
        EXIT SUB
    END IF
    IF Rk = CEND THEN
        WEndProc RW1, RS$, RS2$
        EXIT SUB
    END IF
    IF Rk = CBYTES THEN
        FOR i = 0 TO RB1 - 1
            OB InBuf(i)
        NEXT i
        EXIT SUB
    END IF
    WRec Rk
    IF Rk < 128 THEN EXIT SUB
    SELECT CASE Rk
    CASE TIDENT, TSNG, TDBL, TSTR, TLABEL, TFILE, COBJS, RLREF
        WS RS$
    CASE TINT, RLAB, CLABEL, CCASE, CGOSUB, COBJW
        WW RW1
    CASE TLINE
        WW RW1
        WS RS$
    CASE RSTMT, RX, RLV, RMARK, COBJB
        WB RB1
    CASE RVAR
        WB RB1
        WB RB2
        WB RB3
        WW RW1
        WB RW2
        WS RS$
    CASE RCALL
        WB RB1
        WB RB2
        WS RS$
        WB RNP
        FOR i = 1 TO RNP
            WB RPT(i)
            WB RPF(i)
        NEXT i
        WS RS2$
    CASE RBUILT
        WB RB1
        WS RS$
    CASE RXC
        WB RB1
        WB RB2
        WW RW1
    CASE RLVC
        WB RB1
        WB RB2
    CASE CJUMP, CFREE
        WB RB1
        WW RW1
    CASE CALIAS
        WW RW1
        WW RW2
    CASE CREL
        WB RB1
        WS RS$
    END SELECT
END SUB

' copy records through to (not including) one of kind k1 or k2, or a
' statement's start, a line, a procedure's end or the end
SUB CopyTo (k1, k2)
    DIM k
    DO
        k = PeekRec
        IF k = k1 OR k = k2 OR k = RSTMT OR k = TLINE OR k = CEND OR k = TEOF OR k = TLABEL OR k = CBEGIN THEN EXIT SUB
        NextRec
        PutRec
    LOOP
END SUB

' ---- the code (B2EXPR, B2CTL, B2STMT)

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

SUB Align ()
    WRec CALIGN
END SUB

FUNCTION NewLabel ()
    NewLabel = CbLab
    CbLab = CbLab + 1
END FUNCTION

FUNCTION NewLocal (words)
    CbLocal = CbLocal + words
    NewLocal = CbLocal - words + 1
END FUNCTION

SUB SetLabel (l)
    WRec CLABEL
    WW l
END SUB

SUB Jump (op, l)
    WRec CJUMP
    WB op
    WW l
END SUB

SUB CaseWord (l)
    WRec CCASE
    WW l
END SUB

SUB Reloc (ty, n$)
    WRec CREL
    WB ty
    WS n$
END SUB

SUB CallRt (n$)
    Reloc RCALL, n$
    OB OCXP
    OB 0
    OB 0
END SUB

' a global's load, store or address: op with a 2-byte operand the linker
' fills in (a module static: its offset in the module's block; a COMMON
' variable, n$: the offset in it)
SUB GlobOp (op, cl, off, n$, add)
    DIM v
    OB op
    IF cl = SCCOMMON THEN
        Reloc RGNAME, n$
        v = add
    ELSE
        Reloc RGSTAT, ""
        v = off + add
    END IF
    OB 128 OR ((v AND &H7F00) \ 256)
    OB v AND 255
END SUB

' the string temporaries given back (B2ASM makes the code)
SUB TempReset ()
    IF TempUsed = 0 THEN EXIT SUB
    WRec CTEMP
    TempUsed = 0
END SUB

' take n words off the stack: FJP to the next instruction pops one
SUB DropWords (n)
    DIM i
    FOR i = 1 TO n
        OB OFJP
        OB 0
    NEXT i
END SUB

' words pushed as the room of a result bigger than the arguments
SUB DropPad (n)
    DIM i
    FOR i = 1 TO n
        OB 0
    NEXT i
END SUB

' the words a variable of type ty takes (an array: its slot, 1 word)
FUNCTION TypeWords (ty)
    SELECT CASE ty
    CASE TYSNG: TypeWords = 2
    CASE TYDBL: TypeWords = 4
    CASE TYVOID: TypeWords = 0
    CASE ELSE: TypeWords = 1
    END SELECT
END FUNCTION
