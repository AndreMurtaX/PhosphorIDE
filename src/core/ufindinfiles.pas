unit ufindinfiles;

{ Search a directory tree for a string, on a thread, without waiting.

  THE ONE RULE THIS UNIT EXISTS TO KEEP is `umainform.pas:6-10`: nothing in the
  editor waits. A tree walk over a network share waits for a long time, and a
  thousand files is long enough on a local disk to be felt. So the walk is a
  THREAD, the matches go into a lock-guarded buffer, and the caller drains that
  buffer from its own timer -- exactly the shape `uphosphorrun` uses for a child
  process's pipes and `udebugtransport` for a socket, and for the same reason.

  NO LCL AND NO TIMER IN HERE. A TTimer needs a widgetset, `phosphoridetest`
  links the LCL and deliberately never creates one, and a timer inside
  udebugtransport once killed that program the first time the transport was
  exercised. The caller decides the cadence and calls Poll; a test calls it in a
  loop. Everything below can therefore be checked headless, which is the whole
  reason the matching lives here rather than in the form.

  WHOLE WORD IS NOT AN OPTION, and that is decided here rather than inherited.
  The editor's own Find and Replace dialogs are created with `frHideWholeWord`
  (`umainform.lfm`), so the box has never been shown even though their handlers
  test for it; offering it in this pane alone would be the one search in the
  program that could do something the others cannot. Match case is offered,
  because both dialogs do show that one.

  A BINARY FILE DOES NOT PRODUCE GARBAGE ROWS. A `.pbc`, an image or an
  executable dropped in a source tree will contain the search string sooner or
  later by accident, and a row of control characters in a results list is worse
  than a missed match nobody wanted. A NUL byte in the first few kilobytes is the
  test: it is what every grep uses, it costs one scan of one block, and no text
  file Phosphor can compile contains one. That block is read BEFORE the rest of
  the file, so a 5 MB executable sitting in a source tree costs four kilobytes
  and not five megabytes.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs;

const
  { How much of a file is inspected before deciding it is binary. Enough to catch
    a header, small enough to be one read. }
  BinarySniffBytes = 4096;

  { A line longer than this is not a line anybody wrote; it is a minified blob or
    a binary that got past the sniff. The match still counts -- the row just does
    not carry the whole of it into a list box. }
  MaxRowText = 400;

type
  TFindHit = record
    Path: String;
    Line: Integer;
    Column: Integer;
    Text: String;      // the matching line, trimmed of its ends and capped
  end;
  TFindHits = array of TFindHit;

  TFindHitsEvent = procedure(Sender: TObject; const AHits: TFindHits) of object;
  TFindDoneEvent = procedure(Sender: TObject; AFilesSeen, AHitCount: Integer;
    ACancelled: Boolean; const AError: String) of object;

  TFindSearch = class;

  { The walker. Nothing outside this unit touches it. }
  TFindThread = class(TThread)
  private
    FOwner: TFindSearch;
    procedure Walk(const ADir: String; ADepth: Integer);
    procedure Scan(const APath: String);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TFindSearch);
  end;

  { One search. Start it, Poll it from a timer, Stop it or let it finish.

    A second Start replaces the first: the thread is asked to stop and joined
    before anything else happens, because two walkers filling one buffer would
    interleave results from two different questions. }
  TFindSearch = class
  private
    FThread: TFindThread;
    FLock: TCriticalSection;
    FPending: TFindHits;       // guarded by FLock
    FPendingCount: Integer;    // guarded by FLock
    FFilesSeen: Integer;       // guarded by FLock
    FHitCount: Integer;        // guarded by FLock
    FFinished: Boolean;        // guarded by FLock
    FCancelled: Boolean;       // guarded by FLock
    FError: String;            // guarded by FLock
    FRaisedDone: Boolean;
    FPattern: String;
    FRoot: String;
    FMask: String;
    FMatchCase: Boolean;
    FOnHits: TFindHitsEvent;
    FOnDone: TFindDoneEvent;
    procedure Deposit(const APath: String; ALine, AColumn: Integer;
      const AText: String);
    procedure NoteFile;
    procedure NoteEnd(const AError: String);
    function TakePending: TFindHits;
  public
    constructor Create;
    destructor Destroy; override;

    { Begin. APattern must not be empty and ARoot must be a directory; both are
      answered False rather than raised, because both are things a person types
      into a box. AMask is a semicolon-separated list like `*.bas;*.txt`; empty
      means every file. }
    function Start(const APattern, ARoot, AMask: String;
      AMatchCase: Boolean): Boolean;

    { Ask the walker to stop. Returns once the thread is gone, which is at most
      one file's worth of work away. }
    procedure Stop;

    { Hand whatever has arrived to OnHits, and fire OnDone once. Called from the
      caller's timer -- or from a loop, in a test. }
    procedure Poll;

    function Running: Boolean;

    property OnHits: TFindHitsEvent read FOnHits write FOnHits;
    property OnDone: TFindDoneEvent read FOnDone write FOnDone;
  end;

{ Where APattern occurs in ALine, 1-based, or 0. Case-insensitive unless asked.

  Its own function because it is the one piece of this unit that is pure, and
  every edge a search has -- an empty pattern, a pattern longer than the line, a
  match at either end -- is decided here where a test can reach it. }
function FindInLine(const ALine, APattern: String; AMatchCase: Boolean): Integer;

{ Does this buffer look like something a person wrote? A NUL byte says no. }
function LooksBinary(const ABuffer: String): Boolean;

{ Does AName match one of the semicolon-separated patterns in AMask? An empty
  mask matches everything. Case-insensitive, because Windows is and a mask that
  behaved differently on the two platforms would be a bug report per platform.

  NOT called MatchesMask: LazUtils has one of those and this unit calls it, and
  a local function of the same name would shadow it inside this unit and resolve
  to whichever the compiler saw last outside it. }
function MatchesFileMask(const AName, AMask: String): Boolean;

implementation

uses
  Math, FileUtil, LazFileUtils, LazUTF8, Masks;

const
  { How deep the walk goes. A tree deeper than this is a symlink loop or a
    mistake, and a search that never returns is worse than one that stops. }
  MaxWalkDepth = 24;
  { How many hits are collected before the caller is given a batch. Small enough
    that a list fills visibly, large enough that a file full of matches does not
    lock the buffer once per line. }
  BatchSize = 64;

function FindInLine(const ALine, APattern: String; AMatchCase: Boolean): Integer;
begin
  Result := 0;
  if (APattern = '') or (Length(APattern) > Length(ALine)) then
    Exit;
  if AMatchCase then
    Result := Pos(APattern, ALine)
  else
    { UTF8LowerCase and not LowerCase: the editor writes UTF-8 and a file may
      hold any of it, and a byte-wise fold turns a two-byte letter into two
      folded bytes that match nothing. It is the same reason TEditorDoc saves
      UTF-8 without a BOM rather than "whatever the code page was". }
    Result := Pos(UTF8LowerCase(APattern), UTF8LowerCase(ALine));
end;

function LooksBinary(const ABuffer: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(ABuffer) do
    if ABuffer[I] = #0 then
      Exit(True);
end;

function MatchesFileMask(const AName, AMask: String): Boolean;
begin
  if Trim(AMask) = '' then
    Exit(True);
  { LazUtils splits the list itself, on the separator this passes, and a mask
    that is only spaces is an empty list rather than a pattern. }
  Result := Masks.MatchesMaskList(AName, AMask, ';', False);
end;

{ ------------------------------------------------------------- the walker - }

constructor TFindThread.Create(AOwner: TFindSearch);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TFindThread.Scan(const APath: String);
var
  Stream: TFileStream;
  Buf, Head, Line: String;
  { LineStart and not Start: TThread publishes a Start method, and a local of
    that name inside a method of a TThread descendant is a duplicate
    identifier -- which reads as a mistake in this unit and is a fact about the
    base class. }
  Got, Size, I, LineStart, LineNo, Col: Integer;
begin
  Buf := '';
  try
    Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      { THE SNIFF BEFORE THE READ, and this order is measured rather than
        tidy. A search of `C:\Dev` with no mask reached 268 files in the second
        and a half before Stop was pressed (2026-09-16, the Windows lane), and
        most of that second was spent reading executables and .ppu files WHOLE
        in order to discover, from their first four kilobytes, that they were
        not text. One block answers the question; the rest of the file is read
        only when the answer is yes. A file too large to hold is skipped by the
        size test in Walk before this is reached. }
      Size := Stream.Size;
      Head := '';
      if Size > 0 then
      begin
        SetLength(Head, Min(Size, BinarySniffBytes));
        Got := Stream.Read(Head[1], Length(Head));
        SetLength(Head, Got);
      end;
      if LooksBinary(Head) then
        Exit;
      Buf := Head;
      if Size > Length(Head) then
      begin
        SetLength(Buf, Size);
        Got := Stream.Read(Buf[Length(Head) + 1], Size - Length(Head));
        SetLength(Buf, Length(Head) + Got);
      end;
    finally
      Stream.Free;
    end;
  except
    { A file that cannot be opened is not an error worth stopping for: a lock,
      a permission, a name that vanished between the listing and the read. The
      search goes on and the count of files seen simply does not include it. }
    on Exception do
      Exit;
  end;

  LineNo := 1;
  LineStart := 1;
  for I := 1 to Length(Buf) + 1 do
  begin
    if (I <= Length(Buf)) and (Buf[I] <> #10) then
      Continue;
    if Terminated then
      Exit;
    Line := Copy(Buf, LineStart, I - LineStart);
    { A CR before the LF is the file's, not the match's. }
    if (Line <> '') and (Line[Length(Line)] = #13) then
      SetLength(Line, Length(Line) - 1);
    Col := FindInLine(Line, FOwner.FPattern, FOwner.FMatchCase);
    if Col > 0 then
      FOwner.Deposit(APath, LineNo, Col, Line);
    Inc(LineNo);
    LineStart := I + 1;
  end;
end;

procedure TFindThread.Walk(const ADir: String; ADepth: Integer);
var
  Rec: TSearchRec;
  Full: String;
begin
  if Terminated or (ADepth > MaxWalkDepth) then
    Exit;
  if FindFirstUTF8(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Rec) <> 0 then
    Exit;
  try
    repeat
      if Terminated then
        Exit;
      if (Rec.Name = '.') or (Rec.Name = '..') then
        Continue;
      Full := IncludeTrailingPathDelimiter(ADir) + Rec.Name;
      if (Rec.Attr and faDirectory) <> 0 then
      begin
        { A dot-directory is somebody's bookkeeping -- .git holds a copy of every
          version of every file, and searching it answers a question nobody
          asked with thousands of rows. }
        if (Rec.Name <> '') and (Rec.Name[1] <> '.') then
          Walk(Full, ADepth + 1);
        Continue;
      end;
      if not MatchesFileMask(Rec.Name, FOwner.FMask) then
        Continue;
      { A file bigger than this is not source. Reading it whole to search it
        would be the one place this editor allocates by the hundred megabyte. }
      if Rec.Size > 16 * 1024 * 1024 then
        Continue;
      FOwner.NoteFile;
      Scan(Full);
    until FindNextUTF8(Rec) <> 0;
  finally
    FindCloseUTF8(Rec);
  end;
end;

procedure TFindThread.Execute;
begin
  try
    Walk(ExcludeTrailingPathDelimiter(FOwner.FRoot), 0);
    FOwner.NoteEnd('');
  except
    on E: Exception do
      { THE THREAD NEVER LETS AN EXCEPTION OUT. One that escaped here would take
        the process down with no message, and the caller would see a search that
        simply stopped. It becomes the reason on OnDone instead. }
      FOwner.NoteEnd(E.ClassName + ': ' + E.Message);
  end;
end;

{ ------------------------------------------------------------ the search -- }

constructor TFindSearch.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TFindSearch.Destroy;
begin
  Stop;
  FLock.Free;
  inherited Destroy;
end;

procedure TFindSearch.Deposit(const APath: String; ALine, AColumn: Integer;
  const AText: String);
var
  Row: TFindHit;
begin
  Row.Path := APath;
  Row.Line := ALine;
  Row.Column := AColumn;
  Row.Text := Trim(AText);
  if Length(Row.Text) > MaxRowText then
    Row.Text := Copy(Row.Text, 1, MaxRowText) + ' ...';

  FLock.Acquire;
  try
    if FPendingCount = Length(FPending) then
      SetLength(FPending, Length(FPending) * 2 + BatchSize);
    FPending[FPendingCount] := Row;
    Inc(FPendingCount);
    Inc(FHitCount);
  finally
    FLock.Release;
  end;
end;

procedure TFindSearch.NoteFile;
begin
  FLock.Acquire;
  try
    Inc(FFilesSeen);
  finally
    FLock.Release;
  end;
end;

procedure TFindSearch.NoteEnd(const AError: String);
begin
  FLock.Acquire;
  try
    FFinished := True;
    FError := AError;
  finally
    FLock.Release;
  end;
end;

function TFindSearch.TakePending: TFindHits;
var
  I: Integer;
begin
  Result := nil;
  FLock.Acquire;
  try
    SetLength(Result, FPendingCount);
    for I := 0 to FPendingCount - 1 do
      Result[I] := FPending[I];
    FPendingCount := 0;
  finally
    FLock.Release;
  end;
end;

function TFindSearch.Start(const APattern, ARoot, AMask: String;
  AMatchCase: Boolean): Boolean;
begin
  Result := False;
  if Trim(APattern) = '' then
    Exit;
  if not DirectoryExistsUTF8(ARoot) then
    Exit;

  { A second search replaces the first, and the first is JOINED before anything
    is reset: two walkers depositing into one buffer would interleave the answers
    to two different questions, and the second one would look wrong. }
  Stop;

  FPattern := APattern;
  FRoot := ARoot;
  FMask := AMask;
  FMatchCase := AMatchCase;
  FPendingCount := 0;
  FFilesSeen := 0;
  FHitCount := 0;
  FFinished := False;
  FCancelled := False;
  FRaisedDone := False;
  FError := '';
  SetLength(FPending, 0);

  FThread := TFindThread.Create(Self);
  Result := True;
end;

procedure TFindSearch.Stop;
begin
  if FThread = nil then
    Exit;
  FLock.Acquire;
  try
    { CANCELLING IS AN ENDING AND THE CALLER HEARS ABOUT IT, because a results
      list that simply stopped growing says nothing about whether the search
      finished or was stopped -- and those are different answers to "did you
      look everywhere". Only counted as a cancellation if the walk had not
      already finished on its own. }
    if not FFinished then
    begin
      FCancelled := True;
      FFinished := True;
    end;
  finally
    FLock.Release;
  end;
  FThread.Terminate;
  { NO SOCKET TO CLOSE AND NOTHING TO WAKE: the walk tests Terminated once per
    file and once per line, so the longest this waits is one file. That is the
    whole reason the test is in both places rather than only between files. }
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

function TFindSearch.Running: Boolean;
begin
  Result := FThread <> nil;
end;

procedure TFindSearch.Poll;
var
  Hits: TFindHits;
  Done, Cancelled: Boolean;
  Files, Count: Integer;
  Err: String;
begin
  Hits := TakePending;
  if (Length(Hits) > 0) and Assigned(FOnHits) then
    FOnHits(Self, Hits);

  { ASK WHETHER IT FINISHED **AFTER** TAKING WHAT IT LEFT, which is the ordering
    rule at uphosphorrun.pas:527-535 written the other way round -- there the
    question comes first because the reader can deposit and end between the two
    reads. Here the thread sets FFinished LAST, after its final Deposit, so
    reading the buffer first and the flag second cannot lose a batch either. }
  FLock.Acquire;
  try
    Done := FFinished;
    Cancelled := FCancelled;
    Files := FFilesSeen;
    Count := FHitCount;
    Err := FError;
  finally
    FLock.Release;
  end;

  if not Done then
    Exit;
  if FRaisedDone then
    Exit;
  FRaisedDone := True;

  { The thread is finished but not yet joined; joining here is immediate and
    leaves Running answering False by the time the caller's handler asks. }
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;

  if Assigned(FOnDone) then
    FOnDone(Self, Files, Count, Cancelled, Err);
end;

end.
