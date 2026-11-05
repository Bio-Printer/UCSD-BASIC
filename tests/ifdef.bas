' #DEFINE, #UNDEF, #IFDEF, #IFNDEF, #ELSE, #ENDIF: which lines are compiled
#DEFINE ONE
#IFDEF ONE
PRINT "one"
#ELSE
PRINT "not one"
#ENDIF
#IFNDEF TWO
PRINT "no two"
#IFDEF ONE
PRINT "nested one"
#ELSE
PRINT "nested not one"
#ENDIF
#ELSE
PRINT "two"
#ENDIF
#UNDEF ONE
#IFDEF ONE
this line is not BASIC at all: it is not compiled
#ELSE
PRINT "one undefined"
#ENDIF
' each compiler defines its own name: B2 or BC
#IFDEF B2
PRINT "a compiler"
#ENDIF
#IFDEF BC
PRINT "a compiler"
#ENDIF
#IFDEF B2
#IFDEF BC
PRINT "two compilers?"
#ENDIF
#ENDIF
