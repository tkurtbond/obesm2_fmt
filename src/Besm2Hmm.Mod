MODULE Besm2Hmm; (* The h-m-m outline format (-H/--hmm) *)

(* The Ada BESM2_Fmt.Format_Hmm, a port of besm2-rst.scm's
   process-entity-hmm and its process-stat-hmm and friends: a
   tab-indented outline for h-m-m, one node per line.  The item text is
   the terse format's, except that details are flattened onto one line;
   the section headings are like terse's, without the " — ".

   Indentation starts from -L/--hmm-depth for every entity.  In
   besm2-rst.scm *hmm-depth* is a parameter, and each deeper level a
   parameterize whose extent ends with the entity, so it never builds
   up from one entity to the next.  The -R/--hmm-root line is written
   once per run, by the main module, not here. *)

IMPORT Besm2Config, Besm2Entities, Besm2Layout, Besm2Out, Besm2Str;

TYPE
  String = Besm2Str.String;
  Buffer = Besm2Str.Buffer;

PROCEDURE Indent(depth: INTEGER);
BEGIN Besm2Out.Repeat(09X, depth)
END Indent;

(* s with every line feed made a blank: besm2-rst.scm's all-one-line,
   which splits on newlines and joins with blanks (two newlines in a row
   give two blanks).  An h-m-m node is one line, so a newline inside a
   tagline, description or details -- from a "details: |" block scalar,
   as in FV2021-Coleopteran-2e.yaml's "Weapon: Rocket Pod" -- can't be
   written as it is. *)
PROCEDURE AllOneLine(s: ARRAY OF CHAR): String;
  VAR b: Buffer; i: LONGINT;
BEGIN
  Besm2Str.Reset(b); i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF s[i] = 0AX THEN Besm2Str.AddChar(b, " ") ELSE Besm2Str.AddChar(b, s[i]) END;
    INC(i)
  END;
  RETURN Besm2Str.Get(b)
END AllOneLine;

(* "N CP", "N BP", "N MP" or "N MBP", as in Besm2Terse. *)
PROCEDURE AddLabelPoints(VAR b: Buffer; points: INTEGER; mecha: BOOLEAN);
BEGIN
  Besm2Str.AddInt(b, ABS(points)); Besm2Str.AddChar(b, " ");
  IF mecha THEN
    IF points < 0 THEN Besm2Str.Add(b, "MBP") ELSE Besm2Str.Add(b, "MP") END
  ELSE
    IF points < 0 THEN Besm2Str.Add(b, "BP") ELSE Besm2Str.Add(b, "CP") END
  END
END AddLabelPoints;

PROCEDURE LabelPoints(points: INTEGER; mecha: BOOLEAN): String;
  VAR b: Buffer;
BEGIN Besm2Str.Reset(b); AddLabelPoints(b, points, mecha); RETURN Besm2Str.Get(b)
END LabelPoints;

(* "NAME LEVEL" (with -M's " — " and -l's "Level "), emphasized under -b
   or -i, appended to b.  Only name and level are emphasized, in skills
   too: besm2-rst.scm's process-skill-hmm emphasized the rest of the
   line as well, a bug fixed upstream (besm-tools b04abb5) and in the
   Ada version. *)
PROCEDURE AddNameAndLevel(VAR b: Buffer; name, level: String);
  VAR t: Buffer; s, e: String;
BEGIN
  Besm2Str.Reset(t);
  Besm2Str.Add(t, name^);
  IF Besm2Config.emDash THEN Besm2Str.Add(t, " — ") ELSE Besm2Str.AddChar(t, " ") END;
  IF Besm2Config.level THEN Besm2Str.Add(t, "Level ") END;
  Besm2Str.Add(t, level^);
  s := Besm2Str.Get(t); e := Besm2Layout.Emphasizing(s^);
  Besm2Str.Add(b, e^)
END AddNameAndLevel;

(* ---- Items: besm2-rst.scm's process-stat-hmm and friends ---- *)

PROCEDURE Stat(s: Besm2Entities.Stat; mecha: BOOLEAN): String;
  VAR b: Buffer;
BEGIN
  Besm2Str.Reset(b);
  Besm2Str.Add(b, s.name^); Besm2Str.AddChar(b, " "); Besm2Str.Add(b, s.value^);
  Besm2Str.Add(b, " ("); AddLabelPoints(b, s.points, mecha); Besm2Str.AddChar(b, ")");
  RETURN Besm2Str.Get(b)
END Stat;

PROCEDURE Derived(d: Besm2Entities.Derived): String;
  VAR b: Buffer; alts: String;
BEGIN
  Besm2Str.Reset(b);
  Besm2Str.Add(b, d.name^); Besm2Str.AddChar(b, " "); Besm2Str.Add(b, d.value^);
  IF d.alternatives.n > 0 THEN
    alts := Besm2Str.Join(d.alternatives, ", ");
    Besm2Str.Add(b, " ("); Besm2Str.Add(b, alts^); Besm2Str.AddChar(b, ")")
  END;
  RETURN Besm2Str.Get(b)
END Derived;

(* Details, flattened, then sep, if there are any. *)
PROCEDURE AddDetails(VAR b: Buffer; details: String; sep: ARRAY OF CHAR);
  VAR s: String;
BEGIN
  IF Besm2Str.Length(details^) > 0 THEN
    s := AllOneLine(details^); Besm2Str.Add(b, s^); Besm2Str.Add(b, sep)
  END
END AddDetails;

PROCEDURE Attribute(a: Besm2Entities.Attribute; mecha: BOOLEAN): String;
  VAR b: Buffer;
BEGIN
  Besm2Str.Reset(b);
  AddNameAndLevel(b, a.name, a.level);
  Besm2Str.Add(b, " ("); AddDetails(b, a.details, ". ");
  AddLabelPoints(b, a.points, mecha); Besm2Str.AddChar(b, ")");
  RETURN Besm2Str.Get(b)
END Attribute;

(* Two blanks after defect details, one after attribute details, as in
   terse. *)
PROCEDURE Defect(d: Besm2Entities.Defect; mecha: BOOLEAN): String;
  VAR b: Buffer; e: String;
BEGIN
  Besm2Str.Reset(b);
  e := Besm2Layout.Emphasizing(d.name^); Besm2Str.Add(b, e^);
  Besm2Str.Add(b, " ("); AddDetails(b, d.details, ".  ");
  AddLabelPoints(b, d.points, mecha); Besm2Str.AddChar(b, ")");
  RETURN Besm2Str.Get(b)
END Defect;

PROCEDURE Skill(s: Besm2Entities.Skill): String;
  VAR b: Buffer; specs: String;
BEGIN
  Besm2Str.Reset(b);
  AddNameAndLevel(b, s.name, s.level);
  Besm2Str.Add(b, " (");
  IF s.specialisations.n > 0 THEN
    specs := Besm2Str.Join(s.specialisations, ", "); Besm2Str.Add(b, specs^); Besm2Str.Add(b, ".  ")
  END;
  Besm2Str.AddInt(b, s.points); Besm2Str.Add(b, " SP)");
  RETURN Besm2Str.Get(b)
END Skill;

(* ---- Sections ---- *)

(* The items of l, on one line at depth, separated by ", ", or each on
   its own line at depth under -S/--hmm-separate. *)
PROCEDURE Items(l: Besm2Entities.List; mecha: BOOLEAN; depth: INTEGER);
  VAR i: INTEGER; x: Besm2Entities.Named;
BEGIN
  Indent(depth);
  FOR i := 0 TO l.n - 1 DO
    IF i > 0 THEN
      IF Besm2Config.hmmSeparate THEN Besm2Out.Ln; Indent(depth)
      ELSE Besm2Out.String(", ")
      END
    END;
    x := l.items[i];
    WITH x: Besm2Entities.Stat DO Besm2Out.Str(Stat(x, mecha))
    | x: Besm2Entities.Derived DO Besm2Out.Str(Derived(x))
    | x: Besm2Entities.Attribute DO Besm2Out.Str(Attribute(x, mecha))
    | x: Besm2Entities.Defect DO Besm2Out.Str(Defect(x, mecha))
    | x: Besm2Entities.Skill DO Besm2Out.Str(Skill(x))
    END
  END;
  Besm2Out.Ln
END Items;

(* A section heading at depth, in bold. *)
PROCEDURE Heading(depth: INTEGER; text: ARRAY OF CHAR);
BEGIN Indent(depth); Besm2Out.Str(Besm2Layout.Bold(text))
END Heading;

(* " (N CP)" or the like, under -s/--subtotals. *)
PROCEDURE Subtotal(points: INTEGER; mecha: BOOLEAN);
BEGIN
  IF Besm2Config.showSubtotals THEN
    Besm2Out.String(" ("); Besm2Out.Str(LabelPoints(points, mecha)); Besm2Out.Char(")")
  END
END Subtotal;

(* Writes e.  entityNo is unused -- an outline has no underlined
   headers -- and taken only so that every format is called the same
   way, as in the Ada version. *)
PROCEDURE ProcessEntity*(e: Besm2Entities.Entity; entityNo: INTEGER);
  VAR d1, d2, d3: INTEGER; flat: String;
BEGIN
  d1 := Besm2Config.hmmDepth + 1;   (* the entity *)
  d2 := d1 + 1;                     (* its sections *)
  d3 := d2 + 1;                     (* their items *)

  Indent(d1);
  IF e.name # NIL THEN
    Besm2Out.Str(e.name); Besm2Out.String(" (");
    Besm2Out.Str(LabelPoints(e.entityTotal, e.mecha)); Besm2Out.Char(")")
  ELSE
    Besm2Out.Str(LabelPoints(e.entityTotal, e.mecha))
  END;
  Besm2Out.Ln;

  IF e.tagline # NIL THEN
    flat := AllOneLine(e.tagline^);
    Indent(d2); Besm2Out.Str(Besm2Layout.Italics(flat^)); Besm2Out.Ln
  END;

  IF ~Besm2Config.omitEntityDescription & (e.description # NIL) THEN
    (* With a trailing blank, as in besm2-rst.scm. *)
    Indent(d2); Besm2Out.Str(AllOneLine(e.description^)); Besm2Out.Char(" "); Besm2Out.Ln
  END;

  IF e.size # NIL THEN
    Indent(d2); Besm2Out.Str(Besm2Layout.Bold("Size:")); Besm2Out.Char(" "); Besm2Out.Str(e.size);
    Besm2Out.Ln
  END;

  IF e.stats.n > 0 THEN
    Heading(d2, "Statistics");
    (* This subtotal alone has a trailing blank, as in terse. *)
    IF Besm2Config.showSubtotals THEN Subtotal(e.statsTotal, e.mecha); Besm2Out.Char(" ") END;
    Besm2Out.Ln;
    Items(e.stats, e.mecha, d3)
  END;

  IF e.derived.n > 0 THEN
    Heading(d2, "Derived Values"); Besm2Out.Ln;
    Items(e.derived, e.mecha, d3)
  END;

  IF e.attributes.n > 0 THEN
    IF e.mecha THEN Heading(d2, "Mecha Sub-Attributes") ELSE Heading(d2, "Attributes") END;
    Subtotal(e.attributesTotal, e.mecha); Besm2Out.Ln;
    Items(e.attributes, e.mecha, d3)
  END;

  IF e.defects.n > 0 THEN
    IF e.mecha THEN Heading(d2, "Mecha Defects") ELSE Heading(d2, "Defects") END;
    Subtotal(e.defectsTotal, e.mecha); Besm2Out.Ln;
    Items(e.defects, e.mecha, d3)
  END;

  IF e.skills.n > 0 THEN
    Heading(d2, "Skills");
    IF Besm2Config.showSubtotals THEN
      Besm2Out.String(" ("); Besm2Out.Str(Besm2Str.Int(e.skillsTotal)); Besm2Out.String(" SP)")
    END;
    Besm2Out.Ln;
    Items(e.skills, e.mecha, d3)
  END
END ProcessEntity;

END Besm2Hmm.
