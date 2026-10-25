' HANOI -- the towers of Hanoi: a recursive SUB
DEFINT A-Z
DIM SHARED moves

SUB Move (n, from$, to$, via$)
    IF n = 0 THEN EXIT SUB
    Move n - 1, from$, via$, to$
    moves = moves + 1
    PRINT "Move disc"; n; "from "; from$; " to "; to$
    Move n - 1, via$, to$, from$
END SUB

Move 4, "A", "C", "B"
PRINT moves; "moves"
