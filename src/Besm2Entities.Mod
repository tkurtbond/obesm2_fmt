MODULE Besm2Entities; (* A BESM entity, read once from its YAML *)

(* The Ada BESM2_Fmt.Entities: each entity (character, template, item)
   is decoded from its YAML mapping once, by Load, into plain records
   that all four output formats read.  besm2-rst.scm instead walks the
   raw YAML again in each of its four formats, including work they
   share: make-attribute-details and the sorting of attributes, defects
   and skills are done here, once.

   No exceptions in Oberon: Load returns FALSE on the first error, with
   either an olibfyaml error (a missing key, a malformed number) or a
   message of its own.  Its own messages are for YAML of the wrong
   shape -- a list that isn't a sequence, an item that isn't a mapping
   -- which olibfyaml treats as a programming error and halts on, and
   which the Ada version doesn't check either (it dies with an
   assertion failure, status 1).  Here they are ordinary input errors
   (PLAN.md, step 4). *)

IMPORT Besm2Layout, Besm2Str, Fyaml;

CONST
  Enhancement = 0; Limiter = 1;   (* the two kinds of customizer *)

TYPE
  String = Besm2Str.String;

  (* The base of the five kinds of item, so one list type and one sort
     serve them all.  A backend takes an item out with a type guard:
     stats.items[i](Stat). *)
  Named* = POINTER TO NamedDesc;
  NamedDesc* = RECORD name-: String END;

  Stat* = POINTER TO StatDesc;
  StatDesc* = RECORD (NamedDesc)
    value-: String;
    points-: INTEGER
  END;

  Derived* = POINTER TO DerivedDesc;
  DerivedDesc* = RECORD (NamedDesc)
    value-: String;
    alternatives-: Besm2Str.List          (* none: n = 0 *)
  END;

  Attribute* = POINTER TO AttributeDesc;
  AttributeDesc* = RECORD (NamedDesc)
    (* With " (effective)" already added when there is one: every
       format does it the same way. *)
    level-: String;
    points-: INTEGER;
    (* make-attribute-details: elements, enhancements and limiters, and
       the details text, combined; "" for none. *)
    details-: String
  END;

  Defect* = POINTER TO DefectDesc;
  DefectDesc* = RECORD (NamedDesc)
    points-: INTEGER;
    details-: String                      (* trimmed; "" for none *)
  END;

  Skill* = POINTER TO SkillDesc;
  SkillDesc* = RECORD (NamedDesc)
    level-: String;
    points-: INTEGER;
    specialisations-: Besm2Str.List       (* none: n = 0 *)
  END;

  Items = POINTER TO ARRAY OF Named;
  List* = RECORD
    items-: Items;                        (* items[0 .. n-1] *)
    n-: INTEGER
  END;

  (* Reads one item of a list; see LoadList. *)
  Loader = PROCEDURE (m: Fyaml.Node; VAR x: Named): BOOLEAN;

  Entity* = POINTER TO EntityDesc;
  EntityDesc* = RECORD
    (* NIL when the key is absent; the Ada version's Has_Name and
       friends. *)
    name-, tagline-, description-, size-: String;
    mecha-: BOOLEAN;
    (* Stats and derived values in document order; attributes, defects
       and skills sorted by name, ignoring case, as every format of
       besm2-rst.scm sorts them. *)
    stats-, derived-, attributes-, defects-, skills-: List;
    statsTotal-, attributesTotal-, defectsTotal-: INTEGER;
    skillsTotal-: INTEGER;                (* not part of entityTotal, as in besm2-rst.scm *)
    entityTotal-: INTEGER
  END;

VAR
  (* The error from the Load in progress: one of these is set when a
     loader returns FALSE.  Module state rather than a parameter to
     every loader; Load hands them back. *)
  yamlError: Fyaml.Error;
  message: String;

(* ---- Lists ---- *)

PROCEDURE Clear(VAR l: List);
BEGIN l.items := NIL; l.n := 0
END Clear;

PROCEDURE Add(VAR l: List; x: Named);
  VAR t: Items; i: INTEGER;
BEGIN
  IF l.items = NIL THEN NEW(l.items, 8)
  ELSIF l.n = LEN(l.items^) THEN
    NEW(t, 2 * l.n);
    FOR i := 0 TO l.n - 1 DO t[i] := l.items[i] END;
    l.items := t
  END;
  l.items[l.n] := x; INC(l.n)
END Add;

(* Sorts l by name, ignoring case (Besm2Str.LessCI, as the Ada CI_Less).
   An insertion sort: stable, and the lists are short. *)
PROCEDURE SortByName(VAR l: List);
  VAR i, j: INTEGER; x: Named;
BEGIN
  FOR i := 1 TO l.n - 1 DO
    x := l.items[i]; j := i;
    WHILE (j > 0) & Besm2Str.LessCI(x.name^, l.items[j - 1].name^) DO
      l.items[j] := l.items[j - 1]; DEC(j)
    END;
    l.items[j] := x
  END
END SortByName;

(* ---- Errors ---- *)

(* Fails with message "PATH: text", PATH being n's place in the
   document, as in /0/attributes/2/enhancements/1. *)
PROCEDURE Fail(n: Fyaml.Node; text: ARRAY OF CHAR): BOOLEAN;
  VAR path: Fyaml.String;
BEGIN
  path := n.Path();
  message := Besm2Str.Concat3(path^, ": ", text);
  RETURN FALSE
END Fail;

(* ---- Fields ---- *)

(* The text of the scalar for key, which must be there. *)
PROCEDURE Required(m: Fyaml.Node; key: ARRAY OF CHAR; VAR s: String): BOOLEAN;
  VAR t: Fyaml.String;
BEGIN
  IF ~m.StringField(key, t, yamlError) THEN RETURN FALSE END;
  s := Besm2Str.Of(t^);
  RETURN TRUE
END Required;

(* The text of the scalar for key, or NIL if there's no such key: the
   Ada Has_Key then String_Value.  A key whose value isn't a scalar is
   an error. *)
PROCEDURE Optional(m: Fyaml.Node; key: ARRAY OF CHAR; VAR s: String): BOOLEAN;
BEGIN
  s := NIL;
  RETURN ~m.HasKey(key) OR Required(m, key, s)
END Optional;

PROCEDURE Integer(m: Fyaml.Node; key: ARRAY OF CHAR; VAR i: INTEGER): BOOLEAN;
BEGIN RETURN m.IntegerField(key, i, yamlError)
END Integer;

(* The sequence for key, or NIL if there's no such key; anything else
   there is an error. *)
PROCEDURE Sequence(m: Fyaml.Node; key: ARRAY OF CHAR; VAR s: Fyaml.Node): BOOLEAN;
BEGIN
  s := m.Value(key);
  IF (s # NIL) & ~s.IsSequence() THEN RETURN Fail(s, "not a sequence") END;
  RETURN TRUE
END Sequence;

(* The text of scalar n. *)
PROCEDURE Scalar(n: Fyaml.Node; VAR s: String): BOOLEAN;
  VAR t: Fyaml.String;
BEGIN
  IF ~n.IsScalar() THEN RETURN Fail(n, "not a scalar") END;
  t := n.Scalar(); s := Besm2Str.Of(t^);
  RETURN TRUE
END Scalar;

(* The scalars of sequence seq, in order, appended to l. *)
PROCEDURE Strings(seq: Fyaml.Node; VAR l: Besm2Str.List): BOOLEAN;
  VAR it: Fyaml.ItemIter; item: Fyaml.Node; s: String;
BEGIN
  seq.Items(it);
  WHILE it.Next(item) DO
    IF ~Scalar(item, s) THEN RETURN FALSE END;
    Besm2Str.Append(l, s)
  END;
  RETURN TRUE
END Strings;

(* The strings for key, which is optional, into l (empty if absent). *)
PROCEDURE StringList(m: Fyaml.Node; key: ARRAY OF CHAR; VAR l: Besm2Str.List): BOOLEAN;
  VAR seq: Fyaml.Node;
BEGIN
  Besm2Str.Clear(l);
  RETURN Sequence(m, key, seq) & ((seq = NIL) OR Strings(seq, l))
END StringList;

(* ---- Enhancements, limiters and attribute details ---- *)

(* An enhancement counts as a minus in the details text and a limiter as
   a plus.  The plus is always ASCII; -n/--no-unicode-minus changes only
   the minus. *)
PROCEDURE AddSign(VAR b: Besm2Str.Buffer; kind: INTEGER);
  VAR minus: String;
BEGIN
  IF kind = Enhancement THEN minus := Besm2Layout.MinusGlyph(); Besm2Str.Add(b, minus^)
  ELSE Besm2Str.AddChar(b, "+")
  END
END AddSign;

(* besm2-rst.scm's format-customizers, for one item of an enhancements
   or limiters list: either a plain name, "NAME -1" (an enhancement) or
   "NAME +1" (a limiter); or a sequence [NAME, COUNTS-AS, APPLIES-TO...],
   "NAME -N" with no APPLIES-TO, else "NAME: A, B -N".  The Scheme
   matches exactly one and several APPLIES-TO separately, but joining
   one string gives that string, so one case covers both, as in Ada.
   Note that COUNTS-AS is written by AddInt, so a negative one gives
   "+-1" for a limiter, as Ada's Integer'Image does. *)
PROCEDURE Customizer(item: Fyaml.Node; kind: INTEGER; VAR s: String): BOOLEAN;
  VAR b: Besm2Str.Buffer; name, a: String; appliesTo: Besm2Str.List;
    part: Fyaml.Node; countsAs: INTEGER; i, len: LONGINT;
BEGIN
  Besm2Str.Reset(b);
  IF item.IsScalar() THEN
    IF ~Scalar(item, name) THEN RETURN FALSE END;
    Besm2Str.Add(b, name^); Besm2Str.AddChar(b, " "); AddSign(b, kind); Besm2Str.AddChar(b, "1")
  ELSIF item.IsSequence() THEN
    len := item.Length();
    (* The Ada version reads item 2 before checking the length, so a
       shorter one dies there, with an assertion failure. *)
    IF len < 2 THEN RETURN Fail(item, "customizer sequence too short") END;
    part := item.Item(0);
    IF ~Scalar(part, name) THEN RETURN FALSE END;
    part := item.Item(1);
    IF ~part.IntegerValue(countsAs, yamlError) THEN RETURN FALSE END;
    Besm2Str.Add(b, name^);
    IF len > 2 THEN
      Besm2Str.Clear(appliesTo);
      FOR i := 2 TO len - 1 DO
        part := item.Item(i);
        IF ~Scalar(part, a) THEN RETURN FALSE END;
        Besm2Str.Append(appliesTo, a)
      END;
      a := Besm2Str.Join(appliesTo, ", ");
      Besm2Str.Add(b, ": "); Besm2Str.Add(b, a^)
    END;
    Besm2Str.AddChar(b, " "); AddSign(b, kind); Besm2Str.AddInt(b, countsAs)
  ELSE
    RETURN Fail(item, "do not understand customizer")
  END;
  s := Besm2Str.Get(b);
  RETURN TRUE
END Customizer;

(* The customizers of sequence seq (NIL for none) appended to l. *)
PROCEDURE Customizers(seq: Fyaml.Node; kind: INTEGER; VAR l: Besm2Str.List): BOOLEAN;
  VAR it: Fyaml.ItemIter; item: Fyaml.Node; s: String;
BEGIN
  IF seq # NIL THEN
    seq.Items(it);
    WHILE it.Next(item) DO
      IF ~Customizer(item, kind, s) THEN RETURN FALSE END;
      Besm2Str.Append(l, s)
    END
  END;
  RETURN TRUE
END Customizers;

(* besm2-rst.scm's make-attribute-details: the elements, sorted and
   joined with ", "; then the enhancements and limiters together, sorted
   and joined with ", "; then the details text; the non-empty ones of
   those joined with "; ".  "" if all three are empty. *)
PROCEDURE AttributeDetails(m: Fyaml.Node; detailsText: String; VAR s: String): BOOLEAN;
  VAR parts, elements, custom: Besm2Str.List; enhancements, limiters: Fyaml.Node;
BEGIN
  Besm2Str.Clear(parts); Besm2Str.Clear(custom);
  IF ~StringList(m, "elements", elements) THEN RETURN FALSE END;
  IF elements.n > 0 THEN
    Besm2Str.SortCI(elements); Besm2Str.Append(parts, Besm2Str.Join(elements, ", "))
  END;
  IF ~Sequence(m, "enhancements", enhancements) OR ~Sequence(m, "limiters", limiters)
     OR ~Customizers(enhancements, Enhancement, custom)
     OR ~Customizers(limiters, Limiter, custom) THEN
    RETURN FALSE
  END;
  IF custom.n > 0 THEN
    Besm2Str.SortCI(custom); Besm2Str.Append(parts, Besm2Str.Join(custom, ", "))
  END;
  IF Besm2Str.Length(detailsText^) > 0 THEN Besm2Str.Append(parts, detailsText) END;
  s := Besm2Str.Join(parts, "; ");
  RETURN TRUE
END AttributeDetails;

(* ---- Items ---- *)

(* The "details" text, trimmed; "" if absent. *)
PROCEDURE Details(m: Fyaml.Node; VAR s: String): BOOLEAN;
BEGIN
  IF ~Optional(m, "details", s) THEN RETURN FALSE END;
  IF s = NIL THEN s := Besm2Str.Empty() ELSE s := Besm2Str.Trim(s^) END;
  RETURN TRUE
END Details;

PROCEDURE LoadStat(m: Fyaml.Node; VAR x: Named): BOOLEAN;
  VAR s: Stat;
BEGIN
  NEW(s); x := s;
  RETURN Required(m, "name", s.name) & Required(m, "value", s.value)
         & Integer(m, "points", s.points)
END LoadStat;

PROCEDURE LoadDerived(m: Fyaml.Node; VAR x: Named): BOOLEAN;
  VAR d: Derived;
BEGIN
  NEW(d); x := d;
  RETURN Required(m, "name", d.name) & Required(m, "value", d.value)
         & StringList(m, "alternatives", d.alternatives)
END LoadDerived;

(* level is required, for every attribute, mecha ones included:
   besm-tools commit 6139f21, ported to the Ada version too. *)
PROCEDURE LoadAttribute(m: Fyaml.Node; VAR x: Named): BOOLEAN;
  VAR a: Attribute; detailsText, effective: String;
BEGIN
  NEW(a); x := a;
  IF ~Required(m, "name", a.name) OR ~Integer(m, "points", a.points)
     OR ~Required(m, "level", a.level) OR ~Details(m, detailsText)
     OR ~Optional(m, "effective", effective) THEN
    RETURN FALSE
  END;
  IF (effective # NIL) & (Besm2Str.Length(effective^) > 0) THEN
    a.level := Besm2Str.Concat3(a.level^, " (", effective^);
    a.level := Besm2Str.Concat(a.level^, ")")
  END;
  RETURN AttributeDetails(m, detailsText, a.details)
END LoadAttribute;

PROCEDURE LoadDefect(m: Fyaml.Node; VAR x: Named): BOOLEAN;
  VAR d: Defect;
BEGIN
  NEW(d); x := d;
  RETURN Required(m, "name", d.name) & Integer(m, "points", d.points)
         & Details(m, d.details)
END LoadDefect;

PROCEDURE LoadSkill(m: Fyaml.Node; VAR x: Named): BOOLEAN;
  VAR s: Skill;
BEGIN
  NEW(s); x := s;
  RETURN Required(m, "name", s.name) & Required(m, "level", s.level)
         & Integer(m, "points", s.points)
         & StringList(m, "specialisations", s.specialisations)
END LoadSkill;

(* ---- Entities ---- *)

(* The items of the sequence for key (none if absent), each a mapping
   read by load, into l. *)
PROCEDURE LoadList(m: Fyaml.Node; key: ARRAY OF CHAR; load: Loader; VAR l: List): BOOLEAN;
  VAR seq, item: Fyaml.Node; it: Fyaml.ItemIter; x: Named;
BEGIN
  Clear(l);
  IF ~Sequence(m, key, seq) THEN RETURN FALSE END;
  IF seq # NIL THEN
    seq.Items(it);
    WHILE it.Next(item) DO
      IF ~item.IsMapping() THEN RETURN Fail(item, "not a mapping") END;
      IF ~load(item, x) THEN RETURN FALSE END;
      Add(l, x)
    END
  END;
  RETURN TRUE
END LoadList;

(* Reads entity e from mapping m.  On failure, returns FALSE with either
   yerr, an olibfyaml error, or msg, a message of its own, set (the
   other NIL), and e NIL.  The minus sign in attribute details depends
   on Besm2Config.unicodeMinus, so parse the command line first. *)
PROCEDURE Load*(m: Fyaml.Node; VAR e: Entity; VAR yerr: Fyaml.Error; VAR msg: String): BOOLEAN;
  VAR ok: BOOLEAN; i: INTEGER; tagline: String;
BEGIN
  yamlError := NIL; message := NIL; e := NIL;
  NEW(e);
  IF ~m.IsMapping() THEN ok := Fail(m, "not a mapping")
  ELSE
    ok := Optional(m, "name", e.name) & Optional(m, "tagline", tagline)
      & Optional(m, "description", e.description) & Optional(m, "size", e.size)
      (* BooleanFieldOr, not HasKey: "mecha: false" must turn mecha off.
         besm-tools commit 8da3e95 fixed besm2-rst.scm, which tested the
         key's presence, and the Ada version followed. *)
      & m.BooleanFieldOr("mecha", FALSE, e.mecha, yamlError)
      & LoadList(m, "stats", LoadStat, e.stats)
      & LoadList(m, "derived", LoadDerived, e.derived)
      & LoadList(m, "attributes", LoadAttribute, e.attributes)
      & LoadList(m, "defects", LoadDefect, e.defects)
      & LoadList(m, "skills", LoadSkill, e.skills)
  END;
  IF ~ok THEN
    yerr := yamlError; msg := message; e := NIL;
    RETURN FALSE
  END;
  IF tagline # NIL THEN e.tagline := Besm2Str.Trim(tagline^) END;
  SortByName(e.attributes); SortByName(e.defects); SortByName(e.skills);
  e.statsTotal := 0; e.attributesTotal := 0; e.defectsTotal := 0; e.skillsTotal := 0;
  FOR i := 0 TO e.stats.n - 1 DO INC(e.statsTotal, e.stats.items[i](Stat).points) END;
  FOR i := 0 TO e.attributes.n - 1 DO INC(e.attributesTotal, e.attributes.items[i](Attribute).points) END;
  FOR i := 0 TO e.defects.n - 1 DO INC(e.defectsTotal, e.defects.items[i](Defect).points) END;
  FOR i := 0 TO e.skills.n - 1 DO INC(e.skillsTotal, e.skills.items[i](Skill).points) END;
  e.entityTotal := e.statsTotal + e.attributesTotal + e.defectsTotal;
  yerr := NIL; msg := NIL;
  RETURN TRUE
END Load;

END Besm2Entities.
