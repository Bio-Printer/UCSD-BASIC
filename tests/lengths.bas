' LENGTH: strings of a declared length, short and long (B2ONLY)
DEFINT A-Z
DIM a(5) AS STRING LENGTH 4, s AS STRING LENGTH 6, n$(2) LENGTH 3
DIM big AS STRING LENGTH 4096
s = "abcdefgh": PRINT s; LEN(s)
a(1) = "hello": a(2) = "hi": PRINT a(1); "|"; a(2); "|"; a(3); "|"; LEN(a(1))
n$(0) = "xyzzy": PRINT n$(0); LEN(n$(1))
big = STRING$(300, "x") + STRING$(300, "y")
PRINT LEN(big); " "; MID$(big, 299, 4); " "; RIGHT$(big, 2)
big = big + big: PRINT LEN(big)
FOR i = 1 TO 4: big = big + big: NEXT: PRINT LEN(big)
PRINT INSTR(big, "yx"); INSTR(500, big, "yx"); ASC(big, 4096)
d$ = big: PRINT LEN(d$)
SWAP a(1), s: PRINT a(1); " "; s
MID$(a(2), 1, 1) = "H": PRINT a(2)
PRINT UCASE$(a(1)); LEFT$(big, 3); a(1) + a(2)
PRINT a(1) < a(2); a(1) = "abcd"; big > d$
PRINT Twice$(a(1)); " "; Twice$("123456")
Show a()
REDIM PRESERVE a(10): a(9) = "nine!": PRINT a(1); a(9); UBOUND(a)
OPEN "LONG.TXT" FOR OUTPUT AS #1
PRINT #1, LEFT$(big, 700): PRINT #1, "short"
CLOSE #1
big = ""
OPEN "LONG.TXT" FOR INPUT AS #1
LINE INPUT #1, big: LINE INPUT #1, s
CLOSE #1
PRINT LEN(big); " "; MID$(big, 298, 6); " "; s
big = SPACE$(1000) + "end": PRINT LEN(LTRIM$(big)); LEN(big)
KILL "LONG.TXT"
PRINT "done"

FUNCTION Twice$ (t AS STRING LENGTH 3)
    Twice$ = t + t
END FUNCTION

SUB Show (v() AS STRING LENGTH 4)
    PRINT "show "; v(1); v(2)
END SUB
