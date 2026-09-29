MODULE TestEntities; (* Besm2Entities.Load, on the real fixtures and made-up ones *)

(* Expected values come from the fixtures and from the Ada binary's
   terse output for them (PLAN.md, step 4), not from this port.  Run
   from obj/: the fixtures are read from ../test/data/. *)

IMPORT Besm2Config, Besm2Entities, Besm2Str, Check, Fyaml;

TYPE
  Entity = Besm2Entities.Entity;

VAR
  e: Entity;
  msg: Besm2Str.String;
  yerr: Fyaml.Error;

PROCEDURE Is(s: Besm2Str.String; t: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN (s # NIL) & (s^ = t)
END Is;

(* The first entity of the first document of file (in test/data/), or
   NIL, reporting why. *)
PROCEDURE FromFile(file: ARRAY OF CHAR): Entity;
  VAR d: Fyaml.Document; err: Fyaml.Error; root: Fyaml.Node; path: Besm2Str.String;
BEGIN
  path := Besm2Str.Concat("../test/data/", file);
  d := Fyaml.ParseFile(path^, err);
  IF d = NIL THEN Check.Check(FALSE, err.msg^); RETURN NIL END;
  root := d.Root(); root := root.Item(0);
  IF ~Besm2Entities.Load(root, e, yerr, msg) THEN e := NIL END;
  d.Close;
  RETURN e
END FromFile;

(* Loads the first entity of YAML text; TRUE if it loaded.  e, yerr and
   msg are left as Load sets them. *)
PROCEDURE FromText(text: ARRAY OF CHAR): BOOLEAN;
  VAR d: Fyaml.Document; err: Fyaml.Error; root: Fyaml.Node; ok: BOOLEAN;
BEGIN
  d := Fyaml.ParseString(text, err);
  IF d = NIL THEN Check.Check(FALSE, err.msg^); RETURN FALSE END;
  root := d.Root(); root := root.Item(0);
  ok := Besm2Entities.Load(root, e, yerr, msg);
  d.Close;
  RETURN ok
END FromText;

(* Loading text fails with message msg (Load's own) containing text. *)
PROCEDURE FailsWith(yaml, text: ARRAY OF CHAR; label: ARRAY OF CHAR);
  VAR ok: BOOLEAN; i, j: LONGINT;
BEGIN
  ok := ~FromText(yaml) & (e = NIL) & (yerr = NIL) & (msg # NIL);
  IF ok THEN   (* msg contains text *)
    i := 0; ok := FALSE;
    WHILE ~ok & (msg[i] # 0X) DO
      j := 0;
      WHILE (text[j] # 0X) & (msg[i + j] = text[j]) DO INC(j) END;
      ok := text[j] = 0X; INC(i)
    END
  END;
  Check.Check(ok, label)
END FailsWith;

(* Loading text fails with an olibfyaml error of kind. *)
PROCEDURE YamlFails(yaml: ARRAY OF CHAR; kind: INTEGER; label: ARRAY OF CHAR);
BEGIN
  Check.Check(~FromText(yaml) & (e = NIL) & (msg = NIL) & (yerr # NIL) & (yerr.kind = kind), label)
END YamlFails;

PROCEDURE Name(l: Besm2Entities.List; i: INTEGER): Besm2Str.String;
BEGIN
  IF i < l.n THEN RETURN l.items[i].name END;
  RETURN NIL
END Name;

PROCEDURE Enyon;
  VAR s: Besm2Entities.Stat; d: Besm2Entities.Derived; a: Besm2Entities.Attribute;
    sk: Besm2Entities.Skill; df: Besm2Entities.Defect;
BEGIN
  e := FromFile("enyon-boase-2e.yaml");
  Check.Check(e # NIL, "enyon-boase-2e loads");
  IF e = NIL THEN RETURN END;
  Check.Check(Is(e.name, "Lieutenant Enyon Boase"), "name");
  Check.Check((e.tagline = NIL) & (e.description = NIL) & (e.size = NIL), "absent fields are NIL");
  Check.Check(~e.mecha, "mecha is off when absent");
  Check.Check(e.stats.n = 3, "3 stats");
  s := e.stats.items[0](Besm2Entities.Stat);
  Check.Check(Is(s.name, "Body") & Is(s.value, "8") & (s.points = 8), "first stat is Body 8, 8 points");
  Check.Check(Is(Name(e.stats, 2), "Soul"), "stats keep document order");
  Check.Check(e.derived.n = 5, "5 derived values");
  d := e.derived.items[0](Besm2Entities.Derived);
  Check.Check(Is(d.name, "ACV") & Is(d.value, "9") & (d.alternatives.n = 0),
    "derived ACV 9, abbreviation not expanded here");
  Check.Check(e.attributes.n = 3, "3 attributes");
  a := e.attributes.items[1](Besm2Entities.Attribute);
  Check.Check(Is(a.name, "Extra Actions") & Is(a.level, "1") & (a.points = 4)
    & Is(a.details, "+1 Extra Action"), "Extra Actions 1, details, 4 points");
  a := e.attributes.items[0](Besm2Entities.Attribute);
  Check.Check(Is(a.details, ""), "no details is the empty string");
  df := e.defects.items[0](Besm2Entities.Defect);
  Check.Check((e.defects.n = 2) & Is(df.name, "Conditional Ownership: Army ownership")
    & (df.points = -2) & Is(df.details, ""), "defects");
  Check.Check(e.skills.n = 9, "9 skills");
  sk := e.skills.items[1](Besm2Entities.Skill);
  Check.Check(Is(sk.name, "Law") & Is(sk.level, "1") & (sk.points = 2)
    & (sk.specialisations.n = 1) & Is(sk.specialisations.items[0], "Military"),
    "Law 1, specialisation Military");
  (* The Ada terse -s output: 20 CP, 18 CP, 3 BP, 25 SP, 35 CP. *)
  Check.Check((e.statsTotal = 20) & (e.attributesTotal = 18) & (e.defectsTotal = -3)
    & (e.skillsTotal = 25), "subtotals match the Ada -t -s output");
  Check.Check(e.entityTotal = 35, "entity total leaves out skills (35 CP)")
END Enyon;

PROCEDURE Coleopteran;
  VAR a: Besm2Entities.Attribute; df: Besm2Entities.Defect;
BEGIN
  e := FromFile("FV2021-Coleopteran-2e.yaml");
  Check.Check(e # NIL, "FV2021-Coleopteran-2e loads (with a bogus key)");
  IF e = NIL THEN RETURN END;
  Check.Check(e.mecha, "mecha: true");
  Check.Check(e.stats.n = 0, "no stats");
  Check.Check((e.description # NIL) & (e.description[Besm2Str.Length(e.description^) - 1] = 0AX),
    "description keeps its trailing newline (it isn't trimmed)");
  Check.Check(Is(Name(e.attributes, 0), "Accessories") & Is(Name(e.attributes, 7), "Toughness")
    & Is(Name(e.attributes, 8), "Weapon: Plasma Fist") & Is(Name(e.attributes, 10), "Weapon: Rocket Pod"),
    "attributes sorted by name");
  a := e.attributes.items[9](Besm2Entities.Attribute);
  Check.Check(Is(a.details, "Damage 45, Long-Range, Unreliable"),
    "a block scalar's trailing newline is trimmed from details");
  a := e.attributes.items[10](Besm2Entities.Attribute);
  msg := Besm2Str.Concat3("Damage 45, Auto-fire, Area Effect, Limited Shots ×2 [3 shots],", 0AX, "Stoppable");
  Check.Check(Is(a.details, msg^), "an embedded newline is kept in details (the formats deal with it)");
  df := e.defects.items[0](Besm2Entities.Defect);
  Check.Check(Is(df.details, "Huge (1-10 tonnes)"), "defect details trimmed");
  Check.Check(Is(Name(e.defects, 1), "Hanger Queen"), "defects sorted");
  (* The Ada terse output: 44 MP, 4 MBP, 40 MP. *)
  Check.Check((e.attributesTotal = 44) & (e.defectsTotal = -4) & (e.entityTotal = 40),
    "totals match the Ada -t output")
END Coleopteran;

PROCEDURE Customizers;
  CONST
    (* YAML turns the \n in the double-quoted details into a newline. *)
    Yaml = '- {name: X, attributes: [{name: A, level: 1, points: 1, effective: 3, elements: [Fire, air], enhancements: [Area, [Range, 5], [Zone, 2, a], [Big, 3, b, c]], limiters: [Slow, [Short, -1]], details: "  hi\n"}]}';
  VAR a: Besm2Entities.Attribute;
BEGIN
  Check.Check(FromText(Yaml), "every customizer shape loads");
  IF e = NIL THEN RETURN END;
  a := e.attributes.items[0](Besm2Entities.Attribute);
  Check.Check(Is(a.level, "1 (3)"), "effective level is added to the level");
  Check.Check(Is(a.details, "air, Fire; Area −1, Big: b, c −3, Range −5, Short +-1, Slow +1, Zone: a −2; hi"),
    "details as the Ada version writes them: elements; customizers; text, each sorted");
  Besm2Config.unicodeMinus := FALSE;
  IF FromText(Yaml) THEN a := e.attributes.items[0](Besm2Entities.Attribute) END;
  Check.Check(Is(a.details, "air, Fire; Area -1, Big: b, c -3, Range -5, Short +-1, Slow +1, Zone: a -2; hi"),
    "-n gives ASCII minus signs in details");
  Besm2Config.unicodeMinus := TRUE;
  Check.Check(FromText('- {name: X, attributes: [{name: A, level: 1, points: 1, effective: ""}]}'),
    "an empty effective loads");
  a := e.attributes.items[0](Besm2Entities.Attribute);
  Check.Check(Is(a.level, "1"), "an empty effective adds nothing")
END Customizers;

PROCEDURE Misc;
BEGIN
  Check.Check(FromText('- {mecha: false}') & ~e.mecha & (e.name = NIL), "mecha: false is off; no name");
  Check.Check(FromText('- {tagline: "  Hero.  "}') & Is(e.tagline, "Hero."), "tagline is trimmed");
  Check.Check(FromText('- {size: Large, description: ""}') & Is(e.size, "Large") & Is(e.description, ""),
    "size; an empty description is present, not NIL");
  Check.Check(FromText('- {skills: [{name: b, level: 1, points: 1}, {name: A, level: 1, points: 2}, {name: a, level: 1, points: 3}]}')
    & (e.skills.n = 3) & Is(Name(e.skills, 0), "A") & Is(Name(e.skills, 1), "a") & Is(Name(e.skills, 2), "b"),
    "skills sorted ignoring case, equal names kept in order");
  Check.Check(FromText('- {derived: [{name: DCV, value: 5, alternatives: [x, y]}]}')
    & (e.derived.items[0](Besm2Entities.Derived).alternatives.n = 2), "derived alternatives")
END Misc;

PROCEDURE Errors;
BEGIN
  YamlFails('- {stats: [{name: B, value: 3}]}', Fyaml.MissingKey, "a missing points is a MissingKey error");
  YamlFails('- {stats: [{name: B, value: 3, points: x}]}', Fyaml.DataError, "points: x is a DataError");
  YamlFails('- {name: [a]}', Fyaml.DataError, "a name that isn't a scalar is a DataError");
  YamlFails('- {mecha: yes}', Fyaml.DataError, "mecha: yes is a DataError (YAML 1.2 core schema)");
  YamlFails('- {attributes: [{name: A, points: 1}]}', Fyaml.MissingKey, "an attribute's level is required");
  YamlFails('- {attributes: [{name: A, level: 1, points: 1, enhancements: [[Range, x]]}]}', Fyaml.DataError,
    "a customizer's counts-as must be an integer");
  FailsWith('- 5', "/0: not a mapping", "an entity that isn't a mapping");
  FailsWith('- {stats: 5}', "/0/stats: not a sequence", "stats that isn't a sequence");
  FailsWith('- {stats: [5]}', "/0/stats/0: not a mapping", "a stat that isn't a mapping");
  FailsWith('- {attributes: [{name: A, level: 1, points: 1, elements: [{a: 1}]}]}',
    "/0/attributes/0/elements/0: not a scalar", "an element that isn't a scalar");
  FailsWith('- {attributes: [{name: A, level: 1, points: 1, enhancements: [[Range]]}]}',
    "/0/attributes/0/enhancements/0: customizer sequence too short", "a customizer of one item");
  FailsWith('- {attributes: [{name: A, level: 1, points: 1, limiters: [{a: 1}]}]}',
    "/0/attributes/0/limiters/0: do not understand customizer", "a customizer that is a mapping");
  FailsWith('- {attributes: [{name: A, level: 1, points: 1, limiters: [[R, 2, [a]]]}]}',
    "/0/attributes/0/limiters/0/2: not a scalar", "an applies-to that isn't a scalar");
  FailsWith('- {attributes: [{name: A, level: 1, points: 1, enhancements: Area}]}',
    "/0/attributes/0/enhancements: not a sequence", "enhancements that isn't a sequence")
END Errors;

BEGIN
  Enyon;
  Coleopteran;
  Customizers;
  Misc;
  Errors;
  Check.Summary
END TestEntities.
