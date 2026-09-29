MODULE Besm2Str; (* Heap strings, string lists and a string builder *)

(* What the Ada version gets from Unbounded_String, Ada.Strings.Fixed,
   Integer'Image and Vectors of Unbounded_String.  Oberon-2 function
   procedures can't return arrays, so a string is a String: a pointer
   to a 0X-terminated ARRAY OF CHAR, whose text ends at the first 0X
   (LEN counts the array, not the text).  Strings are never changed
   once built, so they may be shared.

   Independent of Fyaml, like the Ada Text_Layout, so it can be tested
   without YAML.  Lengths are in bytes; DisplayLength counts UTF-8
   characters. *)

TYPE
  String* = POINTER TO ARRAY OF CHAR;
  Strings* = POINTER TO ARRAY OF String;

  (* A growable list of strings: items[0 .. n-1].  Clear a List
     before its first use: a local one is not initialized. *)
  List* = RECORD
    items-: Strings;
    n-: INTEGER
  END;

  (* Builds a string by appending; Get returns a copy of the text so
     far.  Reset a Buffer before its first use: a local one is not
     initialized. *)
  Buffer* = RECORD
    s: String;
    len: LONGINT
  END;

VAR
  empty: String;

(* The bytes of s before its first 0X (or all of s if it has none). *)
PROCEDURE Length*(s: ARRAY OF CHAR): LONGINT;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
  RETURN i
END Length;

(* The number of characters in s, a UTF-8 string -- not its length in
   bytes.  Counts every byte that isn't a UTF-8 continuation byte
   (80X..0BFX); doesn't check that s is well-formed UTF-8.  The
   column widths of the grid tables are measured with this, as
   besm2-rst.scm's are with Chicken's character-counting
   string-length; with a byte count, a column holding a curly quote
   or a "×" would come out narrow and the table borders wouldn't line
   up. *)
PROCEDURE DisplayLength*(s: ARRAY OF CHAR): LONGINT;
  VAR i, n: LONGINT;
BEGIN
  i := 0; n := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF (s[i] < 80X) OR (s[i] > 0BFX) THEN INC(n) END;
    INC(i)
  END;
  RETURN n
END DisplayLength;

(* A new String holding s[start .. start+len-1]. *)
PROCEDURE Slice(VAR s: ARRAY OF CHAR; start, len: LONGINT): String;
  VAR r: String; i: LONGINT;
BEGIN
  NEW(r, len + 1);
  FOR i := 0 TO len - 1 DO r[i] := s[start + i] END;
  r[len] := 0X;
  RETURN r
END Slice;

(* A new String holding the text of s. *)
PROCEDURE Of*(s: ARRAY OF CHAR): String;
BEGIN RETURN Slice(s, 0, Length(s))
END Of;

(* The empty string, shared. *)
PROCEDURE Empty*(): String;
BEGIN RETURN empty
END Empty;

PROCEDURE IsSpace(c: CHAR): BOOLEAN;
BEGIN RETURN (c = " ") OR (c = 09X) OR (c = 0AX) OR (c = 0DX)
END IsSpace;

(* s without leading and trailing blanks, tabs, line feeds and carriage
   returns.  All four, not just blanks: a YAML literal block scalar
   ("details: |") ends with a newline, which besm2-rst.scm's
   string-trim-both removes, and which would otherwise end up in the
   middle of a sentence in the output (a bug the Ada port hit with
   Ada.Strings.Fixed.Trim, which strips only blanks). *)
PROCEDURE Trim*(s: ARRAY OF CHAR): String;
  VAR first, last: LONGINT;
BEGIN
  first := 0; last := Length(s) - 1;
  WHILE (first <= last) & IsSpace(s[first]) DO INC(first) END;
  WHILE (last >= first) & IsSpace(s[last]) DO DEC(last) END;
  RETURN Slice(s, first, last - first + 1)
END Trim;

(* Ada.Characters.Handling.To_Lower, which the Ada version sorts with:
   it lowers A..Z and also the Latin-1 capitals C0X..DEX except D7X.
   In UTF-8 those are lead bytes, so this doesn't lower non-ASCII
   letters, but it does move names starting with some of them (C3X,
   for example, becomes E3X) relative to others.  Copied as is so that
   names sort as they do in the Ada version (PLAN.md, open questions). *)
PROCEDURE Lower(c: CHAR): CHAR;
BEGIN
  IF ((c >= "A") & (c <= "Z")) OR ((c >= 0C0X) & (c <= 0DEX) & (c # 0D7X)) THEN
    RETURN CHR(ORD(c) + 32)
  END;
  RETURN c
END Lower;

(* TRUE if a comes before b ignoring case, as the Ada version's CI_Less:
   both lowered, then compared byte by byte, a proper prefix first. *)
PROCEDURE LessCI*(VAR a, b: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT; ca, cb: CHAR;
BEGIN
  i := 0;
  LOOP
    IF i < LEN(a) THEN ca := Lower(a[i]) ELSE ca := 0X END;
    IF i < LEN(b) THEN cb := Lower(b[i]) ELSE cb := 0X END;
    IF ca # cb THEN RETURN ca < cb END;
    IF ca = 0X THEN RETURN FALSE END;
    INC(i)
  END
END LessCI;

(* ---- Buffer ---- *)

(* Always allocates: a local Buffer's pointer is garbage before its
   first Reset, not NIL (voc doesn't zero local records; confirmed,
   when testing "allocate only if NIL" halted with "Index out of
   range"). *)
PROCEDURE Reset*(VAR b: Buffer);
BEGIN
  NEW(b.s, 64); b.len := 0; b.s[0] := 0X
END Reset;

(* Room for n more bytes and the 0X. *)
PROCEDURE Reserve(VAR b: Buffer; n: LONGINT);
  VAR t: String; i: LONGINT;
BEGIN
  IF b.len + n + 1 > LEN(b.s^) THEN
    NEW(t, 2 * (b.len + n + 1));
    FOR i := 0 TO b.len DO t[i] := b.s[i] END;
    b.s := t
  END
END Reserve;

PROCEDURE Add*(VAR b: Buffer; s: ARRAY OF CHAR);
  VAR i, n: LONGINT;
BEGIN
  n := Length(s);
  Reserve(b, n);
  FOR i := 0 TO n - 1 DO b.s[b.len + i] := s[i] END;
  INC(b.len, n); b.s[b.len] := 0X
END Add;

PROCEDURE AddChar*(VAR b: Buffer; c: CHAR);
BEGIN
  Reserve(b, 1);
  b.s[b.len] := c; INC(b.len); b.s[b.len] := 0X
END AddChar;

(* Appends c n times; nothing if n <= 0. *)
PROCEDURE AddRepeat*(VAR b: Buffer; c: CHAR; n: LONGINT);
BEGIN
  WHILE n > 0 DO AddChar(b, c); DEC(n) END
END AddRepeat;

(* Appends i in decimal, with a leading "-" if negative and no blanks,
   as the Ada version's Trim (Integer'Image (i), Left). *)
PROCEDURE AddInt*(VAR b: Buffer; i: INTEGER);
  VAR digits: ARRAY 12 OF CHAR; n: INTEGER; u: LONGINT;
BEGIN
  (* INTEGER is 32 bits and LONGINT 64 under -OC, so -u can't overflow
     even for MIN(INTEGER), and DIV and MOD only see non-negative
     values (voc's DIV misbehaves near MIN(LONGINT): olibfyaml's
     AGENTS.md). *)
  u := i;
  IF u < 0 THEN AddChar(b, "-"); u := -u END;
  n := 0;
  REPEAT
    digits[n] := CHR(ORD("0") + SHORT(u MOD 10)); u := u DIV 10; INC(n)
  UNTIL u = 0;
  WHILE n > 0 DO DEC(n); AddChar(b, digits[n]) END
END AddInt;

(* A copy of b's text. *)
PROCEDURE Get*(VAR b: Buffer): String;
BEGIN
  RETURN Slice(b.s^, 0, b.len)
END Get;

PROCEDURE BufLength*(VAR b: Buffer): LONGINT;
BEGIN RETURN b.len
END BufLength;

(* ---- Conveniences built on Buffer ---- *)

(* i in decimal, as AddInt writes it. *)
PROCEDURE Int*(i: INTEGER): String;
  VAR b: Buffer;
BEGIN Reset(b); AddInt(b, i); RETURN Get(b)
END Int;

PROCEDURE Concat*(a, b: ARRAY OF CHAR): String;
  VAR buf: Buffer;
BEGIN Reset(buf); Add(buf, a); Add(buf, b); RETURN Get(buf)
END Concat;

PROCEDURE Concat3*(a, b, c: ARRAY OF CHAR): String;
  VAR buf: Buffer;
BEGIN Reset(buf); Add(buf, a); Add(buf, b); Add(buf, c); RETURN Get(buf)
END Concat3;

(* c n times; the empty string if n <= 0. *)
PROCEDURE Repeat*(c: CHAR; n: LONGINT): String;
  VAR buf: Buffer;
BEGIN Reset(buf); AddRepeat(buf, c, n); RETURN Get(buf)
END Repeat;

(* ---- List ---- *)

PROCEDURE Clear*(VAR l: List);
BEGIN l.items := NIL; l.n := 0
END Clear;

PROCEDURE Append*(VAR l: List; s: String);
  VAR t: Strings; i: INTEGER;
BEGIN
  IF l.items = NIL THEN NEW(l.items, 8); l.n := 0
  ELSIF l.n = LEN(l.items^) THEN
    NEW(t, 2 * l.n);
    FOR i := 0 TO l.n - 1 DO t[i] := l.items[i] END;
    l.items := t
  END;
  l.items[l.n] := s; INC(l.n)
END Append;

(* Appends every item of from to l. *)
PROCEDURE AppendList*(VAR l: List; VAR from: List);
  VAR i: INTEGER;
BEGIN
  FOR i := 0 TO from.n - 1 DO Append(l, from.items[i]) END
END AppendList;

(* The items joined with sep between them; "" for an empty list. *)
PROCEDURE Join*(VAR l: List; sep: ARRAY OF CHAR): String;
  VAR buf: Buffer; i: INTEGER;
BEGIN
  Reset(buf);
  FOR i := 0 TO l.n - 1 DO
    IF i > 0 THEN Add(buf, sep) END;
    Add(buf, l.items[i]^)
  END;
  RETURN Get(buf)
END Join;

(* Sorts l by LessCI.  An insertion sort: stable, and the lists here
   are a handful of items. *)
PROCEDURE SortCI*(VAR l: List);
  VAR i, j: INTEGER; s: String;
BEGIN
  FOR i := 1 TO l.n - 1 DO
    s := l.items[i]; j := i;
    WHILE (j > 0) & LessCI(s^, l.items[j - 1]^) DO
      l.items[j] := l.items[j - 1]; DEC(j)
    END;
    l.items[j] := s
  END
END SortCI;

BEGIN
  NEW(empty, 1); empty[0] := 0X
END Besm2Str.
