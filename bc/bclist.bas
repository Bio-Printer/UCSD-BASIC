' BCLIST -- the listing: each BASIC statement and the P-code made for it
'
' Pass 3 writes, for each statement of a procedure, where its code starts
' and its line (the temporary file LTmpName$), and when the procedure is
' finished (its jumps resolved, its entry code in front) its code and
' relocations (LCodName$: ListSave).  After pass 3, ListModule reads them
' back and writes each procedure's statements with the code between them
' disassembled: offsets within the procedure, calls and global variables
' by name (the linker fills in the numbers).  (After, not during, pass 3:
' the GEN segment and this one do not fit into the code space together.)
#INCLUDE "BCCOM"
#INCLUDE "BCGENCOM"

' opcodes 128..215: a name (4) and an operand format (1), then a blank
FUNCTION OpTable$ (part)
    DIM tb$
    SELECT CASE part
    CASE 0
        tb$ = "ABI   ABR   ADI   ADR   LAND  DIF   DVI   DVR   CHK   FLO   FLT   INN   "
        tb$ = tb$ + "INT   LOR   MODI  MPI   MPR   NGI   NGR   NOT   SRS   SBI   SBR   SGS   "
        tb$ = tb$ + "SQI   SQR   STO   IXS   UNI   S2P   CSP U LDCN  ADJ U FJP S INC B IND B "
        tb$ = tb$ + "IXA B LAO B LSA A LAE E MOV B LDO B "
    CASE 1
        tb$ = "SAS U SRO B XJP X RNP U CIP U EQU T GEQ T GRT T LDA D LDC C LEQ T LES T "
        tb$ = tb$ + "LOD D NEQ T STR D UJP S LDP   STP   LDM U STM U LDB   STB   IXP P RBP U "
        tb$ = tb$ + "CBP U EQUI  GEQI  GRTI  LLA B LDCIW LEQI  LESI  LDL B NEQI  STL B CXP 2 "
        tb$ = tb$ + "CLP U CGP U LPA A STE E NOP   EFJ S "
    CASE ELSE
        tb$ = "NFJ S BPT B XIT   NOP   "
    END SELECT
    OpTable$ = tb$
END FUNCTION

FUNCTION Hex4$ (v)
    Hex4$ = RIGHT$("000" + HEX$(v), 4)
END FUNCTION

FUNCTION CodeWord (a)
    CodeWord = Code(a) OR (Code(a + 1) * 256)
END FUNCTION

' the name a relocation at a gives (or "")
FUNCTION RelAt$ (a)
    DIM i
    FOR i = 0 TO NRel - 1
        IF (RelPos(i) = a AND RelType(i) = RCALL) OR (RelPos(i) = a + 1 AND RelType(i) <> RCALL) THEN
            IF RelType(i) = RGSTAT THEN
                RelAt$ = "(static)"
            ELSE
                RelAt$ = RelName$(i)
            END IF
            EXIT FUNCTION
        END IF
    NEXT i
END FUNCTION

FUNCTION CspName$ (n)
    SELECT CASE n
    CASE 1: CspName$ = "NEW"
    CASE 2: CspName$ = "MOVELEFT"
    CASE 3: CspName$ = "MOVERIGHT"
    CASE 4: CspName$ = "EXIT"
    CASE 5: CspName$ = "UNITREAD"
    CASE 6: CspName$ = "UNITWRITE"
    CASE 9: CspName$ = "TIME"
    CASE 10: CspName$ = "FILLCHAR"
    CASE 11: CspName$ = "SCAN"
    CASE 23: CspName$ = "TRUNC"
    CASE 24: CspName$ = "ROUND"
    CASE 25: CspName$ = "SIN"
    CASE 26: CspName$ = "COS"
    CASE 27: CspName$ = "LOG"
    CASE 28: CspName$ = "ATAN"
    CASE 29: CspName$ = "LN"
    CASE 30: CspName$ = "EXP"
    CASE 31: CspName$ = "SQRT"
    CASE 32: CspName$ = "MARK"
    CASE 33: CspName$ = "RELEASE"
    CASE 34: CspName$ = "IORESULT"
    CASE 40: CspName$ = "MEMAVAIL"
    CASE 100: CspName$ = "DADD"
    CASE 101: CspName$ = "DSUB"
    CASE 102: CspName$ = "DMUL"
    CASE 103: CspName$ = "DDIV"
    CASE 104: CspName$ = "DNEG"
    CASE 105: CspName$ = "DCMP"
    CASE 106: CspName$ = "FTOD"
    CASE 107: CspName$ = "DTOF"
    CASE 108: CspName$ = "ITOD"
    CASE 109: CspName$ = "DTOI"
    CASE 123: CspName$ = "DPOW"
    CASE 124: CspName$ = "DFLOOR"
    CASE 126: CspName$ = "DFABS"
    CASE 133: CspName$ = "DTOA"
    CASE 134: CspName$ = "ATOD"
    END SELECT
END FUNCTION

' one instruction at a: its text; a moves past it
FUNCTION Disasm$ (BYREF a, jtab)
    DIM op, t$, f$, nm$, v, n, i, lo, hi, s$, r$
    op = Code(a)
    a = a + 1
    IF op < 128 THEN
        Disasm$ = "SLDC " + IStr$(op)
        EXIT FUNCTION
    END IF
    IF op >= &HD8 AND op <= &HE7 THEN
        Disasm$ = "SLDL " + IStr$(op - &HD7)
        EXIT FUNCTION
    END IF
    IF op >= &HE8 AND op <= &HF7 THEN
        Disasm$ = "SLDO " + IStr$(op - &HE7)
        EXIT FUNCTION
    END IF
    IF op >= &HF8 THEN
        Disasm$ = "SIND " + IStr$(op - &HF8)
        EXIT FUNCTION
    END IF
    i = op - 128
    t$ = OpTable$(i \ 42)
    t$ = MID$(t$, (i MOD 42) * 6 + 1, 6)
    nm$ = RTRIM$(LEFT$(t$, 4))
    f$ = MID$(t$, 5, 1)
    r$ = RelAt$(a - 1)
    SELECT CASE f$
    CASE "U"
        s$ = IStr$(Code(a))
        IF op = OCSP THEN
            IF CspName$(Code(a)) <> "" THEN s$ = s$ + " (" + CspName$(Code(a)) + ")"
        END IF
        a = a + 1
    CASE "B"
        v = Code(a)
        a = a + 1
        IF v > 127 THEN
            v = (v AND 127) * 256 + Code(a)
            a = a + 1
        END IF
        s$ = IStr$(v)
    CASE "D", "E"
        s$ = IStr$(Code(a)) + ","
        a = a + 1
        v = Code(a)
        a = a + 1
        IF v > 127 THEN
            v = (v AND 127) * 256 + Code(a)
            a = a + 1
        END IF
        s$ = s$ + IStr$(v)
    CASE "2"
        s$ = IStr$(Code(a)) + "," + IStr$(Code(a + 1))
        a = a + 2
    CASE "W"
        s$ = IStr$(CodeWord(a))
        a = a + 2
    CASE "S"
        v = Code(a)
        a = a + 1
        IF v < 128 THEN
            s$ = "->" + Hex4$(a + v)
        ELSE
            v = jtab + v - 256
            s$ = "->" + Hex4$(v - CodeWord(v))
        END IF
    CASE "T"
        v = Code(a)
        a = a + 1
        SELECT CASE v
        CASE 2: s$ = "REAL"
        CASE 4: s$ = "STR"
        CASE 6: s$ = "BOOL"
        CASE ELSE: s$ = IStr$(v)
        END SELECT
    CASE "A"
        n = Code(a)
        a = a + 1
        s$ = CHR$(34)
        FOR i = 0 TO n - 1
            v = Code(a + i)
            IF v >= 32 AND v < 127 THEN s$ = s$ + CHR$(v) ELSE s$ = s$ + "?"
        NEXT i
        s$ = s$ + CHR$(34)
        a = a + n
    CASE "C"
        n = Code(a)
        a = a + 1
        IF a AND 1 THEN a = a + 1
        s$ = IStr$(n) + ":"
        FOR i = 1 TO n
            s$ = s$ + " " + Hex4$(CodeWord(a))
            a = a + 2
        NEXT i
    CASE "X"
        IF a AND 1 THEN a = a + 1
        lo = CodeWord(a)
        hi = CodeWord(a + 2)
        a = a + 4
        s$ = IStr$(lo) + ".." + IStr$(hi) + " else:"
        ' the else jump is a UJP that follows; then the table
        s$ = s$ + " " + Disasm$(a, jtab) + " ["
        FOR i = 0 TO hi - lo
            IF i > 0 THEN s$ = s$ + " "
            s$ = s$ + Hex4$(a - CodeWord(a))
            a = a + 2
        NEXT i
        s$ = s$ + "]"
    CASE "P"
        s$ = IStr$(Code(a)) + "," + IStr$(Code(a + 1))
        a = a + 2
    END SELECT
    IF r$ <> "" THEN s$ = s$ + "  " + r$
    Disasm$ = nm$ + " " + s$
END FUNCTION

SUB ListCode (a0, a1, jtab)
    DIM a, b, t$
    a = a0
    DO WHILE a < a1
        b = a
        t$ = Disasm$(a, jtab)
        PRINT #CHLST, "        "; Hex4$(b); "  "; t$
    LOOP
END SUB

' a procedure: its statements and their code (delta: the entry code's
' bytes, put in front after the statements' offsets were taken)
SUB ListProc (nm$, delta)
    DIM l$, t$, p0, p1, sp, ln, jtab, more, ln1, t1$
    jtab = PC - 2
    PRINT #CHLST, ""
    PRINT #CHLST, "---- "; nm$; ": "; IStr$(PC); " bytes, data "; IStr$(CodeWord(jtab - 8)); ", parameters "; IStr$(CodeWord(jtab - 6))
    IF delta > 0 THEN
        PRINT #CHLST, "      (entry)"
        ListCode 0, delta, jtab
    END IF
    ' its statements' records, up to the * after them
    more = 0
    LINE INPUT #CHLREC, l$
    IF l$ <> "*" THEN
        LINE INPUT #CHLREC, t$
        sp = INSTR(l$, " ")
        p0 = VAL(LEFT$(l$, sp - 1)) + delta
        ln = VAL(MID$(l$, sp + 1))
        more = 1
    END IF
    DO WHILE more
        LINE INPUT #CHLREC, l$
        IF l$ = "*" THEN
            p1 = CodeEndPos
            more = 0
        ELSE
            LINE INPUT #CHLREC, t1$
            sp = INSTR(l$, " ")
            p1 = VAL(LEFT$(l$, sp - 1)) + delta
            ln1 = VAL(MID$(l$, sp + 1))
        END IF
        IF ln > 0 THEN
            PRINT #CHLST, RIGHT$("     " + IStr$(ln), 5); "  "; t$
        ELSE
            PRINT #CHLST, "      "; t$
        END IF
        IF p1 > p0 THEN ListCode p0, p1, jtab
        IF more THEN
            IF p1 > p0 THEN p0 = p1
            ln = ln1
            t$ = t1$
        END IF
    LOOP
    IF NLong > 0 THEN PRINT #CHLST, "      jump table: "; IStr$(NLong); " entries"
END SUB

' the next number of l$ from position p on (p moves past it)
FUNCTION NextNum (l$, BYREF p)
    DIM q
    q = INSTR(p, l$ + " ", " ")
    NextNum = VAL(MID$(l$, p, q - p))
    p = q + 1
END FUNCTION

' the listing LstName$ of the module pass 3 compiled, from its two
' temporary files (which go)
SUB ListModule ()
    DIM nm$, l$, i, p, k, n, delta
    REDIM Code(MAXCODE) AS BYTE, RelPos(MAXREL), RelType(MAXREL) AS BYTE, RelName$(MAXREL)
    OPEN LstName$ FOR OUTPUT AS #CHLST
    PRINT #CHLST, "BC listing of "; SrcName$
    OPEN LTmpName$ FOR INPUT AS #CHLREC
    OPEN LCodName$ FOR INPUT AS #CHLCOD
    DO WHILE NOT EOF(CHLCOD)
        LINE INPUT #CHLCOD, nm$
        LINE INPUT #CHLCOD, l$
        p = 1
        PC = NextNum(l$, p)
        delta = NextNum(l$, p)
        NLong = NextNum(l$, p)
        CodeEndPos = NextNum(l$, p)
        NRel = NextNum(l$, p)
        i = 0
        DO WHILE i < PC
            LINE INPUT #CHLCOD, l$
            FOR k = 1 TO LEN(l$) - 1 STEP 2
                Code(i) = VAL("&H" + MID$(l$, k, 2))
                i = i + 1
            NEXT k
        LOOP
        FOR i = 0 TO NRel - 1
            LINE INPUT #CHLCOD, l$
            p = 1
            RelPos(i) = NextNum(l$, p)
            RelType(i) = NextNum(l$, p)
            RelName$(i) = MID$(l$, p)
        NEXT i
        ListProc nm$, delta
    LOOP
    CLOSE #CHLCOD
    CLOSE #CHLREC
    CLOSE #CHLST
    KILL LCodName$
    KILL LTmpName$
    ERASE Code, RelPos, RelType, RelName$
END SUB

' ---- BCLIST, the program: the listing of the module BCGEN compiled

ReadJob
StepNames
ListModule
CompileDone
