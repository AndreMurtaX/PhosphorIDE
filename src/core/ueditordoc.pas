unit ueditordoc;

{ One open file: its SynEdit, where it came from, and the lines the user has
  marked as breakpoints.

  The editor control is CREATED HERE rather than dropped on a form, because there
  is one per tab and the number of tabs is not known until someone opens a file.
  Everything a tab needs to know about itself lives on this object, so the main
  form's job is reduced to asking the active document questions.

  BREAKPOINTS ARE KEPT EVEN THOUGH NOTHING CAN STOP AT ONE YET. The phosphor host
  has no way for an outside process to pause a running program -- see
  docs/debug-protocol.md -- so a breakpoint set today is a mark in a margin and a
  line in a session file, and that is all. Keeping them anyway is deliberate: the
  editor side of debugging is the half that can be built and tested now, and a
  breakpoint list that already survives editing is what the other half will need
  the day the host can answer.

  Which is the interesting part: breakpoints are attached to LINE NUMBERS, and
  line numbers move when text above them is edited. The set itself lives in
  ubreakpoints, where it can be tested without a window; what THIS unit adds is
  the wiring -- a handler on SynEdit's own senrLineCount notification, so that
  inserting a line at the top does not silently move every mark one statement down
  from the statement the user chose. Writing the arithmetic and forgetting the
  handler is exactly the defect this comment exists to prevent a second time: it
  was found on 2026-09-10, by grepping for callers of a method that had none. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, SynEdit, LazSynEditText, SynEditFoldedView,
  ubreakpoints, utextfile;

type
  { Says the breakpoint SET moved, and whether an edit is what moved it. The
    flag exists because those two cases need different timing from a listener;
    TEditorDoc.LinesChanged says why. }
  TBreakpointsChangedEvent = procedure(Sender: TObject;
    AFromEdit: Boolean) of object;

  TEditorDoc = class
  private
    FEdit: TSynEdit;
    FFileName: String;
    { WHAT THE FILE ON DISK USED, so that saving it gives it back. Both are set
      by LoadFromFile and defaulted for a buffer that has never been one. }
    FShape: TTextShape;
    FBlameLine: Integer;
    FUntitledIndex: Integer;
    FBreakpoints: TBreakpointSet;
    FOnBreakpointsChanged: TBreakpointsChangedEvent;
    FOnFoldsChanged: TNotifyEvent;
    { SynEdit's own notification that lines were inserted or removed. Registering
      for it is what makes a breakpoint follow its statement; without it the marks
      stay on their line numbers while the text slides out from under them, which
      is invisible until the day something actually stops at one. }
    procedure LinesChanged(Sender: TSynEditStrings; AIndex, ACount: Integer);
    { A FOLD OPENED OR CLOSED. Not an edit: no line moved and the set did not
      change. What changed is which lines are DRAWN, and the gutter's marks are a
      picture of the set, so the picture has to be taken again. }
    procedure FoldsChanged(Sender: TSynEditStrings; AIndex, ACount: Integer);
    { A LINE'S TEXT CHANGED, which is a different notification from a line being
      added or removed. Roadmap item 24 needs both: the blamed line FOLLOWS an
      insertion above it and LOSES ITS MARK when it is itself typed into. }
    procedure LineEdited(Sender: TSynEditStrings; AIndex, ACount: Integer);
    function FoldedView: TSynEditFoldedView;
    procedure Changed(AFromEdit: Boolean);
    function GetModified: Boolean;
    procedure SetModified(AValue: Boolean);
    function GetCaretLine: Integer;
    function GetCaretCol: Integer;
    function GetBreakpointCount: Integer;
    function GetBreakpoint(AIndex: Integer): Integer;
  public
    { Creates the SynEdit as a child of AParent. The control is owned by AParent,
      so freeing the tab frees the editor; this object owns nothing but its lists
      and must be freed alongside. }
    constructor Create(AParent: TWinControl);
    destructor Destroy; override;

    { Reads APath as UTF-8. Raises on an unreadable file -- the caller has a user
      to tell. }
    procedure LoadFromFile(const APath: String);

    { Writes UTF-8 with NO byte-order mark. This is not a preference: the Phosphor
      lexer has no BOM handling at all, and a leading BOM byte is the lexical
      error `unexpected character` on line 1 of an otherwise perfect program. Every
      Windows editor and `Set-Content -Encoding utf8` writes one, which is how
      that trap earned its comment in the lexer.

      AND IT GIVES THE FILE BACK THE LINE ENDINGS IT CAME WITH. See the body. }
    procedure SaveToFile(const APath: String);

    { The tab's caption: the file's name, or `untitled-3`, with a leading `*`
      while there are unsaved changes. }
    function DisplayName: String;

    { The name to show in the window title and the status bar: the full path, or
      the untitled name. }
    function FullDisplayName: String;

    { True when this document has never been saved and so has no path. }
    function IsUntitled: Boolean;

    procedure ToggleBreakpoint(ALine: Integer);
    procedure ClearBreakpoints;
    function HasBreakpoint(ALine: Integer): Boolean;

    { WHICH VISIBLE ROW IS STANDING IN FOR THIS LINE, or 0 when the line is
      drawn. A fold hides lines; the row the user can still see and click is the
      collapsed header, and with blocks nested inside blocks it is the OUTERMOST
      collapsed one -- `CollapsedLineForFoldAtLine` answers that and
      `ExpandedLineForBlockAtLine` does not, which is why only the first appears
      here (measured 2026-09-17: with a `for` inside a collapsed `function`,
      every line of the `for` answers the `function`'s header). }
    function CollapsedHeaderFor(ALine: Integer): Integer;

    { How many breakpoints this visible row is hiding underneath it. Zero for an
      ordinary line, and zero for a collapsed header whose block holds none. }
    function HiddenBreakpointCount(AHeaderLine: Integer): Integer;

    { Open the block whose header is AHeaderLine. Nothing happens if it is not a
      collapsed header. The caret is NOT moved: this is a reveal, not a jump. }
    procedure RevealFoldAt(AHeaderLine: Integer);

    { THE LINE THE LAST RUN BLAMED, or 0. Roadmap item 24.

      IT IS A MEMORY OF A RUN AND NOT AN OPINION ABOUT THE TEXT. Nothing here
      compiles anything; this is what the host said, the last time it was asked,
      about the file as it then stood. So it follows an insertion above it the
      way a breakpoint does -- the arithmetic is the same `TrackLine` -- and it
      is DROPPED the moment the line itself is typed into, because a claim about
      text that has changed is a claim about text that no longer exists.

      The caller clears it when a run starts, unconditionally: unlike the
      Problems pane, which empties only when a preference says so, a mark in the
      TEXT that outlived the run that produced it would be a lie whatever that
      preference says. }
    property BlameLine: Integer read FBlameLine write FBlameLine;

    property Edit: TSynEdit read FEdit;
    property FileName: String read FFileName write FFileName;
    { The line ending this document will be written with -- the one its file
      arrived with, or the platform's for a buffer that has never been saved.
      Readable so that a caller rewriting the file by another route can match it. }
    property Shape: TTextShape read FShape;
    property UntitledIndex: Integer read FUntitledIndex write FUntitledIndex;
    property Modified: Boolean read GetModified write SetModified;
    property CaretLine: Integer read GetCaretLine;
    property CaretCol: Integer read GetCaretCol;
    property BreakpointCount: Integer read GetBreakpointCount;
    property Breakpoints[AIndex: Integer]: Integer read GetBreakpoint;
    { The whole set, for handing to a debug adapter. }
    property BreakpointSet: TBreakpointSet read FBreakpoints;
    { Fired when a fold opened or closed. The SET did not change -- this is the
      one event here that says only "the picture is stale". }
    property OnFoldsChanged: TNotifyEvent read FOnFoldsChanged write FOnFoldsChanged;

    { Fired whenever the SET changed -- a toggle, a clear, or an edit that moved
      or dropped one. It exists because the gutter's marks are a SECOND copy of
      this information, drawn by SynEdit and kept by the window, and the two
      copies must not be allowed to disagree.

      THE EDIT CASE IS THE ONE THAT NEEDS AN EVENT. A toggle is a call the window
      already makes, so it could refresh afterwards by hand; an edit is not.
      SynEdit moves its own marks when lines are inserted or removed, and
      TBreakpointSet.TrackEdit moves these -- two pieces of arithmetic that agree
      until they do not: TrackEdit DROPS a breakpoint whose line was deleted, and
      nothing says SynEdit's marks make the same choice. So the set stays the
      truth, this says it moved, and the window rebuilds the marks from it. }
    property OnBreakpointsChanged: TBreakpointsChangedEvent
      read FOnBreakpointsChanged write FOnBreakpointsChanged;
  end;

implementation

uses
  LazFileUtils;

type
  { A descendant declared for one reason: to reach TSynEdit's PROTECTED
    ViewedTextBuffer, which is where SynEdit publishes the line-count
    notification. Lazarus offers no public equivalent -- the `property
    TextBuffer;` at synedit.pp:1373 belongs to an internal helper class in that
    unit's implementation section, not to TSynEdit -- and AddChangeHandler is
    declared only on TSynEditStringsLinked (lazsynedittext.pas:495), which is what
    ViewedTextBuffer is and TextBuffer is not.

    ViewedTextBuffer is the buffer AS VIEWED, and its own comment warns that folds
    make that differ from the text. THAT DAY CAME: roadmap item 17 gave this
    editor folding, and item 20 is the one that came back here to look. The worry
    does not materialise for LinesChanged -- measured 2026-09-17, with
    `function outer()` collapsed, an insertion at TEXT line 13 arrives as
    senrLineCount AIndex=13, which is the TEXT index and not the view row, so
    TrackEdit gets what it always got.

    The same descendant now also reaches FoldedTextBuffer, a sibling protected
    property on the same class (syneditmiscclasses.pp:220), which is the folded
    view itself. It must descend from TSynEdit and NOT from TCustomSynEdit: the
    latter is TSynEdit's ancestor, so a descendant of it is TSynEdit's SIBLING and
    the cast is `Warning: (4040) Class types are not related` -- which this
    project's -vewn bar refuses.

    The alternative was to infer the delta from Lines.Count inside OnChange, and
    it is wrong for the case that matters: pasting six lines into the middle of a
    file tells you the count went up by six but not WHERE, and a breakpoint below
    the paste is exactly what notices. Reading the notification SynEdit already
    sends is the accurate answer.

    A descendant may see its ancestor's protected members; this patches nothing,
    assumes nothing about layout, and keeps compiling if the property is ever made
    public. }
  TSynEditAccess = class(TSynEdit);

constructor TEditorDoc.Create(AParent: TWinControl);
begin
  inherited Create;
  FEdit := TSynEdit.Create(AParent);
  FEdit.Parent := AParent;
  FEdit.Align := alClient;
  FEdit.WantTabs := True;
  FFileName := '';
  FUntitledIndex := 0;
  { A buffer nobody loaded gets this machine's convention and a closing newline,
    which is what a text file is expected to have. }
  FShape.Ending := System.LineEnding;
  FShape.FinalNewline := True;
  FBlameLine := 0;
  FBreakpoints := TBreakpointSet.Create;
  TSynEditAccess(FEdit).ViewedTextBuffer.AddChangeHandler(senrLineCount, @LinesChanged);
  { AND THE ONE FOLDING SENDS. `senrLineMappingChanged` is the notification a
    fold opening or closing produces (lazsynedittext.pas:56 names it "folds
    added/removed"); OnChange does not fire for a fold and TSynStatusChange has
    no member for one, so this is the only way to hear about it. }
  TSynEditAccess(FEdit).ViewedTextBuffer.AddChangeHandler(senrLineMappingChanged,
                                                          @FoldsChanged);
  TSynEditAccess(FEdit).ViewedTextBuffer.AddChangeHandler(senrLineChange,
                                                          @LineEdited);
end;

destructor TEditorDoc.Destroy;
begin
  { The handler must come off before FEdit is let go: it points at a method of
    THIS object, and the editor outlives it by however long the parent tab takes
    to be freed. }
  if FEdit <> nil then
  begin
    TSynEditAccess(FEdit).ViewedTextBuffer.RemoveChangeHandler(senrLineCount, @LinesChanged);
    TSynEditAccess(FEdit).ViewedTextBuffer.RemoveChangeHandler(senrLineMappingChanged,
                                                               @FoldsChanged);
    TSynEditAccess(FEdit).ViewedTextBuffer.RemoveChangeHandler(senrLineChange,
                                                               @LineEdited);
  end;
  { FEdit itself belongs to the parent control and is freed with it. Freeing it
    here as well is a double free the first time a tab is closed. }
  FEdit := nil;
  FBreakpoints.Free;
  inherited Destroy;
end;

{ The folded view, or nil before there is an editor. Every fold question below
  goes through this one place, so the cast appears once. }
function TEditorDoc.FoldedView: TSynEditFoldedView;
begin
  if FEdit = nil then
    Result := nil
  else
    Result := TSynEditFoldedView(TSynEditAccess(FEdit).FoldedTextBuffer);
end;

function TEditorDoc.CollapsedHeaderFor(ALine: Integer): Integer;
var
  FV: TSynEditFoldedView;
begin
  Result := 0;
  FV := FoldedView;
  if (FV = nil) or (ALine < 1) or (ALine > FEdit.Lines.Count) then
    Exit;
  { -1 MEANS THE LINE IS DRAWN, which is the answer for every line in a file
    nobody has folded, so this is the cheap case and it stays cheap: one tree
    lookup per breakpoint, and a buffer has a few dozen at most. }
  Result := FV.CollapsedLineForFoldAtLine(ALine);
  if Result < 1 then
    Result := 0;
end;

function TEditorDoc.HiddenBreakpointCount(AHeaderLine: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  if AHeaderLine < 1 then
    Exit;
  for I := 0 to FBreakpoints.Count - 1 do
    if CollapsedHeaderFor(FBreakpoints.Lines[I]) = AHeaderLine then
      Inc(Result);
end;

procedure TEditorDoc.RevealFoldAt(AHeaderLine: Integer);
var
  FV: TSynEditFoldedView;
begin
  FV := FoldedView;
  if (FV = nil) or (AHeaderLine < 1) then
    Exit;
  { 0-BASED, whatever syneditfoldedview.pp:517 says in its comment. The
    implementation is `fFoldTree.FindFoldForLine(AStartIndex+1, True)`
    (:3993-4006), so a 1-based editor line goes in as ALine-1. Measured
    2026-09-17; the comment beside the declaration says "1-based" and is wrong,
    which is worth knowing before spending an afternoon on an off-by-one. }
  FV.UnFoldAtTextIndex(AHeaderLine - 1);
end;

procedure TEditorDoc.FoldsChanged(Sender: TSynEditStrings; AIndex, ACount: Integer);
begin
  if Assigned(FOnFoldsChanged) then
    FOnFoldsChanged(Self);
end;

procedure TEditorDoc.LinesChanged(Sender: TSynEditStrings; AIndex, ACount: Integer);
begin
  { AIndex is 0-based and names the line the change happened AT; ACount is the
    number of lines added, or negative for removed. A breakpoint strictly above
    AIndex+1 is untouched -- pressing Enter at the end of line 5 inserts line 6
    and must leave a mark on line 5 exactly where it was. }
  FBreakpoints.TrackEdit(AIndex + 1, ACount);
  { THE SAME ARITHMETIC, on the one other line number this object remembers. }
  FBlameLine := TrackLine(FBlameLine, AIndex + 1, ACount);
  { TRUE: this is SynEdit's own line-count notification, and other handlers on it
    have not run yet. Whoever listens has to know that, because SynEdit moves ITS
    marks on the same notification and a listener that redraws from here is
    redrawing into the middle of an edit. }
  Changed(True);
end;

procedure TEditorDoc.Changed(AFromEdit: Boolean);
begin
  if Assigned(FOnBreakpointsChanged) then
    FOnBreakpointsChanged(Self, AFromEdit);
end;

procedure TEditorDoc.LineEdited(Sender: TSynEditStrings; AIndex, ACount: Integer);
begin
  { AIndex is 0-based and ACount is how many lines were modified. A blame on any
    of them is about text that is no longer there.

    SynEdit sends this for the line the caret is on as it is typed, which is
    exactly the moment the claim stops being true -- and it is why this is a
    separate handler from LinesChanged: typing INSIDE a line changes no count at
    all, so the breakpoint notification never fires for it. }
  if (FBlameLine >= AIndex + 1) and (FBlameLine <= AIndex + ACount) then
    FBlameLine := 0;
end;

procedure TEditorDoc.LoadFromFile(const APath: String);
var
  Raw: TStringList;
  Text: String;
begin
  { READ THE BYTES FIRST, because the shape has to be seen before anything
    splits the text on it. TStringList.LoadFromFile would have thrown that away
    before this object could look. }
  Text := ReadWholeFile(APath);
  FShape := DetectShape(Text);

  Raw := TStringList.Create;
  try
    SplitLines(Text, Raw);
    FEdit.Lines.Assign(Raw);
  finally
    Raw.Free;
  end;
  { The path is expanded ONCE, here, and everything downstream compares and
    reports the expanded form. A relative path works until the editor's working
    directory is not what the user assumed -- and then the same file is open in
    two tabs under two names, each unaware of the other's edits. }
  FFileName := ExpandFileNameUTF8(APath);
  FEdit.Modified := False;
end;

procedure TEditorDoc.SaveToFile(const APath: String);
var
  Text: String;
begin
  { NOT `FEdit.Lines.Text`, WHICH REWRITES EVERY LINE OF THE FILE -- see
    utextfile's header for what that cost and how it was measured. The shape this
    document was loaded with is handed back, and the bytes go through the one
    writer both halves of the program share. }
  Text := JoinLines(FEdit.Lines, FShape);
  WriteWholeFile(APath, Text);

  FFileName := ExpandFileNameUTF8(APath);
  FEdit.Modified := False;
end;

function TEditorDoc.IsUntitled: Boolean;
begin
  Result := FFileName = '';
end;

function TEditorDoc.DisplayName: String;
begin
  if IsUntitled then
    Result := Format('untitled-%d', [FUntitledIndex])
  else
    Result := ExtractFileName(FFileName);
  if Modified then
    Result := '*' + Result;
end;

function TEditorDoc.FullDisplayName: String;
begin
  if IsUntitled then
    Result := Format('untitled-%d', [FUntitledIndex])
  else
    Result := FFileName;
end;

function TEditorDoc.GetModified: Boolean;
begin
  Result := (FEdit <> nil) and FEdit.Modified;
end;

procedure TEditorDoc.SetModified(AValue: Boolean);
begin
  if FEdit <> nil then
    FEdit.Modified := AValue;
end;

function TEditorDoc.GetCaretLine: Integer;
begin
  if FEdit = nil then
    Result := 0
  else
    Result := FEdit.CaretY;
end;

function TEditorDoc.GetCaretCol: Integer;
begin
  if FEdit = nil then
    Result := 0
  else
    Result := FEdit.CaretX;
end;

function TEditorDoc.HasBreakpoint(ALine: Integer): Boolean;
begin
  Result := FBreakpoints.Has(ALine);
end;

function TEditorDoc.GetBreakpointCount: Integer;
begin
  Result := FBreakpoints.Count;
end;

function TEditorDoc.GetBreakpoint(AIndex: Integer): Integer;
begin
  Result := FBreakpoints[AIndex];
end;

procedure TEditorDoc.ToggleBreakpoint(ALine: Integer);
begin
  FBreakpoints.Toggle(ALine);
  Changed(False);
end;

procedure TEditorDoc.ClearBreakpoints;
begin
  FBreakpoints.Clear;
  Changed(False);
end;

end.
