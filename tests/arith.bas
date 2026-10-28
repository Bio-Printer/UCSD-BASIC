' integers, reals, doubles: arithmetic, conversion, printing
DEFINT I-N
i = 7: j = -3
PRINT i + j; i - j; i * j; i \ j; i MOD j; -17 \ 5; -17 MOD 5
PRINT 32767 + 1 = -32768, &HFF, &H7FFF, -32768
PRINT i / 2, 1 / 3, 2 ^ 10, 10 / 4
x# = 1.5: y! = 1.0! / 3
PRINT x# * 2, y!, CDBL(x#) + y!
PRINT CINT(2.5), CINT(-2.5), FIX(-3.7), INT(-3.7), INT(3.7), ABS(-5), SGN(-2.5)
PRINT SQR(16), 3.14159 * 2, 1E10, 1.5E-5, 123456789!
PRINT (5 > 3) + 0, (5 < 3), NOT 0, 5 AND 3, 5 OR 3, 5 XOR 3
k = 10: k = k * k: PRINT k, k \ 7, k MOD 7
PRINT STR$(42); STR$(-42); "|"; HEX$(255); "|"; HEX$(-1)
PRINT VAL("12.5") + 1, VAL("  -3"), VAL("&H10")
