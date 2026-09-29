MODULE Besm2Out; (* Where the program's output goes: standard output or a file *)

(* The Ada version sends everything to Ada.Text_IO's current output and
   redirects it for -o/--output with Set_Output.  voc's Out can't be
   redirected, so every output module writes through this one instead,
   and ToFile switches it to a file.

   Writes go through Platform, not Files: Platform.New reports a file
   that can't be created as an error code, where Files defers creating
   it to Register and then halts on failure.  Output is buffered (voc's
   Out writes each line separately, as it flushes on every Out.Ln), so
   call Close, or Flush, before exiting or writing anything else to the
   same place, such as an error on standard error. *)

IMPORT Besm2Str, Platform, SYSTEM;

CONST
  BufSize = 8192;

VAR
  fd: Platform.FileHandle;        (* where output goes *)
  toFile: BOOLEAN;                (* fd is a file from ToFile, not stdout *)
  buf: ARRAY BufSize OF CHAR;
  used: LONGINT;
  error-: Platform.ErrorCode;     (* the first write error, 0 if none *)

(* Writes out what is buffered. *)
PROCEDURE Flush*;
  VAR e: Platform.ErrorCode;
BEGIN
  IF used > 0 THEN
    e := Platform.Write(fd, SYSTEM.ADR(buf[0]), used);
    IF (e # 0) & (error = 0) THEN error := e END;
    used := 0
  END
END Flush;

PROCEDURE Char*(c: CHAR);
BEGIN
  IF used = BufSize THEN Flush END;
  buf[used] := c; INC(used)
END Char;

(* Writes s up to its first 0X. *)
PROCEDURE String*(s: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO Char(s[i]); INC(i) END
END String;

(* Writes s, a String; nothing for NIL.  For the result of a function:
   voc won't pass a dereferenced function result, F()^, as an open
   array, so String(F()^) doesn't compile but Str(F()) does. *)
PROCEDURE Str*(s: Besm2Str.String);
BEGIN
  IF s # NIL THEN String(s^) END
END Str;

(* A line feed, as Ada.Text_IO.New_Line writes. *)
PROCEDURE Ln*;
BEGIN Char(0AX)
END Ln;

(* c, n times; nothing if n <= 0. *)
PROCEDURE Repeat*(c: CHAR; n: LONGINT);
BEGIN
  WHILE n > 0 DO Char(c); DEC(n) END
END Repeat;

(* Sends output from now on to a new file at path, replacing any file
   there.  Returns the error code (0 on success), leaving output on
   standard output if the file can't be created.  Output already
   written stays where it went. *)
PROCEDURE ToFile*(path: ARRAY OF CHAR): Platform.ErrorCode;
  VAR h: Platform.FileHandle; e: Platform.ErrorCode;
BEGIN
  Flush;
  e := Platform.New(path, h);
  IF e = 0 THEN
    IF toFile THEN e := Platform.Close(fd) END;
    fd := h; toFile := TRUE; e := 0
  END;
  RETURN e
END ToFile;

(* Flushes, closes the file if there is one, and goes back to standard
   output.  Returns the first error from writing or closing, 0 if
   none. *)
PROCEDURE Close*(): Platform.ErrorCode;
  VAR e: Platform.ErrorCode;
BEGIN
  Flush;
  IF toFile THEN
    e := Platform.Close(fd);
    IF (e # 0) & (error = 0) THEN error := e END;
    fd := Platform.StdOut; toFile := FALSE
  END;
  RETURN error
END Close;

BEGIN
  fd := Platform.StdOut; toFile := FALSE; used := 0; error := 0
END Besm2Out.
