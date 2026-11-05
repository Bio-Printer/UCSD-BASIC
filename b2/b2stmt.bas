' B2STMT -- pass 7: the other statements (docs/B2DESIGN.md)
'
' Assignments and SUB calls (all code already: B2EXPR's), PRINT, WRITE,
' INPUT, LINE INPUT, OPEN, CLOSE, GET, PUT, SEEK, KILL, CHAIN, SWAP,
' RANDOMIZE, CLS, LOCATE, END, READ, RESTORE, DIM, REDIM, ERASE, MID$ =,
' POKE, POKEB, CSP, OSCALL, ON ERROR and the module's DATA: the calls of
' the library around the code B2EXPR made of their expressions and
' targets.  A statement's string temporaries are given back after it
' (CTEMP), PRINT's, WRITE's and READ's after each item, as BC did.  GET
' and PUT need a block in another order than it comes: it is kept (KeepBlk:
' as large as B2EXPR's largest, the header's WHBLK) and written later.
#INCLUDE "B2COM"
#INCLUDE "B2REC"
#INCLUDE "B2OPS"

' the blocks kept (Kp: the records' bytes, KpS$: their names; KpN each
' slot's length); the channel of PRINT # ... (a constant, or minus a local)
DIM SHARED Kp(), KpS$(), KpN(4), KpCap, Chan

' ---- the code B2EXPR made

' a block's records to its end (RXCE, RLVCE) or to RLVL / RLVS, copied
' (keep 0) or kept in slot keep: TempUsed if it made temporaries.  The
' record that ended it is current.
SUB CopyCode (keep)
    DIM i, b
    IF keep > 0 THEN KpN(keep) = 0
    DO
        NextRec
        SELECT CASE Rk
        CASE RXCE, RLVCE
            IF RB1 AND XFTEMP THEN TempUsed = 1
            EXIT SUB
        CASE RLVL, RLVS, TEOF, RSTMT, TLINE, CEND
            EXIT SUB
        CASE ELSE
            IF keep = 0 THEN
                PutRec
            ELSE
                b = (keep - 1) * KpCap
                IF KpN(keep) + 260 > KpCap THEN
                    ErrNo 84   ' expression too complex
                    KpN(keep) = 0
                END IF
                Kp(b + KpN(keep)) = Rk
                KpN(keep) = KpN(keep) + 1
                SELECT CASE Rk
                CASE CBYTES
                    Kp(b + KpN(keep)) = RB1
                    KpN(keep) = KpN(keep) + 1
                    FOR i = 0 TO RB1 - 1
                        Kp(b + KpN(keep)) = InBuf(i)
                        KpN(keep) = KpN(keep) + 1
                    NEXT i
                CASE CJUMP, CFREE
                    Kp(b + KpN(keep)) = RB1
                    Kp(b + KpN(keep) + 1) = RW1
                    KpN(keep) = KpN(keep) + 2
                CASE CLABEL, CCASE, CGOSUB
                    Kp(b + KpN(keep)) = RW1
                    KpN(keep) = KpN(keep) + 1
                CASE CREL
                    Kp(b + KpN(keep)) = RB1
                    KpS$(b + KpN(keep)) = RS$
                    KpN(keep) = KpN(keep) + 1
                END SELECT
            END IF
        END SELECT
    LOOP
END SUB

' a slot's records written
SUB PutKept (k)
    DIM i, j, n, b, r
    b = (k - 1) * KpCap
    i = 0
    DO WHILE i < KpN(k)
        r = Kp(b + i)
        i = i + 1
        SELECT CASE r
        CASE CBYTES
            n = Kp(b + i)
            FOR j = 1 TO n
                OB Kp(b + i + j)
            NEXT j
            i = i + n + 1
        CASE CJUMP
            Jump Kp(b + i), Kp(b + i + 1)
            i = i + 2
        CASE CFREE
            WRec CFREE
            WB Kp(b + i)
            WW Kp(b + i + 1)
            i = i + 2
        CASE CLABEL, CCASE, CGOSUB
            WRec r
            WW Kp(b + i)
            i = i + 1
        CASE CREL
            Reloc Kp(b + i), KpS$(b + i)
            KpS$(b + i) = ""
            i = i + 1
        CASE ELSE
            WRec r
        END SELECT
    LOOP
END SUB

' the next record a compiled block?  (RXC or RLVC read, then: its type in
' BTy, flags BFl, value BVal)
DIM SHARED BTy, BFl, BVal

FUNCTION NextBlock ()
    DIM k
    k = PeekRec
    IF k = RXC OR k = RLVC THEN
        NextRec
        BTy = RB1
        BFl = RB2
        IF k = RXC THEN BVal = RW1 ELSE BVal = 0
        NextBlock = -1
    END IF
END FUNCTION

' the next block copied (its type: the function's)
FUNCTION CopyNext ()
    IF NextBlock THEN
        CopyCode 0
        CopyNext = BTy
    END IF
END FUNCTION

' ---- the code's small parts

SUB Lsa (s$)
    DIM i
    OB OLSA
    OB LEN(s$)
    FOR i = 1 TO LEN(s$)
        OB ASC(s$, i)
    NEXT i
END SUB

' an array's slot: its address (an array parameter holds the caller's)
SUB SlotOf (cl, off, n$)
    SELECT CASE cl
    CASE SCLOCAL, SCPARAM: Lla off
    CASE SCSTATIC, SCCOMMON: GlobOp OLAO, cl, off, n$, 0
    CASE SCREF: Ldl off
    END SELECT
END SUB

FUNCTION ElemBytes (ty)
    SELECT CASE ty
    CASE TYBYTE: ElemBytes = 1
    CASE TYSNG: ElemBytes = 4
    CASE TYDBL: ElemBytes = 8
    CASE ELSE: ElemBytes = 2
    END SELECT
END FUNCTION

' the bytes GET and PUT move for a type
FUNCTION TypeBytes (ty)
    SELECT CASE ty
    CASE TYBYTE: TypeBytes = 1
    CASE TYINT: TypeBytes = 2
    CASE TYSNG: TypeBytes = 4
    CASE TYDBL: TypeBytes = 8
    END SELECT
END FUNCTION

' #n of PRINT, INPUT ...: (RMARK MCHAN, then its block) a constant, or its
' value into a new local
SUB ChanOf ()
    Chan = 0
    IF PeekRec <> RMARK THEN EXIT SUB
    NextRec
    ChanBlk
END SUB

SUB ChanBlk ()
    DIM t
    IF NOT NextBlock THEN EXIT SUB
    IF BFl AND XFICON THEN
        Chan = BVal
        CopyCode 0
        EXIT SUB
    END IF
    t = NewLocal(1)
    CopyCode 0
    Stl t
    Chan = -t
END SUB

SUB PushCh ()
    IF Chan >= 0 THEN Ldc Chan ELSE Ldl -Chan
END SUB

' ---- the statements

SUB StPrint ()
    DIM k, nl, ty
    Chan = 0
    nl = 1
    DO
        k = PeekRec
        IF k = TSEMI THEN
            NextRec
            nl = 0
        ELSEIF k = TCOMMA THEN
            NextRec
            PushCh
            CallRt "_PCOMMA"
            nl = 0
        ELSEIF k = RMARK THEN
            NextRec
            IF RB1 = MCHAN THEN
                ChanBlk
            ELSE
                k = RB1
                PushCh
                ty = CopyNext
                IF k = MTAB THEN CallRt "_PTAB" ELSE CallRt "_PSPC"
                nl = 1
                TempReset
            END IF
        ELSEIF k = RXC THEN
            IF NextBlock THEN
                PushCh
                CopyCode 0
                SELECT CASE BTy
                CASE TYSTR: CallRt "_PSTR"
                CASE TYINT: CallRt "_PINT"
                CASE TYSNG: CallRt "_PSNG"
                CASE TYDBL: CallRt "_PDBL"
                END SELECT
            END IF
            nl = 1
            TempReset
        ELSE
            EXIT DO
        END IF
    LOOP
    IF nl THEN
        PushCh
        CallRt "_PNL"
    END IF
END SUB

SUB StWrite ()
    DIM first
    ChanOf
    first = 1
    DO WHILE NextBlock
        IF first = 0 THEN
            PushCh
            Lsa ","
            CallRt "_PSTR"
        END IF
        first = 0
        PushCh
        CopyCode 0
        SELECT CASE BTy
        CASE TYSTR: CallRt "_WQSTR"
        CASE TYINT
            CallRt "_STRI"
            CallRt "_LTRIM"
            CallRt "_PSTR"
        CASE TYSNG
            CallRt "_STRS"
            CallRt "_LTRIM"
            CallRt "_PSTR"
        CASE TYDBL
            CallRt "_STRD"
            CallRt "_LTRIM"
            CallRt "_PSTR"
        END SELECT
        TempUsed = 1
        TempReset
    LOOP
    PushCh
    CallRt "_PNL"
END SUB

' INPUT / LINE INPUT: [channel] [prompt] qm, the targets
SUB StInput (isline)
    DIM qm, p$, hasp, ty
    ChanOf
    IF PeekRec = TSTR THEN
        NextRec
        p$ = RS$
        hasp = 1
    END IF
    NextRec
    qm = RW1
    IF isline THEN
        IF NOT NextBlock THEN EXIT SUB
        IF BTy <> TYSTR THEN ErrNo 55   ' LINE INPUT needs a string variable
        CopyCode 0
        PushCh
        IF hasp THEN Lsa p$ ELSE Ldc 0
        CallRt "_LINPUT"
        TempUsed = 1
        CopyCode 0
        EXIT SUB
    END IF
    PushCh
    IF hasp THEN Lsa p$ ELSE Ldc 0
    Ldc qm
    CallRt "_INPUT"
    DO WHILE NextBlock
        ty = BTy
        CopyCode 0
        SELECT CASE ty
        CASE TYSTR
            OB 0
            CallRt "_INFS"
            TempUsed = 1
        CASE TYINT, TYBYTE
            OB 0
            CallRt "_INFI"
        CASE TYSNG
            DropPad 4
            CallRt "_INFD"
            EmitCsp 107
        CASE TYDBL
            DropPad 4
            CallRt "_INFD"
        END SELECT
        CopyCode 0
    LOOP
END SUB

SUB StRead ()
    DIM ty
    DO WHILE NextBlock
        ty = BTy
        CopyCode 0
        OB 0
        CallRt "_READ"
        IF ty <> TYSTR THEN
            DropPad 3
            CallRt "_VAL"
            IF ty = TYSNG THEN
                EmitCsp 107
            ELSEIF ty <> TYDBL THEN
                CallRt "_DCINT"
            END IF
        END IF
        TempUsed = 1
        CopyCode 0
        TempReset
    LOOP
END SUB

' GET #n, [pos], v / PUT #n, [pos], e: TINT pos?, [n, pos], the target or
' the value, n
SUB StGetPut (isput)
    DIM ty, fl
    NextRec
    IF RW1 THEN
        ty = CopyNext
        ty = CopyNext
        CallRt "_SEEK"
    END IF
    IF NOT NextBlock THEN EXIT SUB
    ty = BTy
    fl = BFl
    IF isput THEN
        IF ty = TYSTR THEN
            ' n, then the value
            CopyCode 1
            ty = CopyNext
            PutKept 1
            CallRt "_PUTS"
            EXIT SUB
        END IF
        CopyCode 0
        fl = CopyNext
        Ldc TypeBytes(ty)
        CallRt "_PUTR"
        EXIT SUB
    END IF
    IF fl AND XFADDR THEN
        CopyCode 0
        fl = CopyNext
        Ldc TypeBytes(ty)
        CallRt "_GETR"
        EXIT SUB
    END IF
    ' a string: its address, n, its value, its length; the store
    CopyCode 0
    CopyCode 1
    CopyCode 2
    fl = CopyNext
    PutKept 1
    CallRt "_SLEN"
    CallRt "_GETS"
    TempUsed = 1
    PutKept 2
END SUB

SUB StDim ()
    DIM pr, cl, ty, off, n$, nd, i, k
    NextRec
    pr = RW1
    DO WHILE PeekRec = RVAR
        NextRec
        cl = RB3
        ty = RB2
        off = RW1
        n$ = RS$
        NextRec
        nd = RW1
        FOR i = 1 TO nd
            k = CopyNext
            CallRt "_ABND"
        NEXT i
        SlotOf cl, off, n$
        Ldc ElemBytes(ty)
        k = 0
        IF ty = TYSTR THEN k = 1
        IF pr THEN k = k + 2
        Ldc k
        Ldc nd
        CallRt "_ADIM"
        TempReset
    LOOP
END SUB

SUB StStmt (k)
    DIM ty, t, s$
    SELECT CASE k
    CASE SASSIGN, SCALL
        ty = CopyNext
    CASE KPRINT
        StPrint
    CASE KWRITE
        StWrite
    CASE KINPUT
        StInput 0
    CASE SLINPUT
        StInput 1
    CASE KREAD
        StRead
    CASE KOPEN
        ty = CopyNext
        NextRec
        Ldc RW1
        ty = CopyNext
        ty = CopyNext
        CallRt "_OPEN"
    CASE KCLOSE
        IF PeekRec <> RXC THEN
            Ldc 0
            CallRt "_CLOSE"
        END IF
        DO WHILE NextBlock
            CopyCode 0
            CallRt "_CLOSE"
        LOOP
    CASE KGET
        StGetPut 0
    CASE KPUT
        StGetPut 1
    CASE KSEEK
        ty = CopyNext
        ty = CopyNext
        CallRt "_SEEK"
    CASE KKILL
        ty = CopyNext
        CallRt "_KILL"
    CASE KCHAIN
        ty = CopyNext
        CallRt "_CHAIN"
    CASE KSWAP
        ty = CopyNext
        t = CopyNext
        IF ty <> t THEN ErrNo 66   ' SWAP needs two variables of one type
        IF ty = TYSTR THEN
            CallRt "_SSWAP"
        ELSE
            Ldc TypeBytes(ty)
            CallRt "_SWAP"
        END IF
    CASE KRANDOMIZE
        ty = CopyNext
        CallRt "_RANDOMIZE"
    CASE KCLS
        CallRt "_CLS"
    CASE KLOCATE
        ty = CopyNext
        ty = CopyNext
        CallRt "_LOCATE"
    CASE KEND
        ty = CopyNext
        CallRt "_HALT"
    CASE KRESTORE
        NextRec
        GlobOp OLDO, RB3, RW1, RS$, 0
        NextRec
        IF RW1 >= 0 THEN
            Ldc RW1
            OB OADI
        END IF
        CallRt "_RESTORE"
    CASE KDIM, KREDIM
        StDim
    CASE KERASE
        DO WHILE PeekRec = RVAR
            NextRec
            SlotOf RB3, RW1, RS$
            CallRt "_AFREE"
        LOOP
    CASE SMIDSET
        ty = CopyNext
        IF ty <> TYSTR THEN ErrNo 68   ' MID$ needs a string variable
        ty = CopyNext
        ty = CopyNext
        ty = CopyNext
        CallRt "_MIDSET"
    CASE SPOKE, SPOKEB
        ty = CopyNext
        IF k = SPOKEB THEN OB 0
        ty = CopyNext
        IF k = SPOKEB THEN OB OSTB ELSE OB OSTO
    CASE SCSP, SOSCALL
        ' the first a constant: its number (its code dropped)
        IF NextBlock THEN
            IF (BFl AND XFICON) = 0 THEN
                IF k = SCSP THEN ErrRec 69, 0, 0, "CSP" ELSE ErrRec 69, 0, 0, "OSCALL"   ' {s}: a constant expected
            END IF
            t = BVal
            CopyCode 3
        END IF
        DO WHILE NextBlock
            CopyCode 0
        LOOP
        IF k = SCSP THEN
            EmitCsp t
        ELSE
            OB OCXP
            OB 0
            OB t
        END IF
    CASE SONERR
        NextRec
        Ldc RW1
        CallRt "_ONERR"
    CASE SDATAL
        NextRec
        OB 0
        CallRt "_DMARK"
        GlobOp OSRO, RB3, RW1, RS$, 0
        DO WHILE PeekRec = TSTR
            NextRec
            Lsa RS$
            CallRt "_DATA"
        LOOP
    END SELECT
    TempReset
END SUB

FUNCTION IsStmt (k)
    SELECT CASE k
    CASE SASSIGN, SCALL, KPRINT, KWRITE, KINPUT, SLINPUT, KREAD, KOPEN, KCLOSE, KGET, KPUT
        IsStmt = -1
    CASE KSEEK, KKILL, KCHAIN, KSWAP, KRANDOMIZE, KCLS, KLOCATE, KEND, KRESTORE, KDIM, KREDIM
        IsStmt = -1
    CASE KERASE, SMIDSET, SPOKE, SPOKEB, SCSP, SOSCALL, SONERR, SDATAL
        IsStmt = -1
    END SELECT
END FUNCTION

SUB StmtPass ()
    DIM k
    DO
        NextRec
        SELECT CASE Rk
        CASE TEOF
            EXIT DO
        CASE RSTMT
            k = RB1
            PutRec
            IF IsStmt(k) THEN
                TempUsed = 0
                StStmt k
            END IF
        CASE ELSE
            PutRec
        END SELECT
    LOOP
END SUB

' ---- B2STMT, the program: pass 7 of the job's compile step, then B2ASM

ReadJob
StepNames
ErrCount = 0
InOpen PassFile$(6)
' (three blocks kept, each as large as the largest B2EXPR made, and a
' CBYTES record more)
KpCap = Capped(InHead(WHBLK) + 270, 8000)
REDIM Kp(3 * KpCap), KpS$(3 * KpCap)
OutOpen PassFile$(7)
MemNote "start"
StmtPass
CLOSE #CHIN
OutClose 7
IF ErrCount > 0 THEN CompileFailed
IF OptKeep = 0 THEN KILL PassFile$(6)
IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words (B2STMT)"
ChainTo "B2ASM", ""
