' CHAIN's second program: its COMMAND$, the file the first one left open,
' then CHAIN with a string variable
DEFINT A-Z
PRINT "chain2: ["; COMMAND$; "]"
OPEN "CHAINED.DAT" FOR INPUT AS #1
LINE INPUT #1, l$
CLOSE #1
PRINT "chain2 reads: "; l$
next$ = "#5:CHAIN3"
CHAIN next$
