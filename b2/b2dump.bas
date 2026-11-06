' B2DUMP -- one of B2's intermediate files as text (on the P-System: as
' tools/b2dump.py shows it on the host)
'
'   B2DUMP NAME.W5         writes NAME.D5 (beside it): each BASIC line as a
'                          comment, then what the passes so far made of it
'
' (B2 -K keeps the files: NAME.W0 B2LEX's tokens ... NAME.W7 B2STMT's, in
' BASIC2:/MAP when there is one: NAME.W5 without a volume is looked for
' there too.)  Its first lines: the file, the pass, the source's path.
' Each statement on a line of its own, the expressions in { }, the targets
' in < >, the code bytes in hex, labels as Ln:, jumps as UJP Ln, FJP Ln ...
#INCLUDE "B2COM"
#INCLUDE "B2REC"
#INCLUDE "B2OPS"

DIM SHARED Ln$, Ind

' the line being made, written (when it has something)
SUB DFlush ()
    IF Ln$ <> "" THEN PRINT #CHLST, SPACE$(Ind * 4); Ln$
    Ln$ = ""
END SUB

SUB DAdd (s$)
    IF LEN(Ln$) + LEN(s$) > 200 THEN DFlush
    IF Ln$ <> "" THEN Ln$ = Ln$ + " "
    Ln$ = Ln$ + s$
END SUB

FUNCTION TyName$ (t)
    SELECT CASE t
    CASE TYINT: TyName$ = "INT"
    CASE TYSNG: TyName$ = "SNG"
    CASE TYDBL: TyName$ = "DBL"
    CASE TYSTR: TyName$ = "STR"
    CASE TYBYTE: TyName$ = "BYTE"
    CASE ELSE: TyName$ = "void"
    END SELECT
END FUNCTION

FUNCTION Hex2$ (b)
    Hex2$ = RIGHT$("0" + HEX$(b), 2)
END FUNCTION

' the name of an opcode a jump has
FUNCTION JumpName$ (op)
    SELECT CASE op
    CASE OUJP: JumpName$ = "UJP"
    CASE OFJP: JumpName$ = "FJP"
    CASE OEFJ: JumpName$ = "EFJ"
    CASE ONFJ: JumpName$ = "NFJ"
    CASE ELSE: JumpName$ = Hex2$(op)
    END SELECT
END FUNCTION

FUNCTION LabName$ (l)
    IF l = LFALSE THEN LabName$ = "Lfalse" ELSE LabName$ = "L" + IStr$(l)
END FUNCTION

FUNCTION StmtName$ (k)
    SELECT CASE k
    CASE SASSIGN: StmtName$ = "ASSIGN"
    CASE SCALL: StmtName$ = "CALL"
    CASE SMIDSET: StmtName$ = "MID$="
    CASE SPOKE: StmtName$ = "POKE"
    CASE SPOKEB: StmtName$ = "POKEB"
    CASE SCSP: StmtName$ = "CSP"
    CASE SOSCALL: StmtName$ = "OSCALL"
    CASE SENDIF: StmtName$ = "END IF"
    CASE SENDSEL: StmtName$ = "END SELECT"
    CASE SENDSUB: StmtName$ = "END SUB"
    CASE SENDFN: StmtName$ = "END FUNCTION"
    CASE SLINPUT: StmtName$ = "LINE INPUT"
    CASE SDATAL: StmtName$ = "DATA list"
    CASE SONERR: StmtName$ = "ON ERROR"
    CASE SEXITSUB: StmtName$ = "EXIT SUB"
    CASE SCASEELSE: StmtName$ = "CASE ELSE"
    CASE ELSE: StmtName$ = KwName$(k)
    END SELECT
END FUNCTION

FUNCTION ModeName$ (m)
    SELECT CASE m
    CASE XANY: ModeName$ = "any"
    CASE XCOND: ModeName$ = "cond"
    CASE XNCOND: ModeName$ = "notcond"
    CASE XLVT: ModeName$ = "as-target"
    CASE XCALL: ModeName$ = "call"
    CASE XSEL: ModeName$ = "select"
    CASE XCHAN: ModeName$ = "channel"
    CASE XPUT: ModeName$ = "put"
    CASE XRAW: ModeName$ = "raw"
    CASE ELSE: ModeName$ = TyName$(m)
    END SELECT
END FUNCTION

FUNCTION ClsName$ (c)
    SELECT CASE c
    CASE SCLOCAL: ClsName$ = "local"
    CASE SCSTATIC: ClsName$ = "static"
    CASE SCCOMMON: ClsName$ = "common"
    CASE SCPARAM: ClsName$ = "param"
    CASE SCREF: ClsName$ = "byref"
    CASE ELSE: ClsName$ = "?"
    END SELECT
END FUNCTION

SUB DumpPass ()
    DIM i, t$
    DO
        NextRec
        SELECT CASE Rk
        CASE TEOF
            DFlush
            PRINT #CHLST, "; end"
            EXIT DO
        CASE TLINE
            DFlush
            PRINT #CHLST, "'"; RIGHT$("     " + IStr$(RW1), 5); "  "; RS$
        CASE TFILE
            DFlush
            PRINT #CHLST, "; file "; RS$
        CASE TIDENT
            DAdd RS$
        CASE TINT
            DAdd IStr$(RW1)
        CASE TSNG, TDBL
            DAdd RS$
        CASE TSTR
            DAdd CHR$(34) + RS$ + CHR$(34)
        CASE TLABEL
            DAdd "label:" + RS$
        CASE TSKIP
            DAdd "(skipped)"
        CASE RSTMT
            DFlush
            DAdd "[" + StmtName$(RB1) + "]"
        CASE RX
            DAdd "{" + ModeName$(RB1) + ":"
        CASE RXE, RXCE
            DAdd "}"
        CASE RLV
            DAdd "<target:"
        CASE RLVE, RLVCE
            DAdd ">"
        CASE RMARK
            SELECT CASE RB1
            CASE MTAB: DAdd "TAB"
            CASE MSPC: DAdd "SPC"
            CASE MCHAN: DAdd "#"
            CASE MMORE: DAdd "(more)"
            CASE ELSE: DAdd "(last)"
            END SELECT
        CASE RSEL
            DAdd "SEL"
        CASE RLREF
            DAdd "to:" + RS$
        CASE RVAR
            t$ = RS$ + "[" + TyName$(RB2) + " " + ClsName$(RB3) + " " + IStr$(RW1)
            IF RB1 = SKARRAY THEN t$ = t$ + " array"
            DAdd t$ + "]"
        CASE RPROC
            DAdd RS2$ + "=call " + RS$
        CASE RBUILT
            DAdd RS$
        CASE RLAB
            DAdd LabName$(RW1)
        CASE RXC
            DAdd "{code " + TyName$(RB1) + ":"
        CASE RLVC
            DAdd "<target " + TyName$(RB1) + ":"
        CASE RLVL
            DAdd "| load:"
        CASE RLVS
            DAdd "| store:"
        CASE CBYTES
            t$ = ""
            FOR i = 0 TO RB1 - 1
                IF i > 0 THEN t$ = t$ + " "
                t$ = t$ + Hex2$(InBuf(i))
            NEXT i
            DAdd t$
        CASE CJUMP
            DAdd JumpName$(RB1) + " " + LabName$(RW1)
        CASE CCASE
            DAdd "case " + LabName$(RW1)
        CASE CLABEL
            DFlush
            Ind = Ind - 1
            Ln$ = LabName$(RW1) + ":"
            DFlush
            Ind = Ind + 1
        CASE CALIAS
            DAdd LabName$(RW1) + "=" + LabName$(RW2)
        CASE CREL
            IF RB1 = RCALL THEN DAdd "(call " + RS$ + ")" ELSE IF RB1 = RGSTAT THEN DAdd "(static)" ELSE DAdd "(" + RS$ + ")"
        CASE CALIGN
            DAdd "align"
        CASE CTEMP
            DAdd "(temporaries back)"
        CASE CGOSUB
            DAdd "(gosub return " + LabName$(RW1) + ")"
        CASE CFREE
            DAdd "(free " + IStr$(RW1) + ")"
        CASE CBEGIN
            DFlush
            PRINT #CHLST, "PROC "; CbName$; "  frame "; IStr$(CbLocal); ", labels "; IStr$(CbLab)
            Ind = 1
        CASE CEND
            DFlush
            Ind = 0
            PRINT #CHLST, "END PROC"
        CASE COBJB, COBJW, COBJS
        CASE ELSE
            IF Rk < 100 THEN DAdd KwName$(Rk) ELSE IF Rk < 128 THEN DAdd KwName$(Rk) ELSE DAdd "?" + IStr$(Rk)
        END SELECT
    LOOP
END SUB

' ---- B2DUMP, the program

DIM f$, o$, p
f$ = UCASE$(LTRIM$(RTRIM$(COMMAND$)))
IF f$ = "" THEN
    PRINT "Dump what file (NAME.Wn)? ";
    LINE INPUT f$
    f$ = UCASE$(LTRIM$(RTRIM$(f$)))
END IF
' (-K's files are in BASIC2:/MAP when it is there)
IF NOT FileExists(f$) AND INSTR(f$, ":") = 0 THEN
    IF FileExists("BASIC2:/MAP/" + f$) THEN f$ = "BASIC2:/MAP/" + f$
END IF
IF NOT FileExists(f$) THEN
    PRINT "B2DUMP: no file "; f$
    SYSTEM 1
END IF
' NAME.Wn -> NAME.Dn
p = INSTR(f$, ".W")
IF p > 0 THEN o$ = LEFT$(f$, p) + "D" + MID$(f$, p + 2) ELSE o$ = f$ + ".D"
InOpen f$
OPEN o$ FOR OUTPUT AS #CHLST
PRINT #CHLST, "; "; f$; " (pass "; IStr$(InHead(WHPASS)); ")"
PRINT #CHLST, "; the source: "; HeadPath$
DumpPass
CLOSE #CHLST
CLOSE #CHIN
PRINT "  "; o$
