MODULE Besm2Config; (* Settings from the command line *)

(* The Ada BESM2_Fmt.Config: besm2-rst.scm's top-level *star* variables.
   Besm2Cli sets them from the command line; the output modules read
   them.  Exported read-write because Oberon has no "writable only by
   Besm2Cli"; nothing else should change them, except tests. *)

IMPORT Besm2Str;

CONST
  (* Output formats.  Grid (reST grid tables) is the default; -t, -H
     and -m choose the others, and the last of them given wins, as in
     besm2-rst.scm. *)
  Grid* = 0; Terse* = 1; Hmm* = 2; RawMs* = 3;

VAR
  format*: INTEGER;

  oneTable*: BOOLEAN;              (* -1/--one *)
  boldHead*: BOOLEAN;              (* on; -B/--no-bold-head clears it *)
  bolding*: BOOLEAN;               (* -b/--bold *)
  omitEntityDescription*: BOOLEAN; (* -D/--omit-description *)
  debugging*: BOOLEAN;             (* -d/--debug *)
  hmmOutput*: BOOLEAN;             (* set by -H with format *)
  hmmSeparate*: BOOLEAN;           (* -S/--hmm-separate *)
  italicizing*: BOOLEAN;           (* -i/--italics *)
  level*: BOOLEAN;                 (* -l/--level *)
  emDash*: BOOLEAN;                (* -M/--em-dash *)
  pageAfterDescription*: BOOLEAN;  (* -p/--page *)
  showSubtotals*: BOOLEAN;         (* -s/--subtotals *)
  (* On: negative numbers get U+2212 MINUS SIGN; -n/--no-unicode-minus
     clears it, for ASCII "-".  The default is the Ada version's own
     choice, not besm2-rst.scm's. *)
  unicodeMinus*: BOOLEAN;

  hmmDepth*: INTEGER;              (* -L/--hmm-depth, >= 0 *)
  tableWidth*: INTEGER;            (* -w/--width *)

  hmmRoot*: Besm2Str.String;       (* -R/--hmm-root; NIL = not given *)
  outputFile*: Besm2Str.String;    (* -o/--output; NIL = standard output *)

  underliner*: CHAR;               (* -u/--underliner *)
  subunderliner*: CHAR;            (* -U/--subunderliner; 0X = not given *)

  (* The fill of the separator under a table's header row: "=" (a real
     reST header), or "-" under -1/--one, where a repeated "=" line would
     make the first table's header look like the only one in HTML. *)
  headSep*: CHAR;

BEGIN
  format := Grid;
  oneTable := FALSE; boldHead := TRUE; bolding := FALSE;
  omitEntityDescription := FALSE; debugging := FALSE;
  hmmOutput := FALSE; hmmSeparate := FALSE; italicizing := FALSE;
  level := FALSE; emDash := FALSE; pageAfterDescription := FALSE;
  showSubtotals := FALSE; unicodeMinus := TRUE;
  hmmDepth := 0; tableWidth := 60;
  hmmRoot := NIL; outputFile := NIL;
  underliner := "-"; subunderliner := 0X;
  headSep := "="
END Besm2Config.
