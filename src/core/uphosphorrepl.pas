unit uphosphorrepl;

{ Reading a Phosphor REPL's transcript, and remembering what was typed into it.

  NO LCL IN HERE, for the reason `ubreakpoints`, `uphosphorcomplete`,
  `ufindinfiles` and `uphosphoroutline` have none: everything below is a decision
  about a string, and `tests/phosphoridetest.lpr` pins all of them without a
  window. The pane, the child process and the timer are the form's business.

  WHAT A REPL TRANSCRIPT LOOKS LIKE, MEASURED RATHER THAN IMAGINED. Driven with
  its stdin on a pipe -- which is exactly what the editor gives it --
  `bin/phosphor.exe` answers this, byte for byte:

      Phosphor BASIC 0.0.1 -- REPL. Variables and functions persist across lines.
      Type a multi-line block and it waits for the terminator. Ctrl+Z then Enter to quit.
      phosphor> 42
      phosphor> phosphor> 1
      phosphor>      ...>      ...> 1
      2
      3
      phosphor> phosphor> after
      phosphor> <newline>

  from `println 6*7 / x = 1 / println x / for i = 1 to 3 / println i / next /
  nosuchthing( / println "after"`, with `error: unexpected token in expression`
  on STDERR and exit 0. Four things in that are load-bearing:

  - THE PROMPT IS NOT A LINE. It is written before every read and carries no
    newline (`Phosphor host/console/phosphor.lpr:3899`), so it reaches the editor
    through `TPhosphorRunner.FlushPrompt` as an unterminated tail with
    `ACompleteLine = False`. It is also not conditional on stdout being a
    console, which is why it arrives over a pipe at all.
  - A LINE THAT PRODUCES NO OUTPUT PUTS TWO PROMPTS ON ONE LINE. `x = 1` prints
    nothing, so the next prompt lands against the previous one and the pair
    arrives glued to whatever is printed after them. That is what
    `SplitReplPrompts` is for.
  - THE CONTINUATION PROMPT IS FIVE SPACES AND `...> `, and it appears once per
    continued line, so a three-line block shows two of them.
  - AN ERROR IS `error: <msg>` ON STDERR with no prefix, no path and no line.
    `uphosphormsg` already classifies that as `pmkReplError` and already refuses
    it as a jump target; nothing here needs to know about it.

    ON LINUX IT ARRIVES LATE, and that is the host's and not this editor's.
    FPC's StdErr is a buffered text file, nothing in the REPL loop flushes it,
    and on Unix the bytes therefore sit in the buffer until the process exits --
    so a diagnostic for a line typed at 10:00 lands underneath whatever has
    happened since. Measured on both platforms with a driver holding the pipes,
    2026-09-16, and written up in `docs/phosphor-repl-debt.md` with the one-line
    ask. Nothing here compensates for it: `TPhosphorRunner` shows lines in the
    order the bytes arrive, and inventing an order would be this side guessing
    at something only the host knows.

  THE PROMPTS ARE CITED, NOT EXTRACTED, and that is a deliberate exception to the
  rule at the top of CLAUDE.md. There is no registry to read them out of -- they
  are two string literals inside a `Writeln` in another repository -- so the rule
  says cite the source with a line number, which is what the constants below do.
  If a Phosphor release changes them, nothing here breaks loudly: an unrecognised
  prompt is simply emitted verbatim as ordinary text and the transcript reads one
  line less tidily. That is the right failure for a cosmetic fact.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { Phosphor host/console/phosphor.lpr:3899, both of them, on one line:
      if pending = '' then host.Output('phosphor> ') else host.Output('     ...> ');
    The trailing space is part of each, and the continuation is FIVE spaces. }
  ReplPrompt = 'phosphor> ';
  ReplContinuation = '     ...> ';

  { A transcript keeps this many lines, for the reason MaxOutputLines exists: a
    program printing without end must not make the editor its memory problem.
    The oldest go first, which is the half nobody was reading. }
  MaxReplLines = 5000;

  { How many lines of history a session remembers. A person does not scroll back
    past this, and an unbounded list is an unbounded list. }
  MaxReplHistory = 200;

type
  TReplSegment = record
    Text: String;
    IsPrompt: Boolean;
  end;
  TReplSegments = array of TReplSegment;

{ Split one emitted line or fragment into prompt segments and the rest.

  A PROMPT CAN ONLY BE AT THE START, or immediately after another prompt. That
  is not a simplification -- it is what the host does: the prompt is written
  before the read, so anything that follows on the same line is the answer to it.
  The rule is what keeps `println "phosphor> done"` intact: a prompt-looking
  string in the MIDDLE of a line is text somebody printed.

  CONCATENATING THE SEGMENTS REPRODUCES THE INPUT, byte for byte, always. The
  caller may paint them differently; it may not lose one. }
function SplitReplPrompts(const AText: String): TReplSegments;

{ Is the whole of AText nothing but prompts? Such a fragment is where the caret
  goes, and the caller shows it without a newline after it. }
function IsAllPrompt(const AText: String): Boolean;

type
  { What was typed into the prompt, and how Up and Down walk it.

    Every rule here is about a string and an index, which is why it is in this
    unit and not in the form. The one that is not obvious is the DRAFT: pressing
    Up with a half-typed line has to be undoable, so the first Up stashes what
    was there and Down past the newest gives it back. Without that, one keystroke
    silently destroys what somebody was in the middle of writing. }
  TReplHistory = class
  private
    FLines: TStringList;
    FIndex: Integer;      // -1 = not walking; otherwise an index into FLines
    FDraft: String;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    { Remember a line that was sent. An empty one is not remembered, and neither
      is one identical to the line before it -- pressing Enter twice on the same
      thought should not need two Ups to get back past. }
    procedure Add(const ALine: String);

    { Walk back. ACurrent is what is in the box right now, and it is stashed on
      the FIRST step so that walking forward again can restore it. At the oldest
      entry it stays there. }
    function Older(const ACurrent: String): String;

    { Walk forward. Past the newest entry it answers the stashed draft and stops
      there, which is the position a person expects to land in. }
    function Newer: String;

    { Back to the draft position, and forget the draft. Called when a line is
      sent: the next Up starts from the end again. }
    procedure Reset;

    { True while Up/Down are walking rather than sitting on the draft. }
    function Walking: Boolean;

    procedure Clear;
    property Count: Integer read GetCount;
  end;

implementation

function StartsWithAt(const AText, APrefix: String; APos: Integer): Boolean;
begin
  Result := (APrefix <> '') and (APos >= 1) and
            (APos + Length(APrefix) - 1 <= Length(AText)) and
            (Copy(AText, APos, Length(APrefix)) = APrefix);
end;

function SplitReplPrompts(const AText: String): TReplSegments;
var
  { At and not Pos: Pos is a function in scope here, and a local that shadows one
    compiles and then reads as a mistake to everybody who meets it. }
  At, N: Integer;

  procedure Emit(const AWhat: String; APrompt: Boolean);
  begin
    if AWhat = '' then
      Exit;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Text := AWhat;
    Result[N].IsPrompt := APrompt;
  end;

begin
  Result := nil;
  if AText = '' then
    Exit;

  At := 1;
  while StartsWithAt(AText, ReplPrompt, At) or
        StartsWithAt(AText, ReplContinuation, At) do
  begin
    if StartsWithAt(AText, ReplPrompt, At) then
    begin
      Emit(ReplPrompt, True);
      Inc(At, Length(ReplPrompt));
    end
    else
    begin
      Emit(ReplContinuation, True);
      Inc(At, Length(ReplContinuation));
    end;
  end;

  Emit(Copy(AText, At, MaxInt), False);
end;

function IsAllPrompt(const AText: String): Boolean;
var
  Segs: TReplSegments;
  I: Integer;
begin
  Segs := SplitReplPrompts(AText);
  Result := Length(Segs) > 0;
  for I := 0 to High(Segs) do
    if not Segs[I].IsPrompt then
      Exit(False);
end;

{ ---------------------------------------------------------------- history --- }

constructor TReplHistory.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FIndex := -1;
  FDraft := '';
end;

destructor TReplHistory.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

function TReplHistory.GetCount: Integer;
begin
  Result := FLines.Count;
end;

procedure TReplHistory.Add(const ALine: String);
begin
  if Trim(ALine) = '' then
    Exit;
  if (FLines.Count > 0) and (FLines[FLines.Count - 1] = ALine) then
    Exit;
  FLines.Add(ALine);
  while FLines.Count > MaxReplHistory do
    FLines.Delete(0);
end;

function TReplHistory.Older(const ACurrent: String): String;
begin
  Result := ACurrent;
  if FLines.Count = 0 then
    Exit;
  if FIndex < 0 then
  begin
    { THE FIRST STEP STASHES THE DRAFT. Without this, one Up destroys a
      half-typed line and nothing brings it back. }
    FDraft := ACurrent;
    FIndex := FLines.Count - 1;
  end
  else if FIndex > 0 then
    Dec(FIndex);
  Result := FLines[FIndex];
end;

function TReplHistory.Newer: String;
begin
  if FIndex < 0 then
    Exit(FDraft);
  if FIndex >= FLines.Count - 1 then
  begin
    { Past the newest is the draft, and it stops there rather than wrapping. }
    FIndex := -1;
    Exit(FDraft);
  end;
  Inc(FIndex);
  Result := FLines[FIndex];
end;

procedure TReplHistory.Reset;
begin
  FIndex := -1;
  FDraft := '';
end;

function TReplHistory.Walking: Boolean;
begin
  Result := FIndex >= 0;
end;

procedure TReplHistory.Clear;
begin
  FLines.Clear;
  Reset;
end;

end.
