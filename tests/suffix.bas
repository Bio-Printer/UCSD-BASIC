' the type suffixes: % INTEGER, # SINGLE (and none), ! DOUBLE, $ STRING, ~ BYTE
d! = 1# / 3#
d! = d! + 1! / 3!
s# = 1 / 3
x = 1 / 3
PRINT d!; s#; x; LEN(MKD$(d!)); LEN(MKS$(s#)); LEN(MKS$(x))
PRINT 1.1234567891!; 1.1234567891#; 1.1234567891
b~ = 200
b~ = b~ + 100
PRINT b~
DIM c AS BYTE
c = 65
PRINT c; c~
DIM a~(3)
a~(1) = 511
PRINT a~(1)
n% = 7: n# = 7.5: n! = 7.25: n$ = "seven"
PRINT n%; n#; n!; n$; n
