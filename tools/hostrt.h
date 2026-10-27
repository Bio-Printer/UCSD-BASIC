/* hostrt.h -- the run-time library of BASIC programs translated to C by
 * bas2c.py: the host (Linux) build of the BASIC compiler.
 *
 * It does what the P-System's library (lib/*.bas) does, as far as the
 * compiler uses it, with the same results: INTEGER is 16 bits and wraps,
 * strings are at most 255 characters, arrays are indexed from 0 with their
 * bounds checked, comparisons give -1 / 0.  Files: text files are lines,
 * binary files bytes; a volume name (VOL: #5: *) is dropped and names are
 * found whatever their case (NAME.TEXT is also looked for as name.bas).
 */
#ifndef HOSTRT_H
#define HOSTRT_H
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <dirent.h>
#include <unistd.h>

typedef int16_t bint;
typedef struct { unsigned char len; char s[255]; } bstr;

static void brt_fatal(int code, const char *what);

/* ---- strings */

static bstr bs_lit(const char *s, int n)
{
    bstr r;
    if (n > 255) brt_fatal(15, "string too long");
    r.len = n;
    memcpy(r.s, s, n);
    return r;
}
#define BS(lit) bs_lit(lit, sizeof(lit) - 1)

static bstr bs_empty(void) { bstr r; r.len = 0; return r; }

static bstr bs_cat(bstr a, bstr b)
{
    if (a.len + b.len > 255) brt_fatal(15, "string too long");
    memcpy(a.s + a.len, b.s, b.len);
    a.len += b.len;
    return a;
}

static bint bs_cmp(bstr a, bstr b)
{
    int n = a.len < b.len ? a.len : b.len;
    int c = memcmp(a.s, b.s, n);
    if (c) return c < 0 ? -1 : 1;
    return a.len < b.len ? -1 : a.len > b.len ? 1 : 0;
}

static bint bs_len(bstr a) { return a.len; }

static bint bs_asc(bstr a, bint p)
{
    if (p < 1 || p > a.len) return 0;
    return (unsigned char)a.s[p - 1];
}

static bstr bs_chr(bint c) { bstr r; r.len = 1; r.s[0] = (char)(c & 255); return r; }

static bstr bs_mid(bstr a, bint st, bint n)
{
    bstr r;
    if (st < 1 || n < 0) brt_fatal(5, "illegal function call (MID$)");
    r.len = 0;
    if (st > a.len) return r;
    if (n > a.len - st + 1) n = a.len - st + 1;
    r.len = n;
    memcpy(r.s, a.s + st - 1, n);
    return r;
}

static bstr bs_left(bstr a, bint n)
{
    if (n < 0) brt_fatal(5, "illegal function call (LEFT$)");
    if (n < a.len) a.len = n;
    return a;
}

static bstr bs_right(bstr a, bint n)
{
    bstr r;
    if (n < 0) brt_fatal(5, "illegal function call (RIGHT$)");
    if (n >= a.len) return a;
    r.len = n;
    memcpy(r.s, a.s + a.len - n, n);
    return r;
}

static bint bs_instr(bint st, bstr a, bstr b)
{
    int i;
    if (st < 1) brt_fatal(5, "illegal function call (INSTR)");
    if (st > a.len) return b.len == 0 && st == a.len + 1 ? st : 0;
    if (b.len == 0) return st;
    for (i = st - 1; i + b.len <= a.len; i++)
        if (memcmp(a.s + i, b.s, b.len) == 0) return i + 1;
    return 0;
}

static bstr bs_ucase(bstr a) { int i; for (i = 0; i < a.len; i++) if (a.s[i] >= 'a' && a.s[i] <= 'z') a.s[i] -= 32; return a; }
static bstr bs_lcase(bstr a) { int i; for (i = 0; i < a.len; i++) if (a.s[i] >= 'A' && a.s[i] <= 'Z') a.s[i] += 32; return a; }

static bstr bs_ltrim(bstr a)
{
    int i = 0;
    while (i < a.len && a.s[i] == ' ') i++;
    return bs_mid(a, i + 1, 255);
}

static bstr bs_rtrim(bstr a)
{
    while (a.len > 0 && a.s[a.len - 1] == ' ') a.len--;
    return a;
}

static bstr bs_trim(bstr a) { return bs_ltrim(bs_rtrim(a)); }

static bstr bs_space(bint n)
{
    bstr r;
    if (n < 0 || n > 255) brt_fatal(n < 0 ? 5 : 15, "SPACE$");
    r.len = n;
    memset(r.s, ' ', n);
    return r;
}

static bstr bs_string(bint n, bint c)
{
    bstr r;
    if (n < 0 || n > 255) brt_fatal(n < 0 ? 5 : 15, "STRING$");
    r.len = n;
    memset(r.s, c & 255, n);
    return r;
}

/* STR$ of an integer: a blank for the sign of one that is not negative */
static bstr bs_stri(bint v)
{
    char b[16];
    int n = sprintf(b, v < 0 ? "%d" : " %d", (int)v);
    return bs_lit(b, n);
}

static bstr bs_hex(bint v)
{
    char b[8];
    int n = sprintf(b, "%X", (unsigned)(uint16_t)v);
    return bs_lit(b, n);
}

/* VAL: the number at the start (blanks skipped), 0 if none */
static double bs_val(bstr a)
{
    char b[256];
    int i = 0;
    memcpy(b, a.s, a.len);
    b[a.len] = 0;
    while (b[i] == ' ') i++;
    if (b[i] == '&' && (b[i + 1] == 'H' || b[i + 1] == 'h'))
        return (double)(int16_t)strtol(b + i + 2, 0, 16);
    for (char *p = b; *p; p++)
        if (*p == 'D' || *p == 'd') *p = 'E';
    return strtod(b + i, 0);
}

static bstr bs_mkd(double d) { return bs_lit((const char *)&d, 8); }
static double bs_cvd(bstr a) { double d = 0; memcpy(&d, a.s, a.len < 8 ? a.len : 8); return d; }
static bstr bs_mki(bint v) { char b[2]; b[0] = v & 255; b[1] = (v >> 8) & 255; return bs_lit(b, 2); }
static bint bs_cvi(bstr a) { return (bint)(bs_asc(a, 1) | (bs_asc(a, 2) << 8)); }

/* MID$(s, st, n) = v */
static void bs_midset(bstr *s, bint st, bint n, bstr v)
{
    int i;
    if (st < 1 || st > s->len) brt_fatal(5, "illegal function call (MID$)");
    for (i = 0; i < n && i < v.len && st - 1 + i < s->len; i++)
        s->s[st - 1 + i] = v.s[i];
}

/* ---- numbers */

static bint b_idiv(bint a, bint b)
{
    if (b == 0) brt_fatal(11, "division by zero");
    return (bint)(a / b);
}

static bint b_imod(bint a, bint b)
{
    if (b == 0) brt_fatal(11, "division by zero");
    return (bint)(a % b);
}

/* CINT of a real: rounded, half away from zero */
static bint b_cint(double d)
{
    d = d < 0 ? -floor(-d + 0.5) : floor(d + 0.5);
    if (d > 32767 || d < -32768) brt_fatal(6, "overflow");
    return (bint)d;
}

/* ---- arrays: indexes 0..bound in each dimension */

typedef struct { bint nd; bint dim[8]; int esize; int isstr; char *data; } barr;

static void ar_free(barr *a)
{
    free(a->data);
    a->data = 0;
    a->nd = 0;
}

static void ar_dim(barr *a, int esize, int isstr, int nd, ...);

#include <stdarg.h>
static void ar_dim(barr *a, int esize, int isstr, int nd, ...)
{
    va_list ap;
    long n = 1;
    int i;
    ar_free(a);
    va_start(ap, nd);
    for (i = 0; i < nd; i++) {
        int b = va_arg(ap, int);
        if (b < 0) brt_fatal(9, "subscript out of range (DIM)");
        a->dim[i] = b + 1;
        n *= b + 1;
    }
    va_end(ap);
    a->nd = nd;
    a->esize = esize;
    a->isstr = isstr;
    a->data = calloc(n ? n : 1, esize);
}

/* REDIM PRESERVE: the elements kept, as bytes (as the library's _ADIM) */
static void ar_dimp(barr *a, int esize, int isstr, int nd, ...)
{
    va_list ap;
    long n = 1, ob = 1;
    int i;
    char *old = a->data;
    for (i = 0; i < a->nd; i++)
        ob *= a->dim[i];
    ob *= a->esize;
    va_start(ap, nd);
    for (i = 0; i < nd; i++) {
        int b = va_arg(ap, int);
        if (b < 0) brt_fatal(9, "subscript out of range (DIM)");
        a->dim[i] = b + 1;
        n *= b + 1;
    }
    va_end(ap);
    a->nd = nd;
    a->esize = esize;
    a->isstr = isstr;
    a->data = calloc(n ? n : 1, esize);
    if (old) {
        memcpy(a->data, old, ob < n * esize ? ob : n * esize);
        free(old);
    }
}

static void *ax(barr *a, int nd, ...)
{
    va_list ap;
    long lin = 0;
    int i;
    if (!a->data) brt_fatal(9, "array not dimensioned");
    if (nd != a->nd) brt_fatal(9, "wrong number of dimensions");
    va_start(ap, nd);
    for (i = 0; i < nd; i++) {
        int x = va_arg(ap, int);
        if (x < 0 || x >= a->dim[i]) brt_fatal(9, "subscript out of range");
        lin = lin * a->dim[i] + x;
    }
    va_end(ap);
    return a->data + lin * a->esize;
}

static bint ar_ub(barr *a, bint k)
{
    if (!a->data) brt_fatal(9, "array not dimensioned");
    if (k < 1 || k > a->nd) brt_fatal(9, "subscript out of range (UBOUND)");
    return a->dim[k - 1] - 1;
}

/* ---- files */

#define NFILES 16
static struct bfile { FILE *f; int mode; int col; } brt_f[NFILES];
static int brt_trap;
static bint brt_err;
static int brt_col;

static void brt_closeall(void)
{
    int i;
    fflush(stdout);
    for (i = 1; i < NFILES; i++)
        if (brt_f[i].f) {
            fclose(brt_f[i].f);
            brt_f[i].f = 0;
        }
}

static void brt_fatal(int code, const char *what)
{
    fflush(stdout);
    fprintf(stderr, "Run-time error %d: %s\n", code, what);
    brt_closeall();
    exit(2);
}

/* an I/O error: trapped (ON ERROR RESUME NEXT) it sets ERR, else it stops */
static void brt_ioerr(int code, const char *what)
{
    if (brt_trap) {
        brt_err = code;
        return;
    }
    brt_fatal(code, what);
}

/* the host file for a P-System name */
static void brt_hostname(bstr n, char *out, int forwrite)
{
    char b[256];
    char *p, *base;
    DIR *d;
    struct dirent *e;
    memcpy(b, n.s, n.len);
    b[n.len] = 0;
    /* a size, [n] or [*], is the P-System's: not part of the name */
    if (n.len > 2 && b[n.len - 1] == ']' && (p = strrchr(b, '[')) != 0)
        *p = 0;
    p = strrchr(b, ':');
    base = p ? p + 1 : b;
    if (*base == '*') base++;
    strcpy(out, base);
    if (forwrite) return;
    d = opendir(".");
    if (!d) return;
    while ((e = readdir(d)) != 0)
        if (strcasecmp(e->d_name, base) == 0) {
            strcpy(out, e->d_name);
            closedir(d);
            return;
        }
    closedir(d);
    /* NAME.TEXT: name.bas */
    {
        size_t l = strlen(base);
        if (l > 5 && strcasecmp(base + l - 5, ".TEXT") == 0) {
            char alt[256];
            strcpy(alt, base);
            strcpy(alt + l - 5, ".bas");
            d = opendir(".");
            while (d && (e = readdir(d)) != 0)
                if (strcasecmp(e->d_name, alt) == 0) {
                    strcpy(out, e->d_name);
                    break;
                }
            if (d) closedir(d);
        }
    }
}

static void b_open(bstr name, bint mode, bint ch, bint reclen)
{
    char hn[300];
    const char *m;
    (void)reclen;
    brt_err = 0;
    if (ch < 1 || ch >= NFILES) { brt_ioerr(52, "bad file number"); return; }
    if (brt_f[ch].f) { brt_ioerr(55, "file already open"); return; }
    brt_hostname(name, hn, mode == 2);
    switch (mode) {
    case 1: m = "rb"; break;
    case 2: m = "wb"; break;
    case 3: m = "ab"; break;
    default:
        m = "r+b";
        if (access(hn, F_OK) != 0) m = "w+b";
        break;
    }
    brt_f[ch].f = fopen(hn, m);
    brt_f[ch].mode = mode;
    brt_f[ch].col = 0;
    if (!brt_f[ch].f) brt_ioerr(53, "file not found");
}

static void b_close(bint ch)
{
    if (ch == 0) {
        brt_closeall();
        return;
    }
    if (ch > 0 && ch < NFILES && brt_f[ch].f) {
        fclose(brt_f[ch].f);
        brt_f[ch].f = 0;
    }
}

static FILE *brt_file(bint ch)
{
    if (ch < 1 || ch >= NFILES || !brt_f[ch].f) brt_fatal(52, "bad file number");
    return brt_f[ch].f;
}

/* SEEK #ch, pos: the next GET or PUT at byte pos (1 the first) */
static void b_seek(bint ch, long pos)
{
    fseek(brt_file(ch), pos - 1, SEEK_SET);
}


static bint b_eof(bint ch)
{
    FILE *f = brt_file(ch);
    int c = getc(f);
    if (c == EOF) return -1;
    ungetc(c, f);
    return 0;
}

static bstr b_linput(bint ch, bstr *prompt)
{
    char b[1024];
    FILE *f;
    int n;
    if (ch == 0) {
        if (prompt) printf("%.*s", prompt->len, prompt->s);
        fflush(stdout);
        f = stdin;
        brt_col = 0;
    } else
        f = brt_file(ch);
    if (!fgets(b, sizeof b, f)) {
        if (ch == 0) exit(0);
        brt_fatal(62, "input past end of file");
    }
    n = strlen(b);
    while (n > 0 && (b[n - 1] == '\n' || b[n - 1] == '\r')) n--;
    if (n > 255) n = 255;
    return bs_lit(b, n);
}

static void b_kill(bstr name)
{
    char hn[300];
    brt_err = 0;
    brt_hostname(name, hn, 0);
    if (remove(hn) != 0) brt_ioerr(53, "file not found");
}

/* GET / PUT: bytes */
static void b_getr(void *p, bint ch, bint n)
{
    FILE *f = brt_file(ch);
    unsigned char *q = p;
    int i, c;
    for (i = 0; i < n; i++) {
        c = getc(f);
        q[i] = c == EOF ? 0 : c;
    }
}

static void b_putr(void *p, bint ch, bint n) { fwrite(p, 1, n, brt_file(ch)); }

static bstr b_gets(bint ch, bint n)
{
    bstr r;
    r.len = n;
    b_getr(r.s, ch, n);
    return r;
}

static void b_puts(bint ch, bstr s) { fwrite(s.s, 1, s.len, brt_file(ch)); }

/* ---- PRINT */

static FILE *brt_out(bint ch, int **col)
{
    if (ch == 0) {
        *col = &brt_col;
        return stdout;
    }
    *col = &brt_f[ch].col;
    return brt_file(ch);
}

static void p_str(bint ch, bstr s)
{
    int *col;
    FILE *f = brt_out(ch, &col);
    fwrite(s.s, 1, s.len, f);
    *col += s.len;
}

static void p_int(bint ch, bint v)
{
    char b[16];
    int n = sprintf(b, v < 0 ? "%d " : " %d ", (int)v);
    p_str(ch, bs_lit(b, n));
}

static void p_nl(bint ch)
{
    int *col;
    FILE *f = brt_out(ch, &col);
    putc('\n', f);
    *col = 0;
}

static void p_comma(bint ch)
{
    int *col;
    brt_out(ch, &col);
    do p_str(ch, BS(" ")); while (*col % 14);
}

static void p_tab(bint ch, bint n)
{
    int *col;
    brt_out(ch, &col);
    if (*col >= n - 1) p_nl(ch);
    while (*col < n - 1) p_str(ch, BS(" "));
}

static void p_spc(bint ch, bint n) { while (n-- > 0) p_str(ch, BS(" ")); }

static void p_dbl(bint ch, double d)
{
    char b[40];
    int n = sprintf(b, d < 0 ? "%.15g " : " %.15g ", d);
    p_str(ch, bs_lit(b, n));
}

/* ---- the program */

static bstr brt_cmdline;

static bstr b_command(void) { return brt_cmdline; }

static void b_halt(bint code)
{
    brt_closeall();
    exit(code);
}

static void b_onerr(bint on)
{
    brt_trap = on;
    brt_err = 0;
}

static bint b_errno(void) { return brt_err; }

static char brt_self[512];             /* this program's file: CHAIN runs one beside it */

/* CHAIN "[VOL:]PROGRAM [args]": the host program PROGRAM (lower case) in this one's
   directory takes its place, with the args as its command line */
static void b_chain(bstr cmd)
{
    char line[300], path[900], *argv[64], *p, *name;
    int n = 0, i;
    memcpy(line, cmd.s, cmd.len);
    line[cmd.len] = 0;
    p = line;
    while (*p == ' ') p++;
    name = p;
    while (*p && *p != ' ') p++;
    if (*p) *p++ = 0;
    if (strrchr(name, ':')) name = strrchr(name, ':') + 1;
    for (i = 0; name[i]; i++) name[i] = tolower((unsigned char)name[i]);
    snprintf(path, sizeof path, "%s/%s", brt_self, name);
    argv[n++] = path;
    while (*p && n < 62) {
        while (*p == ' ') p++;
        if (!*p) break;
        argv[n++] = p;
        while (*p && *p != ' ') p++;
        if (*p) *p++ = 0;
    }
    argv[n] = 0;
    brt_closeall();
    fflush(stdout);
    execv(path, argv);
    brt_ioerr(53, "CHAIN: no such program");
}

static void brt_init(int argc, char **argv)
{
    char b[256];
    int i, n = 0;
    ssize_t k = readlink("/proc/self/exe", brt_self, sizeof brt_self - 1);
    brt_self[k > 0 ? k : 0] = 0;
    if (strrchr(brt_self, '/')) *strrchr(brt_self, '/') = 0;
    b[0] = 0;
    for (i = 1; i < argc; i++) {
        if (i > 1 && n < 250) b[n++] = ' ';
        while (*argv[i] && n < 255) b[n++] = *argv[i]++;
    }
    brt_cmdline = bs_lit(b, n);
}

#endif
