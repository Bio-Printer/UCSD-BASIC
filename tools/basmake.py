#!/usr/bin/env python3
"""basmake.py -- the makefiles of the volumes BASIC: (BC, tools/mkvolume.py) and BASIC2: (B2,
tools/mkvolume2.py), for UCSD-C's MAKE (on its TOOLS: volume; MAN MAKE):

  VOL:MAKEFILE.TEXT        everything: the MAKE of the four below in turn (MAKE -f VOL:MAKEFILE),
                           and INSTALL (MAKE -f VOL:MAKEFILE INSTALL)
  VOL:/SRC/MAKEFILE.TEXT   the compiler: each module compiled when it or a file it #INCLUDEs
                           changed, each program linked (-MAP) when one of its modules did, as
                           VOL:PROG2.CODE; INSTALL moves them into the old ones' places
                           (B2: DUMPALL too)
  VOL:/LIB/MAKEFILE.TEXT   the run-time library: joined into VOL:/LIB/BASLIB2.OBJ
  VOL:/DEMO/MAKEFILE.TEXT  the demos       VOL:/TEST/MAKEFILE.TEXT  the tests

A recipe longer than the shell's 79 characters (a link of many modules) MAKE runs as
BC @#4:MAKEnRk, with its commands in that file, a line each: BC's (and B2's) batch file."""
import os, re


def wrap(words, first, indent='\t', width=76):
    """first and the words, folded with \\ (make goes on at a line's end \\)"""
    lines, cur = [], first
    for w in words:
        if len(cur) + 1 + len(w) > width:
            lines.append(cur + ' \\')
            cur = indent + w
        else:
            cur += ' ' + w
    return '\n'.join(lines + [cur]) + '\n'


def includes(path, seen=None):
    """the files path #INCLUDEs (NAME.BAS beside it), and theirs, in order: their upper-case names"""
    seen = [] if seen is None else seen
    for line in open(path, encoding='latin1'):
        m = re.match(r'\s*#INCLUDE\s+"([^"]+)"', line, re.I)
        if not m:
            continue
        n = m.group(1).upper()
        n = n if n.endswith('.BAS') else n + '.BAS'
        host = os.path.join(os.path.dirname(path), n.lower())
        if n not in seen and os.path.exists(host):
            seen.append(n)
            includes(host, seen)
    return seen


def comment(text):
    return ''.join('# %s\n' % l if l else '#\n' for l in text.split('\n'))


def objs_rules(var, mods, hostdir, comp):
    """the compile rule of the modules in $(var) and each one's #INCLUDEs"""
    out = '$(%s)%%.OBJ : $(%s)%%.BAS\n\t$(%s) $(FLAGS) -C $(%s)$*\n\n' % (var, var, comp, var)
    inc = ''
    for m in mods:
        i = includes(os.path.join(hostdir, m.lower() + '.bas'))
        if i:
            inc += wrap(['$(%s)%s' % (var, n) for n in i], '$(%s)%s.OBJ :' % (var, m))
    if inc:
        out += '# each module\'s #INCLUDEs: it is compiled again when one of them changes\n' + inc
    return out


def src_makefile(vol, comp, progs, mods, hostdir, mapdir, dump=None):
    """VOL:/SRC/MAKEFILE.TEXT: progs [(PROG, [MOD ...])]; mapdir: where PROG.MAP is (VOL: or
    VOL:/MAP/); dump: B2's DUMPALL lines"""
    out = comment("""MAKEFILE -- %(c)s, rebuilt: from the shell, MAKE -f %(v)s:/SRC/MAKEFILE (UCSD-C's
MAKE, on TOOLS:).  Compiles each module whose source, or a file it #INCLUDEs, is newer than
its object (NAME.OBJ beside it), and links each program whose modules changed, as
%(v)s:%(p)s2.CODE ... (its map %(m)s%(p)s2.MAP: -MAP).  MAKE -B ... all of them again.
MAKE -f %(v)s:/SRC/MAKEFILE INSTALL then puts them in the old ones' places (each MOVE
deletes the old file and renames the new one; when the new one is not there it says
so and leaves the old one).""" % {'c': comp, 'v': vol, 'p': progs[0][0], 'm': mapdir}) + \
        ('' if not dump else comment("""MAKE -B -f %(v)s:/SRC/MAKEFILE FLAGS=-K keeps every pass's file (%(v)s:/MAP/Wn), and
MAKE -f %(v)s:/SRC/MAKEFILE DUMPALL then makes each into text (%(v)s:/MAP/Dn: B2DUMP -MAP).""" % {'v': vol}))
    out += '%s = %s\nS = %s:/SRC/\nFLAGS =\n\n' % (comp, comp, vol)
    out += wrap(['%s:%s2.CODE' % (vol, p) for p, m in progs], 'all :') + '\n'
    for p, m in progs:
        out += wrap(['$(S)%s.OBJ' % x for x in m], '%s:%s2.CODE :' % (vol, p))
        out += '\t$(%s) -MAP -L %s:%s2=%s\n' % (comp, vol, p, ','.join('$(S)' + x for x in m))
    out += '\n' + objs_rules('S', mods, hostdir, comp) + '\nINSTALL :\n'
    for p, m in progs:
        out += '\tMOVE %s:%s2.CODE %s:%s.CODE\n\tMOVE %s%s2.MAP %s%s.MAP\n' % (vol, p, vol, p, mapdir, p, mapdir, p)
    if dump:
        out += '\nDUMPALL :\n' + ''.join('\t%s\n' % l for l in dump)
    return out + '\n.PHONY : all INSTALL%s\n' % (' DUMPALL' if dump else '')


def lib_makefile(vol, comp, libs, hostdir):
    out = comment("""MAKEFILE -- the run-time library, rebuilt: from the shell, MAKE -f %(v)s:/LIB/MAKEFILE.
Compiles each module whose source or #INCLUDEs changed (NAME.OBJ beside it) and joins
them into %(v)s:/LIB/BASLIB2.OBJ, the same as BASLIB.OBJ.  MAKE -B ... all again.""" % {'v': vol})
    out += '%s = %s\nL = %s:/LIB/\nFLAGS =\n\n' % (comp, comp, vol)
    out += wrap(['$(L)%s.OBJ' % m for m in libs], '$(L)BASLIB2.OBJ :')
    out += '\t$(%s) -J %s:/LIB/BASLIB2=%s\n\n' % (comp, vol, ','.join('$(L)' + m for m in libs))
    return out + objs_rules('L', libs, hostdir, comp)


def progs_makefile(vol, comp, sub, what, progs, hostdirs):
    """the demos' or the tests' makefile: progs [(NAME, [MOD ...])], hostdirs: where NAME.bas is"""
    out = comment("""MAKEFILE -- %(w)s: from the shell, MAKE -f %(v)s:/%(s)s/MAKEFILE.  Compiles and links
each program whose source is newer than its code file (%(v)s:/%(s)s/NAME.CODE; it leaves a
NAME.OBJ too).  MAKE -B ... all of them again.""" % {'w': what, 'v': vol, 's': sub})
    out += '%s = %s\nD = %s:/%s/\nFLAGS =\n\n' % (comp, comp, vol, sub)
    out += wrap(['$(D)%s.CODE' % n for n, m in progs], 'all :') + '\n'
    multi = [(n, m) for n, m in progs if m]
    for n, m in multi:
        out += wrap(['$(D)%s.OBJ' % x for x in [n] + m], '$(D)%s.CODE :' % n)
        out += '\t$(%s) -L $(D)%s=%s\n' % (comp, n, ','.join('$(D)' + x for x in [n] + m))
    if multi:
        out += '$(D)%.OBJ : $(D)%.BAS\n\t$(' + comp + ') $(FLAGS) -C $(D)$*\n'
    out += '$(D)%.CODE : $(D)%.BAS\n\t$(' + comp + ') $(FLAGS) $(D)$*\n'
    inc = ''
    for n, m in progs:
        for x in [n] + m:
            i = includes(os.path.join(hostdirs, x.lower() + '.bas'))
            if i:
                inc += wrap(['$(D)%s' % y for y in i], '$(D)%s.%s :' % (x, 'OBJ' if m or x != n else 'CODE'))
    return out + inc + '\n.PHONY : all\n'


def all_makefile(vol, comp):
    return comment("""MAKEFILE -- everything: the compiler, the library, the demos, the tests, each the MAKE
of its own makefile.  From the shell: MAKE -f %(v)s:MAKEFILE (UCSD-C's MAKE, on TOOLS:),
or MAKE -f %(v)s:MAKEFILE SRC (LIB, DEMO, TEST) for one.  Then MAKE -f %(v)s:MAKEFILE
INSTALL puts the rebuilt compiler (%(v)s:%(c)s2.CODE ...) in the old one's place.""" % {'v': vol, 'c': comp}) + """
all : SRC LIB DEMO TEST

SRC :
\t$(MAKE) -f %(v)s:/SRC/MAKEFILE
LIB :
\t$(MAKE) -f %(v)s:/LIB/MAKEFILE
DEMO :
\t$(MAKE) -f %(v)s:/DEMO/MAKEFILE
TEST :
\t$(MAKE) -f %(v)s:/TEST/MAKEFILE
INSTALL :
\t$(MAKE) -f %(v)s:/SRC/MAKEFILE INSTALL

.PHONY : all SRC LIB DEMO TEST INSTALL
""" % {'v': vol}
