' BCLINK -- the linker: object files (and the library BASLIB.OBJ) into a
' UCSD Pascal II.0 code file
'
' The object files are read from the start several times, never sought:
'   1. every module, procedure and COMMON variable, and the names each
'      module refers to (calls, COMMON variables);
'   then what is linked: the main program's body, the run-time library's
'   start and end (_RTINIT, _HALT) and every procedure a linked one calls,
'   and the body of each module one of whose procedures is linked (a
'   procedure no one calls is left out);
'   then the layout: the globals from word 3 of the startup procedure's
'   frame (each linked module's statics, then the COMMON variables), the
'   segments (the main one is 1, the others 7, 8, ...) and the procedure
'   numbers;
'   2. once for each segment: its procedures, their calls and global
'      operands filled in, written to the code file after block 0;
'   3. with -MAP, NAME.MAP: the segments' procedures, the lines of the
'      program's own (BCDEBUG says a run-time error's line from it).
' Segment 1 procedure 1 is the startup code made here: zero the globals,
' _RTINIT, the bodies of the linked modules (the main program's last),
' _HALT(0).
#INCLUDE "BCCOM"

CONST MAXLN = 1400, MAXLP = 1040, MAXLM = 90, MAXPREF = 300, MAXLD = 200
CONST MAXLF = 24, LHSIZE = 128
CONST CHIN = 1, CHOUT = 2, CHMAP = 3, CHREF = 4, LKTMP$ = ":BCTEMP.LNK"

' A name is its two hashes (LH1, 15 bits; LH2, its length and each character times its
' place, mod 27011), not its text: the strings took more memory than Z80 mode has.  Two
' names with both hashes the same are one: two procedures "defined twice" (an error, not
' a wrong link: in a program that links every name it calls is defined).  An undefined
' one's text is found at the end (LUndef: up to 10; LinkUndef)
DIM SHARED LH1(), LH2(), LKind() AS BYTE, LDef(), LNext(), LHead(), NLName, LUndef(10), NLUndef
DIM SHARED PNm(), PMod(), PSg() AS BYTE, PLen(), PFl() AS BYTE, PNum() AS BYTE, PLive() AS BYTE, PRef0(), PRefN(), NLP
DIM SHARED MNm$(), MStat(), MBase(), MLive() AS BYTE, MBody(), NLM
' a procedure's names (each once) are in the file LKTMP$ (words), from word PRef0, PRefN
' of them: not in memory (pass 1 writes them, MarkAll reads a procedure's when it is
' linked); PRB, NPRB: the procedure's being read
DIM SHARED PRB(MAXPREF), NPRB, NRefs, DWords(), DOff(), DLive() AS BYTE, NLD
DIM SHARED LSeg$(16), LSegNum(16), LSegLen(16), LSegBlk(16), LSegProcs(16), NLSeg
DIM SHARED LFile$(MAXLF), NLF, LBuf() AS BYTE, LErr, LEof
DIM SHARED Entry() AS BYTE, NEntry, EntryJtab, GlobWords
' the tables' sizes: small at first, grown (LinkGrown) up to the MAX constants;
' the largest procedure (LBuf holds it)
DIM SHARED CapLN, CapLP, CapLM, CapLD, MaxClen

' a table's new size when cap entries were too few: twice as many, max at
' most.  (The linker's tables grow far, the references to thousands: each
' REDIM PRESERVE leaves the old table's memory behind, a hole too small
' for the next, so in few steps.)
FUNCTION LinkGrown (cap, max)
    DIM n
    n = cap * 2
    IF n > max THEN n = max
    LinkGrown = n
END FUNCTION

SUB LinkErrMsg (m$)
    LErr = LErr + 1
    SayLn "Link: " + m$
END SUB

' ---- the object files

FUNCTION RdB ()
    DIM b AS BYTE
    IF EOF(CHIN) THEN
        LEof = 1
        EXIT FUNCTION
    END IF
    GET #CHIN, , b
    RdB = b
END FUNCTION

FUNCTION RdW ()
    DIM lo, hi
    lo = RdB
    hi = RdB
    RdW = lo OR (hi * 256)
END FUNCTION

FUNCTION RdS$ ()
    DIM n, s$
    n = RdB
    IF n > 0 THEN
        s$ = SPACE$(n)
        GET #CHIN, , s$
    END IF
    RdS$ = s$
END FUNCTION

SUB OutB (v)
    DIM b AS BYTE
    b = v AND 255
    PUT #CHOUT, , b
END SUB

SUB OutW (v)
    OutB v AND 255
    OutB (v AND &HFF00) \ 256
END SUB

' the next record of a file: its letter, 0 at the end (a module's "BCOB"
' is read here)
FUNCTION NextRec ()
    DIM c, s$
    c = RdB
    IF c = 66 THEN
        s$ = CHR$(RdB) + CHR$(RdB) + CHR$(RdB)
        IF s$ <> "COB" THEN
            LinkErrMsg "not a BC object file"
            EXIT FUNCTION
        END IF
        c = RdB
    END IF
    IF LEof THEN c = 0
    NextRec = c
END FUNCTION

' ---- names

' n$'s hashes: LHash1, LHash2
SUB LHashes (n$, BYREF h1, BYREF h2)
    DIM i, c
    h1 = 0
    h2 = LEN(n$)
    FOR i = 1 TO LEN(n$)
        c = ASC(n$, i)
        h1 = (((h1 AND &HFFF) * 8) + h1 \ 4096) XOR c
        h2 = (h2 + c * ((i AND 31) + 1)) MOD 27011
    NEXT i
END SUB

' a name's index (made if new)
FUNCTION LNameIx (n$)
    DIM h, h1, h2, i
    LHashes n$, h1, h2
    h = h1 AND (LHSIZE - 1)
    i = LHead(h)
    DO WHILE i > 0
        IF LH1(i) = h1 AND LH2(i) = h2 THEN
            LNameIx = i
            EXIT FUNCTION
        END IF
        i = LNext(i)
    LOOP
    IF NLName >= CapLN THEN
        IF CapLN >= MAXLN THEN Fatal "Link: too many names"
        CapLN = LinkGrown(CapLN, MAXLN)
        REDIM PRESERVE LH1(CapLN), LH2(CapLN), LKind(CapLN) AS BYTE, LDef(CapLN), LNext(CapLN)
    END IF
    NLName = NLName + 1
    LH1(NLName) = h1
    LH2(NLName) = h2
    LKind(NLName) = 0
    LDef(NLName) = 0
    LNext(NLName) = LHead(h)
    LHead(h) = NLName
    LNameIx = NLName
END FUNCTION

FUNCTION SegIx (n$)
    DIM i
    FOR i = 1 TO NLSeg
        IF LSeg$(i) = n$ THEN
            SegIx = i
            EXIT FUNCTION
        END IF
    NEXT i
    IF NLSeg >= 16 THEN
        LinkErrMsg "too many segments"
        SegIx = 1
        EXIT FUNCTION
    END IF
    NLSeg = NLSeg + 1
    LSeg$(NLSeg) = n$
    SegIx = NLSeg
END FUNCTION

' a P record's line table skipped
SUB SkipLines ()
    DIM n, i, pc, x, j
    n = RdW
    FOR i = 1 TO n
        pc = RdW
        IF pc = -1 THEN
            ' (a file's name: no string made of it)
            x = RdB
            FOR j = 1 TO x
                pc = RdB
            NEXT j
        ELSE
            x = RdW
        END IF
    NEXT i
END SUB

' ---- pass 1

' (each phase that is done once a segment of its own: in memory with the
' library's RTSELDOM, which opens a file, there is little room)
SEGMENT LKPASS1
' a P record (the letter read): its procedure entered, with the names it
' refers to (each once)
SUB ReadProc1 (m)
    DIM fl, nm$, sg$, parmsz, rw, clen, jtab, nrel, i, pos, ty, t$, x, k, j, dup, p
    fl = RdB
    nm$ = RdS$
    sg$ = RdS$
    parmsz = RdW
    rw = RdB
    clen = RdW
    jtab = RdW
    IF clen > MaxClen THEN MaxClen = clen
    FOR i = 1 TO clen
        x = RdB
    NEXT i
    x = LNameIx(nm$)
    p = 0
    IF LKind(x) = 1 THEN
        LinkErrMsg nm$ + " defined twice"
    ELSE
        IF NLP >= CapLP THEN
            IF CapLP >= MAXLP THEN Fatal "Link: too many procedures"
            CapLP = LinkGrown(CapLP, MAXLP)
            REDIM PRESERVE PNm(CapLP), PMod(CapLP), PSg(CapLP) AS BYTE, PLen(CapLP), PFl(CapLP) AS BYTE, PNum(CapLP) AS BYTE
            REDIM PRESERVE PLive(CapLP) AS BYTE, PRef0(CapLP), PRefN(CapLP)
        END IF
        NLP = NLP + 1
        PNm(NLP) = x
        PMod(NLP) = m
        PSg(NLP) = SegIx(sg$)
        PLen(NLP) = (clen + 1) AND &HFFFE
        PFl(NLP) = fl
        PNum(NLP) = 0
        PLive(NLP) = 0
        PRef0(NLP) = NRefs
        PRefN(NLP) = 0
        NPRB = 0
        p = NLP
        LKind(x) = 1
        LDef(x) = NLP
        IF fl = 1 THEN MBody(m) = NLP
    END IF
    nrel = RdW
    FOR i = 1 TO nrel
        pos = RdW
        ty = RdB
        t$ = RdS$
        IF ty <> 3 AND p > 0 THEN
            k = LNameIx(t$)
            dup = 0
            FOR j = 1 TO NPRB
                IF PRB(j) = k THEN
                    dup = 1
                    EXIT FOR
                END IF
            NEXT j
            IF dup = 0 THEN
                IF NPRB >= MAXPREF THEN Fatal "Link: a procedure calls too many"
                NPRB = NPRB + 1
                PRB(NPRB) = k
            END IF
        END IF
    NEXT i
    IF p > 0 THEN
        FOR j = 1 TO NPRB
            PUT #CHREF, , PRB(j)
        NEXT j
        PRefN(p) = NPRB
        NRefs = NRefs + NPRB
    END IF
    SkipLines
END SUB

SUB Pass1 ()
    DIM f, c, m, x, w, nm$, strong
    IF FileExists(LKTMP$) THEN KILL LKTMP$
    OPEN LKTMP$ FOR BINARY AS #CHREF
    FOR f = 1 TO NLF
        OPEN LFile$(f) FOR BINARY AS #CHIN
        LEof = 0
        m = 0
        DO
            c = NextRec
            SELECT CASE c
            CASE 0
                EXIT DO
            CASE 77
                IF NLM >= CapLM THEN
                    IF CapLM >= MAXLM THEN Fatal "Link: too many modules"
                    CapLM = LinkGrown(CapLM, MAXLM)
                    REDIM PRESERVE MNm$(CapLM), MStat(CapLM), MBase(CapLM), MLive(CapLM) AS BYTE, MBody(CapLM)
                END IF
                NLM = NLM + 1
                m = NLM
                MNm$(m) = RdS$
                MStat(m) = 0
                MLive(m) = 0
                MBody(m) = 0
                FOR x = 1 TO m - 1
                    IF MNm$(x) = MNm$(m) THEN LinkErrMsg "two modules " + MNm$(m)
                NEXT x
            CASE 80
                ReadProc1 m
            CASE 68
                strong = RdB
                nm$ = RdS$
                w = RdW
                x = LNameIx(nm$)
                IF LKind(x) = 1 THEN
                    LinkErrMsg nm$ + " is a procedure and a variable"
                ELSEIF LKind(x) = 2 THEN
                    IF w > DWords(LDef(x)) THEN DWords(LDef(x)) = w
                ELSE
                    IF NLD >= CapLD THEN
                        IF CapLD >= MAXLD THEN Fatal "Link: too many COMMON variables"
                        CapLD = LinkGrown(CapLD, MAXLD)
                        REDIM PRESERVE DWords(CapLD), DOff(CapLD), DLive(CapLD) AS BYTE
                    END IF
                    NLD = NLD + 1
                    LKind(x) = 2
                    LDef(x) = NLD
                    DWords(NLD) = w
                    DLive(NLD) = 0
                END IF
            CASE 71
                MStat(m) = RdW
            CASE 69
                m = 0
            CASE ELSE
                LinkErrMsg LFile$(f) + ": a bad record"
                EXIT DO
            END SELECT
        LOOP
        CLOSE #CHIN
    NEXT f
END SUB

' ---- what is linked

SEGMENT LKLAY
' a name a linked procedure uses: the procedure (and its module's body)
' linked, or the COMMON variable kept
SUB MarkName (x)
    DIM p, b
    IF LKind(x) = 1 THEN
        p = LDef(x)
        IF PLive(p) = 0 THEN PLive(p) = 1
        IF MLive(PMod(p)) = 0 THEN
            MLive(PMod(p)) = 1
            b = MBody(PMod(p))
            IF b > 0 THEN
                IF PLive(b) = 0 THEN PLive(b) = 1
            END IF
        END IF
    ELSEIF LKind(x) = 2 THEN
        DLive(LDef(x)) = 1
    ELSE
        ' (its text at the end: LinkUndef)
        LErr = LErr + 1
        IF NLUndef < 10 THEN
            NLUndef = NLUndef + 1
            LUndef(NLUndef) = x
        END IF
        LKind(x) = 3
    END IF
END SUB

SUB MarkAll ()
    DIM p, j, again, x
    IF NLM = 0 THEN EXIT SUB
    MLive(1) = 1
    IF MBody(1) > 0 THEN PLive(MBody(1)) = 1
    x = LNameIx("_RTINIT")
    MarkName x
    x = LNameIx("_HALT")
    MarkName x
    DO
        again = 0
        FOR p = 1 TO NLP
            IF PLive(p) = 1 THEN
                PLive(p) = 2
                again = 1
                IF PRefN(p) > 0 THEN
                    SEEK #CHREF, PRef0(p) * 2# + 1
                    FOR j = 1 TO PRefN(p)
                        GET #CHREF, , x
                        MarkName x
                    NEXT j
                END IF
            END IF
        NEXT p
    LOOP WHILE again
END SUB

' ---- the layout

SUB Layout ()
    DIM m, d, p, s, n, i
    GlobWords = 3
    FOR m = 1 TO NLM
        MBase(m) = 0
        IF MLive(m) THEN
            MBase(m) = GlobWords
            GlobWords = GlobWords + MStat(m)
        END IF
    NEXT m
    FOR d = 1 TO NLD
        IF DLive(d) THEN
            DOff(d) = GlobWords
            GlobWords = GlobWords + DWords(d)
        END IF
    NEXT d
    IF GlobWords > 16000 OR GlobWords < 0 THEN LinkErrMsg "too many global variables"
    ' segment numbers: "" (the main one) is 1, the others 7, 8 ... in order
    FOR s = 1 TO NLSeg
        LSegNum(s) = 0
        LSegLen(s) = 0
        LSegProcs(s) = 0
    NEXT s
    s = SegIx("")
    LSegNum(s) = 1
    LSegProcs(s) = 1
    n = 6
    FOR p = 1 TO NLP
        IF PLive(p) THEN
            s = PSg(p)
            IF LSegNum(s) = 0 THEN
                n = n + 1
                IF n > 15 THEN
                    LinkErrMsg "more than 10 segments"
                    n = 15
                END IF
                LSegNum(s) = n
            END IF
            LSegProcs(s) = LSegProcs(s) + 1
            IF LSegProcs(s) > 255 THEN LinkErrMsg "more than 255 procedures in segment " + LSeg$(s)
            PNum(p) = LSegProcs(s)
            ' (with its procedure dictionary and, in the main one, the startup
            ' code: a segment's length is a word)
            IF LSegLen(s) > 32000 - PLen(p) - 2 * LSegProcs(s) THEN
                LinkErrMsg "segment " + LSeg$(s) + " too large (32000 bytes at most)"
                LSegLen(s) = 0
            END IF
            LSegLen(s) = LSegLen(s) + PLen(p)
        END IF
    NEXT p
END SUB

' ---- the startup procedure (segment 1 procedure 1, lex level 0)

SUB EB (b)
    IF NEntry >= 600 THEN Fatal "Link: too many modules"
    Entry(NEntry) = b AND 255
    NEntry = NEntry + 1
END SUB

CONST OCGP2 = &HCF, OCXP2 = &HCD

SUB ECall (x)
    DIM p
    p = LDef(x)
    IF LSegNum(PSg(p)) = 1 THEN
        EB OCGP2
        EB PNum(p)
    ELSE
        EB OCXP2
        EB LSegNum(PSg(p))
        EB PNum(p)
    END IF
END SUB

SUB MakeEntry ()
    DIM g, m, exitpos, p
    NEntry = 0
    g = (GlobWords - 3) * 2
    IF g > 0 THEN
        ' FILLCHAR(globals, 0, bytes, 0)
        EB &HA5
        EB 3
        EB 0
        EB &HC7
        EB g AND 255
        EB (g AND &HFF00) \ 256
        EB 0
        EB &H9E
        EB 10
    END IF
    ECall LNameIx("_RTINIT")
    ' the bodies: the main program's last
    FOR m = 2 TO NLM
        IF MLive(m) AND MBody(m) > 0 THEN ECall PNm(MBody(m))
    NEXT m
    IF MBody(1) > 0 THEN ECall PNm(MBody(1))
    EB 0
    ECall LNameIx("_HALT")
    exitpos = NEntry
    EB &HC1
    EB 0
    IF NEntry AND 1 THEN EB 0
    EntryJtab = NEntry + 8
    EB g AND 255
    EB (g AND &HFF00) \ 256
    EB 4
    EB 0
    p = EntryJtab - 4 - exitpos
    EB p AND 255
    EB (p AND &HFF00) \ 256
    p = EntryJtab - 2
    EB p AND 255
    EB (p AND &HFF00) \ 256
    EB 1
    EB 0
END SUB

' ---- NAME.MAP (-MAP): beside the code file, a text file: each segment
' (S#) and its procedures by number (P#), with their names and lengths,
' and -- the program's own, not the library's -- their lines: where each
' line's code starts (the procedure's offset, I#) and its number, "I#:N",
' after "FILE name" for the file they are in.  A run-time error's I# is
' after the call, so its line is the last that starts before it (BCDEBUG
' looks it up there).  Written at the end, in a segment of its own (MAP),
' with the object files opened in the main segment (MAP and RTSELDOM, which
' opens them, not in memory together).

SEGMENT MAP

' the map's line for the start of segment s (k its number)
SUB MapSeg (k, s, out$)
    DIM m$
    IF k = 1 THEN m$ = ModOf$(out$) ELSE m$ = LSeg$(s)
    PRINT #CHMAP, ""
    PRINT #CHMAP, "S# " + IStr$(k) + " " + m$ + ", " + IStr$(LSegLen(s)) + " bytes, " + IStr$(LSegProcs(s)) + " procedures"
    IF k = 1 THEN PRINT #CHMAP, "  P#   1  (the start)"
END SUB

' a P record after its name: its segment, sizes, code and relocations
' skipped (its line table is next)
SUB SkipProc ()
    DIM sg$, clen, i, x, nrel
    sg$ = RdS$
    x = RdW
    x = RdB
    clen = RdW
    x = RdW
    FOR i = 1 TO clen
        x = RdB
    NEXT i
    nrel = RdW
    FOR i = 1 TO nrel
        x = RdW
        x = RdB
        sg$ = RdS$
    NEXT i
END SUB

' a P record's line table into the map: "FILE name", "I#:N I#:N ..."
SUB MapLines ()
    DIM n, i, pc, l$
    n = RdW
    FOR i = 1 TO n
        pc = RdW
        IF pc = -1 THEN
            IF l$ <> "" THEN PRINT #CHMAP, l$
            PRINT #CHMAP, "    FILE " + RdS$
            l$ = ""
        ELSE
            IF l$ = "" THEN l$ = "   "
            l$ = l$ + " " + IStr$(pc) + ":" + IStr$(RdW)
            IF LEN(l$) > 64 THEN
                PRINT #CHMAP, l$
                l$ = ""
            END IF
        END IF
    NEXT i
    IF l$ <> "" THEN PRINT #CHMAP, l$
END SUB

' one object file's procedures of segment s (the file open), in the order
' of their numbers (Layout numbered them in this order)
SUB MapFile (s)
    DIM c, nm$, x, p
    DO
        c = NextRec
        SELECT CASE c
        CASE 0
            EXIT DO
        CASE 77
            nm$ = RdS$
        CASE 80
            x = RdB
            nm$ = RdS$
            p = LDef(LNameIx(nm$))
            SkipProc
            IF PLive(p) <> 0 AND PSg(p) = s THEN
                IF PFl(p) = 1 AND PMod(p) = 1 THEN nm$ = "the main program (" + nm$ + ")"
                PRINT #CHMAP, "  P# " + RIGHT$("  " + IStr$(PNum(p)), 3) + "  " + nm$ + ", " + IStr$(PLen(p)) + " bytes"
                IF LEFT$(nm$, 1) = "_" THEN SkipLines ELSE MapLines
            ELSE
                SkipLines
            END IF
        CASE 68
            x = RdB
            nm$ = RdS$
            x = RdW
        CASE 71
            x = RdW
        CASE 69
        CASE ELSE
            EXIT DO
        END SELECT
    LOOP
END SUB

SEGMENT

SUB WriteMap (out$)
    DIM k, s, f, m$
    m$ = DirOf$(out$) + ModOf$(out$) + ".MAP"
    OPEN m$ FOR OUTPUT AS #CHMAP
    PRINT #CHMAP, out$; ": its segments (S#), procedures (P#) and lines (I#:N)"
    FOR k = 1 TO 15
        FOR s = 1 TO NLSeg
            IF LSegNum(s) = k THEN
                MapSeg k, s, out$
                FOR f = 1 TO NLF
                    OPEN LFile$(f) FOR BINARY AS #CHIN
                    LEof = 0
                    MapFile s
                    CLOSE #CHIN
                NEXT f
            END IF
        NEXT s
    NEXT k
    CLOSE #CHMAP
    IF OptQuiet = 0 THEN SayLn "  map " + m$
END SUB

' ---- pass 2: one segment's procedures

' a procedure's image patched: its calls, global operands, number
SUB PatchProc (p, clen, jtab)
    DIM nrel, i, pos, ty, t$, x, t, v, m
    m = PMod(p)
    nrel = RdW
    FOR i = 1 TO nrel
        pos = RdW
        ty = RdB
        t$ = RdS$
        SELECT CASE ty
        CASE 1
            x = LNameIx(t$)
            IF LKind(x) = 1 THEN
                t = LDef(x)
                IF PSg(t) = PSg(p) THEN
                    LBuf(pos) = &HCF
                    LBuf(pos + 1) = PNum(t)
                    LBuf(pos + 2) = &HD7
                ELSE
                    LBuf(pos) = &HCD
                    LBuf(pos + 1) = LSegNum(PSg(t))
                    LBuf(pos + 2) = PNum(t)
                END IF
            END IF
        CASE 3, 4
            v = (LBuf(pos) AND 127) * 256 + LBuf(pos + 1)
            IF ty = 3 THEN
                v = v + MBase(m)
            ELSE
                x = LNameIx(t$)
                IF LKind(x) = 2 THEN v = v + DOff(LDef(x))
            END IF
            LBuf(pos) = 128 OR ((v AND &H7F00) \ 256)
            LBuf(pos + 1) = v AND 255
        END SELECT
    NEXT i
    LBuf(jtab) = PNum(p)
END SUB

' the segment s: its procedures from the object files, written; their
' dictionary words are kept in jt()
SUB WriteSeg (s, jt(), BYREF slen)
    DIM f, c, p, fl, nm$, sg$, parmsz, rw, clen, jtab, i, x, skip, nrel
    FOR f = 1 TO NLF
        OPEN LFile$(f) FOR BINARY AS #CHIN
        LEof = 0
        DO
            c = NextRec
            SELECT CASE c
            CASE 0
                EXIT DO
            CASE 77
                nm$ = RdS$
            CASE 80
                fl = RdB
                nm$ = RdS$
                sg$ = RdS$
                parmsz = RdW
                rw = RdB
                clen = RdW
                jtab = RdW
                x = LNameIx(nm$)
                p = LDef(x)
                skip = 1
                IF LKind(x) = 1 THEN
                    IF PLive(p) <> 0 AND PSg(p) = s THEN skip = 0
                END IF
                IF skip THEN
                    FOR i = 1 TO clen
                        x = RdB
                    NEXT i
                    nrel = RdW
                    FOR i = 1 TO nrel
                        x = RdW
                        x = RdB
                        sg$ = RdS$
                    NEXT i
                    SkipLines
                ELSE
                    FOR i = 0 TO clen - 1
                        LBuf(i) = RdB
                    NEXT i
                    PatchProc p, clen, jtab
                    SkipLines
                    IF clen AND 1 THEN
                        LBuf(clen) = 0
                        clen = clen + 1
                    END IF
                    FOR i = 0 TO clen - 1
                        OutB LBuf(i)
                    NEXT i
                    jt(PNum(p)) = slen + jtab
                    slen = slen + clen
                END IF
            CASE 68
                x = RdB
                nm$ = RdS$
                x = RdW
            CASE 71
                x = RdW
            CASE 69
            CASE ELSE
                EXIT DO
            END SELECT
        LOOP
        CLOSE #CHIN
    NEXT f
END SUB

' the undefined names (LUndef): their texts, from the object files (the names they call)
SEGMENT MAP
SUB LinkUndef ()
    DIM f, c, i, j, n, h1, h2, nrel, t$, k, x
    FOR f = 1 TO NLF
        OPEN LFile$(f) FOR BINARY AS #CHIN
        LEof = 0
        DO
            c = NextRec
            IF c <> 77 AND c <> 80 AND c <> 68 AND c <> 71 AND c <> 69 THEN EXIT DO
            SELECT CASE c
            CASE 77
                t$ = RdS$
            CASE 80
                x = RdB
                t$ = RdS$
                t$ = RdS$
                x = RdW
                x = RdB
                n = RdW
                x = RdW
                FOR i = 1 TO n
                    x = RdB
                NEXT i
                nrel = RdW
                FOR i = 1 TO nrel
                    x = RdW
                    x = RdB
                    t$ = RdS$
                    LHashes t$, h1, h2
                    FOR k = 1 TO NLUndef
                        j = LUndef(k)
                        IF j > 0 THEN
                            IF LH1(j) = h1 AND LH2(j) = h2 THEN
                                SayLn "Link: undefined: " + t$
                                LUndef(k) = 0
                            END IF
                        END IF
                    NEXT k
                NEXT i
                SkipLines
            CASE 68
                x = RdB
                t$ = RdS$
                x = RdW
            CASE 71
                x = RdW
            END SELECT
        LOOP
        CLOSE #CHIN
    NEXT f
END SUB

SEGMENT

' ---- linking

' the files of "A,B,C": each NAME.OBJ, and the library
SEGMENT LKPASS1
SUB ObjFiles (objs$, addlib)
    DIM i, j, n$, lib$
    NLF = 0
    i = 1
    DO WHILE i <= LEN(objs$)
        j = INSTR(i, objs$ + ",", ",")
        n$ = LTRIM$(RTRIM$(MID$(objs$, i, j - i)))
        IF n$ <> "" THEN
            IF NLF >= MAXLF - 1 THEN
                LinkErrMsg "too many object files"
            ELSE
                NLF = NLF + 1
                LFile$(NLF) = WithSuffix$(n$, ".OBJ")
            END IF
        END IF
        i = j + 1
    LOOP
    IF addlib THEN
        ' beside the program's objects, on the prefix, BASIC:/LIB, the boot
        ' disk
        lib$ = DirOf$(LFile$(1)) + "BASLIB.OBJ"
        IF NOT FileExists(lib$) THEN lib$ = "BASLIB.OBJ"
        IF NOT FileExists(lib$) THEN lib$ = "BASIC:/LIB/BASLIB.OBJ"
        IF NOT FileExists(lib$) THEN lib$ = "*BASLIB.OBJ"
        NLF = NLF + 1
        LFile$(NLF) = lib$
    END IF
    FOR i = 1 TO NLF
        IF NOT FileExists(LFile$(i)) THEN LinkErrMsg "no file " + LFile$(i)
    NEXT i
END SUB

' the code file's block 0: the segments' blocks and lengths, their names
SEGMENT LKHEAD
SUB WriteHead (out$)
    DIM k, n, s, j, pn$
    FOR k = 0 TO 15
        n = 0
        FOR s = 1 TO NLSeg
            IF LSegNum(s) = k AND LSegNum(s) > 0 THEN n = s
        NEXT s
        IF n > 0 THEN
            OutW LSegBlk(n)
            OutW LSegLen(n)
        ELSE
            OutW 0
            OutW 0
        END IF
    NEXT k
    FOR k = 0 TO 15
        n = 0
        FOR s = 1 TO NLSeg
            IF LSegNum(s) = k AND LSegNum(s) > 0 THEN n = s
        NEXT s
        IF n = 0 THEN
            OutW 0
            OutW 0
            OutW 0
            OutW 0
        ELSE
            IF k = 1 THEN pn$ = ModOf$(out$) ELSE pn$ = UCASE$(LSeg$(n))
            pn$ = LEFT$(pn$ + "        ", 8)
            FOR j = 1 TO 8
                OutB ASC(pn$, j)
            NEXT j
        END IF
    NEXT k
    FOR k = 1 TO 512 - 192
        OutB 0
    NEXT k
END SUB

SEGMENT
FUNCTION LinkProg (out$, objs$)
    DIM s, k, i, blk, n, j, len0, pn$, jt(256), slen
    LErr = 0
    NLName = 0
    NLP = 0
    NLM = 0
    NRefs = 0
    NLD = 0
    NLSeg = 0
    ' (BC's programs: up to 530 names, 390 procedures -- none grown, no holes left)
    CapLN = 600
    CapLP = 400
    CapLM = 24
    CapLD = 40
    MaxClen = 0
    NLUndef = 0
    REDIM LH1(CapLN), LH2(CapLN), LKind(CapLN) AS BYTE, LDef(CapLN), LNext(CapLN), LHead(LHSIZE)
    REDIM PNm(CapLP), PMod(CapLP), PSg(CapLP) AS BYTE, PLen(CapLP), PFl(CapLP) AS BYTE, PNum(CapLP) AS BYTE
    REDIM PLive(CapLP) AS BYTE, PRef0(CapLP), PRefN(CapLP)
    REDIM MNm$(CapLM), MStat(CapLM), MBase(CapLM), MLive(CapLM) AS BYTE, MBody(CapLM)
    REDIM DWords(CapLD), DOff(CapLD), DLive(CapLD) AS BYTE
    MemNote "entry"
    s = SegIx("")
    ObjFiles objs$, 1
    IF LErr = 0 THEN
        Pass1
        MemNote "Pass1"
        IF LErr = 0 THEN MarkAll
        CLOSE #CHREF
    END IF
    IF LErr = 0 THEN Layout
    IF LErr > 0 THEN
        IF NLUndef > 0 THEN LinkUndef
        SayLn "Link: " + IStr$(LErr) + " error(s): no " + out$
        GOTO done
    END IF
    ' (LBuf: the largest procedure, and a byte to make it even)
    REDIM LBuf(MaxClen + 1) AS BYTE, Entry(600) AS BYTE
    MakeEntry
    MemNote "MakeEntry"
    s = SegIx("")
    LSegLen(s) = LSegLen(s) + NEntry
    ' the blocks: each segment from a block boundary, after block 0
    blk = 1
    FOR k = 1 TO 15
        FOR s = 1 TO NLSeg
            IF LSegNum(s) = k THEN
                LSegLen(s) = LSegLen(s) + 2 * LSegProcs(s) + 2
                LSegBlk(s) = blk
                blk = blk + (LSegLen(s) + 511) \ 512
            END IF
        NEXT s
    NEXT k
    IF OptQuiet = 0 THEN SayLn "Linking " + out$
    OPEN out$ FOR OUTPUT AS #CHOUT
    MemNote "open"
    ' block 0: the segment dictionary
    WriteHead out$
    ' the segments
    FOR k = 1 TO 15
        FOR s = 1 TO NLSeg
            IF LSegNum(s) = k THEN
                slen = 0
                IF k = 1 THEN
                    FOR i = 0 TO NEntry - 1
                        OutB Entry(i)
                    NEXT i
                    jt(1) = EntryJtab
                    slen = NEntry
                END IF
                WriteSeg s, jt(), slen
                MemNote "seg"
                ' the procedure dictionary: self-relative, the highest first
                FOR j = LSegProcs(s) TO 1 STEP -1
                    OutW slen - jt(j)
                    slen = slen + 2
                NEXT j
                OutB k
                OutB LSegProcs(s)
                slen = slen + 2
                IF slen <> LSegLen(s) THEN LinkErrMsg "internal: the length of segment " + LSeg$(s)
                DO WHILE slen AND 511
                    OutB 0
                    slen = slen + 1
                LOOP
                IF OptQuiet = 0 THEN
                    pn$ = LSeg$(s)
                    IF k = 1 THEN pn$ = ModOf$(out$)
                    SayLn "  segment " + IStr$(k) + " " + LEFT$(pn$ + "        ", 8) + " " + IStr$(LSegLen(s)) + " bytes, " + IStr$(LSegProcs(s)) + " procedures"
                END IF
            END IF
        NEXT s
    NEXT k
    CLOSE #CHOUT
    ERASE LBuf, Entry
    IF OptQuiet = 0 THEN SayLn "  globals " + IStr$(GlobWords - 3) + " words"
    IF JobFlags AND JFMAP THEN WriteMap out$
    IF OptMem THEN SayLn "  least free memory: " + IStr$(FRE(-1)) + " words"
    IF LErr = 0 THEN LinkProg = -1
done:
    ERASE LH1, LH2, LKind, LDef, LNext, LHead, PNm, PMod, PSg, PLen, PFl, PNum, PLive, PRef0, PRefN
    ERASE MNm$, MStat, MBase, MLive, MBody, DWords, DOff, DLive
    IF FileExists(LKTMP$) THEN KILL LKTMP$
END FUNCTION

' -J LIB=A,B: the object files one after another (a library); the zero
' bytes that fill a file's last block are left out
SEGMENT JOIN
FUNCTION JoinLib (out$, objs$)
    DIM f, c, z, i
    LErr = 0
    ObjFiles objs$, 0
    IF LErr > 0 THEN EXIT FUNCTION
    IF OptQuiet = 0 THEN SayLn "Joining " + out$
    OPEN out$ FOR OUTPUT AS #CHOUT
    MemNote "open"
    FOR f = 1 TO NLF
        OPEN LFile$(f) FOR BINARY AS #CHIN
        LEof = 0
        z = 0
        DO
            c = RdB
            IF LEof THEN EXIT DO
            IF c = 0 THEN
                z = z + 1
            ELSE
                FOR i = 1 TO z
                    OutB 0
                NEXT i
                z = 0
                OutB c
            END IF
        LOOP
        CLOSE #CHIN
    NEXT f
    CLOSE #CHOUT
    JoinLib = -1
END FUNCTION

SEGMENT

' ---- BCLINK, the program: the job's step, L OUT=A,B (link) or J LIB=A,B
' (join)

' -L OUT=A,B: the code file and the object files
FUNCTION DoLink (spec$)
    DIM e, out$, objs$
    e = INSTR(spec$, "=")
    IF e = 0 THEN
        out$ = spec$
        objs$ = spec$
    ELSE
        out$ = LEFT$(spec$, e - 1)
        objs$ = MID$(spec$, e + 1)
    END IF
    out$ = WithSuffix$(out$, ".CODE")
    DoLink = LinkProg(out$, objs$)
END FUNCTION

FUNCTION DoJoin (spec$)
    DIM e
    e = INSTR(spec$, "=")
    IF e = 0 THEN
        SayLn "BC: -J LIB=A,B,..."
        EXIT FUNCTION
    END IF
    DoJoin = JoinLib(WithSuffix$(LEFT$(spec$, e - 1), ".OBJ"), MID$(spec$, e + 1))
END FUNCTION

DIM ok
ReadJob
IF LEFT$(JobCur$, 1) = "L" THEN ok = DoLink(MID$(JobCur$, 3)) ELSE ok = DoJoin(MID$(JobCur$, 3))
PhaseDone ok
