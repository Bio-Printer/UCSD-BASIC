# Notes for Claude

- Build: `tools/setup.sh` (emulator runner, boot disk), `tools/buildhost.sh`
  (host BC: build/bc, bclex, bcgen, bclist, bclink), `tools/mklib.sh`,
  `tools/mkself.sh`, `tools/mkvolume.py`.
  The sibling checkouts are expected in `../bio-printer/` (the emulator,
  UCSD-TinyC, UCSD-Pascal-Volumes); see setup.sh's variables.
- BC is five programs that CHAIN to each other through the job file
  :BCTEMP.JOB (docs/DESIGN.md section 1); tools/bcprogs.py lists each one's
  modules (the first its main one) for every build tool.  A new module goes
  there.  BCGEN keeps segments GEN and DECL (one segment holds at most 255
  procedures).
- After a change to the compiler or the library run `tools/runtests.py`,
  `tools/selfcompile.py` (must say IDENTICAL six times: BASLIB and the five programs) and, for the volume,
  `tools/voltest.py`.  New cross-module calls need `tools/mkdecls.py`
  (buildhost.sh runs it).
- BC's sources must stay within the part of the language tools/bas2c.py
  translates, and their lines under 250 characters.
- Keep docs/LANGUAGE.md and docs/DESIGN.md current; they are on the volume.
- When the volume changes, update UCSD-Pascal-Volumes too: BLK_format/BASIC.BLK,
  the extracted files (`tools/extract_all.py BLK_format .`), the manifest and a
  README.txt entry.
- Pascal booleans passed to the OS must be 1, not BASIC's -1 (SYSTEM.C).
- A library procedure that makes a temporary string it does not return
  (e.g. prints `_ISTR`'s text) must give it back itself: `t = _TTOP` ...
  `_TTOP = t`; the compiler only resets after string expressions it sees.
- Sub-volumes: lib/rtsubv.bas (tests/subvol, runtests makes the
  sub-volumes from tests/subvol.dirs).  The volume's layout and batch files
  are made by tools/mkvolume.py; run voltest.py and voltest.py --pascal
  after changing it.
- BASIC sources are NAME.BAS (text files) on the P-System and in the
  volume; BC still takes NAME.TEXT.  The library writes a new .BAS or
  .TEXT file as text and sets its kind (the FIB's DFKIND) itself.
- BC's emitter procedure is EmitCsp: a SUB named Csp would take the CSP
  statement's place.  bas2c turns the CSP statement into nothing and
  CSP%() into 0.  BC no longer checks for the Harvard layout (docs/DESIGN.md
  section 10: what the Z80 mode leaves).  PSYS_MODE=z80 needs the Z80
  interpreter pascal.bin (setup.sh copies UCSD-TinyC's).
- BASIC:INSTALL.TEXT (mkvolume) is a batch file of Tiny-C's shell (BIGGY
  1.32: @FILE; MOVE replaces): voltest runs it after BUILD.
- The tests boot build/psys/data/Big_Disk.BLK (setup.sh copies BOOT_DISK);
  BIGGY 1.29 is the first whose systems make a new NAME.BAS a text file;
  1.30's shell (and Tiny-C's library: __istext) reads NAME.BAS as text.
- Code space (Harvard): BCGEN (its main segment, GEN, DECL, SUBVOL) is the
  largest program; LIST is a program of its own (BCLIST, after BCGEN).
  voltest compares the P-System's listing (-S) with the host's.
- CHAIN: lib/rtchain.bas (_CHAIN), the pexec protocol of BIGGY's GETCMD;
  tests/chain (+ chain.progs) and tools/chaintest.py (from the shell; also
  --pascal).  bas2c translates CHAIN (hostrt.h b_chain: execv of the host
  program of that name beside the running one), PEEK and OSVAR (0).
