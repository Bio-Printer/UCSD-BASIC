' STATLIB -- the statistics FUNCTIONs STATS uses: a module of its own,
' compiled to STATLIB.OBJ and linked with STATS
DEFINT A-Z

FUNCTION Mean# (x#(), n)
    DIM s#, i
    FOR i = 0 TO n - 1
        s# = s# + x#(i)
    NEXT i
    Mean# = s# / n
END FUNCTION

FUNCTION StdDev# (x#(), n)
    DIM m#, s#, i
    m# = Mean#(x#(), n)
    FOR i = 0 TO n - 1
        s# = s# + (x#(i) - m#) * (x#(i) - m#)
    NEXT i
    StdDev# = SQR(s# / n)
END FUNCTION

' an insertion sort
SUB SortD (x#(), n)
    DIM i, j, t#
    FOR i = 1 TO n - 1
        t# = x#(i)
        j = i - 1
        DO WHILE j >= 0
            IF x#(j) <= t# THEN EXIT DO
            x#(j + 1) = x#(j)
            j = j - 1
        LOOP
        x#(j + 1) = t#
    NEXT i
END SUB
