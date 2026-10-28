' recursion 50 deep with strings and numbers; GOSUB 50 deep; FOR 30 deep
DEFINT A-Z
PRINT Depth$(50, "")
PRINT Sum!(50)
g = 0: GOSUB 100: PRINT "gosubs"; g
DIM v(30)
FOR a1 = 1 TO 1: FOR a2 = 1 TO 1: FOR a3 = 1 TO 1: FOR a4 = 1 TO 1: FOR a5 = 1 TO 1
FOR a6 = 1 TO 1: FOR a7 = 1 TO 1: FOR a8 = 1 TO 1: FOR a9 = 1 TO 1: FOR b0 = 1 TO 1
FOR b1 = 1 TO 1: FOR b2 = 1 TO 1: FOR b3 = 1 TO 1: FOR b4 = 1 TO 1: FOR b5 = 1 TO 1
FOR b6 = 1 TO 1: FOR b7 = 1 TO 1: FOR b8 = 1 TO 1: FOR b9 = 1 TO 1: FOR c0 = 1 TO 1
FOR c1 = 1 TO 1: FOR c2 = 1 TO 1: FOR c3 = 1 TO 1: FOR c4 = 1 TO 1: FOR c5 = 1 TO 1
FOR c6 = 1 TO 1: FOR c7 = 1 TO 1: FOR c8 = 1 TO 1: FOR c9 = 1 TO 1: FOR d0 = 1 TO 2
n = n + 1
NEXT d0, c9, c8, c7, c6, c5, c4, c3, c2, c1, c0, b9, b8, b7, b6, b5, b4, b3, b2, b1, b0
NEXT a9, a8, a7, a6, a5, a4, a3, a2, a1
PRINT "for"; n
END
100 g = g + 1: IF g < 50 THEN GOSUB 100
RETURN
FUNCTION Depth$ (n, s$)
  IF n = 0 THEN Depth$ = s$: EXIT FUNCTION
  Depth$ = Depth$(n - 1, s$ + CHR$(48 + n MOD 10))
END FUNCTION
FUNCTION Sum! (n)
  IF n = 0 THEN RETURN 0
  RETURN n + Sum!(n - 1)
END FUNCTION
