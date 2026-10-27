' compile errors: calls, arrays, labels (pass 3 only, 2)
DECLARE SUB s1 (a)
DECLARE FUNCTION f1 (a, b)
DECLARE SUB s2 (x())
DIM x(3), y$(2)
s2 y$()
s2 z
z = x(1, 2)
z = q(1)
s1 = 3
z = s1
lab:
lab:
ON ERROR GOTO 5
GOTO nolabel
END
SUB s1 (a)
END SUB
FUNCTION f1 (a, b)
  f1 = a
END FUNCTION
SUB s2 (x())
END SUB
