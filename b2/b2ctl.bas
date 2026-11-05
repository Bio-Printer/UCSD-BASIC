' B2CTL -- pass 6: the control structures (docs/B2DESIGN.md)
'
' IF / ELSEIF / ELSE / END IF, DO / LOOP, WHILE / WEND, FOR / NEXT, SELECT
' CASE / CASE / END SELECT, EXIT, CONTINUE, GOTO, GOSUB, RETURN, EXIT SUB,
' ON ... GOTO / GOSUB: their jumps and labels, around the code B2EXPR made
' of their expressions (a condition's jumps to LFALSE get the statement's
' label here).  The blocks are open on a stack (B2SYN checked them), not
' in a recursion: their statements are other passes', copied through.
' The labels and FOR's temporaries are new ones (CBEGIN's counts).  A
' statement's string temporaries are given back (CTEMP) where BC did.
#INCLUDE "B2COM"

' the open blocks: kind (KIF ...), labels (Bl1: false / next / top, Bl2:
' end / exit, Bl3: continue), a condition made temporaries (BlF); a CASE
' body is open (BlIn: 1, 2 CASE ELSE's)
DIM SHARED BlK(MAXCTL), Bl1(MAXCTL), Bl2(MAXCTL), Bl3(MAXCTL), BlF(MAXCTL), BlIn(MAXCTL), NBl
' a FOR's: its variable (class, type, offset, name), limit's and step's
' locals (0: a constant step, its code kept in FsB, 256 an alignment), the
' step's sign (0: known at run time only)
DIM SHARED FvCl(MAXCTL), FvTy(MAXCTL), FvOff(MAXCTL), FvNm$(MAXCTL), FLim(MAXCTL), FStep(MAXCTL)
DIM SHARED FSign(MAXCTL), FsB(MAXCTL * 16), FsN(MAXCTL)
' the procedure's GOSUBs; the last block copied made temporaries
DIM SHARED NGosub, BlkTemp, OnLab(50)

' ---- the code B2EXPR made

' a compiled block (RXC read) copied to its end, a condition's LFALSE
' made lf; BlkTemp: it made temporaries
SUB CopyBlock (lf)
    BlkTemp = 0
    IF Rk <> RXC THEN EXIT SUB
    PutRec
    DO
        NextRec
        IF Rk = CJUMP AND RW1 = LFALSE THEN RW1 = lf
        PutRec
        IF Rk = RXCE OR Rk = TEOF THEN EXIT DO
    LOOP
    IF RB1 AND XFTEMP THEN BlkTemp = 1
END SUB

' the next record a compiled block?  (read, then)
FUNCTION NextBlock ()
    IF PeekRec = RXC THEN
        NextRec
        NextBlock = -1
    END IF
END FUNCTION

SUB AtFalse (f)
    IF f THEN
        TempUsed = 1
        TempReset
    END IF
END SUB

' a condition: jump to lf when false; its temporaries given back on the way
' through; returns whether it made some (AtFalse gives them back at lf)
FUNCTION CondJ (lf)
    CondJ = 0
    IF NextBlock THEN
        CopyBlock lf
        CondJ = BlkTemp
        TempUsed = BlkTemp
        TempReset
    END IF
END FUNCTION

' ---- the blocks

FUNCTION PushBl (k, a, b, c)
    IF NBl >= MAXCTL THEN
        ErrNo 34   ' blocks nested too deep
        NBl = 0
    END IF
    NBl = NBl + 1
    BlK(NBl) = k
    Bl1(NBl) = a
    Bl2(NBl) = b
    Bl3(NBl) = c
    BlF(NBl) = 0
    BlIn(NBl) = 0
    PushBl = NBl
END FUNCTION

FUNCTION FindBl (k)
    DIM i
    FOR i = NBl TO 1 STEP -1
        IF BlK(i) = k THEN
            FindBl = i
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

' ---- a FOR's variable (a simple one), its limit and step

SUB FvLoad (k)
    DIM w, ty
    ty = FvTy(k)
    w = TypeWords(ty)
    SELECT CASE FvCl(k)
    CASE SCLOCAL, SCPARAM
        IF w = 1 THEN
            Ldl FvOff(k)
        ELSE
            Lla FvOff(k)
            OB OLDM
            OB w
        END IF
    CASE SCSTATIC, SCCOMMON
        IF w = 1 THEN
            GlobOp OLDO, FvCl(k), FvOff(k), FvNm$(k), 0
        ELSE
            GlobOp OLAO, FvCl(k), FvOff(k), FvNm$(k), 0
            OB OLDM
            OB w
        END IF
    CASE SCREF
        Ldl FvOff(k)
        IF ty = TYBYTE THEN
            OB 0
            OB OLDB
        ELSEIF w = 1 THEN
            OB OSIND0
        ELSE
            OB OLDM
            OB w
        END IF
    END SELECT
END SUB

SUB FvPre (k)
    DIM w, ty
    ty = FvTy(k)
    w = TypeWords(ty)
    SELECT CASE FvCl(k)
    CASE SCLOCAL, SCPARAM
        IF w > 1 THEN Lla FvOff(k)
    CASE SCSTATIC, SCCOMMON
        IF w > 1 THEN GlobOp OLAO, FvCl(k), FvOff(k), FvNm$(k), 0
    CASE SCREF
        Ldl FvOff(k)
        IF ty = TYBYTE THEN OB 0
    END SELECT
END SUB

SUB FvStore (k)
    DIM w, ty
    ty = FvTy(k)
    w = TypeWords(ty)
    IF FvCl(k) = SCREF THEN
        IF ty = TYBYTE THEN
            OB OSTB
        ELSEIF w = 1 THEN
            OB OSTO
        ELSE
            OB OSTM
            OB w
        END IF
        EXIT SUB
    END IF
    IF ty = TYBYTE THEN
        Ldc 255
        OB OLAND
    END IF
    SELECT CASE FvCl(k)
    CASE SCLOCAL, SCPARAM
        IF w = 1 THEN
            Stl FvOff(k)
        ELSE
            OB OSTM
            OB w
        END IF
    CASE SCSTATIC, SCCOMMON
        IF w = 1 THEN
            GlobOp OSRO, FvCl(k), FvOff(k), FvNm$(k), 0
        ELSE
            OB OSTM
            OB w
        END IF
    END SELECT
END SUB

' a local of w words onto the stack
SUB LdLoc (off, w)
    IF w = 1 THEN
        Ldl off
    ELSE
        Lla off
        OB OLDM
        OB w
    END IF
END SUB

' DCMP's relation codes: 0 == 1 <> 2 < 3 <= 4 > 5 >=
SUB CmpOp (op, ty)
    IF ty = TYDBL THEN
        IF op = TLE THEN Ldc 3 ELSE Ldc 5
        EmitCsp 105
    ELSEIF ty = TYINT THEN
        IF op = TLE THEN OB OLEQI ELSE OB OGEQI
    ELSE
        IF op = TLE THEN OB OLEQ ELSE OB OGEQ
        OB 2
    END IF
END SUB

' the comparison of a FOR: v <= limit (up) or v >= limit (down)
SUB ForTest (k, up, lexit)
    DIM ty
    ty = FvTy(k)
    IF ty = TYBYTE THEN ty = TYINT
    FvLoad k
    LdLoc FLim(k), TypeWords(ty)
    IF up THEN CmpOp TLE, ty ELSE CmpOp TGE, ty
    Jump OFJP, lexit
END SUB

' the step: its local, or the constant's code kept
SUB ForStep (k, ty)
    DIM i
    IF FStep(k) > 0 THEN
        LdLoc FStep(k), TypeWords(ty)
    ELSE
        FOR i = 1 TO FsN(k)
            IF FsB(k * 16 + i) = 256 THEN Align ELSE OB FsB(k * 16 + i)
        NEXT i
    END IF
END SUB

' a block's value stored into a new local of w words (Lla before it)
FUNCTION StoreNew (w)
    DIM t
    t = NewLocal(w)
    IF w > 1 THEN Lla t
    CopyBlock 0
    IF w = 1 THEN
        Stl t
    ELSE
        OB OSTM
        OB w
    END IF
    StoreNew = t
END FUNCTION

' FOR: RVAR v, the assignment's block, the limit's, the step's
SUB CtlFor ()
    DIM k, ty, w, ltop, lcont, lexit, lneg, lbody, f, fl, i
    ltop = NewLabel
    lcont = NewLabel
    lexit = NewLabel
    k = PushBl(KFOR, ltop, lexit, lcont)
    NextRec
    FvCl(k) = RB3
    FvTy(k) = RB2
    FvOff(k) = RW1
    FvNm$(k) = RS$
    ty = RB2
    IF ty = TYBYTE THEN ty = TYINT
    w = TypeWords(ty)
    ' v = a
    IF NextBlock THEN CopyBlock 0
    f = BlkTemp
    ' the limit
    IF NextBlock THEN FLim(k) = StoreNew(w)
    f = f OR BlkTemp
    ' the step: a constant's code kept, else a local
    FStep(k) = 0
    FSign(k) = 0
    FsN(k) = 0
    IF NextBlock THEN
        fl = RB2
        IF fl AND XFICON THEN
            IF RW1 < 0 THEN FSign(k) = -1 ELSE FSign(k) = 1
        ELSEIF fl AND XFRCON THEN
            IF fl AND XFNEG THEN FSign(k) = -1 ELSE FSign(k) = 1
        END IF
        IF FSign(k) <> 0 THEN
            DO
                NextRec
                IF Rk = RXCE OR Rk = TEOF THEN EXIT DO
                IF Rk = CBYTES THEN
                    FOR i = 0 TO RB1 - 1
                        IF FsN(k) < 15 THEN FsN(k) = FsN(k) + 1
                        FsB(k * 16 + FsN(k)) = InBuf(i)
                    NEXT i
                ELSEIF Rk = CALIGN THEN
                    IF FsN(k) < 15 THEN FsN(k) = FsN(k) + 1
                    FsB(k * 16 + FsN(k)) = 256
                END IF
            LOOP
        ELSE
            FStep(k) = StoreNew(w)
            f = f OR BlkTemp
        END IF
    END IF
    TempUsed = f
    TempReset
    SetLabel ltop
    IF FSign(k) > 0 THEN
        ForTest k, 1, lexit
    ELSEIF FSign(k) < 0 THEN
        ForTest k, 0, lexit
    ELSE
        ' the step's sign at run time
        lneg = NewLabel
        lbody = NewLabel
        ForStep k, ty
        IF ty = TYINT THEN
            OB 0
        ELSE
            OB OLDC
            OB w \ 2
            Align
            FOR i = 1 TO w
                OW 0
            NEXT i
        END IF
        CmpOp TGE, ty
        Jump OFJP, lneg
        ForTest k, 1, lexit
        Jump OUJP, lbody
        SetLabel lneg
        ForTest k, 0, lexit
        SetLabel lbody
    END IF
END SUB

' NEXT: v = v + step, to the top
SUB CtlNext ()
    DIM k, ty
    k = NBl
    IF k = 0 THEN EXIT SUB
    ty = FvTy(k)
    IF ty = TYBYTE THEN ty = TYINT
    SetLabel Bl3(k)
    FvPre k
    FvLoad k
    ForStep k, ty
    IF ty = TYINT THEN
        OB OADI
    ELSEIF ty = TYSNG THEN
        OB OADR
    ELSE
        EmitCsp 100
    END IF
    FvStore k
    Jump OUJP, Bl1(k)
    SetLabel Bl2(k)
    FvNm$(k) = ""
    NBl = NBl - 1
END SUB

' CASE: the body before ends (to END SELECT), the items: each a condition
' (to the body when true; the last one to the next CASE when false)
SUB CtlCase (iselse)
    DIM k, lbody, lskip, f, m
    k = FindBl(KSELECT)
    IF k = 0 THEN EXIT SUB
    IF BlIn(k) = 1 THEN Jump OUJP, Bl2(k)
    IF Bl1(k) >= 0 THEN
        SetLabel Bl1(k)
        AtFalse BlF(k)
        Bl1(k) = -1
    END IF
    IF iselse THEN
        BlIn(k) = 2
        EXIT SUB
    END IF
    lbody = NewLabel
    Bl1(k) = NewLabel
    f = 0
    DO WHILE PeekRec = RMARK
        NextRec
        m = RB1
        IF NOT NextBlock THEN EXIT DO
        IF m = MMORE THEN
            lskip = NewLabel
            CopyBlock lskip
            f = f OR BlkTemp
            Jump OUJP, lbody
            SetLabel lskip
        ELSE
            CopyBlock Bl1(k)
            f = f OR BlkTemp
            EXIT DO
        END IF
    LOOP
    BlF(k) = f
    SetLabel lbody
    TempUsed = f
    TempReset
    BlIn(k) = 1
END SUB

' ON e GOTO / GOSUB labels: a case table
SUB CtlOn ()
    DIM isgosub, n, i, lafter, site, l
    IF NextBlock THEN CopyBlock 0
    TempUsed = BlkTemp
    TempReset
    NextRec
    isgosub = RW1
    DO WHILE PeekRec = RLAB
        NextRec
        IF n < 50 THEN
            n = n + 1
            OnLab(n) = RW1
        ELSE
            ErrNo 52   ' more than 50 labels
        END IF
    LOOP
    lafter = NewLabel
    OB OXJP
    Align
    OW 1
    OW n
    Jump OUJP, lafter
    IF isgosub THEN
        site = GosubSite(lafter)
        l = CbLab
        FOR i = 1 TO n
            CaseWord l + i - 1
        NEXT i
        FOR i = 1 TO n
            SetLabel NewLabel
            Ldc site
            CallRt "_GSPUSH"
            Jump OUJP, OnLab(i)
        NEXT i
    ELSE
        FOR i = 1 TO n
            CaseWord OnLab(i)
        NEXT i
    END IF
    SetLabel lafter
END SUB

' a GOSUB's return point: its number (RETURN goes back through B2ASM's table)
FUNCTION GosubSite (l)
    IF NGosub >= 100 THEN
        ErrNo 114   ' more than 100 GOSUBs in one procedure
        EXIT FUNCTION
    END IF
    NGosub = NGosub + 1
    WRec CGOSUB
    WW l
    GosubSite = NGosub
END FUNCTION

' ---- the statements

' a statement of B2CTL's (RSTMT k written; the record after it next)
SUB CtlStmt (k)
    DIM b, l, t
    SELECT CASE k
    CASE KIF
        l = NewLabel
        b = PushBl(KIF, l, NewLabel, 0)
        BlF(b) = CondJ(l)
    CASE KELSEIF
        b = NBl
        Jump OUJP, Bl2(b)
        SetLabel Bl1(b)
        AtFalse BlF(b)
        l = NewLabel
        Bl1(b) = l
        BlF(b) = CondJ(l)
    CASE KELSE
        b = NBl
        Jump OUJP, Bl2(b)
        SetLabel Bl1(b)
        AtFalse BlF(b)
        Bl1(b) = -1
        BlF(b) = 0
    CASE SENDIF
        b = NBl
        IF Bl1(b) >= 0 THEN
            SetLabel Bl1(b)
            AtFalse BlF(b)
        END IF
        SetLabel Bl2(b)
        NBl = NBl - 1
    CASE KDO
        b = PushBl(KDO, NewLabel, NewLabel, NewLabel)
        SetLabel Bl1(b)
        BlF(b) = CondJ(Bl2(b))
    CASE KLOOP
        b = NBl
        SetLabel Bl3(b)
        t = CondJ(Bl2(b))
        Jump OUJP, Bl1(b)
        SetLabel Bl2(b)
        AtFalse BlF(b) OR t
        NBl = NBl - 1
    CASE KWHILE
        l = NewLabel
        b = PushBl(KWHILE, l, NewLabel, l)
        SetLabel l
        BlF(b) = CondJ(Bl2(b))
    CASE KWEND
        b = NBl
        Jump OUJP, Bl1(b)
        SetLabel Bl2(b)
        AtFalse BlF(b)
        NBl = NBl - 1
    CASE KFOR
        CtlFor
    CASE KNEXT
        CtlNext
    CASE KSELECT
        IF NextBlock THEN CopyBlock 0
        TempUsed = BlkTemp
        TempReset
        b = PushBl(KSELECT, -1, NewLabel, 0)
    CASE KCASE
        CtlCase 0
    CASE SCASEELSE
        CtlCase 1
    CASE SENDSEL
        b = FindBl(KSELECT)
        IF BlIn(b) = 1 THEN Jump OUJP, Bl2(b)
        IF Bl1(b) >= 0 THEN
            SetLabel Bl1(b)
            AtFalse BlF(b)
        END IF
        SetLabel Bl2(b)
        NBl = b - 1
    CASE KEXIT, KCONTINUE
        NextRec
        b = FindBl(RW1)
        IF b > 0 THEN
            IF k = KEXIT THEN Jump OUJP, Bl2(b) ELSE Jump OUJP, Bl3(b)
        END IF
    CASE SEXITSUB
        Jump OUJP, 0
    CASE KRETURN
        Jump OUJP, 1
    CASE KGOTO
        NextRec
        Jump OUJP, RW1
    CASE KGOSUB
        NextRec
        t = RW1
        l = NewLabel
        Ldc GosubSite(l)
        CallRt "_GSPUSH"
        Jump OUJP, t
        SetLabel l
    CASE KON
        CtlOn
    END SELECT
END SUB

FUNCTION IsCtl (k)
    SELECT CASE k
    CASE KIF, KELSEIF, KELSE, SENDIF, KDO, KLOOP, KWHILE, KWEND, KFOR, KNEXT
        IsCtl = -1
    CASE KSELECT, KCASE, SCASEELSE, SENDSEL, KEXIT, KCONTINUE, SEXITSUB
        IsCtl = -1
    CASE KRETURN, KGOTO, KGOSUB, KON
        IsCtl = -1
    END SELECT
END FUNCTION

SUB CtlPass ()
    DIM k
    DO
        NextRec
        SELECT CASE Rk
        CASE TEOF
            EXIT DO
        CASE CBEGIN
            PutRec
            NBl = 0
            NGosub = 0
        CASE RSTMT
            k = RB1
            PutRec
            IF IsCtl(k) THEN CtlStmt k
        CASE ELSE
            PutRec
        END SELECT
    LOOP
END SUB

' ---- B2CTL, the program: pass 6 of the job's compile step, then B2STMT

ReadJob
StepNames
ErrCount = 0
InOpen PassFile$(5)
OutOpen PassFile$(6)
MemNote "start"
CtlPass
CLOSE #CHIN
OutClose 6
IF ErrCount > 0 THEN CompileFailed
IF OptKeep = 0 THEN KILL PassFile$(5)
IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words (B2CTL)"
ChainTo "B2STMT", ""
