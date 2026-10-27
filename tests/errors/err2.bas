' compile errors: procedures and declarations
DECLARE SUB s1 (a)
DECLARE FUNCTION f1 (a, b)
SUB s1 (a, b)
END SUB
FUNCTION f1 (a)
  f1 = 1
  SHARED nothere
  DIM SHARED z
END FUNCTION
SUB s2 ()
  SUB inner
END SUB
SUB s1 (a)
END SUB
SUB s3$ ()
END SUB
DIM x(3)
x = 1
y = x(1, 2)
z = f1(1)
z = LEN()
z = LEN(1, 2)
z = MID$("a")
z = INSTR()
z = FRE()
z = OSVAR(z)
z = SADD()
w$ = STR$()
CALL nosuch
CALL s1(1, 2, 3)
a% AS INTEGER
DEFINT 1
ON ERROR GOTO lab
lab:
lab:
s1 = 3
z = s1
END
