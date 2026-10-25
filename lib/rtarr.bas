' RTARR -- the run-time library: arrays
'
' An array variable (its slot) holds 0 or a heap block: the number of
' dimensions, the element's bytes (+ 256 for strings), each dimension's
' count (bound + 1: every index starts at 0), then the elements.
#INCLUDE "RTCOM"

' DIM's bounds, one at a time
SUB _ABND (n)
    IF _NABND >= 8 THEN _RTERR 9
    POKE _ABUF + _NABND * 2, n
    _NABND = _NABND + 1
END SUB

' the strings of an array given back (from element k0 on)
SUB _AFREESTR (p, k0)
    DIM nd, total, i, a, v
    nd = PEEK(p)
    total = 1
    FOR i = 1 TO nd
        total = total * PEEK(p + 2 + i * 2)
    NEXT i
    a = p + 4 + nd * 2
    FOR i = k0 TO total - 1
        v = PEEK(a + i * 2)
        IF _OWNED(v) THEN _MFREE v
    NEXT i
END SUB

SUB _AFREE (slot)
    DIM p
    p = PEEK(slot)
    IF p = 0 THEN EXIT SUB
    IF PEEK(p + 2) AND 256 THEN _AFREESTR p, 0
    _MFREE p
    POKE slot, 0
END SUB

' DIM / REDIM: flags 1 = strings, 2 = PRESERVE (the elements kept)
SUB _ADIM (slot, esize, flags, nd)
    DIM total, i, n, bytes, hdr, p, old, ob, oe
    IF nd <> _NABND THEN _RTERR 9
    total = 1
    FOR i = 0 TO nd - 1
        n = PEEK(_ABUF + i * 2) + 1
        IF n <= 0 THEN _RTERR 9
        IF total > 32000 \ n THEN _RTERR 7
        total = total * n
    NEXT i
    IF total > (32000 - 20) \ esize THEN _RTERR 7
    hdr = 4 + nd * 2
    bytes = total * esize
    p = _MALLOC(hdr + bytes)
    CSP 10, p, 0, hdr + bytes, 0
    POKE p, nd
    POKE p + 2, esize OR ((flags AND 1) * 256)
    FOR i = 0 TO nd - 1
        POKE p + 4 + i * 2, PEEK(_ABUF + i * 2) + 1
    NEXT i
    _NABND = 0
    old = PEEK(slot)
    IF old <> 0 AND (flags AND 2) <> 0 THEN
        ' PRESERVE: the elements as bytes; strings no longer kept go
        oe = PEEK(old + 2) AND 255
        ob = 1
        FOR i = 1 TO PEEK(old)
            ob = ob * PEEK(old + 2 + i * 2)
        NEXT i
        IF flags AND 1 THEN
            IF ob > total THEN _AFREESTR old, total
        END IF
        ob = ob * oe
        IF ob > bytes THEN ob = bytes
        CSP 2, old + 4 + PEEK(old) * 2, 0, p + hdr, 0, ob
        _MFREE old
    ELSE
        _AFREE slot
    END IF
    POKE slot, p
END SUB

FUNCTION _ARR (slot, nd)
    DIM p
    p = PEEK(slot)
    IF p = 0 THEN _RTERR 9
    IF PEEK(p) <> nd THEN _RTERR 9
    _ARR = p
END FUNCTION

FUNCTION _AX1 (slot, i)
    DIM p
    p = _ARR(slot, 1)
    IF NOT _ULT(i, PEEK(p + 4)) THEN _RTERR 9
    _AX1 = p + 6 + i * (PEEK(p + 2) AND 255)
END FUNCTION

FUNCTION _AX2 (slot, i, j)
    DIM p, n2
    p = _ARR(slot, 2)
    n2 = PEEK(p + 6)
    IF NOT _ULT(i, PEEK(p + 4)) OR NOT _ULT(j, n2) THEN _RTERR 9
    _AX2 = p + 8 + (i * n2 + j) * (PEEK(p + 2) AND 255)
END FUNCTION

' 3 or more indexes: each pushed with _AIDX, then _AXN
SUB _AIDX (i)
    IF _NAIX >= 8 THEN _RTERR 9
    POKE _AIXB + _NAIX * 2, i
    _NAIX = _NAIX + 1
END SUB

FUNCTION _AXN (slot, nd)
    DIM p, k, lin, i, n
    _NAIX = 0
    p = _ARR(slot, nd)
    lin = 0
    FOR k = 0 TO nd - 1
        i = PEEK(_AIXB + k * 2)
        n = PEEK(p + 4 + k * 2)
        IF NOT _ULT(i, n) THEN _RTERR 9
        lin = lin * n + i
    NEXT k
    _AXN = p + 4 + nd * 2 + lin * (PEEK(p + 2) AND 255)
END FUNCTION

FUNCTION _AUB (slot, k)
    DIM p
    p = PEEK(slot)
    IF p = 0 THEN _RTERR 9
    IF k < 1 OR k > PEEK(p) THEN _RTERR 9
    _AUB = PEEK(p + 2 + k * 2) - 1
END FUNCTION
