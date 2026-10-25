' DATA, READ, RESTORE; WRITE
DEFINT A-Z
READ a, b$, c!, d#
PRINT a; b$; c!; d#
FOR i = 1 TO 3: READ n$: PRINT "["; n$; "]";: NEXT: PRINT
RESTORE again
READ x, y: PRINT x + y
RESTORE
READ a: PRINT a
WRITE 1, "two", 3.5, -4
DATA 10, "hello, world", 2.5, 1.25D0
DATA plain text ,  " quoted ", last
again:
DATA 7, 8
