' GUESS -- guess the number: INPUT, RND, a DO loop
DEFINT A-Z
RANDOMIZE TIMER
secret = INT(RND * 100) + 1
tries = 0
PRINT "I am thinking of a number from 1 to 100."
DO
    INPUT "Your guess"; g
    tries = tries + 1
    IF g < secret THEN
        PRINT "Higher."
    ELSEIF g > secret THEN
        PRINT "Lower."
    END IF
LOOP UNTIL g = secret
PRINT "Right! You took"; tries; "tries."
