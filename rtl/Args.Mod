MODULE Args;

(* voc's Args interface (argc and Get), for programs built with -OC.

   voc ships Args only in its -O2 library (2/sym/Args.sym), not in the
   -OC one this program must use for olibfyaml, but ArgParser imports
   it.  Modules has the same information, numbered the same way:
   argument 0 is the program's own name, and argc counts it.  This is
   ArgParser's poc-rtl/Args.Mod, which fills the same gap for poc. *)

IMPORT Modules;

VAR
  argc-: INTEGER;

PROCEDURE Get*(n: INTEGER; VAR val: ARRAY OF CHAR);
BEGIN
  Modules.GetArg(n, val)
END Get;

BEGIN
  argc := Modules.ArgCount
END Args.
