' a run-time error in the library's OPEN (segment RTSELDOM), called from a
' procedure in a segment of its own: where it was is the procedure's line
SEGMENT TWO
SUB OpenIt (f$)
    PRINT "opening "; f$
    OPEN f$ FOR INPUT AS #1
    PRINT "not reached"
END SUB

SEGMENT
PRINT "start"
OpenIt "NOSUCH.TXT"
