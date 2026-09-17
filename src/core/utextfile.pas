unit utextfile;

{ What a text file's bytes look like, and how to change some of them without
  changing the rest.

  WHY THIS IS A UNIT AND NOT THREE FUNCTIONS IN THE DOCUMENT. Two things rewrite
  a `.bas` in this editor -- `TEditorDoc.SaveToFile`, for the file in a tab, and
  roadmap item 21's replace-in-files, for the files that are not -- and they must
  agree to the byte about what a line ending is. They cannot share code that
  lives in `ueditordoc`, and the reason is worth carrying:

      A PROGRAM THAT LINKS `SynEdit` CANNOT RUN HEADLESS. `synedit.pp`'s
      initialization calls `InitSynDefaultFont`, whose first act is
      `Screen.Fonts` -- the system's font list, which needs a widgetset. Without
      one the process dies BEFORE `main`, silently, with exit code 0 and no
      output: measured on 2026-09-17 by bisecting a probe that wrote a file as
      its very first statement and never wrote it. It is the same trap
      `CLAUDE.md` records for `Interfaces`, one unit further in, and it is why
      `tests/phosphoridetest.lpr` has always named `SynEditHighlighter` and
      `SynEditTextBuffer` and never `SynEdit`.

  So the rules live here, with no LCL in the unit at all, and `phosphoridetest`
  pins every one of them without a window.

  THE RULE ITSELF: A FILE IS GIVEN BACK THE ENDINGS IT CAME WITH. Until
  2026-09-17 this editor did not do that. `TStrings.Text` joins with
  `TextLineBreakStyle`, which defaults to the machine's own convention
  (`stringl.inc`, `GetTextStr` -> `GetLineBreakCharLBS`) and which
  `TSynEditStringList` does not override -- so a program written on Linux,
  opened on Windows and saved with one character changed came back with EVERY
  LINE ENDING REWRITTEN. Measured through the real editor: Ctrl+S on
  `rem a\nx = 1\n` returned `rem a\r\nx = 1\r\n`, and a file that did not end
  with a newline gained one. No error, no warning, and only the bytes to show it.

  It was a defect before roadmap item 21 and item 21 made it blocking: a replace
  across a tree may not change one thing it was not asked to.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { What a file's bytes said about its own shape. }
  TTextShape = record
    Ending: String;        // #13#10, #10, or #13
    FinalNewline: Boolean; // did the last line carry one
  end;

{ Read APath's bytes as they are -- no splitting, no conversion, no BOM
  handling. Raises on an unreadable file, because the caller has a user to tell. }
function ReadWholeFile(const APath: String): String;

{ Write AText's bytes exactly, through a temporary beside the target so that a
  full disk or a dropped share cannot leave half a file where a whole one was.
  This is the only writer in the program besides TEditorDoc.SaveToFile, and the
  two agree because SaveToFile calls it. }
procedure WriteWholeFile(const APath, AText: String);

{ WHICH ENDING THIS TEXT USES, AND WHETHER IT CLOSES WITH ONE.

  THE FIRST BREAK DECIDES. A file with mixed endings is one somebody's tools
  disagreed about; taking the first at least leaves the majority of such a file
  alone, where taking the platform's would rewrite all of it. Empty text, or text
  with no break at all, answers the platform's convention -- there is nothing to
  preserve and something has to be chosen. }
function DetectShape(const AText: String): TTextShape;

{ Split AText on any of CRLF, LF or CR, dropping the terminators. A trailing
  terminator does NOT produce a final empty line: `a\nb\n` is two lines, which is
  what every editor shows and what JoinLines puts back. }
procedure SplitLines(const AText: String; ALines: TStrings);

{ The inverse, using AShape. JoinLines(SplitLines(t)) is t for every t this unit
  can be given -- which is the property that makes a rewrite safe, and which
  `phosphoridetest` checks over a table of shapes rather than trusting it. }
function JoinLines(ALines: TStrings; const AShape: TTextShape): String;

implementation

function ReadWholeFile(const APath: String): String;
var
  Stream: TFileStream;
begin
  Result := '';
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[1], Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure WriteWholeFile(const APath, AText: String);
var
  Stream: TFileStream;
  Temp: String;
begin
  { WRITE BESIDE THE FILE, THEN REPLACE IT. fmCreate truncates the target the
    instant it is opened, so a disk that fills, a network share that drops or a
    process killed mid-write leaves a file that is empty or half a program --
    and the version that was there is gone. The user's only copy was the one
    just destroyed by the act of trying to save it.

    The temporary lives in the SAME directory, because a rename across a
    filesystem is a copy and stops being atomic. }
  Temp := APath + '.tmp-phosphoride';
  Stream := TFileStream.Create(Temp, fmCreate);
  try
    try
      if Length(AText) > 0 then
        Stream.WriteBuffer(AText[1], Length(AText));
    finally
      Stream.Free;
    end;

    { RenameFile does not overwrite on Windows, so the target goes first -- and
      only once the new bytes are known to be safely written. }
    if FileExists(APath) and not DeleteFile(APath) then
      raise EWriteError.CreateFmt('cannot replace %s', [APath]);
    if not RenameFile(Temp, APath) then
      raise EWriteError.CreateFmt('wrote %s but could not rename it to %s',
        [Temp, APath]);
  except
    { The half-written temporary is this unit's mess to clear up; leaving one
      beside every failed save is its own small defect. }
    if FileExists(Temp) then
      DeleteFile(Temp);
    raise;
  end;
end;

function DetectShape(const AText: String): TTextShape;
var
  I: Integer;
begin
  Result.Ending := System.LineEnding;
  Result.FinalNewline := True;
  if AText = '' then
    Exit;
  Result.FinalNewline := (AText[Length(AText)] = #10) or
                         (AText[Length(AText)] = #13);
  for I := 1 to Length(AText) do
  begin
    if AText[I] = #13 then
    begin
      if (I < Length(AText)) and (AText[I + 1] = #10) then
        Result.Ending := #13#10
      else
        { A lone CR: the convention no current system writes, and cheap enough
          to keep rather than silently convert somebody's file to something
          else. }
        Result.Ending := #13;
      Exit;
    end;
    if AText[I] = #10 then
    begin
      Result.Ending := #10;
      Exit;
    end;
  end;
  { No break anywhere: one line, and nothing to preserve. }
end;

procedure SplitLines(const AText: String; ALines: TStrings);
var
  I, Start: Integer;
begin
  ALines.Clear;
  if AText = '' then
    Exit;
  Start := 1;
  I := 1;
  while I <= Length(AText) do
  begin
    if AText[I] = #13 then
    begin
      ALines.Add(Copy(AText, Start, I - Start));
      if (I < Length(AText)) and (AText[I + 1] = #10) then
        Inc(I);
      Inc(I);
      Start := I;
    end
    else if AText[I] = #10 then
    begin
      ALines.Add(Copy(AText, Start, I - Start));
      Inc(I);
      Start := I;
    end
    else
      Inc(I);
  end;
  { WHAT IS LEFT AFTER THE LAST TERMINATOR, and only if there is anything. A
    file ending in a newline has no final empty line -- see the header. }
  if Start <= Length(AText) then
    ALines.Add(Copy(AText, Start, Length(AText) - Start + 1));
end;

function JoinLines(ALines: TStrings; const AShape: TTextShape): String;
var
  I: Integer;
begin
  Result := '';
  if ALines.Count = 0 then
    Exit;
  for I := 0 to ALines.Count - 1 do
  begin
    if I > 0 then
      Result := Result + AShape.Ending;
    Result := Result + ALines[I];
  end;
  if AShape.FinalNewline then
    Result := Result + AShape.Ending;
end;

end.
