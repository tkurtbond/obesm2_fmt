MODULE TestStr; (* Besm2Str: lengths, trimming, integers, lists, sorting *)

IMPORT Besm2Str, Check;

VAR
  b: Besm2Str.Buffer;
  l: Besm2Str.List;
  s: Besm2Str.String;
  x, y: ARRAY 16 OF CHAR;
  i: INTEGER;

PROCEDURE Is(s: Besm2Str.String; t: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN (s # NIL) & (s^ = t)
END Is;

PROCEDURE Less(a, b: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Besm2Str.LessCI(a, b)
END Less;

BEGIN
  Check.Check(Besm2Str.Length("Body") = 4, "Length of ASCII text");
  Check.Check(Besm2Str.Length("") = 0, "Length of the empty string");
  (* "×" is C3 97; "“" is E2 80 9C. *)
  Check.Check(Besm2Str.Length("Shots ×2") = 9, "Length counts bytes");
  Check.Check(Besm2Str.DisplayLength("Shots ×2") = 8, "DisplayLength counts UTF-8 characters");
  Check.Check(Besm2Str.DisplayLength("“") = 1, "DisplayLength of a 3-byte character");

  Check.Check(Is(Besm2Str.Of("abc"), "abc"), "Of copies text");
  s := Besm2Str.Of("abc");
  Check.Check(LEN(s^) = 4, "Of sizes the array to the text and its 0X");
  Check.Check(Is(Besm2Str.Empty(), ""), "Empty is empty");

  Check.Check(Is(Besm2Str.Trim("  a b  "), "a b"), "Trim strips blanks at both ends only");
  s := Besm2Str.Concat("text", 0AX);
  Check.Check(Is(Besm2Str.Trim(s^), "text"),
    "Trim strips the newline a literal block scalar ends with");
  Besm2Str.Reset(b);
  Besm2Str.AddChar(b, 09X); Besm2Str.AddChar(b, 0DX); Besm2Str.AddChar(b, 0AX);
  Besm2Str.Add(b, " x"); Besm2Str.AddChar(b, 0AX); Besm2Str.Add(b, "y"); Besm2Str.AddChar(b, 09X);
  s := Besm2Str.Get(b); COPY(s^, x);
  s := Besm2Str.Concat3("x", 0AX, "y"); COPY(s^, y);
  Check.Check(Is(Besm2Str.Trim(x), y), "Trim strips tab, CR and LF, not inside");
  Check.Check(Is(Besm2Str.Trim("   "), ""), "Trim of all blanks is empty");
  Check.Check(Is(Besm2Str.Trim(""), ""), "Trim of the empty string");

  Check.Check(Is(Besm2Str.Int(0), "0"), "Int of 0");
  Check.Check(Is(Besm2Str.Int(42), "42"), "Int of a positive number");
  Check.Check(Is(Besm2Str.Int(-7), "-7"), "Int of a negative number has an ASCII minus");
  Check.Check(Is(Besm2Str.Int(MAX(INTEGER)), "2147483647"), "Int of MAX(INTEGER)");
  Check.Check(Is(Besm2Str.Int(MIN(INTEGER)), "-2147483648"), "Int of MIN(INTEGER)");

  Besm2Str.Reset(b);
  Besm2Str.Add(b, "a"); Besm2Str.AddChar(b, "b"); Besm2Str.AddRepeat(b, "-", 3);
  Besm2Str.AddRepeat(b, "x", 0); Besm2Str.AddRepeat(b, "x", -2); Besm2Str.AddInt(b, 12);
  Check.Check(Is(Besm2Str.Get(b), "ab---12"), "Buffer appends text, characters, repeats, integers");
  Check.Check(Besm2Str.BufLength(b) = 7, "BufLength");
  Besm2Str.Reset(b);
  Check.Check(Is(Besm2Str.Get(b), ""), "Reset empties a Buffer");
  Besm2Str.Reset(b); Besm2Str.AddRepeat(b, "z", 1000);
  s := Besm2Str.Get(b);
  Check.Check(Besm2Str.Length(s^) = 1000, "Buffer grows");
  Check.Check(Is(Besm2Str.Concat3("**", "x", "**"), "**x**"), "Concat3");
  Check.Check(Is(Besm2Str.Repeat("=", 3), "==="), "Repeat");

  Besm2Str.Clear(l);
  Check.Check(Is(Besm2Str.Join(l, ", "), ""), "Join of an empty list");
  Besm2Str.Append(l, Besm2Str.Of("one"));
  Check.Check(Is(Besm2Str.Join(l, ", "), "one"), "Join of one item");
  Besm2Str.Append(l, Besm2Str.Of("two")); Besm2Str.Append(l, Besm2Str.Of("three"));
  Check.Check(Is(Besm2Str.Join(l, ", "), "one, two, three"), "Join of three items");

  Check.Check(Less("apple", "Banana"), "LessCI ignores case (a < B)");
  Check.Check(~Less("Banana", "apple"), "LessCI ignores case (not B < a)");
  Check.Check(~Less("Same", "sAME") & ~Less("sAME", "Same"), "LessCI: equal ignoring case");
  Check.Check(Less("Area", "Area Effect"), "LessCI: a proper prefix comes first");
  Check.Check(Less("Zebra", "Élan"), "LessCI: ASCII before a UTF-8 lead byte");
  (* The Ada To_Lower folding: "É" is C3 89, and C3 is folded to E3,
     past "“" (E2 80 9C), which isn't folded. *)
  Check.Check(Less("“quoted”", "Élan"), "LessCI folds UTF-8 lead byte C3 as Ada's To_Lower does");

  Besm2Str.Clear(l);
  Besm2Str.Append(l, Besm2Str.Of("delta")); Besm2Str.Append(l, Besm2Str.Of("Charlie"));
  Besm2Str.Append(l, Besm2Str.Of("alpha")); Besm2Str.Append(l, Besm2Str.Of("Bravo"));
  s := Besm2Str.Of("ALPHA"); Besm2Str.Append(l, s);
  Besm2Str.SortCI(l);
  Check.Check(Is(Besm2Str.Join(l, ","), "alpha,ALPHA,Bravo,Charlie,delta"),
    "SortCI sorts ignoring case, keeping equal items in order");
  Besm2Str.Clear(l);
  FOR i := 0 TO 15 DO y[0] := CHR(ORD("a") + i); y[1] := 0X; Besm2Str.Append(l, Besm2Str.Of(y)) END;
  Check.Check(l.n = 16, "List grows past its first allocation");
  Check.Check(Is(l.items[15], "p"), "List keeps items in order as it grows");

  Check.Summary
END TestStr.
