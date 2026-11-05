' B2SYM -- the symbol table's globals (#INCLUDE "B2SYM": B2DECL, B2NAME, B2EXPR's own small one)

' ---- the symbol table (B2DECL, B2NAME: B2SYMT)
COMMON SHARED NSym, NModSym, NPar, CurSeg, NSegName, SymCap, ParCap
COMMON SHARED SName$(), SKind() AS BYTE, SType() AS BYTE, SCls() AS BYTE
COMMON SHARED SOff(), SFlags() AS BYTE, SScope() AS BYTE, SNext()
COMMON SHARED SAux(), SAux2(), SSeg() AS BYTE, HashHead()
COMMON SHARED PType() AS BYTE, PFlg() AS BYTE, SegName$(), DefType()
COMMON SHARED StaticWords, DeclName$, DeclFlags, ParName$(), ParFlags(), NData

