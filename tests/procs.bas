' SUB and FUNCTION: recursion, BYREF, arrays, strings, STATIC, SHARED
DEFINT A-Z
DECLARE FUNCTION Fib (n)
DIM SHARED total
DIM a(10)
FOR i = 0 TO 10: a(i) = i * i: NEXT
PRINT Fib(15); SumArr(a(), 10)
x = 5: Twice x: PRINT x
y = 5: Twice (y): PRINT y
PRINT Rev$("abcdef"); " "; Rev$("")
FOR i = 1 TO 3: Counter: NEXT
AddTotal 5: AddTotal 7: PRINT total
s$ = "keep": Modify s$: PRINT s$
r$ = "x": ByRefS r$: PRINT r$
PRINT Pad$("ab", 5); "|"
PRINT Max(3, 9), Max(-2, -8)

FUNCTION Fib (n)
  IF n < 2 THEN Fib = n: EXIT FUNCTION
  Fib = Fib(n - 1) + Fib(n - 2)
END FUNCTION

FUNCTION SumArr (v(), n)
  DIM i, s
  FOR i = 0 TO n: s = s + v(i): NEXT
  SumArr = s
END FUNCTION

SUB Twice (BYREF v)
  v = v * 2
END SUB

FUNCTION Rev$ (s$)
  DIM r$, i
  FOR i = LEN(s$) TO 1 STEP -1
    r$ = r$ + MID$(s$, i, 1)
  NEXT
  Rev$ = r$
END FUNCTION

SUB Counter
  STATIC c
  c = c + 1
  PRINT "call"; c
END SUB

SUB AddTotal (n)
  total = total + n
END SUB

SUB Modify (s$)
  s$ = s$ + " changed"
END SUB

SUB ByRefS (BYREF s$)
  s$ = s$ + "yz"
END SUB

FUNCTION Pad$ (s$, n)
  RETURN s$ + SPACE$(n - LEN(s$))
END FUNCTION

FUNCTION Max (a, b)
  IF a > b THEN RETURN a
  RETURN b
END FUNCTION
