' out of memory: the program's strings are given back, so the library
' still finds where it was (deep in the library: _SASG, _MALLOC, _NEWBLK)
DIM a$(1000), i
PRINT "start"
FOR i = 1 TO 1000
    a$(i) = SPACE$(250)
NEXT i
PRINT "not reached"
