' B2NODE -- B2EXPR's expression nodes (#INCLUDE "B2NODE")

' ---- B2EXPR's: one statement's expression nodes, and the operands they
' name (its symbols: SKind ... above, STx$ their names in messages)
COMMON SHARED NNode, NOp() AS BYTE, NTy() AS BYTE, NA(), NB(), NV(), NX()
COMMON SHARED NN(), NS$(), NIsBool() AS BYTE, PreNode, ArgCount, HiNode, STx$()
CONST NICON = 1, NRCON = 2, NSCON = 3, NVAR = 4, NELEM = 5, NCALL = 6
CONST NBUILT = 7, NNEG = 8, NNOT = 9, NBIN = 10, NCONV = 11, NBOOL = 12
CONST NADDR = 13
COMMON SHARED NodeCap

