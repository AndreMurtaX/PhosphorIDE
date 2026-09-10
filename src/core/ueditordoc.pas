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
  Classes, SysUtils, Controls, SynEdit, LazSynEditText, ubreakpoints;

type
  TEditorDoc = class
  private
    FEdit: TSynEdit;
    FFileName: String;
    FUntitledIndex: Integer;
    FBreakpoints: TBreakpointSet;
    { SynEdit's own notification that lines were inserted or removed. Registering
      for it is what makes a breakpoint follow its statement; without it the marks
      stay on their line numbers while the text slides out from under them, which
      is invisible until the day something actually stops at one. }
    procedure LinesChanged(Sender: TSynEditStrings; AIndex, ACount: Integer);
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
      that trap earned its comment in the lexer. }
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

    property Edit: TSynEdit read FEdit;
    property FileName: String read FFileName write FFileName;
    property UntitledIndex: Integer read FUntitledIndex write FUntitledIndex;
    property Modified: Boolean read GetModified write SetModified;
    property CaretLine: Integer read GetCaretLine;
    property CaretCol: Integer read GetCaretCol;
    property BreakpointCount: Integer read GetBreakpointCount;
    property Breakpoints[AIndex: Integer]: Integer read GetBreakpoint;
    { The whole set, for handing to a debug adapter. }
    property BreakpointSet: TBreakpointSet read FBreakpoints;
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
    make that differ from the text. This highlighter enables no folding
    (docs/architecture.md says why), so the two are the same here -- and the day
    folding arrives, this is one of the places that has to be looked at.

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
  FBreakpoints := TBreakpointSet.Create;
  TSynEditAccess(FEdit).ViewedTextBuffer.AddChangeHandler(senrLineCount, @LinesChanged);
end;

destructor TEditorDoc.Destroy;
begin
  { The handler must come off before FEdit is let go: it points at a method of
    THIS object, and the editor outlives it by however long the parent tab takes
    to be freed. }
  if FEdit <> nil then
    TSynEditAccess(FEdit).ViewedTextBuffer.RemoveChangeHandler(senrLineCount, @LinesChanged);
  { FEdit itself belongs to the parent control and is freed with it. Freeing it
    here as well is a double free the first time a tab is closed. }
  FEdit := nil;
  FBreakpoints.Free;
  inherited Destroy;
end;

procedure TEditorDoc.LinesChanged(Sender: TSynEditStrings; AIndex, ACount: Integer);
begin
  { AIndex is 0-based and names the line the change happened AT; ACount is the
    number of lines added, or negative for removed. A breakpoint strictly above
    AIndex+1 is untouched -- pressing Enter at the end of line 5 inserts line 6
    and must leave a mark on line 5 exactly where it was. }
  FBreakpoints.TrackEdit(AIndex + 1, ACount);
end;

procedure TEditorDoc.LoadFromFile(const APath: String);
var
  Raw: TStringList;
begin
  Raw := TStringList.Create;
  try
    Raw.LoadFromFile(APath);
    FEdit.Lines.Assign(Raw);
  finally
    Raw.Free;
  end;
  FFileName := APath;
  FEdit.Modified := False;
end;

procedure TEditorDoc.SaveToFile(const APath: String);
var
  Stream: TFileStream;
  Text: String;
begin
  Text := FEdit.Lines.Text;
  Stream := TFileStream.Create(APath, fmCreate);
  try
    if Length(Text) > 0 then
      Stream.WriteBuffer(Text[1], Length(Text));
  finally
    Stream.Free;
  end;
  FFileName := APath;
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
end;

procedure TEditorDoc.ClearBreakpoints;
begin
  FBreakpoints.Clear;
end;

end.
