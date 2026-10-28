' STATS -- a program of two modules: this one and STATLIB (its FUNCTIONs).
' Built with
'     BC -C BASIC:/DEMO/STATLIB
'     BC -C BASIC:/DEMO/STATS
'     BC -L BASIC:/DEMO/STATS=BASIC:/DEMO/STATS,BASIC:/DEMO/STATLIB
' (DEMOS.TEXT does it).  The numbers are the DATA below.
DEFINT A-Z
DECLARE FUNCTION Mean! (x!(), n)
DECLARE FUNCTION StdDev! (x!(), n)
DECLARE SUB SortD (x!(), n)

DIM x!(99)
n = 0
DO
    READ v!
    IF v! < 0 THEN EXIT DO
    x!(n) = v!
    n = n + 1
LOOP
PRINT n; "numbers"
PRINT "mean     "; Mean!(x!(), n)
PRINT "std. dev."; StdDev!(x!(), n)
SortD x!(), n
PRINT "smallest "; x!(0)
PRINT "median   "; x!(n \ 2)
PRINT "largest  "; x!(n - 1)

DATA 12.5, 7, 3.25, 19, 8, 11.75, 4, 15, 9.5, 6
DATA -1
