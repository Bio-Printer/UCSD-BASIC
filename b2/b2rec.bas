' B2REC -- the intermediate files' records (docs/B2DESIGN.md section 3), the
' symbols' kinds and classes they carry, and B2IO's globals (#INCLUDE "B2REC"
' after B2COM: the passes from B2SYN on)

' ---- B2SYN's marks (140..159)
' RSTMT b: a statement of kind b starts (a keyword's code, or SAAAA)
' RX b ... RXE: an expression (b: XAAAA, how it is wanted)
' RLV b ... RLVE: a target (b: LVAAAA, what is made of it)
' RMARK b: PRINT's TAB( and SPC( (MTAB, MSPC), a #channel (MCHAN), a CASE's
' item, the last (MLAST) or not (MMORE), PRINT's USING format (MUSING)
' RSEL: the value of SELECT CASE (in a CASE's condition); RLREF s: a label
' gone to (GOTO, GOSUB, ON, RESTORE: its text)
CONST RSTMT = 140, RX = 141, RXE = 142, RLV = 143, RLVE = 144, RMARK = 145, RSEL = 146, RLREF = 147
' ---- B2NAME's operands (160..179)
' RVAR kind type class offset dims name len: a variable or array (name: a
'   COMMON variable's, for the linker; else its own; len: a string's LENGTH, 0
'   for BASIC's 255)
' RPROC type kind name np (type flags len) * np text: a procedure called
' RBUILT id text: a built-in function;  RLAB w: a label (by number)
CONST RVAR = 160, RPROC = 161, RBUILT = 162, RLAB = 163
' ---- B2EXPR's (180..199)
' RXC type flags value ... RXCE t: a compiled expression (or assignment); t:
'   it made string temporaries (XFTEMP)
' RLVC type flags kind [pre] RLVL [load] RLVS [store] RLVCE t: a compiled
'   target (kind, a string's: 0 BASIC's, n a LENGTH n string's slot, -n a
'   LENGTH n array's element: the library's _SGET, _SPUT)
CONST RXC = 180, RXCE = 181, RLVC = 182, RLVL = 183, RLVS = 184, RLVCE = 185
' ---- code (200..219): what B2ASM assembles
' CBYTES n bytes; CJUMP op label; CCASE label; CLABEL label; CALIAS l m
' CREL kind name; CALIGN (a 0 if the code is at an odd byte); CTEMP (the
' string temporaries given back); CGOSUB label (a GOSUB's return point);
' CFREE kind offset (a local given back at the exit: 1 string, 2 array);
' CBEGIN ... CEND a procedure (CBxxx below); COBJB b, COBJW w, COBJS s the
' object file's other records
CONST CBYTES = 200, CJUMP = 201, CCASE = 202, CLABEL = 203, CALIAS = 204
CONST CREL = 205, CALIGN = 206, CTEMP = 207, CGOSUB = 208, CFREE = 209
CONST CBEGIN = 210, CEND = 211, COBJB = 212, COBJW = 213, COBJS = 214

' statement kinds besides the keywords' (RSTMT's operand)
CONST SASSIGN = 100, SCALL = 101, SMIDSET = 102, SPOKE = 103, SPOKEB = 104
CONST SCSP = 105, SOSCALL = 106, SENDIF = 107, SENDSEL = 108, SENDSUB = 109
CONST SENDFN = 110, SLINPUT = 111, SDATAL = 112, SONERR = 113, SEXITSUB = 114
CONST SCASEELSE = 115
' how an expression is wanted (RX's operand): a value of its own type
' (XANY), of a type (TYxxx), the jumps of a condition to the statement's
' "false" label (XCOND; XNCOND its NOT), the type of the target before it
' (XLVT), a SUB called (XCALL), SELECT CASE's value (XSEL), a channel
' (XCHAN: a constant, else a local), PUT's value (XPUT), CSP's arguments
' (XRAW: a comparison as 1/0)
CONST XANY = 0, XCOND = 10, XNCOND = 11, XLVT = 12, XCALL = 13, XSEL = 14
CONST XCHAN = 15, XPUT = 16, XRAW = 17
' a target (RLV's operand): an assignment (with the RX XLVT after it: all
' code), its parts before and after the value (LVPS), GET's (LVGET), its
' address (LVADDR)
CONST LVASSIGN = 1, LVPS = 2, LVGET = 3, LVADDR = 4
CONST MTAB = 1, MSPC = 2, MCHAN = 3, MLAST = 4, MMORE = 5, MUSING = 6
' RXC's flags: made string temporaries; an INTEGER constant (its value
' follows); a real constant, negative; an address (PUT's lvalue)
CONST XFTEMP = 1, XFICON = 2, XFRCON = 4, XFNEG = 8, XFADDR = 16
' the label a condition jumps to when it is false (B2CTL sets the real one)
CONST LFALSE = -1

' ---- symbols: kinds, storage classes, flags
CONST SKVAR = 1, SKARRAY = 2, SKSUB = 4, SKFUNC = 5, SKLABEL = 6
CONST SCLOCAL = 1, SCSTATIC = 2, SCCOMMON = 3, SCPARAM = 4, SCREF = 5
CONST SFSHARED = 1, SFDEFINED = 2, SFPRIVATE = 4, SFAS = 8, SFUSED = 16
CONST SFRUNTIME = 32, SFSETLAB = 64, SFGOSUB = 128
CONST PFBYREF = 1, PFARRAY = 2

' ---- B2IO: the record just read (its kind Rk and operands), the header
' read (InHead) and the counts written (OutHead)
COMMON SHARED Rk, RB1, RB2, RB3, RW1, RW2, RW3, RS$, RS2$, RNP, RPT(), RPF(), RPL()
' (OutPos counts the bytes written, modulo 65536; OutBlk, OutOff: where
' the next one goes, a block of 512 and the byte in it -- for SEEK)
COMMON SHARED InHead(), OutHead(), OutPos, OutBlk, OutOff, InPend, InPendK
' the procedure being copied: CBEGIN's fields (CBxxx)
COMMON SHARED CbKind, CbPw, CbRw, CbResOff, CbResTy, CbMark, CbLocal, CbLab
COMMON SHARED CbZero, CbFlags, CbName$, CbSeg$, CbBlk, CbOff, InProc
' the bytes of code being collected for a CBYTES record
COMMON SHARED OutBuf() AS BYTE, NOutBuf, InBuf() AS BYTE, TempUsed

