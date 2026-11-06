' PRINT USING and USING$: QuickBASIC's format (B2ONLY)
DEFINT A-Z
PRINT USING "###.##"; 3.14159
PRINT USING "###.##"; -3.14159
PRINT USING "##"; 7; 12; 345
PRINT USING ".##"; .5
PRINT USING "#,###,###"; 1234567
PRINT USING "+##.#"; 2.5; -2.5
PRINT USING "##.#-"; 2.5; -2.5
PRINT USING "$$###.##"; 12.5
PRINT USING "**###"; 42
PRINT USING "**$##.##"; 3.75
PRINT USING "##.##^^^^"; 12345.678
PRINT USING "Item ! costs \  \ and & _# done"; "Apple"; "abcdefgh"; "all of it"
PRINT USING "[##]"; 1; 2; 3
PRINT USING "x=### "; 5;
PRINT "next"
a$ = USING$("##.##", 2.345)
PRINT a$; "|"; LEN(a$)
PRINT USING$("&-&", "ab", "cd"); USING$("###", 99)
n = 3: d! = 1.5
PRINT USING "### ####.###"; n; d!
OPEN "U.TXT" FOR OUTPUT AS #1
PRINT #1, USING "##.#"; 9.25
CLOSE #1
OPEN "U.TXT" FOR INPUT AS #1
LINE INPUT #1, l$
CLOSE #1
KILL "U.TXT"
PRINT "file:"; l$
