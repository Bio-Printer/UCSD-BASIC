' control structures
DEFINT A-Z
FOR i = 1 TO 10 STEP 3: PRINT i;: NEXT: PRINT
FOR i = 5 TO 1 STEP -2: PRINT i;: NEXT i: PRINT
s = -1: FOR i = 3 TO 0 STEP s: PRINT i;: NEXT: PRINT
FOR x! = 0 TO 1 STEP .25: PRINT x!;: NEXT: PRINT
i = 0
DO WHILE i < 3: i = i + 1: PRINT "w"; i;: LOOP: PRINT
DO: i = i - 1: PRINT "u"; i;: LOOP UNTIL i = 0: PRINT
WHILE i < 2: i = i + 1: PRINT "W"; i;: WEND: PRINT
FOR i = 1 TO 3
  FOR j = 1 TO 3
    IF j = 2 THEN CONTINUE FOR
    IF i = 3 THEN EXIT FOR
    PRINT i * 10 + j;
  NEXT j
NEXT i
PRINT
FOR i = 1 TO 2: FOR j = 1 TO 2: PRINT i; j;: NEXT j, i: PRINT
FOR i = 1 TO 6
  SELECT CASE i
  CASE 1: PRINT "one";
  CASE 2, 3: PRINT "two-three";
  CASE 4 TO 5: PRINT "four-five";
  CASE ELSE: PRINT "other";
  END SELECT
NEXT: PRINT
n$ = "beta"
SELECT CASE n$
CASE "alpha": PRINT "A"
CASE IS < "c": PRINT "before c"
CASE ELSE: PRINT "?"
END SELECT
IF i = 7 THEN
  PRINT "seven"
ELSEIF i = 6 THEN
  PRINT "six"
ELSE
  PRINT "else"
END IF
k = 2
ON k GOTO 100, 200, 300
100 PRINT "100": GOTO 400
200 PRINT "200"
300 PRINT "300"
400 GOSUB sub1: GOSUB sub1
ON 2 GOSUB sub1, sub2
PRINT "done"
END
sub1: PRINT "in sub1": RETURN
sub2: PRINT "in sub2": RETURN
