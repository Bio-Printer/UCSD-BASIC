' BCDECL -- pass 2: the declarations of a module
'
' Reads the token file once and enters in the symbol table what every
' procedure may use before its text is compiled: the SUBs and FUNCTIONs
' (defined here or DECLAREd: their parameters and types, their segment),
' the shared variables (DIM SHARED, COMMON SHARED) and OPTION EXPLICIT.
' DEFINT/DEFSNG/DEFDBL/DEFSTR are followed in order, so a parameter gets
' the type its letter has where the procedure is.
#INCLUDE "BCCOM"

' ---- in the main segment: used by pass 3 too

' DEFINT A-C, X ... (the token after the keyword is current)
SUB DefLetters (ty)
    DIM a, b
    DO
        IF Tok <> TIDENT THEN
            ErrMsg "a letter expected"
            EXIT SUB
        END IF
        a = ASC(TokS$, 1) - 65
        b = a
        GetTok
        IF Tok = TMINUS THEN
            GetTok
            IF Tok = TIDENT THEN b = ASC(TokS$, 1) - 65
            GetTok
        END IF
        IF a >= 0 AND b <= 25 AND a <= b THEN
            FOR a = a TO b
                DefType(a) = ty
            NEXT a
        END IF
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

FUNCTION DefKw (k)
    SELECT CASE k
    CASE KDEFINT: DefKw = TYINT
    CASE KDEFSNG: DefKw = TYSNG
    CASE KDEFDBL: DefKw = TYDBL
    CASE KDEFSTR: DefKw = TYSTR
    END SELECT
END FUNCTION

SUB ResetDefs ()
    DIM i
    FOR i = 0 TO 25
        DefType(i) = TYSNG
    NEXT i
END SUB

' a declared name and its type: "N" with SFAS for AS type (and for a name
' with no suffix), else N with its suffix.  Returns the type; the name is
' left in DeclName$, the flags in DeclFlags.
FUNCTION DeclType (n$, isproc)
    DIM ty
    DeclName$ = n$
    DeclFlags = 0
    ty = NameType(n$)
    IF Tok = KAS THEN
        GetTok
        IF SuffixType(n$) THEN ErrMsg "a name with a type suffix declared AS a type"
        ty = ParseType
        DeclFlags = SFAS
    ELSEIF SuffixType(n$) = 0 THEN
        IF isproc THEN
            DeclFlags = SFAS
        ELSE
            DeclName$ = n$ + TypeChar$(ty)
        END IF
    END IF
    DeclType = ty
END FUNCTION

' the parameter list of a SUB or FUNCTION (the "(" is current or absent):
' the types go into PType/PFlg from NPar + 1, the names into ParName$.
' Returns the number of parameters.
FUNCTION ParseParams ()
    DIM n, fl, ty, nm$
    IF Tok <> TLPAR THEN EXIT FUNCTION
    GetTok
    IF Tok = TRPAR THEN
        GetTok
        EXIT FUNCTION
    END IF
    DO
        fl = 0
        IF Tok = KBYREF THEN
            fl = PFBYREF
            GetTok
        ELSEIF Tok = KBYVAL THEN
            GetTok
        END IF
        IF Tok <> TIDENT THEN
            ErrMsg "a parameter name expected"
            EXIT DO
        END IF
        nm$ = TokS$
        GetTok
        IF Tok = TLPAR THEN
            GetTok
            Expect TRPAR, ")"
            fl = PFARRAY
        END IF
        ty = DeclType(nm$, 0)
        n = n + 1
        IF NPar + n > MAXPAR THEN Fatal "too many parameters"
        PType(NPar + n) = ty
        PFlg(NPar + n) = fl
        IF n <= 30 THEN
            ParName$(n) = DeclName$
            ParFlags(n) = DeclFlags
        END IF
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
    Expect TRPAR, ")"
    IF n > 30 THEN ErrMsg "more than 30 parameters"
    ParseParams = n
END FUNCTION

' SUB/FUNCTION NAME (params) [AS type] [STATIC]: the procedure's symbol
' (made, or the DECLAREd one checked).  The keyword is current.
FUNCTION ProcHeader (defining, priv)
    DIM isfunc, nm$, ty, fl, np, s, i, j, same
    isfunc = Tok = KFUNCTION
    GetTok
    IF Tok <> TIDENT THEN
        ErrMsg "a procedure name expected"
        SkipStmt
        EXIT FUNCTION
    END IF
    nm$ = TokS$
    GetTok
    np = ParseParams
    IF isfunc THEN
        ty = DeclType(nm$, 1)
        nm$ = DeclName$
        fl = DeclFlags
    ELSE
        ty = TYVOID
        IF SuffixType(nm$) THEN ErrMsg "a SUB name with a type suffix"
    END IF
    IF Tok = KSTATIC THEN GetTok
    s = FindProc(nm$)
    IF s > 0 THEN
        ' declared before: the same parameters?
        same = SAux2(s) = np AND SType(s) = ty
        IF same THEN
            FOR i = 1 TO np
                j = SAux(s) + i - 1
                IF PType(j) <> PType(NPar + i) OR PFlg(j) <> PFlg(NPar + i) THEN same = 0
            NEXT i
        END IF
        IF NOT same THEN ErrMsg nm$ + ": not as declared before"
        IF defining THEN
            IF SFlags(s) AND SFDEFINED THEN ErrMsg nm$ + " defined twice"
            SFlags(s) = SFlags(s) OR SFDEFINED
            SSeg(s) = CurSeg
        END IF
    ELSE
        IF FindSym(nm$) > 0 THEN ErrMsg nm$ + " is already the name of something else"
        IF isfunc THEN s = AddSym(nm$, SKFUNC, ty) ELSE s = AddSym(nm$, SKSUB, ty)
        SFlags(s) = fl
        SAux(s) = NPar + 1
        SAux2(s) = np
        NPar = NPar + np
        SSeg(s) = CurSeg
        IF defining THEN SFlags(s) = SFlags(s) OR SFDEFINED
    END IF
    IF priv THEN SFlags(s) = SFlags(s) OR SFPRIVATE
    ProcHeader = s
END FUNCTION

' the number of dimensions in a DIM's ( ... ): its commas at depth 1
' (the bounds are skipped: pass 3 compiles them).  "(" is current.
FUNCTION CountDims ()
    DIM depth, n
    GetTok
    IF Tok = TRPAR THEN
        GetTok
        EXIT FUNCTION
    END IF
    n = 1
    depth = 0
    DO
        IF Tok = TLPAR THEN
            depth = depth + 1
        ELSEIF Tok = TRPAR THEN
            IF depth = 0 THEN EXIT DO
            depth = depth - 1
        ELSEIF Tok = TCOMMA AND depth = 0 THEN
            n = n + 1
        ELSEIF Tok = TLINE OR Tok = TEOF OR Tok = TCOLON THEN
            ErrMsg ") expected"
            CountDims = n
            EXIT FUNCTION
        END IF
        GetTok
    LOOP
    GetTok
    CountDims = n
END FUNCTION

' the words a variable of type ty takes (an array: its slot, 1 word)
FUNCTION TypeWords (ty)
    SELECT CASE ty
    CASE TYSNG: TypeWords = 2
    CASE TYDBL: TypeWords = 4
    CASE TYVOID: TypeWords = 0
    CASE ELSE: TypeWords = 1
    END SELECT
END FUNCTION

' ---- pass 2 itself
SEGMENT DECL

' DIM SHARED / COMMON SHARED: the variables (the keyword after SHARED is current)
SUB DeclShared (iscommon)
    DIM nm$, nd, ty, s, kind
    DO
        IF Tok <> TIDENT THEN
            ErrMsg "a variable name expected"
            SkipStmt
            EXIT SUB
        END IF
        nm$ = TokS$
        GetTok
        nd = 0
        kind = SKVAR
        IF Tok = TLPAR THEN
            kind = SKARRAY
            nd = CountDims
            IF iscommon THEN nd = 0
        END IF
        ty = DeclType(nm$, 0)
        nm$ = DeclName$
        s = FindSym(nm$)
        IF s > 0 THEN
            ErrMsg nm$ + " declared twice"
        ELSE
            s = AddSym(nm$, kind, ty)
            SFlags(s) = DeclFlags OR SFSHARED
            SAux(s) = nd
            IF iscommon THEN
                SCls(s) = SCCOMMON
            ELSE
                SCls(s) = SCSTATIC
                SOff(s) = StaticWords
                IF kind = SKARRAY THEN
                    StaticWords = StaticWords + 1
                ELSE
                    StaticWords = StaticWords + TypeWords(ty)
                END IF
            END IF
        END IF
        IF Tok <> TCOMMA THEN EXIT DO
        GetTok
    LOOP
END SUB

' skip a procedure's body: to its END SUB / END FUNCTION
SUB SkipBody ()
    DO
        SkipStmt
        IF Tok = TEOF THEN EXIT SUB
        GetTok
        DO WHILE Tok = TLABEL
            GetTok
        LOOP
        IF Tok = KEND THEN
            GetTok
            IF Tok = KSUB OR Tok = KFUNCTION THEN
                GetTok
                EXIT SUB
            END IF
        END IF
    LOOP
END SUB

SUB DeclPass ()
    DIM s, k, priv
    ResetDefs
    OptExplicit = 0
    CurSeg = 1
    OpenTok
    DO WHILE Tok <> TEOF
        priv = 0
        k = Tok
        IF k = KPRIVATE THEN
            GetTok
            k = Tok
            priv = 1
        END IF
        SELECT CASE k
        CASE TLINE, TCOLON, TLABEL
            GetTok
            CONTINUE DO
        CASE KDEFINT, KDEFSNG, KDEFDBL, KDEFSTR
            GetTok
            DefLetters DefKw(k)
        CASE KOPTION
            GetTok
            IF Tok = KEXPLICIT THEN
                OptExplicit = 1
                GetTok
            END IF
        CASE KSEGMENT
            GetTok
            IF Tok = TIDENT THEN
                CurSeg = SegIndex(TokS$)
                GetTok
            ELSE
                CurSeg = 1
            END IF
        CASE KDECLARE
            GetTok
            IF Tok = KSUB OR Tok = KFUNCTION THEN
                s = ProcHeader(0, priv)
            ELSE
                ErrMsg "SUB or FUNCTION expected"
            END IF
        CASE KSUB, KFUNCTION
            s = ProcHeader(1, priv)
            SkipBody
        CASE KDIM
            GetTok
            IF Tok = KSHARED THEN
                GetTok
                DeclShared 0
            END IF
        CASE KCOMMON
            GetTok
            IF Tok = KSHARED THEN GetTok
            DeclShared 1
        END SELECT
        IF Tok <> TLINE AND Tok <> TEOF THEN SkipStmt
    LOOP
    CLOSE #CHTOK
    NModSym = NSym
END SUB
