' CHAIN's third program: no options, and the memory is all its own
DEFINT A-Z
PRINT "chain3: ["; COMMAND$; "]"
IF FRE(0) > 20000 THEN PRINT "chain3: memory free" ELSE PRINT "chain3: little memory"; FRE(0)
END 3
