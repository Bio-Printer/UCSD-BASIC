' files in sub-volumes: VOL:/A/NAME, VOL:A\B\NAME, two written at once,
' a file replaced, APPEND, BINARY, KILL, errors, a full sub-volume
DEFINT A-Z
OPEN "#5:/A/B/HELLO.TEXT" FOR INPUT AS #1
LINE INPUT #1, l$
CLOSE #1
PRINT l$
OPEN "#5:/A/T1.TEXT" FOR OUTPUT AS #1
FOR i = 1 TO 3: PRINT #1, "first"; i: NEXT
CLOSE #1
OPEN "#5:a\b\t2.text" FOR OUTPUT AS #1
PRINT #1, "in B"
CLOSE #1
OPEN "#5:/T0.TEXT" FOR OUTPUT AS #1
PRINT #1, "on the volume"
CLOSE #1
' two at once in A, 400 lines each (more than one page)
OPEN "#5:/A/X1.TEXT" FOR OUTPUT AS #1
OPEN "#5:/A/X2.TEXT" FOR OUTPUT AS #2
FOR i = 1 TO 400
  PRINT #1, "x1 line"; i
  PRINT #2, "x2 line"; i; "of the second file"
NEXT
CLOSE
FOR f = 1 TO 2
  OPEN "#5:/A/X" + LTRIM$(STR$(f)) + ".TEXT" FOR INPUT AS #1
  n = 0: bad = 0
  DO WHILE NOT EOF(1)
    LINE INPUT #1, l$
    n = n + 1
    IF f = 1 AND l$ <> "x1 line" + STR$(n) + " " THEN bad = bad + 1
    IF f = 2 AND l$ <> "x2 line" + STR$(n) + " of the second file" THEN bad = bad + 1
  LOOP
  CLOSE #1
  PRINT "X"; f; n; "lines"; bad; "wrong"
NEXT
' replaced, then appended to
OPEN "#5:/A/T1.TEXT" FOR OUTPUT AS #1
PRINT #1, "second"
CLOSE #1
OPEN "#5:/A/T1.TEXT" FOR APPEND AS #1
PRINT #1, "appended"
CLOSE #1
FOR k = 1 TO 3
  SELECT CASE k
  CASE 1: f$ = "#5:/A/T1.TEXT"
  CASE 2: f$ = "#5:A/B/T2.TEXT"
  CASE 3: f$ = "#5:T0.TEXT"
  END SELECT
  OPEN f$ FOR INPUT AS #1
  DO WHILE NOT EOF(1)
    LINE INPUT #1, l$
    PRINT f$; ": "; l$
  LOOP
  CLOSE #1
NEXT
' a byte file
OPEN "#5:/A/B/DATA.BIN" FOR BINARY AS #3
FOR i = 1 TO 700: PUT #3, , i: NEXT
CLOSE #3
OPEN "#5:/A/B/DATA.BIN" FOR BINARY AS #3
sum = 0
FOR i = 1 TO 700: GET #3, , w: IF w = i THEN sum = sum + 1
NEXT
CLOSE #3
PRINT "words read back"; sum
KILL "#5:/A/X2.TEXT"
ON ERROR RESUME NEXT
OPEN "#5:/A/X2.TEXT" FOR INPUT AS #1
PRINT "killed: err"; ERR
OPEN "#5:/NOSUCH/X.TEXT" FOR OUTPUT AS #1
PRINT "no sub-volume: err"; ERR
OPEN "#5:/A/NOSUCH.TEXT" FOR INPUT AS #1
PRINT "no file: err"; ERR
KILL "#5:/A/NOSUCH.TEXT"
PRINT "kill: err"; ERR
' more than B has room for
OPEN "#5:/A/B/BIG.TEXT" FOR OUTPUT AS #1
FOR i = 1 TO 2000
  PRINT #1, "a line of the file that does not fit"; i
  IF ERR THEN EXIT FOR
NEXT
PRINT "full: err"; ERR; "after line"; i
CLOSE #1
ON ERROR GOTO 0
PRINT "done"
