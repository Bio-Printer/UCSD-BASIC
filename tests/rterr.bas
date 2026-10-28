' a subscript out of range in a SUB
DIM SHARED x(25)

SUB fill (n)
    DIM a
    FOR a = 1 TO n
        PRINT a; CHR$(13);
        x(a) = a
    NEXT a
END SUB

PRINT "start"
fill 30
PRINT "not reached"
