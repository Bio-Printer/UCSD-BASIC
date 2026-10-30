' CONSTs BCLEX puts in as integers (A, B, D%, E, F, G, and C's A), and where it must not
' (C, a sum; S$, R, H#; L, the GOSUB's label: a label of a CONST's name)
CONST A = 5, B = -3, C = A + 1, D% = &H10, E = -32768, F = A, G = B
CONST S$ = "x", R = 1.5, H# = 2, L = 3
DIM SHARED T(A)

SUB Local2 ()
    DIM K
    K = B * 2
    PRINT "local"; B; K
END SUB

FUNCTION Twice (x)
    Twice = x * 2
END FUNCTION

PRINT A; B; C; D%; E; F; G; S$; R; H#
Local2
PRINT "after"; B
T(A) = Twice(A)
PRINT T(5); UBOUND(T)
SELECT CASE C
CASE A: PRINT "a"
CASE C: PRINT "c"
END SELECT
GOSUB L
PRINT -A; A ^ 2; 2 ^ B; A MOD 3; E \ 2
END
L:
PRINT "label L"
RETURN
