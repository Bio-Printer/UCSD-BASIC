' arrays: one and more dimensions (from 0), strings, bytes, REDIM, ERASE, UBOUND
DEFINT A-Z
DIM a(5), m(2, 3), s$(3), b(10) AS BYTE, d#(2), cube(1, 2, 3)
FOR i = 0 TO 5: a(i) = i * 10: NEXT
FOR i = 0 TO 2: FOR j = 0 TO 3: m(i, j) = i * 10 + j: NEXT j, i
s$(0) = "zero": s$(3) = "three": s$(1) = s$(0) + "+one"
FOR i = 0 TO 10: b(i) = i * 30: NEXT
d#(1) = 1 / 7#
cube(1, 2, 3) = 123: cube(0, 1, 2) = 12
PRINT a(0); a(5); m(2, 3); m(1, 2); s$(0); " "; s$(1); " "; s$(3); "["; s$(2); "]"
PRINT b(9); b(10); d#(1); cube(1, 2, 3) + cube(0, 1, 2)
PRINT UBOUND(a); UBOUND(m, 2); LBOUND(a)
REDIM a(2): PRINT a(2); UBOUND(a)
n = 4: REDIM PRESERVE s$(n): PRINT s$(3); UBOUND(s$)
ERASE m
PRINT Total(a(), 2)
DIM big(1000)
FOR i = 0 TO 1000: big(i) = i: NEXT
t = 0: FOR i = 0 TO 1000 STEP 100: t = t + big(i): NEXT: PRINT t
FUNCTION Total (v(), n)
  DIM i, s
  v(0) = 7
  FOR i = 0 TO n: s = s + v(i): NEXT
  Total = s
END FUNCTION
