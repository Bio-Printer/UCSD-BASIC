' B2SYM -- the symbol table's globals (#INCLUDE "B2SYM": B2DECL, B2NAME, B2EXPR's own small one)

' ---- the symbol table (B2DECL, B2NAME: B2SYMT)
COMMON SHARED NSym, NModSym, NPar, CurSeg, NSegName, SymCap, ParCap
COMMON SHARED SName$(), SKind() AS BYTE, SType() AS BYTE, SCls() AS BYTE
COMMON SHARED SOff(), SFlags() AS BYTE, SScope() AS BYTE, SNext()
COMMON SHARED SAux(), SAux2(), SSeg() AS BYTE, HashHead()
COMMON SHARED PType() AS BYTE, PFlg() AS BYTE, SegName$(), DefType()
COMMON SHARED StaticWords, DeclName$, DeclFlags, ParName$(), ParFlags(), NData
' a string's LENGTH (0: BASIC's 255): the last declaration's (DeclType);
' B2DECL's and B2NAME's of the symbols and parameters that have one, a list
' (few have: SymLen, ParLen -- a word a symbol was 1,300 words in Z80 mode):
' SLx the symbol (PLx the parameter), SLv its LENGTH; B2EXPR's statement's
' table SLen, PLen (a word each)
COMMON SHARED DeclLen, SLx(), SLv(), NSL, SLCap, PLx(), PLv(), NPL, PLCap, SLen(), PLen()

