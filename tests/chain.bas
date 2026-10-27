' CHAIN: the program ends and another runs, with the rest of the line as
' its COMMAND$; a literal and a string variable; errors
DEFINT A-Z
PRINT "chain: first"
OPEN "CHAINED.DAT" FOR OUTPUT AS #1
PRINT #1, "written before the CHAIN"
ON ERROR RESUME NEXT
CHAIN "#5:NOSUCH"
PRINT "no such program: err"; ERR
CHAIN "#5:CHAIN.BAS."
PRINT "not a code file: err"; ERR
CHAIN ""
PRINT "no name: err"; ERR
CHAIN "#5:CHAIN2 " + STRING$(80, "x")
PRINT "too long: err"; ERR
ON ERROR GOTO 0
CHAIN "#5:CHAIN2 one, two  three"
PRINT "not reached"
