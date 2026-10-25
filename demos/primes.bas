' PRIMES -- the sieve of Eratosthenes: the primes below 2000
DEFINT A-Z
CONST LIMIT = 2000
DIM composite(LIMIT)
count = 0
FOR n = 2 TO LIMIT
    IF NOT composite(n) THEN
        count = count + 1
        FOR m = n * 2 TO LIMIT STEP n
            composite(m) = -1
        NEXT m
    END IF
NEXT n
PRINT "There are"; count; "primes below"; LIMIT
PRINT "The first 50:"
k = 0
FOR n = 2 TO LIMIT
    IF NOT composite(n) THEN
        PRINT RIGHT$("    " + STR$(n), 5);
        k = k + 1
        IF k MOD 10 = 0 THEN PRINT
        IF k = 50 THEN EXIT FOR
    END IF
NEXT n
