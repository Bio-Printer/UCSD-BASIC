' strings: functions, comparison, concatenation, MID$ statement
a$ = "Hello": b$ = "World"
c$ = a$ + ", " + b$ + "!"
PRINT c$; LEN(c$)
PRINT LEFT$(c$, 5); "|"; RIGHT$(c$, 6); "|"; MID$(c$, 8, 5); "|"; MID$(c$, 8)
PRINT INSTR(c$, "o"); INSTR(6, c$, "o"); INSTR(c$, "xyz")
PRINT UCASE$(c$); " "; LCASE$(c$)
PRINT "["; LTRIM$("   x  "); "]["; RTRIM$("   x  "); "]["; TRIM$("  x  "); "]"
PRINT ASC("A"); ASC("ABC", 2); CHR$(66); STRING$(3, "*"); STRING$(2, 65); "["; SPACE$(3); "]"
IF a$ < b$ THEN PRINT "less" ELSE PRINT "not less"
IF "abc" = "abc" AND "ab" < "abc" THEN PRINT "equal ok"
MID$(c$, 1, 5) = "Jelly"
PRINT c$
s$ = ""
FOR i = 1 TO 10
  s$ = s$ + CHR$(64 + i)
NEXT
PRINT s$, LEN(s$)
d$ = s$: s$ = "changed": PRINT d$; " "; s$
SWAP d$, s$: PRINT d$; " "; s$
