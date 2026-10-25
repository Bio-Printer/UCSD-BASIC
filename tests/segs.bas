' code segments: procedures in other segments, called from each other
DEFINT A-Z
PRINT "main"; A1(3)
B1 "hello"
PRINT "end"
SEGMENT ALPHA
FUNCTION A1 (n)
  A1 = n * 2 + B2(n)
END FUNCTION
SEGMENT BETA
SUB B1 (s$)
  PRINT "B1 "; s$; A1(1)
END SUB
FUNCTION B2 (n)
  B2 = n + 100
END FUNCTION
