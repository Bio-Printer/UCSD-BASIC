' MANDEL -- the Mandelbrot set in characters (SINGLE arithmetic)
DEFINT A-Z
CONST W = 64, H = 24, MAXIT = 30
shade$ = " .:-=+*#%@"
FOR row = 0 TO H - 1
    y# = (row - H / 2) * 2.4 / H
    l$ = ""
    FOR col = 0 TO W - 1
        x# = (col - W * 0.65) * 3.2 / W
        zr# = 0: zi# = 0
        it = 0
        DO WHILE it < MAXIT AND zr# * zr# + zi# * zi# < 4
            t# = zr# * zr# - zi# * zi# + x#
            zi# = 2 * zr# * zi# + y#
            zr# = t#
            it = it + 1
        LOOP
        IF it = MAXIT THEN
            l$ = l$ + "@"
        ELSE
            l$ = l$ + MID$(shade$, it MOD 9 + 1, 1)
        END IF
    NEXT col
    PRINT l$
NEXT row
