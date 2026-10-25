#!/usr/bin/env python3
"""pdis.py -- disassemble a UCSD Pascal II.0 code file.

  pdis.py FILE.CODE [segnum]

Code file block 0: DISKINFO[0..15] (block, byte length), SEGNAME[0..15]
(8 chars), SEGKIND[0..15].  Each segment ends with its procedure
dictionary: last word = segnum (low byte) | #procs (high byte); the words
below it are negative self-relative pointers to each procedure's JTAB.
JTAB: byte 0 procnum (0 = assembly), byte 1 lex level; -2 ENTRIC, -4
EXITIC (self-relative), -6 PARMSZ, -8 DATASZ, -10.. long-jump entries.
"""
import struct, sys

# operand formats: '' none, 'U' unsigned byte, 'B' big (1 or 2 bytes),
# 'S' signed jump byte, 'D' db+big, 'W' word, 'X' xjp, 'C' ldc, 'A' string, 'P' ixp
OPS = {
    0x80: ('ABI', ''), 0x81: ('ABR', ''), 0x82: ('ADI', ''), 0x83: ('ADR', ''), 0x84: ('LAND', ''),
    0x85: ('DIF', ''), 0x86: ('DVI', ''), 0x87: ('DVR', ''), 0x88: ('CHK', ''), 0x89: ('FLO', ''),
    0x8A: ('FLT', ''), 0x8B: ('INN', ''), 0x8C: ('INT', ''), 0x8D: ('LOR', ''), 0x8E: ('MODI', ''),
    0x8F: ('MPI', ''), 0x90: ('MPR', ''), 0x91: ('NGI', ''), 0x92: ('NGR', ''), 0x93: ('NOT', ''),
    0x94: ('SRS', ''), 0x95: ('SBI', ''), 0x96: ('SBR', ''), 0x97: ('SGS', ''), 0x98: ('SQI', ''),
    0x99: ('SQR', ''), 0x9A: ('STO', ''), 0x9B: ('IXS', ''), 0x9C: ('UNI', ''), 0x9D: ('S2P', ''),
    0x9E: ('CSP', 'U'), 0x9F: ('LDCN', ''),
    0xA0: ('ADJ', 'U'), 0xA1: ('FJP', 'S'), 0xA2: ('INC', 'B'), 0xA3: ('IND', 'B'), 0xA4: ('IXA', 'B'),
    0xA5: ('LAO', 'B'), 0xA6: ('LSA', 'A'), 0xA7: ('LAE', 'UB'), 0xA8: ('MOV', 'B'), 0xA9: ('LDO', 'B'),
    0xAA: ('SAS', 'U'), 0xAB: ('SRO', 'B'), 0xAC: ('XJP', 'X'), 0xAD: ('RNP', 'U'), 0xAE: ('CIP', 'U'),
    0xAF: ('EQU', 'T'), 0xB0: ('GEQ', 'T'), 0xB1: ('GRT', 'T'), 0xB2: ('LDA', 'D'), 0xB3: ('LDC', 'C'),
    0xB4: ('LEQ', 'T'), 0xB5: ('LES', 'T'), 0xB6: ('LOD', 'D'), 0xB7: ('NEQ', 'T'), 0xB8: ('STR', 'D'),
    0xB9: ('UJP', 'S'), 0xBA: ('LDP', ''), 0xBB: ('STP', ''), 0xBC: ('LDM', 'U'), 0xBD: ('STM', 'U'),
    0xBE: ('LDB', ''), 0xBF: ('STB', ''), 0xC0: ('IXP', 'P'), 0xC1: ('RBP', 'U'), 0xC2: ('CBP', 'U'),
    0xC3: ('EQUI', ''), 0xC4: ('GEQI', ''), 0xC5: ('GRTI', ''), 0xC6: ('LLA', 'B'), 0xC7: ('LDCI', 'W'),
    0xC8: ('LEQI', ''), 0xC9: ('LESI', ''), 0xCA: ('LDL', 'B'), 0xCB: ('NEQI', ''), 0xCC: ('STL', 'B'),
    0xCD: ('CXP', 'UU'), 0xCE: ('CLP', 'U'), 0xCF: ('CGP', 'U'), 0xD0: ('LPA', 'A'), 0xD1: ('STE', 'UB'),
    0xD2: ('NOP', ''), 0xD3: ('EFJ', 'S'), 0xD4: ('NFJ', 'S'), 0xD5: ('BPT', 'B'), 0xD6: ('XIT', ''),
    0xD7: ('NOP', ''),
}
CSP = ["IOC", "NEW", "MVL", "MVR", "EXIT", "UREAD", "UWRITE", "IDS", "TRS", "TIM", "FLC", "SCN",
       None, None, None, None, None, None, None, None, None,
       "GSEG", "RSEG", "TNC", "RND", "SIN", "COS", "LOG", "ATAN", "LN", "EXP", "SQT",
       "MRK", "RLS", "IOR", "UBUSY", "POT", "UWAIT", "UCLEAR", "HLT", "MEMA"]
CSP_EXT = {138: 'CALLI'}       # engine extensions: 100..137 doubles (docs/DOUBLES.md), 138 call through function pointer
CMPT = {2: 'REAL', 4: 'STR', 6: 'BOOL', 8: 'SET', 10: 'BYTE', 12: 'WORD'}


def w(b, a):
    return b[a] | (b[a + 1] << 8)


def disasm(seg, start, end, jtab, out):
    pc = start
    while pc < end:
        op = seg[pc]
        a = pc
        pc += 1
        if op < 0x80:
            out.append((a, 'SLDC %d' % op)); continue
        if 0xD8 <= op <= 0xE7:
            out.append((a, 'SLDL %d' % (op - 0xD7))); continue
        if 0xE8 <= op <= 0xF7:
            out.append((a, 'SLDO %d' % (op - 0xE7))); continue
        if op >= 0xF8:
            out.append((a, 'SIND %d' % (op - 0xF8))); continue
        name, fmt = OPS.get(op, ('???%02X' % op, ''))
        args = []

        def big():
            nonlocal pc
            v = seg[pc]; pc += 1
            if v & 0x80:
                v = ((v & 0x7F) << 8) | seg[pc]; pc += 1
            return v
        for f in fmt:
            if f == 'U':
                args.append(str(seg[pc])); pc += 1
            elif f == 'B':
                args.append(str(big()))
            elif f == 'D':
                db = seg[pc]; pc += 1
                args.append('%d,%d' % (db, big()))
            elif f == 'W':
                v = w(seg, pc); pc += 2
                args.append(str(v - 65536 if v > 32767 else v))
            elif f == 'S':
                v = seg[pc]; pc += 1
                if v < 128:
                    args.append('->%04X' % (pc + v))
                else:
                    ent = jtab + (v - 256)
                    args.append('->%04X (long)' % ((ent - w(seg, ent)) & 0xFFFF) if 0 <= ent < len(seg) else 'long?')
            elif f == 'T':
                t = seg[pc]; pc += 1
                s = CMPT.get(t, str(t))
                if t in (10, 12):
                    s += ' %d' % big()
                args.append(s)
            elif f == 'P':
                args.append('%d,%d' % (seg[pc], seg[pc + 1])); pc += 2
            elif f == 'A':
                n = seg[pc]; pc += 1
                args.append(repr(bytes(seg[pc:pc + n]).decode('latin1'))); pc += n
            elif f == 'C':
                n = seg[pc]; pc += 1
                if pc & 1: pc += 1
                ws = [w(seg, pc + 2 * i) for i in range(n)]; pc += 2 * n
                args.append('%d: %s' % (n, ' '.join('%04X' % x for x in ws)))
            elif f == 'X':
                if pc & 1: pc += 1
                lo, hi = w(seg, pc), w(seg, pc + 2)
                lo = lo - 65536 if lo > 32767 else lo
                hi = hi - 65536 if hi > 32767 else hi
                pc += 4
                if not 0 <= hi - lo < 1024:         # not a table (bad decode): stop here
                    out.append((a, name + ' ?? %d..%d' % (lo, hi)))
                    return out
                els = pc
                pc += 2   # the else jump is a UJP instruction
                tgts = []
                for i in range(hi - lo + 1):
                    e = pc + 2 * i
                    tgts.append('%04X' % ((e - w(seg, e)) & 0xFFFF))
                pc += 2 * (hi - lo + 1)
                args.append('%d..%d else@%04X [%s]' % (lo, hi, els, ' '.join(tgts)))
                out.append((a, name + ' ' + ', '.join(args)))
                disasm(seg, els, els + 2, jtab, out)
                continue
        if name == 'CSP':
            n = int(args[0])
            args[0] += ' (%s)' % (CSP_EXT.get(n) or (CSP[n] if n < len(CSP) and CSP[n] else '?'))
        out.append((a, name + (' ' + ', '.join(args) if args else '')))
    return out


def main(a):
    data = open(a[0], 'rb').read()
    only = int(a[1]) if len(a) > 1 else None
    for s in range(16):
        blk, ln = struct.unpack_from('<HH', data, 4 * s)
        name = data[64 + 8 * s: 72 + 8 * s].decode('latin1')
        kind = w(data, 192 + 2 * s)
        if ln == 0 and blk == 0:
            continue
        if only is not None and s != only:
            continue
        seg = data[blk * 512: blk * 512 + ln]
        print('=== segment %d %r block %d length %d kind %d' % (s, name, blk, ln, kind))
        if ln < 2:
            continue
        segp = ln - 2
        segnum, nprocs = seg[segp], seg[segp + 1]
        print('    segnum %d, %d procs' % (segnum, nprocs))
        for p in range(1, nprocs + 1):
            pa = segp - 2 * p
            jt = (pa - w(seg, pa)) & 0xFFFF
            if jt >= ln:
                print('  proc %d: bad jtab' % p); continue
            procnum, lex = seg[jt], seg[jt + 1]
            if procnum == 0:
                print('  proc %d: assembly' % p); continue
            ent = (jt - 2 - w(seg, jt - 2)) & 0xFFFF
            ext = (jt - 4 - w(seg, jt - 4)) & 0xFFFF
            print('\n  proc %d  lex %d  parmsz %d  datasz %d  enter %04X exit %04X jtab %04X' %
                  (p, lex - 256 if lex > 127 else lex, w(seg, jt - 6), w(seg, jt - 8), ent, ext, jt))
            for adr, txt in disasm(seg, ent, jt - 8, jt, []):
                print('    %04X  %s' % (adr, txt))


if __name__ == '__main__':
    main(sys.argv[1:])
