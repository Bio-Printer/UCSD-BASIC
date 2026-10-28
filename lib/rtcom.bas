' RTCOM -- shared by the modules of the run-time library (BASLIB)
'
' The library is BASIC too.  Its procedures take and return strings as
' pointers (INTEGER): a string is a length byte and its characters (a
' Pascal string), 0 is the empty string.  A string variable holds a block
' of the heap it owns; a temporary (a statement's intermediate strings) is
' in the arena _TBASE.._TEND, given back after the statement (the compiler
' saves _TTOP when a procedure starts and puts it back).  What is neither
' (a constant in the code, a temporary passed as a BYVAL argument) is not
' owned: a variable that holds one gets a block of its own when assigned.
DEFINT A-Z

' ---- the arena, the heap, the GOSUB stack (the compiler uses _TTOP, _GSSP)
COMMON SHARED _TTOP, _TBASE, _TEND, _GSSP, _GSBASE
COMMON SHARED _HEAPLO, _HEAPTOP, _FREETAB, _BIGFREE
' ---- errors: ON ERROR RESUME NEXT, ERR
COMMON SHARED _ERRTRAP, _ERRCODE
' ---- the console: its output buffer, column; the INPUT line
COMMON SHARED _CONBUF, _CONLEN, _CONCOL, _INBUF, _INPOS
' ---- the files: 16 entries of 16 words (channel 1..15)
COMMON SHARED _FTAB
' ---- the command line and the shell's path (CD) Tiny-C's shell gave (Pascal
' strings; 0: none); a file name as opened (on that path) and its size, [n]
' or [*], which only the operating system sees
COMMON SHARED _CMDLINE, _SVPWD, _PATHBUF, _SIZESPEC
' ---- arrays: DIM's bounds, an element's indexes
COMMON SHARED _ABUF, _NABND, _AIXB, _NAIX
' ---- scratch (number formatting), the random seed
COMMON SHARED _SCRATCH, _SEED!, _MINFREE

CONST FFL = 0, FFIB = 2, FBUF = 4, FBLK = 6, FPOS = 8, FLEN = 10, FBSZ = 12
CONST FDLE = 14, FLST = 16, FCOL = 18, FUNG = 20
' (a file in a sub-volume: RTSUBV)
CONST FSVU = 22, FSVF = 24, FSVR = 26, FSVH = 28, FSVB = 30
CONST FREAD = 1, FWRITE = 2, FTEXT = 4, FEOF = 8, FDIRTY = 16, FNEW = 32
CONST FCON = 64, FERR = 128, FZEND = 256

DECLARE SUB _RTERR (code)
DECLARE SUB _IOERR (code)
DECLARE FUNCTION _ULT (a, b)
DECLARE FUNCTION _MALLOC (nbytes)
DECLARE SUB _MFREE (p)
DECLARE FUNCTION _OWNED (p)
DECLARE FUNCTION _TALLOC (n)
DECLARE FUNCTION _STMP (p)
DECLARE FUNCTION _SLEN (p)
DECLARE SUB _SASG (slot, v)
DECLARE SUB _CONPUT (c)
DECLARE SUB _CONFLUSH ()
DECLARE SUB _PSTR (ch, s)
DECLARE SUB _PNL (ch)
DECLARE FUNCTION _FENTRY (ch)
DECLARE SUB _FPUTC (ch, c)
DECLARE FUNCTION _FOPENED (ch)
DECLARE FUNCTION _FGETC (ch)
DECLARE SUB _CLOSE (ch)
DECLARE FUNCTION _CONGETC ()
DECLARE FUNCTION _ISTR (v, lead)
DECLARE FUNCTION _VAL! (s)
DECLARE FUNCTION _FMTD (d!, prec)
DECLARE SUB _HALT (code)
DECLARE SUB _PSPC (ch, n)
DECLARE FUNCTION _SVOPEN (e, name, mode)
DECLARE FUNCTION _SVIO (e, nblocks, b, rd)
DECLARE FUNCTION _SVCLOSE (e)
DECLARE FUNCTION _SVKILL (name)
