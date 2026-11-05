' B2SYN -- pass 2: the statements' syntax (docs/B2DESIGN.md)
'
' Reads the token file and writes each statement as RSTMT kind and its
' parts: expressions bracketed (RX how ... RXE), targets (RLV what ...
' RLVE), defaults written in (LOCATE's 0, MID$'s 255 ...), the forms made
' one: a one-line IF a block IF, NEXT i, j two NEXTs, RETURN x an
' assignment and EXIT FUNCTION, SELECT CASE's items conditions on RSEL.
' The blocks are checked here (B2CTL trusts them).  Names stay names:
' B2NAME resolves them.  What each statement becomes is written above its
' procedure below; B2DECL, B2NAME, B2EXPR, B2CTL and B2STMT read it so.
#INCLUDE "B2COM"

' the open blocks (BkKind: KIF, KFOR, KDO, KWHILE, KSELECT, KSUB, KFUNCTION)
DIM SHARED BkKind(MAXCTL), NBk, NFor, FnName$, InFn
' tokens kept (an assignment's target, read before = says what it is; GET's
' channel, written twice): kind, text, value
DIM SHARED TbK() AS BYTE, TbS$(), TbV(), NTb, TbCap, TbOn, TbQuiet

' ---- tokens

SUB GetTok ()
    DO
        NextRec
        IF Rk <> TFILE THEN EXIT DO
        PutRec
    LOOP
    IF ErrCount >= MAXERR THEN
        Rk = TEOF
        Tok = TEOF
    END IF
END SUB

' the current token written (and kept, TbOn), the next one read
SUB CopyTok ()
    IF TbOn THEN
        IF NTb < TbCap THEN
            NTb = NTb + 1
            TbK(NTb) = Rk
            TbS$(NTb) = RS$
            TbV(NTb) = RW1
        END IF
    END IF
    IF TbQuiet = 0 THEN PutRec
    GetTok
END SUB

' the tokens kept, written
SUB TbOut ()
    DIM i, k, s$, v
    k = Rk
    s$ = RS$
    v = RW1
    FOR i = 1 TO NTb
        Rk = TbK(i)
        RS$ = TbS$(i)
        RW1 = TbV(i)
        PutRec
        IF Rk = TIDENT OR Rk = TSTR OR Rk = TSNG OR Rk = TDBL THEN TbS$(i) = ""
    NEXT i
    Rk = k
    RS$ = s$
    RW1 = v
    NTb = 0
END SUB

FUNCTION AtEnd ()
    AtEnd = Tok = TCOLON OR Tok = TLINE OR Tok = TEOF OR Tok = KELSE
END FUNCTION

SUB SkipStmt ()
    DO WHILE Tok <> TCOLON AND Tok <> TLINE AND Tok <> TEOF
        GetTok
    LOOP
END SUB

FUNCTION IsTok (t)
    IF Tok = t THEN
        GetTok
        IsTok = -1
    END IF
END FUNCTION

SUB Expect (t)
    IF Tok = t THEN
        GetTok
    ELSE
        ErrRec 1, t, Tok, ""   ' {k} expected, not {t}
    END IF
END SUB

SUB StmtEnd ()
    IF NOT AtEnd THEN
        ErrRec 26, 0, Tok, ""   ' the end of the statement expected, not {t}
        SkipStmt
    END IF
END SUB

' ---- the parts of a statement

SUB Stm (k)
    WB RSTMT
    WB k
END SUB

SUB WTokI (v)
    WB TINT
    WW v
END SUB

' an operator between two operands?
FUNCTION IsBinOp ()
    SELECT CASE Tok
    CASE TEQ, TNE, TLT, TGT, TLE, TGE, TPLUS, TMINUS, TMUL, TDIV, TIDIV, TPOW, TAMP, TBAR
        IsBinOp = -1
    CASE KAND, KOR, KXOR, KMOD, TANDALSO, TORELSE
        IsBinOp = -1
    CASE TIDENT
        AndOr
        IsBinOp = Tok <> TIDENT
    END SELECT
END FUNCTION

' ANDALSO, ORELSE: the operators (they are names to the lexer)
SUB AndOr ()
    IF Tok <> TIDENT THEN EXIT SUB
    IF TokS$ = "ANDALSO" THEN
        Rk = TANDALSO
        Tok = TANDALSO
    ELSEIF TokS$ = "ORELSE" THEN
        Rk = TORELSE
        Tok = TORELSE
    END IF
END SUB

' an expression's tokens, as far as they make one (operands and operators
' by turns, the parentheses balanced): B2EXPR parses them
SUB ExprToks ()
    DIM depth, opnd, n
    opnd = 1
    DO
        IF opnd THEN
            SELECT CASE Tok
            CASE TINT, TSNG, TDBL, TSTR, RSEL
                CopyTok
                opnd = 0
            CASE TIDENT
                CopyTok
                opnd = 0
                IF Tok = TLPAR THEN
                    CopyTok
                    depth = depth + 1
                    IF Tok = TRPAR THEN
                        CopyTok
                        depth = depth - 1
                    ELSE
                        opnd = 1
                    END IF
                END IF
            CASE TLPAR
                CopyTok
                depth = depth + 1
            CASE TMINUS, TPLUS, KNOT
                CopyTok
            CASE ELSE
                EXIT DO
            END SELECT
        ELSEIF IsBinOp THEN
            CopyTok
            opnd = 1
        ELSEIF Tok = TRPAR AND depth > 0 THEN
            CopyTok
            depth = depth - 1
        ELSEIF Tok = TCOMMA AND depth > 0 THEN
            CopyTok
            opnd = 1
        ELSE
            EXIT DO
        END IF
        n = n + 1
    LOOP
    ' (nothing: B2EXPR says "an expression expected, not ...")
    IF n = 0 AND NOT AtEnd THEN CopyTok
END SUB

' RX how, an expression, RXE
SUB SExpr (how)
    WB RX
    WB how
    ExprToks
    WB RXE
END SUB

' an expression that is a number written in (a default)
SUB SConst (how, v)
    WB RX
    WB how
    WTokI v
    WB RXE
END SUB

' a target's tokens: a name and its ( indexes )
SUB LvToks ()
    DIM depth
    IF Tok <> TIDENT THEN
        ErrNo 28   ' a variable expected
        EXIT SUB
    END IF
    CopyTok
    IF Tok <> TLPAR THEN EXIT SUB
    DO
        IF Tok = TLPAR THEN
            depth = depth + 1
        ELSEIF Tok = TRPAR THEN
            depth = depth - 1
        ELSEIF Tok = TLINE OR Tok = TEOF OR Tok = TCOLON THEN
            ErrNo 22   ' ) expected
            EXIT SUB
        END IF
        AndOr
        CopyTok
        IF depth = 0 THEN EXIT DO
    LOOP
END SUB

SUB SLv (what)
    WB RLV
    WB what
    LvToks
    WB RLVE
END SUB

' a channel: #n (XCHAN), and the , or ; after it
SUB SChan ()
    GetTok
    SExpr XCHAN
END SUB

' ---- blocks

SUB PushBk (k)
    IF NBk >= MAXCTL THEN
        ErrNo 34   ' blocks nested too deep
        NBk = 0
    END IF
    NBk = NBk + 1
    BkKind(NBk) = k
END SUB

' the innermost block of kind k: its depth (0: none)
FUNCTION FindBk (k)
    DIM i
    FOR i = NBk TO 1 STEP -1
        IF BkKind(i) = k THEN
            FindBk = i
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

' the end of a block of kind k (t: its keyword, for the error): the
' blocks inside it not ended are errors
FUNCTION PopBk (k, t)
    IF NBk > 0 THEN
        IF BkKind(NBk) = k THEN
            NBk = NBk - 1
            PopBk = -1
            EXIT FUNCTION
        END IF
    END IF
    IF FindBk(k) = 0 THEN
        ErrRec 82, 0, t, ""   ' {t} without its block
        EXIT FUNCTION
    END IF
    DO WHILE BkKind(NBk) <> k
        BkMissing BkKind(NBk)
        NBk = NBk - 1
    LOOP
    NBk = NBk - 1
    PopBk = -1
END FUNCTION

SUB BkMissing (k)
    SELECT CASE k
    CASE KIF: ErrNo 35   ' END IF expected
    CASE KFOR: ErrNo 39   ' NEXT expected
    CASE KDO: ErrNo 40   ' LOOP expected
    CASE KWHILE: ErrNo 41   ' WEND expected
    CASE KSELECT: ErrNo 43   ' END SELECT expected
    CASE KFUNCTION: ErrNo 80   ' END FUNCTION expected
    CASE KSUB: ErrNo 81   ' END SUB expected
    END SELECT
    IF k = KFOR THEN NFor = NFor - 1
END SUB

' ---- labels

' GOTO's, GOSUB's ... label: RLREF text
SUB SLabel ()
    DIM t$
    SELECT CASE Tok
    CASE TINT
        t$ = IStr$(TokV)
    CASE TIDENT, TSNG, TDBL, TLABEL
        t$ = TokS$
    CASE ELSE
        ErrNo 32   ' a label expected
        EXIT SUB
    END SELECT
    WB RLREF
    WS t$
    GetTok
END SUB

' ---- statements

' IF c THEN: RSTMT KIF, RX XCOND c RXE; then a block (RSTMT KELSEIF, RX
' XCOND ...; RSTMT KELSE; RSTMT SENDIF) -- a one-line IF the same
SUB SIf ()
    GetTok
    Stm KIF
    SExpr XCOND
    IF Tok = KGOTO THEN
        ' IF c GOTO label
        GetTok
        Stm KGOTO
        SLabel
        Stm SENDIF
        EXIT SUB
    END IF
    Expect KTHEN
    IF Tok = TLINE OR Tok = TEOF THEN
        PushBk KIF
        EXIT SUB
    END IF
    ' on one line
    SLineStmts
    IF Tok = KELSE THEN
        GetTok
        Stm KELSE
        SLineStmts
    END IF
    Stm SENDIF
END SUB

' a one-line IF's statements (a line number: GOTO it)
SUB SLineStmts ()
    IF Tok = TINT THEN
        Stm KGOTO
        SLabel
        EXIT SUB
    END IF
    DO
        IF Tok = TLINE OR Tok = TEOF OR Tok = KELSE THEN EXIT DO
        IF Tok = TCOLON THEN
            GetTok
        ELSE
            SStmt
            IF Tok <> TCOLON THEN EXIT DO
        END IF
    LOOP
END SUB

' FOR v = a TO b [STEP c]: RSTMT KFOR, TIDENT v, RLV LVASSIGN v RLVE,
' RX XLVT a RXE, RX XLVT b RXE, RX XLVT c RXE (c: 1 if none)
SUB SFor ()
    GetTok
    IF Tok <> TIDENT THEN
        ErrNo 36   ' a FOR variable expected
        SkipStmt
        EXIT SUB
    END IF
    Stm KFOR
    PutRec
    SLv LVASSIGN
    Expect TEQ
    SExpr XLVT
    Expect KTO
    SExpr XLVT
    IF Tok = KSTEP THEN
        GetTok
        SExpr XLVT
    ELSE
        SConst XLVT, 1
    END IF
    NFor = NFor + 1
    IF NFor > 30 THEN ErrNo 38   ' FOR loops nested more than 30 deep
    PushBk KFOR
END SUB

' NEXT [v [, w ...]]: RSTMT KNEXT for each
SUB SNextStmt ()
    DO
        IF PopBk(KFOR, KNEXT) THEN NFor = NFor - 1
        Stm KNEXT
        IF Tok <> TIDENT THEN EXIT DO
        GetTok
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' DO [WHILE c | UNTIL c] / LOOP [WHILE c | UNTIL c]: RX XCOND or XNCOND
SUB SDoCond ()
    IF Tok = KWHILE THEN
        GetTok
        SExpr XCOND
    ELSEIF Tok = KUNTIL THEN
        GetTok
        SExpr XNCOND
    END IF
END SUB

' SELECT CASE e: RSTMT KSELECT, RX XSEL e RXE
SUB SSelect ()
    GetTok
    Expect KCASE
    Stm KSELECT
    SExpr XSEL
    PushBk KSELECT
END SUB

' CASE item, ...: RSTMT KCASE, each item a condition on RSEL (RX XCOND
' ... RXE), commas between; CASE ELSE: RSTMT SCASEELSE
SUB SCase ()
    DIM op
    IF NBk > 0 THEN
        IF BkKind(NBk) <> KSELECT THEN
            ErrRec 82, 0, KCASE, ""   ' {t} without its block
            SkipStmt
            EXIT SUB
        END IF
    ELSE
        ErrRec 82, 0, KCASE, ""   ' {t} without its block
        SkipStmt
        EXIT SUB
    END IF
    IF Tok = KELSE THEN
        GetTok
        Stm SCASEELSE
        EXIT SUB
    END IF
    Stm KCASE
    DO
        WB RX
        WB XCOND
        IF Tok = KIS THEN
            GetTok
            op = Tok
            IF op < TEQ OR op > TGE THEN
                ErrNo 42   ' a comparison expected after IS
                op = TEQ
            ELSE
                GetTok
            END IF
            WB RSEL
            WB op
            WB TLPAR
            ExprToks
            WB TRPAR
        ELSE
            ' a value, or a TO b: (the value's tokens kept until TO is seen)
            NTb = 0
            TbOn = 1
            TbQuiet = 1
            ExprToks
            TbOn = 0
            TbQuiet = 0
            WB RSEL
            IF Tok = KTO THEN WB TGE ELSE WB TEQ
            WB TLPAR
            TbOut
            WB TRPAR
            IF Tok = KTO THEN
                ' sel >= (a) ANDALSO sel <= (b)
                GetTok
                WB TANDALSO
                WB RSEL
                WB TLE
                WB TLPAR
                ExprToks
                WB TRPAR
            END IF
        END IF
        WB RXE
        IF Tok <> TCOMMA THEN EXIT DO
        PutRec
        GetTok
    LOOP
END SUB

' INPUT / LINE INPUT: [RX XCHAN #n RXE] [TSTR prompt] TINT qm (a "?"),
' then RLV LVPS ... RLVE for each target
SUB SInput (k)
    DIM qm
    GetTok
    Stm k
    IF Tok = THASH THEN
        SChan
        Expect TCOMMA
    ELSE
        IF Tok = TSEMI THEN GetTok
        qm = 1
        IF Tok = TSTR THEN
            PutRec
            GetTok
            IF Tok = TCOMMA THEN
                qm = 0
                GetTok
            ELSE
                Expect TSEMI
            END IF
        END IF
    END IF
    WTokI qm
    DO
        SLv LVPS
        IF k = SLINPUT OR Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' PRINT [#n,] items: [RX XCHAN], then RX XANY e RXE, TSEMI, TCOMMA, RMARK
' MTAB / MSPC RX TYINT e RXE
SUB SPrint ()
    GetTok
    Stm KPRINT
    IF Tok = THASH THEN
        SChan
        IF Tok = TCOMMA OR Tok = TSEMI THEN GetTok ELSE ErrNo 53   ' , expected
    END IF
    IF Tok = KUSING THEN
        ErrNo 54   ' PRINT USING is not supported
        SkipStmt
        EXIT SUB
    END IF
    DO WHILE NOT AtEnd
        IF Tok = TSEMI OR Tok = TCOMMA THEN
            PutRec
            GetTok
        ELSEIF Tok = TIDENT AND (TokS$ = "TAB" OR TokS$ = "SPC") THEN
            WB RMARK
            IF TokS$ = "TAB" THEN WB MTAB ELSE WB MSPC
            GetTok
            Expect TLPAR
            SExpr TYINT
            Expect TRPAR
        ELSE
            SExpr XANY
            IF NOT AtEnd AND Tok <> TSEMI AND Tok <> TCOMMA THEN EXIT DO
        END IF
    LOOP
END SUB

' WRITE [#n,] items: [RX XCHAN], RX XANY e RXE each
SUB SWrite ()
    GetTok
    Stm KWRITE
    IF Tok = THASH THEN
        SChan
        Expect TCOMMA
    END IF
    DO WHILE NOT AtEnd
        SExpr XANY
        IF Tok = TCOMMA OR Tok = TSEMI THEN
            GetTok
        ELSEIF NOT AtEnd THEN
            EXIT DO
        END IF
    LOOP
END SUB

' OPEN f FOR mode AS #n [LEN = r]: RX TYSTR f, TINT mode, RX TYINT n,
' RX TYINT r (0 if none)
SUB SOpen ()
    DIM mode
    GetTok
    Stm KOPEN
    SExpr TYSTR
    Expect KFOR
    SELECT CASE Tok
    CASE KINPUT: mode = 1
    CASE KOUTPUT: mode = 2
    CASE KAPPEND: mode = 3
    CASE KBINARY: mode = 4
    CASE KRANDOM: mode = 5
    CASE ELSE
        ErrNo 56   ' INPUT, OUTPUT, APPEND, BINARY or RANDOM expected
    END SELECT
    GetTok
    WTokI mode
    Expect KAS
    IF Tok = THASH THEN GetTok
    SExpr TYINT
    IF Tok = TIDENT AND TokS$ = "LEN" THEN
        GetTok
        Expect TEQ
        SExpr TYINT
    ELSE
        SConst TYINT, 0
    END IF
END SUB

' CLOSE [#n, ...]: RX TYINT each (none: all)
SUB SClose ()
    GetTok
    Stm KCLOSE
    IF AtEnd THEN EXIT SUB
    DO
        IF Tok = THASH THEN GetTok
        SExpr TYINT
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' GET #n, [pos], v / PUT #n, [pos], e: TINT (a pos), [RX TYINT n, RX
' TYSNG pos], then GET: RLV LVGET v RLVE / PUT: RX XPUT e RXE, and RX
' TYINT n again
SUB SGetPut (k)
    DIM haspos, i
    GetTok
    Stm k
    IF Tok = THASH THEN GetTok
    ' the channel's tokens kept: written once or twice, later
    NTb = 0
    TbOn = 1
    TbQuiet = 1
    ExprToks
    TbOn = 0
    TbQuiet = 0
    Expect TCOMMA
    IF Tok <> TCOMMA THEN haspos = 1
    WTokI haspos
    IF haspos THEN
        WB RX
        WB TYINT
        FOR i = 1 TO NTb
            Rk = TbK(i)
            RS$ = TbS$(i)
            RW1 = TbV(i)
            PutRec
        NEXT i
        WB RXE
        SExpr TYSNG
    END IF
    Expect TCOMMA
    IF k = KGET THEN SLv LVGET ELSE SExpr XPUT
    WB RX
    WB TYINT
    TbOut
    WB RXE
END SUB

' DIM / REDIM [SHARED] [PRESERVE] items: TINT shared, TINT preserve, then
' each: TIDENT name, TINT n (-1: no ( ), RX TYINT bound RXE * n, [KAS
' type keyword]
SUB SDim (k)
    DIM sh, pr, n
    GetTok
    Stm k
    IF Tok = KSHARED THEN
        sh = 1
        GetTok
        IF FindBk(KSUB) OR FindBk(KFUNCTION) THEN ErrNo 57   ' DIM SHARED inside a procedure
    END IF
    IF Tok = KPRESERVE THEN
        pr = 1
        GetTok
    END IF
    WTokI sh
    WTokI pr
    DO
        IF Tok <> TIDENT THEN
            ErrNo 23   ' a variable name expected
            SkipStmt
            EXIT SUB
        END IF
        PutRec
        GetTok
        IF Tok = TLPAR THEN
            GetTok
            ' the bounds counted first: written after their number
            IF Tok = TRPAR THEN
                GetTok
                WTokI 0
            ELSE
                NTb = 0
                TbOn = 1
                TbQuiet = 1
                n = 0
                DO
                    TbK(NTb + 1) = RX
                    NTb = NTb + 1
                    ExprToks
                    NTb = NTb + 1
                    TbK(NTb) = RXE
                    n = n + 1
                    IF Tok <> TCOMMA THEN EXIT DO
                    GetTok
                LOOP
                TbOn = 0
                TbQuiet = 0
                Expect TRPAR
                WTokI n
                DimBounds
            END IF
        ELSE
            WTokI -1
        END IF
        IF Tok = KAS THEN
            PutRec
            GetTok
            PutRec
            GetTok
        END IF
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' the bounds kept (RX ... RXE each): written, RX TYINT
SUB DimBounds ()
    DIM i
    FOR i = 1 TO NTb
        IF TbK(i) = RX THEN
            WB RX
            WB TYINT
        ELSE
            Rk = TbK(i)
            RS$ = TbS$(i)
            RW1 = TbV(i)
            PutRec
            TbS$(i) = ""
        END IF
    NEXT i
    NTb = 0
END SUB

' the rest of the statement as it is (B2DECL and B2NAME read it):
' DECLARE, COMMON, SHARED, STATIC, DEFxxx, a SUB's header ...
SUB SRaw (k)
    Stm k
    DO WHILE NOT AtEnd
        PutRec
        GetTok
    LOOP
END SUB

' a statement that starts with a name: an assignment (RSTMT SASSIGN, RLV
' LVASSIGN v RLVE, RX XLVT e RXE), a SUB called (RSTMT SCALL, RX XCALL
' name args RXE), MID$( ) =, POKE, POKEB, CSP, OSCALL
SUB SIdent ()
    DIM nm$, depth
    nm$ = TokS$
    IF nm$ = "MID$" THEN
        ' MID$(v, a [, b]) = e: RLV LVADDR v, RX TYINT a, RX TYINT b (255),
        ' RX TYSTR e
        GetTok
        Expect TLPAR
        Stm SMIDSET
        SLv LVADDR
        Expect TCOMMA
        SExpr TYINT
        IF Tok = TCOMMA THEN
            GetTok
            SExpr TYINT
        ELSE
            SConst TYINT, 255
        END IF
        Expect TRPAR
        Expect TEQ
        SExpr TYSTR
        EXIT SUB
    END IF
    IF nm$ = "POKE" OR nm$ = "POKEB" THEN
        GetTok
        IF nm$ = "POKE" THEN Stm SPOKE ELSE Stm SPOKEB
        SExpr TYINT
        Expect TCOMMA
        SExpr TYINT
        EXIT SUB
    END IF
    IF nm$ = "CSP" OR nm$ = "OSCALL" THEN
        GetTok
        IF nm$ = "CSP" THEN Stm SCSP ELSE Stm SOSCALL
        SExpr XANY
        DO WHILE Tok = TCOMMA
            GetTok
            SExpr XRAW
        LOOP
        EXIT SUB
    END IF
    ' the name and its ( ... ) kept: = after them makes an assignment
    NTb = 0
    TbOn = 1
    TbQuiet = 1
    CopyTok
    IF Tok = TLPAR THEN
        DO
            IF Tok = TLPAR THEN
                depth = depth + 1
            ELSEIF Tok = TRPAR THEN
                depth = depth - 1
            ELSEIF Tok = TLINE OR Tok = TEOF OR Tok = TCOLON THEN
                EXIT DO
            END IF
            AndOr
            CopyTok
            IF depth = 0 THEN EXIT DO
        LOOP
    END IF
    TbOn = 0
    TbQuiet = 0
    IF Tok = TEQ THEN
        GetTok
        Stm SASSIGN
        WB RLV
        WB LVASSIGN
        TbOut
        WB RLVE
        SExpr XLVT
        EXIT SUB
    END IF
    Stm SCALL
    WB RX
    WB XCALL
    TbOut
    DO WHILE NOT AtEnd
        AndOr
        CopyTok
    LOOP
    WB RXE
END SUB

' EXIT / CONTINUE FOR | DO | WHILE | SELECT: RSTMT KEXIT (KCONTINUE),
' TINT the block's keyword; EXIT SUB / FUNCTION: RSTMT SEXITSUB
SUB SExit (cont)
    DIM k
    GetTok
    k = Tok
    SELECT CASE k
    CASE KFOR, KDO, KWHILE, KSELECT
    CASE KSUB, KFUNCTION
        IF cont THEN ErrNo 44   ' CONTINUE FOR, DO or WHILE expected
        IF FindBk(KSUB) = 0 AND FindBk(KFUNCTION) = 0 THEN ErrRec 45, 0, Tok, ""   ' EXIT {t} outside a procedure
        GetTok
        Stm SEXITSUB
        EXIT SUB
    CASE ELSE
        ErrNo 46   ' FOR, DO, WHILE, SELECT, SUB or FUNCTION expected
        EXIT SUB
    END SELECT
    GetTok
    IF FindBk(k) = 0 THEN
        ErrNo 47   ' not inside such a block
    ELSEIF cont AND k = KSELECT THEN
        ErrNo 48   ' CONTINUE SELECT?
    ELSE
        IF cont THEN Stm KCONTINUE ELSE Stm KEXIT
        WTokI k
    END IF
END SUB

' ON ERROR GOTO 0 / RESUME NEXT: RSTMT SONERR, TINT 0 / 1;  ON e GOTO /
' GOSUB labels: RSTMT KON, RX TYINT e RXE, TINT (GOSUB), RLREF each
SUB SOn ()
    GetTok
    IF Tok = KERROR THEN
        GetTok
        Stm SONERR
        IF Tok = KRESUME THEN
            GetTok
            Expect KNEXT
            WTokI 1
        ELSE
            Expect KGOTO
            IF Tok <> TINT THEN
                ErrNo 50   ' only ON ERROR GOTO 0 and ON ERROR RESUME NEXT
            ELSEIF TokV <> 0 THEN
                ErrNo 50   ' only ON ERROR GOTO 0 and ON ERROR RESUME NEXT
            END IF
            GetTok
            WTokI 0
        END IF
        EXIT SUB
    END IF
    Stm KON
    SExpr TYINT
    IF Tok = KGOSUB THEN
        WTokI 1
    ELSEIF Tok = KGOTO THEN
        WTokI 0
    ELSE
        ErrNo 51   ' GOTO or GOSUB expected
        SkipStmt
        EXIT SUB
    END IF
    GetTok
    DO
        SLabel
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' SUB / FUNCTION's header: RSTMT KSUB (KFUNCTION), TINT private, its tokens
SUB SProcHead (priv)
    DIM k
    k = Tok
    IF FindBk(KSUB) OR FindBk(KFUNCTION) THEN
        ErrNo 78   ' a SUB or FUNCTION inside a procedure (END SUB missing?)
        DO WHILE NBk > 0
            BkMissing BkKind(NBk)
            NBk = NBk - 1
        LOOP
    ELSEIF NBk > 0 THEN
        DO WHILE NBk > 0
            BkMissing BkKind(NBk)
            NBk = NBk - 1
        LOOP
    END IF
    GetTok
    Stm k
    WTokI priv
    InFn = k = KFUNCTION
    FnName$ = ""
    IF Tok = TIDENT THEN FnName$ = TokS$
    DO WHILE NOT AtEnd
        PutRec
        GetTok
    LOOP
    PushBk k
    NFor = 0
END SUB

' END ...: END IF / SELECT / SUB / FUNCTION, or END [n]
SUB SEnd ()
    DIM k, p
    GetTok
    SELECT CASE Tok
    CASE KIF
        GetTok
        IF PopBk(KIF, KEND) THEN Stm SENDIF
    CASE KSELECT
        GetTok
        IF PopBk(KSELECT, KEND) THEN Stm SENDSEL
    CASE KSUB, KFUNCTION
        ' (the procedure open is ended, whatever its kind)
        k = Tok
        GetTok
        p = FindBk(KSUB)
        IF FindBk(KFUNCTION) > p THEN p = FindBk(KFUNCTION)
        IF p = 0 THEN
            ErrRec 82, 0, KEND, ""   ' {t} without its block
        ELSE
            DO WHILE NBk > p
                BkMissing BkKind(NBk)
                NBk = NBk - 1
            LOOP
            IF BkKind(p) <> k THEN BkMissing BkKind(p)
            IF BkKind(p) = KSUB THEN Stm SENDSUB ELSE Stm SENDFN
            NBk = p - 1
        END IF
        InFn = 0
    CASE ELSE
        Stm KEND
        IF AtEnd THEN SConst TYINT, 0 ELSE SExpr TYINT
    END SELECT
END SUB

' one statement (Tok its first token)
SUB SStmt ()
    DIM k
    k = Tok
    SELECT CASE k
    CASE TIDENT
        SIdent
    CASE KLET
        GetTok
        IF Tok = TIDENT THEN SIdent ELSE ErrNo 28   ' a variable expected
    CASE KPRINT
        SPrint
    CASE KINPUT
        SInput KINPUT
    CASE KLINE
        GetTok
        IF Tok <> KINPUT THEN ErrNo 71   ' LINE INPUT expected
        SInput SLINPUT
    CASE KIF
        SIf
    CASE KELSEIF
        GetTok
        IF FindBk(KIF) = 0 OR BkKind(NBk) <> KIF THEN ErrRec 82, 0, KELSEIF, ""   ' {t} without its block
        Stm KELSEIF
        SExpr XCOND
        Expect KTHEN
    CASE KELSE
        GetTok
        IF FindBk(KIF) = 0 OR BkKind(NBk) <> KIF THEN ErrRec 82, 0, KELSE, ""   ' {t} without its block
        Stm KELSE
        EXIT SUB
    CASE KFOR
        SFor
    CASE KNEXT
        GetTok
        SNextStmt
    CASE KDO
        GetTok
        Stm KDO
        SDoCond
        PushBk KDO
    CASE KLOOP
        GetTok
        IF PopBk(KDO, KLOOP) THEN
            Stm KLOOP
            SDoCond
        ELSE
            SkipStmt
        END IF
    CASE KWHILE
        GetTok
        Stm KWHILE
        SExpr XCOND
        PushBk KWHILE
    CASE KWEND
        GetTok
        IF PopBk(KWHILE, KWEND) THEN Stm KWEND
    CASE KSELECT
        SSelect
    CASE KCASE
        GetTok
        SCase
    CASE KEND
        SEnd
    CASE KGOTO, KGOSUB
        GetTok
        Stm k
        SLabel
    CASE KRETURN
        GetTok
        IF AtEnd THEN
            Stm KRETURN
        ELSEIF InFn = 0 THEN
            ErrNo 49   ' RETURN with a value outside a FUNCTION
            SkipStmt
        ELSE
            ' RETURN e: the function's name = e, EXIT FUNCTION
            Stm SASSIGN
            WB RLV
            WB LVASSIGN
            WB TIDENT
            WS FnName$
            WB RLVE
            SExpr XLVT
            Stm SEXITSUB
        END IF
    CASE KON
        SOn
    CASE KEXIT
        SExit 0
    CASE KCONTINUE
        SExit 1
    CASE KSTOP
        GetTok
        Stm KEND
        SConst TYINT, 0
    CASE KSYSTEM
        GetTok
        Stm KEND
        IF AtEnd THEN SConst TYINT, 0 ELSE SExpr TYINT
    CASE KDIM, KREDIM
        SDim k
    CASE KSHARED
        IF FindBk(KSUB) = 0 AND FindBk(KFUNCTION) = 0 THEN ErrNo 72   ' SHARED outside a procedure
        GetTok
        SRaw KSHARED
    CASE KSTATIC, KERASE, KDEFINT, KDEFSNG, KDEFDBL, KDEFSTR, KDECLARE, KCOMMON, KSEGMENT, KOPTION
        GetTok
        SRaw k
    CASE KDATA
        GetTok
        SRaw KDATA
    CASE TSKIP
        SkipStmt
    CASE KCALL
        GetTok
        IF Tok <> TIDENT THEN
            ErrNo 75   ' a SUB name expected
            SkipStmt
        ELSE
            Stm SCALL
            WB RX
            WB XCALL
            DO WHILE NOT AtEnd
                AndOr
                CopyTok
            LOOP
            WB RXE
        END IF
    CASE KOPEN
        SOpen
    CASE KCLOSE
        SClose
    CASE KGET, KPUT
        SGetPut k
    CASE KSEEK
        GetTok
        Stm KSEEK
        IF Tok = THASH THEN GetTok
        SExpr TYINT
        Expect TCOMMA
        SExpr TYSNG
    CASE KKILL, KCHAIN
        GetTok
        Stm k
        SExpr TYSTR
    CASE KSWAP
        GetTok
        Stm KSWAP
        SLv LVADDR
        Expect TCOMMA
        SLv LVADDR
    CASE KRANDOMIZE
        GetTok
        Stm KRANDOMIZE
        IF AtEnd THEN SConst TYDBL, 0 ELSE SExpr TYDBL
    CASE KCLS
        GetTok
        Stm KCLS
    CASE KLOCATE
        GetTok
        Stm KLOCATE
        IF Tok = TCOMMA THEN SConst TYINT, 0 ELSE SExpr TYINT
        IF Tok = TCOMMA THEN
            GetTok
            SExpr TYINT
        ELSE
            SConst TYINT, 0
        END IF
    CASE KREAD
        GetTok
        Stm KREAD
        DO
            SLv LVPS
            IF Tok <> TCOMMA THEN EXIT DO
            GetTok
        LOOP
    CASE KRESTORE
        GetTok
        Stm KRESTORE
        IF NOT AtEnd THEN SLabel
    CASE KWRITE
        SWrite
    CASE ELSE
        ErrRec 77, 0, Tok, ""   ' a statement expected, not {t}
        SkipStmt
        EXIT SUB
    END SELECT
    StmtEnd
END SUB

' ---- the pass

SUB SynPass ()
    DIM priv
    GetTok
    DO
        SELECT CASE Tok
        CASE TEOF
            EXIT DO
        CASE TLINE, TLABEL
            PutRec
            GetTok
        CASE TCOLON
            GetTok
        CASE KPRIVATE
            GetTok
            IF Tok = KSUB OR Tok = KFUNCTION THEN
                SProcHead 1
            ELSE
                SStmt
            END IF
        CASE KSUB, KFUNCTION
            SProcHead 0
        CASE ELSE
            SStmt
        END SELECT
    LOOP
    DO WHILE NBk > 0
        BkMissing BkKind(NBk)
        NBk = NBk - 1
    LOOP
END SUB

' ---- B2SYN, the program: pass 2 of the job's compile step, then B2DECL

ReadJob
StepNames
ErrCount = 0
InOpen PassFile$(1)
TbCap = Capped(InHead(THSTMT) + 8, 2000)
REDIM TbK(TbCap) AS BYTE, TbS$(TbCap), TbV(TbCap)
OutOpen PassFile$(2)
MemNote "tables"
SynPass
CLOSE #CHIN
OutClose 2
IF ErrCount > 0 THEN CompileFailed
IF OptKeep = 0 THEN KILL PassFile$(1)
ChainTo "B2DECL", ""
