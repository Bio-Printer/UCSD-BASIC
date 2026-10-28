' bitwise & (and) and | (or) of INTEGERs and BYTEs; & still joins strings
DEFINT A-Z
a = 12: b = 10
PRINT a & b; a | b; 12 & 10; 12 | 10
c~ = 240: d~ = 60
PRINT c~ & d~; c~ | d~; c~ & 15
PRINT &HFF & &H0F; &H0F | &HF0
flags = 5
IF flags & 4 = 4 THEN PRINT "bit 2 set"
IF flags & 2 THEN PRINT "wrong" ELSE PRINT "bit 1 clear"
PRINT 1 | 2 & 3
s$ = "ab" & "cd"
PRINT s$
h = 3: x = a&h
PRINT x; a&b
PRINT -1 & 255; 256 | -32768
y# = 2.5
PRINT y# + 1
