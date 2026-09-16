unit umainform;

{ The editor window: tabs of open files, an output pane, and the actions that
  hand a file to the phosphor binary.

  The one rule this unit exists to keep: NOTHING HERE WAITS. Every call into the
  host goes through TPhosphorRunner, which reads the child's pipes on a thread and
  posts back to the main thread. A `run` that never returns is a program the user
  can still stop, save around, and edit while it spins -- which is the entire
  reason the interpreter is a separate process.

  The Debug menu is deliberately half-built and says so out loud. Breakpoints can
  be set and they survive editing; stepping cannot be offered, because the host
  has no way to pause a running program and its breakpoint seam is documented as
  report-and-continue. Offering greyed-out Step buttons with an explanation
  attached is more honest than hiding the menu and more useful than a Step that
  silently does nothing. docs/debug-protocol.md is the specification for the half
  that is missing, and the Debug menu links to it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ActnList, ExtCtrls, StdCtrls, LCLType, SynEdit, SynEditTypes,
  SynEditMiscClasses, SynEditMarkupSpecialLine, SynEditMarks, SynGutter,
  ueditordoc, uphosphorhost, uphosphormsg, uphosphorrun, uphosphorsettings,
  usynphosphor, udebugproto, udebugsession;

type

  { TFrmMain }

  TFrmMain = class(TForm)
    ActAbout: TAction;
    ActCheck: TAction;
    ActClearBreakpoints: TAction;
    ActCloseTab: TAction;
    ActCompile: TAction;
    ActContinue: TAction;
    ActCopy: TAction;
    ActCut: TAction;
    ActDebugStart: TAction;
    ActDebugStop: TAction;
    ActDebugWhy: TAction;
    ActExit: TAction;
    ActFind: TAction;
    ActFindNext: TAction;
    ActFuncRef: TAction;
    ActGotoLine: TAction;
    ActionList1: TActionList;
    ActLangRef: TAction;
    ActNew: TAction;
    ActOpen: TAction;
    ActPack: TAction;
    ActPaste: TAction;
    ActPreferences: TAction;
    ActRedo: TAction;
    ActReplace: TAction;
    ActRun: TAction;
    ActSave: TAction;
    ActSaveAs: TAction;
    ActStepInto: TAction;
    ActStepOut: TAction;
    ActStepOver: TAction;
    ActStop: TAction;
    ActToggleBreakpoint: TAction;
    ActUndo: TAction;
    BtnSendInput: TButton;
    EditInput: TEdit;
    FindDialog1: TFindDialog;
    ListProblems: TListBox;
    MainMenu1: TMainMenu;
    MemoOutput: TMemo;
    MnuAbout: TMenuItem;
    MnuCheck: TMenuItem;
    MnuClearBreakpoints: TMenuItem;
    MnuCloseTab: TMenuItem;
    MnuCompile: TMenuItem;
    MnuContinue: TMenuItem;
    MnuCopy: TMenuItem;
    MnuCut: TMenuItem;
    MnuDebug: TMenuItem;
    MnuDebugStart: TMenuItem;
    MnuDebugStop: TMenuItem;
    MnuDebugWhy: TMenuItem;
    MnuEdit: TMenuItem;
    MnuExit: TMenuItem;
    MnuFile: TMenuItem;
    MnuFind: TMenuItem;
    MnuFindNext: TMenuItem;
    MnuFuncRef: TMenuItem;
    MnuGotoLine: TMenuItem;
    MnuHelp: TMenuItem;
    MnuLangRef: TMenuItem;
    MnuNew: TMenuItem;
    MnuOpen: TMenuItem;
    MnuPack: TMenuItem;
    MnuPaste: TMenuItem;
    MnuPreferences: TMenuItem;
    MnuRecent: TMenuItem;
    MnuRedo: TMenuItem;
    MnuReplace: TMenuItem;
    MnuRun: TMenuItem;
    MnuRunMenu: TMenuItem;
    MnuSave: TMenuItem;
    MnuSaveAs: TMenuItem;
    MnuStepInto: TMenuItem;
    MnuStepOut: TMenuItem;
    MnuStepOver: TMenuItem;
    MnuStop: TMenuItem;
    MnuToggleBreakpoint: TMenuItem;
    MnuTools: TMenuItem;
    MnuUndo: TMenuItem;
    OpenDialog1: TOpenDialog;
    PagesEditors: TPageControl;
    PagesOutput: TPageControl;
    PanelInput: TPanel;
    ReplaceDialog1: TReplaceDialog;
    SaveDialog1: TSaveDialog;
    SepD1: TMenuItem;
    SepD2: TMenuItem;
    SepE1: TMenuItem;
    SepE2: TMenuItem;
    SepE3: TMenuItem;
    SepF1: TMenuItem;
    SepF2: TMenuItem;
    SepF3: TMenuItem;
    SepH1: TMenuItem;
    SepR1: TMenuItem;
    SplitterOutput: TSplitter;
    StatusBar1: TStatusBar;
    TabOutput: TTabSheet;
    TabProblems: TTabSheet;
    TabVariables: TTabSheet;
    ListVariables: TListView;
    TbCheck: TToolButton;
    TbNew: TToolButton;
    TbOpen: TToolButton;
    TbRun: TToolButton;
    TbSave: TToolButton;
    TbSep1: TToolButton;
    TbSep2: TToolButton;
    TbSep3: TToolButton;
    TbStepInto: TToolButton;
    TbStepOver: TToolButton;
    TbStop: TToolButton;
    TbToggleBreakpoint: TToolButton;
    ToolBar1: TToolBar;
    procedure ActAboutExecute(Sender: TObject);
    procedure ActCheckExecute(Sender: TObject);
    procedure ActClearBreakpointsExecute(Sender: TObject);
    procedure ActCloseTabExecute(Sender: TObject);
    procedure ActCompileExecute(Sender: TObject);
    procedure ActCopyExecute(Sender: TObject);
    procedure ActCutExecute(Sender: TObject);
    procedure ActContinueExecute(Sender: TObject);
    procedure ActStepIntoExecute(Sender: TObject);
    procedure ActStepOutExecute(Sender: TObject);
    procedure ActStepOverExecute(Sender: TObject);
    procedure ActDebugStartExecute(Sender: TObject);
    procedure ActDebugStopExecute(Sender: TObject);
    procedure ActDebugWhyExecute(Sender: TObject);
    procedure ActExitExecute(Sender: TObject);
    procedure ActFindExecute(Sender: TObject);
    procedure ActFindNextExecute(Sender: TObject);
    procedure ActFuncRefExecute(Sender: TObject);
    procedure ActGotoLineExecute(Sender: TObject);
    procedure ActLangRefExecute(Sender: TObject);
    procedure ActNewExecute(Sender: TObject);
    procedure ActOpenExecute(Sender: TObject);
    procedure ActPackExecute(Sender: TObject);
    procedure ActPasteExecute(Sender: TObject);
    procedure ActPreferencesExecute(Sender: TObject);
    procedure ActRedoExecute(Sender: TObject);
    procedure ActReplaceExecute(Sender: TObject);
    procedure ActRunExecute(Sender: TObject);
    procedure ActSaveAsExecute(Sender: TObject);
    procedure ActSaveExecute(Sender: TObject);
    procedure ActStopExecute(Sender: TObject);
    procedure ActToggleBreakpointExecute(Sender: TObject);
    procedure ActUndoExecute(Sender: TObject);
    procedure ActionList1Update(AAction: TBasicAction; var Handled: Boolean);
    procedure BtnSendInputClick(Sender: TObject);
    procedure EditInputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FindDialog1Find(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure ListProblemsDblClick(Sender: TObject);
    procedure PagesEditorsChange(Sender: TObject);
    procedure ReplaceDialog1Replace(Sender: TObject);
  private
    FSettings: TPhosphorSettings;
    FRunner: TPhosphorRunner;
    FDebug: TDebugSession;
    FHighlighter: TSynPhosphorSyn;
    FDocs: TList;               // of TEditorDoc, parallel to PagesEditors pages
    FUntitledCounter: Integer;
    FHostPath: String;
    FHostVersion: String;
    FLastSearch: String;
    FPendingPackExe: String;    // set while a compile-then-pack is in flight
    FPendingPackPbc: String;
    FRunLabel: String;          // what the running command is, for the status bar
    { The file THIS run was started on. A diagnostic belongs to the program that
      was handed to the host, and the user is free to switch tabs while it runs --
      so attributing an error to whatever happens to be active when stderr arrives
      sends the caret into the wrong file. Captured at the moment the child is
      spawned, and only cleared when the next one is. }
    FRunPath: String;
    FProblemLines: TStringList; // 'path|line' parallel to ListProblems.Items
    { The output pane is one memo fed by two streams. When a stream hands over an
      unterminated line -- a prompt -- the next thing from THAT stream continues
      it, and anything from the other stream starts a new line instead. Without
      the stream half of that, a diagnostic would be appended to the tail of a
      prompt. }
    FOutputOpen: Boolean;
    FOutputOpenKind: TRunStream;

    { The debug session's clock. Created in code rather than dropped on the form:
      a .lfm component is one more thing that can name a property its .pas does
      not publish, and the fix for that is a modal dialog nobody can dismiss.
      A non-visual timer costs nothing to build here and cannot mismatch.

      It belongs to the FORM and not to udebugtransport, which is not a style
      choice: TTimer needs a widgetset, and phosphoridetest links the LCL while
      deliberately never creating one. A timer inside the transport killed that
      program the first time the transport was exercised -- group header printed,
      nothing after it, exit 0, no summary. }
    FDebugTimer: TTimer;

    { Where execution is stopped, and in which file. Line 0 means nowhere, which
      is what clears the current-line paint. }
    FDebugPath: String;
    FDebugLine: Integer;
    { Shown once per session, on the first stop. Switching to the pane on EVERY
      stop would take the output tab away from someone who chose it, and never
      switching leaves the first-time user reading an empty Output pane wondering
      what Debug did. }
    FVarShown: Boolean;
    { Set by an exception stop. The session is still connected and still reports
      dsStopped, which is true and is not the whole truth: nothing may be sent. }
    FDebugTerminal: Boolean;

    { Whether THIS FORM believes a debug session is under way, which is a
      different question from what TDebugSession.State says and is the one the
      form's own bookkeeping turns on.

      It replaces FDebugTimer.Enabled, which was standing in for it. A timer is a
      cadence, not a fact, and reading one as "a session is live" meant that
      anything which stopped the timer -- including the session ending -- also
      erased the record that there had been anything to end. }
    FDebugLive: Boolean;

    { The lines the host reported it ACTUALLY armed, and for which file. A
      breakpoint the user set on a blank line, a comment or an `endfunction` comes
      back absent from this list, because there is no statement there to stop at.

      IT LIVES IN THE FORM, NOT IN TBreakpointSet. That unit has no LCL reference
      and phosphoridetest pins its arithmetic without a window; giving it a notion
      of "what some host said" would drag a protocol into a unit whose whole value
      is that it has none.

      Known only DURING a session -- cleared when one ends. Keeping it afterwards
      would usually still be true and would sometimes be a lie, and the lie is
      invisible: the user edits the file, the line moves, and a stale flag says a
      live breakpoint is dead. }
    FInstalledPath: String;
    FInstalledLines: TPdbpLines;

    function ActiveDoc: TEditorDoc;
    function DocOfPage(APage: TTabSheet): TEditorDoc;
    procedure FocusEditor(ADoc: TEditorDoc);
    function NewDoc(const APath: String): TEditorDoc;
    function ConfirmSaved(ADoc: TEditorDoc): Boolean;
    procedure SaveDoc(ADoc: TEditorDoc);
    function EnsureSavedForRun(out APath: String): Boolean;
    procedure CloseDocAt(AIndex: Integer);

    procedure ApplyEditorSettings(ADoc: TEditorDoc);
    procedure ApplyAllEditorSettings;
    procedure RefreshTabCaption(ADoc: TEditorDoc);
    procedure RefreshRecentMenu;
    procedure RefreshStatus;
    procedure RefreshDebugActions;
    procedure RepaintEditors;
    function StartDebugSession: Boolean;
    procedure EndDebugSession(const AWhy: String);
    procedure DebugTimerTick(Sender: TObject);
    procedure DebugStateChanged(Sender: TObject);
    procedure DebugStopped(Sender: TObject; const APath: String; ALine: Integer;
      AReason: TPdbpStopReason; const AText: String);
    procedure DebugExited(Sender: TObject; AExitCode: Integer);
    procedure DebugNote(Sender: TObject; const AText: String);
    procedure DebugLinesInstalled(Sender: TObject; const APath: String;
      const AInstalled: TPdbpLines);
    procedure DebugVariables(Sender: TObject; AFrame: Integer;
      const AVars: TPdbpVariables);
    procedure SyncBreakpoints(ADoc: TEditorDoc);
    function DocByPath(const APath: String): TEditorDoc;
    function BreakpointIsArmed(ADoc: TEditorDoc; ALine: Integer): Boolean;
    procedure ClearVariables;

    procedure OpenPath(const APath: String);
    procedure RecentClick(Sender: TObject);

    procedure ResolveHost;
    function RequireHost: Boolean;
    function StartHost(const AArgs: array of String; const AWhat: String): Boolean;

    procedure AddOutput(const AText: String);
    procedure AppendOutput(AKind: TRunStream; const AText: String;
      ACompleteLine: Boolean);
    procedure ScrollOutputToEnd;
    procedure TrimOutput;
    procedure AddProblem(const AMsg: TPhosphorMessage; const AFallbackPath: String);
    procedure GotoSource(const APath: String; ALine: Integer);

    procedure EditorChange(Sender: TObject);
    procedure EditorStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
    procedure EditorSpecialLineMarkup(Sender: TObject; ALine: Integer;
      var ASpecial: Boolean; AMarkup: TSynSelectedColor);
    procedure EditorGutterClick(Sender: TObject; X, Y, ALine: Integer;
      AMark: TSynEditMark);

    procedure RunnerOutput(Sender: TObject; AKind: TRunStream; const AText: String;
      ACompleteLine: Boolean);
    procedure RunnerFinished(Sender: TObject; AExitCode: Integer; AKilled: Boolean);
    procedure RunnerFailed(Sender: TObject; const AReason: String);
  public
    property Settings: TPhosphorSettings read FSettings;
    property HostPath: String read FHostPath;
    property HostVersion: String read FHostVersion;
    procedure SettingsChanged;
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.lfm}

uses
  LCLIntf, LazFileUtils, uaboutform, upreferencesform;

const
  { Where Help points. These are the canonical documents in the Phosphor
    repository; the editor does not ship a copy, because a copy of a reference for
    a language that is still moving is a copy that lies. }
  UrlLanguageReference = 'https://github.com/AndreMurtaX/Phosphor/blob/main/docs/language-reference.md';
  UrlFunctionReference = 'https://github.com/AndreMurtaX/Phosphor/blob/main/docs/function-reference.md';
  UrlDebugProtocol = 'https://github.com/AndreMurtaX/PhosphorIDE/blob/main/docs/debug-protocol.md';

  PhosphorFilter = 'Phosphor BASIC (*.bas)|*.bas|Bytecode (*.pbc)|*.pbc|All files|*.*';

  { How much transcript the output pane keeps. Generous for reading a run, bounded
    so that a program printing without end cannot make the editor its memory
    problem. The oldest lines go first, which is the half nobody was reading. }
  MaxOutputLines = 5000;

  { How often the session is asked to drain its socket. The same 40 ms the output
    pane drains the child's pipes at, and for the same reason: fast enough that a
    stop feels immediate, slow enough that an idle session costs nothing. }
  DebugPollIntervalMs = 40;

{ ---------------------------------------------------------------- lifecycle -- }

procedure TFrmMain.FormCreate(Sender: TObject);
begin
  FDocs := TList.Create;
  FProblemLines := TStringList.Create;
  FUntitledCounter := 0;

  FSettings := TPhosphorSettings.Create;
  FSettings.Load;

  FHighlighter := TSynPhosphorSyn.Create(Self);
  FHighlighter.ApplyTheme(FSettings.DarkTheme);

  FRunner := TPhosphorRunner.Create(Self);
  FRunner.OnOutput := @RunnerOutput;
  FRunner.OnFinished := @RunnerFinished;
  FRunner.OnStartFailed := @RunnerFailed;

  FDebug := TDebugSession.Create(Self);
  FDebug.OnStateChange := @DebugStateChanged;
  FDebug.OnStopped := @DebugStopped;
  FDebug.OnExited := @DebugExited;
  FDebug.OnNote := @DebugNote;
  FDebug.OnLinesInstalled := @DebugLinesInstalled;
  FDebug.OnVariables := @DebugVariables;

  FDebugTimer := TTimer.Create(Self);
  FDebugTimer.Enabled := False;
  FDebugTimer.Interval := DebugPollIntervalMs;
  FDebugTimer.OnTimer := @DebugTimerTick;
  FDebugLine := 0;

  OpenDialog1.Filter := PhosphorFilter;
  SaveDialog1.Filter := PhosphorFilter;

  { GEOMETRY FROM A PREVIOUS RUN IS A CLAIM ABOUT A SCREEN THAT MAY BE GONE. The
    second monitor is unplugged, the laptop is docked somewhere else, the
    resolution changed -- and the window is restored onto coordinates with no
    pixels behind them, which is a program that started and cannot be found.
    Clamped into the current workspace, never refused outright. }
  if FSettings.WindowWidth > 0 then
  begin
    Width := Min(FSettings.WindowWidth, Screen.WorkAreaWidth);
    Height := Min(FSettings.WindowHeight, Screen.WorkAreaHeight);
    Left := Max(Screen.WorkAreaLeft,
                Min(FSettings.WindowLeft, Screen.WorkAreaLeft + Screen.WorkAreaWidth - Width));
    Top := Max(Screen.WorkAreaTop,
               Min(FSettings.WindowTop, Screen.WorkAreaTop + Screen.WorkAreaHeight - Height));
  end;
  if FSettings.WindowMaximised then
    WindowState := wsMaximized;

  { And a stored pane height taller than the window leaves the editor with no
    height at all -- and the splitter with nothing to drag, so there is no way
    back from it inside the program. }
  PagesOutput.Height := Max(60, Min(FSettings.OutputPaneHeight, ClientHeight - 150));

  ResolveHost;
  RefreshRecentMenu;
  RefreshDebugActions;

  { A file named on the command line opens; otherwise there is one empty tab, so
    the window is never a blank grey rectangle with no visible way in. }
  if (ParamCount >= 1) and FileExistsUTF8(ParamStr(1)) then
    OpenPath(ParamStr(1))
  else
    NewDoc('');

  RefreshStatus;
end;

procedure TFrmMain.FormDestroy(Sender: TObject);
var
  I: Integer;
begin
  if FSettings <> nil then
  begin
    FSettings.WindowMaximised := WindowState = wsMaximized;
    if WindowState = wsNormal then
    begin
      FSettings.WindowLeft := Left;
      FSettings.WindowTop := Top;
      FSettings.WindowWidth := Width;
      FSettings.WindowHeight := Height;
    end;
    FSettings.OutputPaneHeight := PagesOutput.Height;
    FSettings.Save;
  end;

  if FDocs <> nil then
  begin
    for I := 0 to FDocs.Count - 1 do
      TEditorDoc(FDocs[I]).Free;
    FDocs.Free;
  end;
  FProblemLines.Free;
  FSettings.Free;
end;

procedure TFrmMain.FormShow(Sender: TObject);
begin
  { The caret belongs in the text, not on a toolbar button, and this is the first
    moment there is a window to put it in. }
  FocusEditor(ActiveDoc);
end;

procedure TFrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  I: Integer;
begin
  CanClose := True;

  { UNSAVED WORK IS ASKED ABOUT FIRST, and the child is killed LAST.

    The other order looks equivalent and is not: killing first and then finding
    that the user cancels at a save prompt leaves the window open with its program
    already dead -- a run destroyed by a close that did not happen. Nothing is
    ended until everything has agreed to end. }
  for I := 0 to FDocs.Count - 1 do
    if not ConfirmSaved(TEditorDoc(FDocs[I])) then
    begin
      CanClose := False;
      Exit;
    end;

  if FRunner.Running then
  begin
    if MessageDlg('PhosphorIDE',
      Format('%s is still running. Stop it and close?', [FRunLabel]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    begin
      CanClose := False;
      Exit;
    end;
    FRunner.Kill;
  end;
end;

{ ---------------------------------------------------------------- documents -- }

function TFrmMain.ActiveDoc: TEditorDoc;
begin
  if (PagesEditors.ActivePageIndex < 0) or (PagesEditors.ActivePageIndex >= FDocs.Count) then
    Result := nil
  else
    Result := TEditorDoc(FDocs[PagesEditors.ActivePageIndex]);
end;

function TFrmMain.DocOfPage(APage: TTabSheet): TEditorDoc;
var
  Idx: Integer;
begin
  if APage = nil then
    Exit(nil);
  Idx := APage.PageIndex;
  if (Idx < 0) or (Idx >= FDocs.Count) then
    Result := nil
  else
    Result := TEditorDoc(FDocs[Idx]);
end;

function TFrmMain.NewDoc(const APath: String): TEditorDoc;
var
  Page: TTabSheet;
begin
  Page := PagesEditors.AddTabSheet;
  Result := TEditorDoc.Create(Page);
  FDocs.Add(Result);

  { A file that will not read raises out of here, and the caller reports it. What
    must NOT survive is the tab: a page and a document that were added before the
    read failed leave an untitled, unhighlighted editor with no event handlers and
    no caption, which the user then has to close by hand and which the run actions
    will happily hand to the host. }
  try
    if APath = '' then
    begin
      Inc(FUntitledCounter);
      Result.UntitledIndex := FUntitledCounter;
    end
    else
      Result.LoadFromFile(APath);
  except
    FDocs.Remove(Result);
    Result.Free;
    Page.Free;
    raise;
  end;

  Result.Edit.Highlighter := FHighlighter;
  Result.Edit.OnChange := @EditorChange;
  Result.Edit.OnStatusChange := @EditorStatusChange;
  Result.Edit.OnSpecialLineMarkup := @EditorSpecialLineMarkup;
  Result.Edit.OnGutterClick := @EditorGutterClick;
  ApplyEditorSettings(Result);

  PagesEditors.ActivePage := Page;
  RefreshTabCaption(Result);
  FocusEditor(Result);
end;

procedure TFrmMain.FocusEditor(ADoc: TEditorDoc);
begin
  { SetFocus on a control whose form is not on screen yet RAISES -- "Can not
    focus" -- and the first thing this window does is create a tab, from
    FormCreate, before it is shown. The file named on the command line was
    therefore reported as unopenable, with the focus error as its reason, on
    2026-09-10. Focus is a thing to ask for once there is somewhere to put it;
    FormShow does it for the tab that exists at startup. }
  if (ADoc = nil) or (ADoc.Edit = nil) then
    Exit;
  if Showing and ADoc.Edit.CanFocus then
    ADoc.Edit.SetFocus;
end;

procedure TFrmMain.CloseDocAt(AIndex: Integer);
var
  Doc: TEditorDoc;
begin
  if (AIndex < 0) or (AIndex >= FDocs.Count) then
    Exit;
  Doc := TEditorDoc(FDocs[AIndex]);
  if not ConfirmSaved(Doc) then
    Exit;
  FDocs.Delete(AIndex);
  Doc.Free;
  PagesEditors.Pages[AIndex].Free;
  if FDocs.Count = 0 then
    NewDoc('');
  RefreshStatus;
end;

function TFrmMain.ConfirmSaved(ADoc: TEditorDoc): Boolean;
var
  Answer: Integer;
begin
  Result := True;
  if (ADoc = nil) or not ADoc.Modified then
    Exit;

  PagesEditors.ActivePageIndex := FDocs.IndexOf(ADoc);
  Answer := MessageDlg('PhosphorIDE',
    Format('Save changes to %s?', [ADoc.FullDisplayName]),
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  case Answer of
    mrYes:
      begin
        { SaveDoc, not ActSaveExecute. The prompt above named a document; saving
          "the active one" instead is a bet that nothing changed the active tab
          between the question and the answer -- and things do, because a
          diagnostic draining in from a still-running child switches tabs. }
        SaveDoc(ADoc);
        Result := not ADoc.Modified;
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TFrmMain.OpenPath(const APath: String);
var
  I, Idx: Integer;
  Doc, Pristine: TEditorDoc;
  Full: String;
begin
  { Every comparison downstream is against an expanded path, so the incoming one
    is expanded here. A relative path opened twice under two spellings is two tabs
    owning one file, each unaware of the other's edits. }
  Full := ExpandFileNameUTF8(APath);
  { Already open? Show that tab rather than opening the file twice, which is how
    two views of one file quietly diverge. }
  for I := 0 to FDocs.Count - 1 do
  begin
    Doc := TEditorDoc(FDocs[I]);
    if (not Doc.IsUntitled) and (CompareFilenames(Doc.FileName, Full) = 0) then
    begin
      PagesEditors.ActivePageIndex := I;
      Exit;
    end;
  end;

  { Open FIRST, discard the pristine tab afterwards. The other order looks tidier
    and leaves two tabs behind: CloseDocAt re-creates an untitled document when it
    empties the list, so closing the only tab before opening produces the empty
    tab it was supposed to remove, plus the new one. }
  Pristine := ActiveDoc;
  if not ((FDocs.Count = 1) and (Pristine <> nil) and Pristine.IsUntitled and
          (not Pristine.Modified) and (Pristine.Edit.Lines.Count <= 1) and
          (Pristine.Edit.Lines.Text = '')) then
    Pristine := nil;

  try
    Doc := NewDoc(Full);
  except
    on E: Exception do
    begin
      MessageDlg('PhosphorIDE', Format('Could not open %s:'#10'%s', [APath, E.Message]),
        mtError, [mbOK], 0);
      Exit;
    end;
  end;

  if Pristine <> nil then
  begin
    Idx := FDocs.IndexOf(Pristine);
    if Idx >= 0 then
    begin
      FDocs.Delete(Idx);
      Pristine.Free;
      PagesEditors.Pages[Idx].Free;
    end;
  end;

  FSettings.AddRecentFile(Doc.FileName);
  RefreshRecentMenu;
  RefreshTabCaption(Doc);
  RefreshStatus;
end;

{ ------------------------------------------------------------------- actions -- }

procedure TFrmMain.ActNewExecute(Sender: TObject);
begin
  NewDoc('');
  RefreshStatus;
end;

procedure TFrmMain.ActOpenExecute(Sender: TObject);
begin
  if OpenDialog1.Execute then
    OpenPath(OpenDialog1.FileName);
end;

procedure TFrmMain.SaveDoc(ADoc: TEditorDoc);
begin
  if ADoc = nil then
    Exit;
  if ADoc.IsUntitled then
  begin
    PagesEditors.ActivePageIndex := FDocs.IndexOf(ADoc);
    ActSaveAsExecute(nil);
    Exit;
  end;
  try
    ADoc.SaveToFile(ADoc.FileName);
  except
    on E: Exception do
    begin
      MessageDlg('PhosphorIDE', Format('Could not save %s:'#10'%s',
        [ADoc.FileName, E.Message]), mtError, [mbOK], 0);
      Exit;
    end;
  end;
  RefreshTabCaption(ADoc);
  RefreshStatus;
end;

procedure TFrmMain.ActSaveExecute(Sender: TObject);
begin
  SaveDoc(ActiveDoc);
end;

procedure TFrmMain.ActSaveAsExecute(Sender: TObject);
var
  Doc, Other: TEditorDoc;
  I: Integer;
  Target: String;
begin
  Doc := ActiveDoc;
  if Doc = nil then
    Exit;
  if not Doc.IsUntitled then
    SaveDialog1.FileName := Doc.FileName
  else
    SaveDialog1.FileName := 'untitled.bas';
  if not SaveDialog1.Execute then
    Exit;

  { TWO TABS MUST NEVER OWN ONE FILE. Each would keep its own text, its own
    modified flag and its own breakpoints, and the last one saved would silently
    win -- so the first user's work disappears into a file they still have open
    and still believe they are editing. }
  Target := ExpandFileNameUTF8(SaveDialog1.FileName);
  for I := 0 to FDocs.Count - 1 do
  begin
    Other := TEditorDoc(FDocs[I]);
    if (Other <> Doc) and (not Other.IsUntitled) and
       (CompareFilenames(Other.FileName, Target) = 0) then
    begin
      MessageDlg('PhosphorIDE',
        Format('%s is already open in another tab.'#10#10 +
               'Close that tab first, or choose a different name.',
               [ExtractFileName(Target)]), mtError, [mbOK], 0);
      Exit;
    end;
  end;

  try
    Doc.SaveToFile(Target);
  except
    on E: Exception do
    begin
      MessageDlg('PhosphorIDE', Format('Could not save %s:'#10'%s',
        [Target, E.Message]), mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FSettings.AddRecentFile(Doc.FileName);
  RefreshRecentMenu;
  RefreshTabCaption(Doc);
  RefreshStatus;
end;

procedure TFrmMain.ActCloseTabExecute(Sender: TObject);
begin
  CloseDocAt(PagesEditors.ActivePageIndex);
end;

procedure TFrmMain.ActExitExecute(Sender: TObject);
begin
  Close;
end;

procedure TFrmMain.ActUndoExecute(Sender: TObject);
begin
  if ActiveDoc <> nil then
    ActiveDoc.Edit.Undo;
end;

procedure TFrmMain.ActRedoExecute(Sender: TObject);
begin
  if ActiveDoc <> nil then
    ActiveDoc.Edit.Redo;
end;

procedure TFrmMain.ActCutExecute(Sender: TObject);
begin
  if ActiveDoc <> nil then
    ActiveDoc.Edit.CutToClipboard;
end;

procedure TFrmMain.ActCopyExecute(Sender: TObject);
begin
  if ActiveDoc <> nil then
    ActiveDoc.Edit.CopyToClipboard;
end;

procedure TFrmMain.ActPasteExecute(Sender: TObject);
begin
  if ActiveDoc <> nil then
    ActiveDoc.Edit.PasteFromClipboard;
end;

procedure TFrmMain.ActFindExecute(Sender: TObject);
begin
  if ActiveDoc = nil then
    Exit;
  if ActiveDoc.Edit.SelAvail then
    FindDialog1.FindText := ActiveDoc.Edit.SelText;
  FindDialog1.Execute;
end;

procedure TFrmMain.FindDialog1Find(Sender: TObject);
var
  Opts: TSynSearchOptions;
begin
  if ActiveDoc = nil then
    Exit;
  Opts := [];
  if not (frDown in FindDialog1.Options) then
    Include(Opts, ssoBackwards);
  if frMatchCase in FindDialog1.Options then
    Include(Opts, ssoMatchCase);
  if frWholeWord in FindDialog1.Options then
    Include(Opts, ssoWholeWord);
  FLastSearch := FindDialog1.FindText;
  if ActiveDoc.Edit.SearchReplace(FLastSearch, '', Opts) = 0 then
    StatusBar1.Panels[3].Text := Format('not found: %s', [FLastSearch]);
end;

procedure TFrmMain.ActFindNextExecute(Sender: TObject);
begin
  if (ActiveDoc = nil) or (FLastSearch = '') then
    Exit;
  if ActiveDoc.Edit.SearchReplace(FLastSearch, '', []) = 0 then
    StatusBar1.Panels[3].Text := Format('not found: %s', [FLastSearch]);
end;

procedure TFrmMain.ActReplaceExecute(Sender: TObject);
begin
  if ActiveDoc = nil then
    Exit;
  ReplaceDialog1.Execute;
end;

procedure TFrmMain.ReplaceDialog1Replace(Sender: TObject);
var
  Opts: TSynSearchOptions;
begin
  if ActiveDoc = nil then
    Exit;
  Opts := [ssoReplace];
  if frReplaceAll in ReplaceDialog1.Options then
    Opts := Opts + [ssoReplaceAll, ssoEntireScope];
  if frMatchCase in ReplaceDialog1.Options then
    Include(Opts, ssoMatchCase);
  if frWholeWord in ReplaceDialog1.Options then
    Include(Opts, ssoWholeWord);
  ActiveDoc.Edit.SearchReplace(ReplaceDialog1.FindText, ReplaceDialog1.ReplaceText, Opts);
end;

procedure TFrmMain.ActGotoLineExecute(Sender: TObject);
var
  Answer: String;
  Line, Code: Integer;
begin
  if ActiveDoc = nil then
    Exit;
  Answer := InputBox('Go to line', 'Line number:', IntToStr(ActiveDoc.CaretLine));
  Val(Answer, Line, Code);
  if (Code = 0) and (Line > 0) then
    GotoSource(ActiveDoc.FullDisplayName, Line);
end;

{ --------------------------------------------------------------- running it -- }

function TFrmMain.EnsureSavedForRun(out APath: String): Boolean;
var
  Doc: TEditorDoc;
begin
  Result := False;
  APath := '';
  Doc := ActiveDoc;
  if Doc = nil then
    Exit;

  { The host reads a FILE. An unsaved buffer is not a program it can run, so the
    choice is to save or to say why nothing happened. A temporary copy would run
    the right text under the wrong name, and every diagnostic would then point at
    a path in the temp directory. }
  if Doc.IsUntitled or (Doc.Modified and FSettings.SaveBeforeRun) then
  begin
    ActSaveExecute(nil);
    if Doc.IsUntitled or Doc.Modified then
      Exit;
  end
  else if Doc.Modified then
  begin
    if MessageDlg('PhosphorIDE',
      'The file has unsaved changes. Run the version on disk?',
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  APath := Doc.FileName;
  Result := APath <> '';
end;

procedure TFrmMain.ResolveHost;
var
  Info: TPhosphorHostInfo;
begin
  FHostPath := LocateHost(FSettings.HostPath);
  FHostVersion := '';
  if FHostPath <> '' then
  begin
    Info := ProbeHost(FHostPath);
    if Info.Ok then
      FHostVersion := Info.Version
    else
      FHostVersion := Info.Diagnostic;
  end;
  { Whether this particular binary can be stepped is a question about the binary,
    so it is asked here, every time the host changes, rather than once at start. }
  FDebug.Probe(FHostPath);
  RefreshDebugActions;
end;

function TFrmMain.RequireHost: Boolean;
begin
  Result := FHostPath <> '';
  if Result then
    Exit;
  MessageDlg('PhosphorIDE',
    'No phosphor binary found.'#10#10 +
    'PhosphorIDE runs programs by handing them to the phosphor host; it does not ' +
    'contain an interpreter of its own. Point it at one in Tools > Preferences, ' +
    'or put phosphor on PATH.',
    mtError, [mbOK], 0);
end;

function TFrmMain.StartHost(const AArgs: array of String; const AWhat: String): Boolean;
var
  WorkDir: String;
  Doc: TEditorDoc;
begin
  Result := False;
  if FRunner.Running then
  begin
    MessageDlg('PhosphorIDE',
      Format('%s is still running. Stop it first.', [FRunLabel]),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  if FSettings.ClearOutputOnRun then
  begin
    MemoOutput.Clear;
    ListProblems.Clear;
    FProblemLines.Clear;
  end;

  Doc := ActiveDoc;
  if (Doc <> nil) and (not Doc.IsUntitled) then
    WorkDir := ExtractFilePath(Doc.FileName)
  else
    WorkDir := '';

  FRunLabel := AWhat;
  if (Doc <> nil) and (not Doc.IsUntitled) then
    FRunPath := Doc.FileName
  else
    FRunPath := '';
  PagesOutput.ActivePage := TabOutput;
  AddOutput(Format('> %s', [AWhat]));
  Result := FRunner.Start(FHostPath, AArgs, WorkDir);
  RefreshStatus;
end;

procedure TFrmMain.ActRunExecute(Sender: TObject);
var
  Path, Root: String;
begin
  if not RequireHost then
    Exit;
  if not EnsureSavedForRun(Path) then
    Exit;

  if FSettings.UseSandbox then
  begin
    Root := FSettings.SandboxRoot;
    if Root = '' then
      Root := ExtractFilePath(Path);
    StartHost(['--sandbox', Root, 'run', Path], Format('run %s (sandboxed)', [ExtractFileName(Path)]));
  end
  else
    StartHost(['run', Path], Format('run %s', [ExtractFileName(Path)]));
end;

procedure TFrmMain.ActCheckExecute(Sender: TObject);
var
  Path, Temp: String;
begin
  if not RequireHost then
    Exit;
  if not EnsureSavedForRun(Path) then
    Exit;
  { compile --check writes a .pbc it does not need, so it goes to a temporary
    name. The point of the call is the diagnostics, not the artefact. }
  Temp := GetTempDir(False) + ExtractFileName(Path) + '.check.pbc';
  StartHost(['compile', '--check', Path, Temp],
    Format('check %s', [ExtractFileName(Path)]));
end;

procedure TFrmMain.ActCompileExecute(Sender: TObject);
var
  Path: String;
begin
  if not RequireHost then
    Exit;
  if not EnsureSavedForRun(Path) then
    Exit;
  SaveDialog1.FileName := ChangeFileExt(Path, '.pbc');
  SaveDialog1.Filter := 'Phosphor bytecode (*.pbc)|*.pbc|All files|*.*';
  try
    if not SaveDialog1.Execute then
      Exit;
    StartHost(['compile', Path, SaveDialog1.FileName],
      Format('compile %s', [ExtractFileName(Path)]));
  finally
    SaveDialog1.Filter := PhosphorFilter;
  end;
end;

procedure TFrmMain.ActPackExecute(Sender: TObject);
var
  Path: String;
begin
  if not RequireHost then
    Exit;
  if not EnsureSavedForRun(Path) then
    Exit;

  SaveDialog1.FileName := ChangeFileExt(Path, {$IFDEF WINDOWS} '.exe' {$ELSE} '' {$ENDIF});
  SaveDialog1.Filter := 'Executable|*' + {$IFDEF WINDOWS} '.exe' {$ELSE} '' {$ENDIF} + '|All files|*.*';
  try
    if not SaveDialog1.Execute then
      Exit;
  finally
    SaveDialog1.Filter := PhosphorFilter;
  end;

  { pack takes COMPILED bytecode, never source -- so this is two runs of the host,
    and the second is started by RunnerFinished only if the first succeeded. }
  FPendingPackExe := SaveDialog1.FileName;
  FPendingPackPbc := GetTempDir(False) + ExtractFileName(Path) + '.pack.pbc';
  { ARMED ONLY IF THE COMPILE ACTUALLY STARTED. StartHost declines when something
    is already running, and a pack left armed by a refusal fires on the NEXT run
    that happens to succeed -- silently writing an executable the user asked for
    minutes ago, from a different program. }
  if not StartHost(['compile', Path, FPendingPackPbc],
       Format('compile %s for packing', [ExtractFileName(Path)])) then
  begin
    FPendingPackExe := '';
    FPendingPackPbc := '';
  end;
end;

procedure TFrmMain.ActStopExecute(Sender: TObject);
begin
  { No note here. Kill is asynchronous -- the child dies, its pipes close, the
    reader threads finish, and the drain sees it; RunnerFinished writes `> killed`
    once that has actually happened. Announcing it twice, once hopefully and once
    truthfully, is how an output pane starts lying about the order of events. }
  if FRunner.Running then
    FRunner.Kill;
end;

{ ------------------------------------------------------------- runner events -- }

procedure TFrmMain.RunnerOutput(Sender: TObject; AKind: TRunStream; const AText: String;
  ACompleteLine: Boolean);
var
  Msg: TPhosphorMessage;
begin
  AppendOutput(AKind, AText, ACompleteLine);

  { Only a WHOLE line is a diagnostic. Half of `phosphor: x.bas:2: unexpected
    token` matches nothing, and worse, half of it could match something else. }
  if (AKind <> rsStdErr) or (not ACompleteLine) then
    Exit;

  if not ParsePhosphorMessage(AText, Msg) then
    Exit;
  if Msg.Kind = pmkPlain then
    Exit;

  AddProblem(Msg, FRunPath);
end;

procedure TFrmMain.RunnerFinished(Sender: TObject; AExitCode: Integer; AKilled: Boolean);
var
  PackExe, PackPbc: String;
begin
  { THE CHILD DYING IS THE END OF THE SESSION, whatever the protocol did or did
    not say. A debuggee that faults, or is killed, or exits before the socket ever
    carried an `exited` event leaves the timer polling a socket with nobody on the
    other end and the Debug menu claiming a session is live. The process is the
    authority on whether the program is still there.

    FDebugLive, not FDebugTimer.Enabled: the timer is how often the socket is
    read, and anything that turned it off for its own reasons would have made
    this test answer "there was no session" about a session there had been. }
  if FDebugLive then
  begin
    { ONE LAST READ FIRST. The child exiting means no more frames will be sent;
      it says nothing about the ones already in the socket buffer. Measured on
      2026-09-16 against the real host: an uncaught error is announced as
      `stopped/exception` and the connection is closed in the same breath, so
      the frame naming WHERE the program died and the death of the process
      arrive inside one 40 ms tick -- and tearing down first threw that frame
      away. The editor showed the stderr diagnostic and never said the program
      had stopped at all. }
    FDebug.Poll;
    FDebug.Stop(False);
    EndDebugSession('');
  end;

  if AKilled then
    AddOutput('> killed')
  else
    AddOutput(Format('> %s (%d)', [PhosphorExitCodeText(AExitCode), AExitCode]));

  { The second half of a pack: only if the compile actually produced bytecode. }
  if (FPendingPackExe <> '') and (not AKilled) and (AExitCode = 0) then
  begin
    PackExe := FPendingPackExe;
    PackPbc := FPendingPackPbc;
    FPendingPackExe := '';
    FPendingPackPbc := '';
    StartHost(['pack', PackPbc, PackExe],
      Format('pack %s', [ExtractFileName(PackExe)]));
    Exit;
  end;
  FPendingPackExe := '';
  FPendingPackPbc := '';

  { One diagnostic means one place to be. Jumping there is what the user was going
    to do next anyway, and doing it only for a source location keeps a `file not
    found` from scrolling the editor to line 0. }
  if (ListProblems.Items.Count = 1) and (FProblemLines.Count = 1) then
  begin
    ListProblems.ItemIndex := 0;
    ListProblemsDblClick(nil);
  end
  else if ListProblems.Items.Count > 0 then
    PagesOutput.ActivePage := TabProblems;

  RefreshStatus;
end;

procedure TFrmMain.RunnerFailed(Sender: TObject; const AReason: String);
begin
  AddOutput('> could not start: ' + AReason);
  RefreshStatus;
end;

procedure TFrmMain.ScrollOutputToEnd;
begin
  { NOT `SelStart := Length(MemoOutput.Text)`. Reading .Text CONCATENATES every
    line into one string, so scrolling that way costs O(total output) per line and
    the whole thing is quadratic: a program printing in a loop wedges the editor
    inside the one call that was supposed to be a scroll. GetTextLen asks the
    widget for the length it already knows. Measured as a hang risk during the
    review on 2026-09-10. }
  MemoOutput.SelStart := MemoOutput.GetTextLen;
end;

procedure TFrmMain.TrimOutput;
var
  Excess: Integer;
begin
  { An output pane is a transcript, not an archive. Left unbounded it is a
    program's memory ceiling as well as its own -- a runaway loop printing a line
    per iteration grows this without limit, and the run cannot be watched because
    the editor is busy holding it. }
  Excess := MemoOutput.Lines.Count - MaxOutputLines;
  if Excess <= 0 then
    Exit;
  MemoOutput.Lines.BeginUpdate;
  try
    while Excess > 0 do
    begin
      MemoOutput.Lines.Delete(0);
      Dec(Excess);
    end;
  finally
    MemoOutput.Lines.EndUpdate;
  end;
end;

procedure TFrmMain.AddOutput(const AText: String);
begin
  { The editor's own notes -- `> run x.bas`, `> finished (0)` -- always start a
    line of their own. }
  FOutputOpen := False;
  MemoOutput.Lines.Add(AText);
  TrimOutput;
  ScrollOutputToEnd;
end;

procedure TFrmMain.AppendOutput(AKind: TRunStream; const AText: String;
  ACompleteLine: Boolean);
var
  Last: Integer;
begin
  Last := MemoOutput.Lines.Count - 1;
  if FOutputOpen and (FOutputOpenKind = AKind) and (Last >= 0) then
    MemoOutput.Lines[Last] := MemoOutput.Lines[Last] + AText
  else
    MemoOutput.Lines.Add(AText);

  FOutputOpen := not ACompleteLine;
  FOutputOpenKind := AKind;

  TrimOutput;
  { Keep the newest line visible without stealing the caret from the editor. }
  ScrollOutputToEnd;
end;

procedure TFrmMain.AddProblem(const AMsg: TPhosphorMessage; const AFallbackPath: String);
var
  Path: String;
begin
  { The host echoes the path it was GIVEN, relative if that is what it got. The
    file this editor handed it is the one it means, so that is what is recorded --
    resolving the echo against a working directory would be a second way to be
    wrong about the same thing. }
  if AMsg.Kind = pmkSourceError then
    Path := AFallbackPath
  else
    Path := '';

  if HasSourceLocation(AMsg) then
  begin
    ListProblems.Items.Add(Format('%s(%d): %s',
      [ExtractFileName(Path), AMsg.Line, AMsg.Text]));
    FProblemLines.Add(Format('%d|%s', [AMsg.Line, Path]));
  end
  else
  begin
    ListProblems.Items.Add(AMsg.Text);
    FProblemLines.Add('0|');
  end;
end;

procedure TFrmMain.ListProblemsDblClick(Sender: TObject);
var
  Idx, Sep, Line, Code: Integer;
  Entry: String;
begin
  Idx := ListProblems.ItemIndex;
  if (Idx < 0) or (Idx >= FProblemLines.Count) then
    Exit;
  Entry := FProblemLines[Idx];
  Sep := Pos('|', Entry);
  if Sep < 1 then
    Exit;
  Val(Copy(Entry, 1, Sep - 1), Line, Code);
  if (Code <> 0) or (Line <= 0) then
    Exit;
  GotoSource(Copy(Entry, Sep + 1, MaxInt), Line);
end;

procedure TFrmMain.GotoSource(const APath: String; ALine: Integer);
var
  I, Line: Integer;
  Doc: TEditorDoc;
begin
  Doc := nil;
  for I := 0 to FDocs.Count - 1 do
    if CompareFilenames(TEditorDoc(FDocs[I]).FullDisplayName, APath) = 0 then
    begin
      PagesEditors.ActivePageIndex := I;
      Doc := TEditorDoc(FDocs[I]);
      Break;
    end;

  { Not open -- the tab was closed while the program ran, or the diagnostic named
    a file this window never had. Open it, and if that is not possible, do
    NOTHING. Falling back to the active document, which is what this used to do,
    moves the caret to a line number in the WRONG FILE: a plausible-looking jump
    to somewhere the error is not. }
  if (Doc = nil) and (APath <> '') and FileExistsUTF8(APath) then
  begin
    OpenPath(APath);
    for I := 0 to FDocs.Count - 1 do
      if CompareFilenames(TEditorDoc(FDocs[I]).FullDisplayName, APath) = 0 then
      begin
        Doc := TEditorDoc(FDocs[I]);
        Break;
      end;
  end;
  if Doc = nil then
    Exit;

  { A line number CAN point past the end: an unterminated block in a three-line
    file is reported at line 4. Clamping puts the caret on the last line rather
    than nowhere. }
  Line := ALine;
  if Line > Doc.Edit.Lines.Count then
    Line := Doc.Edit.Lines.Count;
  if Line < 1 then
    Line := 1;

  Doc.Edit.CaretXY := Point(1, Line);
  Doc.Edit.EnsureCursorPosVisible;
  FocusEditor(Doc);
  RefreshStatus;
end;

{ ------------------------------------------------------------------ stdin --- }

procedure TFrmMain.BtnSendInputClick(Sender: TObject);
begin
  if not FRunner.Running then
  begin
    StatusBar1.Panels[3].Text := 'nothing is running to read that';
    Exit;
  end;
  { Echoed into the output, because a console shows what was typed and a program
    that reads with INPUT does not print the answer back. Without the echo the
    transcript reads as if the program invented the value. }
  AddOutput('< ' + EditInput.Text);
  FRunner.SendInput(EditInput.Text);
  EditInput.Text := '';
end;

procedure TFrmMain.EditInputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    BtnSendInputClick(Sender);
  end;
end;

{ ------------------------------------------------------------------- debug --- }

procedure TFrmMain.ActToggleBreakpointExecute(Sender: TObject);
var
  Doc: TEditorDoc;
begin
  Doc := ActiveDoc;
  if Doc = nil then
    Exit;
  Doc.ToggleBreakpoint(Doc.CaretLine);
  SyncBreakpoints(Doc);
  Doc.Edit.Invalidate;
  RefreshStatus;
end;

procedure TFrmMain.ActClearBreakpointsExecute(Sender: TObject);
var
  Doc: TEditorDoc;
begin
  Doc := ActiveDoc;
  if Doc = nil then
    Exit;
  Doc.ClearBreakpoints;
  SyncBreakpoints(Doc);
  Doc.Edit.Invalidate;
  RefreshStatus;
end;

procedure TFrmMain.ActDebugWhyExecute(Sender: TObject);
begin
  { Reachable from a toolbar or a shortcut even while the menu item is hidden, so
    the answer is guarded here too rather than only where it is offered. }
  if FDebug.Available then
  begin
    MessageDlg('PhosphorIDE',
      Format('Stepping IS available: %s speaks the debug protocol.'#10#10 +
             'Set a breakpoint and press Start Debugging.',
             [FHostPath]), mtInformation, [mbOK], 0);
    Exit;
  end;
  if MessageDlg('Stepping is not available yet',
    FDebug.UnavailableReason + #10#10 +
    'Open the protocol specification on GitHub?',
    mtInformation, [mbYes, mbNo], 0) = mrYes then
    OpenURL(UrlDebugProtocol);
end;

procedure TFrmMain.RefreshDebugActions;
var
  Live, InSession, Stopped: Boolean;
begin
  { Keyed on the STATE and not only on Available. Available says this host could
    debug; it says nothing about whether a session is running, and an enabled
    Start in the middle of one is an offer to listen on a second socket. }
  Live := FDebug.Available;
  InSession := FDebug.State in [dsStarting, dsRunning, dsStopped, dsTerminating];
  Stopped := FDebug.State = dsStopped;

  { Stopped is not enough: an EXCEPTION stop reports dsStopped and accepts
    nothing. The state says where the program is; FDebugTerminal says whether it
    can still be told anything. }
  Stopped := Stopped and (not FDebugTerminal);

  ActDebugStart.Enabled := Live and (not InSession);
  ActDebugStop.Enabled := InSession;
  ActContinue.Enabled := Stopped;
  ActStepOver.Enabled := Stopped;
  ActStepInto.Enabled := Stopped;

  { StepOut is the one step the host is allowed not to have, and it says so in
    the handshake. Offering it against a capability of false is offering a request
    the other end will refuse. }
  ActStepOut.Enabled := Stopped and FDebug.Capabilities.StepOut;

  { Hints are CLEARED when they stop being true. Leaving the "stepping is not
    available" text on an action that is now live is the same defect as the menu
    that lies, one layer down. }
  if Live then
  begin
    ActDebugStart.Hint := 'Run under the debugger and stop at your breakpoints';
    ActDebugStop.Hint := 'End the debug session and kill the program';
    ActContinue.Hint := 'Run on until the next breakpoint';
    ActStepOver.Hint := 'Run to the next line, over any call on this one';
    ActStepInto.Hint := 'Run to the next line, into a call on this one';
    if FDebug.Capabilities.StepOut then
      ActStepOut.Hint := 'Run until this function returns'
    else
      ActStepOut.Hint := 'This host does not offer step out';
    { The menu item asks "Why is stepping unavailable?". On a host that can step
      it has no answer, and it was opening a dialog whose body was the empty
      string -- the explained absence turning into an unexplained blank the
      moment the thing it explained stopped being absent. }
    ActDebugWhy.Visible := False;
  end
  else
  begin
    ActDebugStart.Hint := FDebug.UnavailableReason;
    ActStepOver.Hint := FDebug.UnavailableReason;
    ActStepInto.Hint := FDebug.UnavailableReason;
    ActStepOut.Hint := FDebug.UnavailableReason;
    ActContinue.Hint := FDebug.UnavailableReason;
    ActDebugStop.Hint := FDebug.UnavailableReason;
    ActDebugWhy.Visible := True;
  end;
end;

{ --------------------------------------------------------- the debug session - }

procedure TFrmMain.RepaintEditors;
var
  I: Integer;
begin
  { The stop can be in a file that is not the active tab, so every editor is
    asked to redraw rather than just this one. There are a handful of tabs. }
  for I := 0 to FDocs.Count - 1 do
    if TEditorDoc(FDocs[I]).Edit <> nil then
      TEditorDoc(FDocs[I]).Edit.Invalidate;
end;

function TFrmMain.StartDebugSession: Boolean;
var
  Doc: TEditorDoc;
  Path: String;
  Lines: TPdbpLines;
  I, Port: Integer;
begin
  Result := False;
  if not RequireHost then
    Exit;
  if not EnsureSavedForRun(Path) then
    Exit;
  Doc := ActiveDoc;
  if Doc = nil then
    Exit;

  Lines := nil;
  SetLength(Lines, Doc.BreakpointCount);
  for I := 0 to Doc.BreakpointCount - 1 do
    Lines[I] := Doc.Breakpoints[I];

  { STOP AT ENTRY WHEN THERE ARE NO BREAKPOINTS. Otherwise Start Debugging on a
    program with no marks runs to completion and is indistinguishable from Run --
    the user pressed the debug button and watched nothing happen. With a mark,
    entry would be a stop they did not ask for. }
  Port := FDebug.BeginListen(Path, Lines, Length(Lines) = 0);
  if Port = 0 then
  begin
    MessageDlg('PhosphorIDE',
      'Could not open a local socket for the debugger.', mtError, [mbOK], 0);
    Exit;
  end;

  { The session listens; THIS spawns. Through TPhosphorRunner like everything
    else, which is not ceremony: the debuggee's stdout and stderr still have to
    be read, and an editor holding the socket but not the pipes stalls the
    program behind a full pipe buffer with no protocol symptom at all. }
  if not StartHost(['debug', '--port', IntToStr(Port), Path],
       Format('debug %s', [ExtractFileName(Path)])) then
  begin
    FDebug.AbandonListen('the host would not start');
    Exit;
  end;

  FDebugLive := True;
  FDebugPath := Path;
  FDebugLine := 0;
  FVarShown := False;
  FDebugTerminal := False;
  ClearVariables;
  FDebugTimer.Enabled := True;
  RefreshDebugActions;
  Result := True;
end;

procedure TFrmMain.EndDebugSession(const AWhy: String);
begin
  { IDEMPOTENT, AND THAT IS THE POINT. Three separate things end a session -- the
    protocol's `exited` event, the child process dying, and the state falling
    back to idle -- and in an ordinary run ALL THREE happen, milliseconds apart,
    in that order. The first to arrive does the work and gets to say why; the
    others find nothing left to do. Without this guard the user reads `> the
    debugged program finished` three times for one program. }
  if not FDebugLive then
    Exit;
  FDebugLive := False;
  FDebugTimer.Enabled := False;
  FDebugLine := 0;
  FDebugPath := '';
  { The values were true at a moment that has passed. Leaving them on screen after
    the program is gone is the same defect as the stale hint on an action. }
  ClearVariables;
  TabVariables.Caption := 'Variables';
  FInstalledPath := '';
  FInstalledLines := nil;
  if AWhy <> '' then
    AddOutput('> ' + AWhy);
  RepaintEditors;
  RefreshDebugActions;
  RefreshStatus;
end;

procedure TFrmMain.DebugTimerTick(Sender: TObject);
begin
  { THE PROGRAM'S OUTPUT FIRST, THEN THE PROTOCOL. Both arrive on timers and
    nothing orders the two, so a stop announced before the pending stdout is
    collected prints `> stopped at line 7` ABOVE the PRINT output of lines 1 to
    6 -- and the transcript then tells the user the program reached line 7
    before it printed anything. Measured on 2026-09-16. Draining here costs one
    extra pass over an empty buffer per tick and fixes the ordering for every
    message this handler can produce. }
  FRunner.Drain;
  FDebug.Poll;
end;

procedure TFrmMain.DebugStateChanged(Sender: TObject);
begin
  { THE STRIPE IS A PROPERTY OF BEING STOPPED, NOT A MEMORY OF HAVING BEEN.
    FDebugLine was written on every stop and cleared only when the session ended,
    so from the instant the user pressed Continue until the program was gone the
    editor went on painting "execution is here" across a line the program had
    already left. On a program blocked at `input` that lasts as long as the user
    does; with stepping it is wrong after every single step, which is most of the
    time a debugger is being used at all. }
  if (FDebug.State <> dsStopped) and (FDebugLine <> 0) then
  begin
    FDebugLine := 0;
    RepaintEditors;
  end;

  { AND THE SESSION ENDS WHERE IT IS DECIDED. Idle is idle however it was
    reached -- a clean `exited`, a socket that closed, a desync, a Stop -- and
    routing the ending through the state instead of through three callbacks is
    what stops a fourth way of ending from being discovered later as a session
    that never cleaned up. EndDebugSession is idempotent for exactly this. }
  if FDebugLive and (FDebug.State in [dsIdle, dsUnavailable]) then
    EndDebugSession('');

  RefreshDebugActions;
  RefreshStatus;
end;

procedure TFrmMain.DebugStopped(Sender: TObject; const APath: String;
  ALine: Integer; AReason: TPdbpStopReason; const AText: String);
begin
  { AN EXCEPTION STOP IS TERMINAL AND READ-ONLY. The program is finished; the
    engine has stopped to show where, not to be told what to do next, so Continue
    and the three steps are taken away rather than left live to send a command
    into a run that is over.

    Measured on 2026-09-16, and worth knowing before this is trusted: today's
    host does not linger on that stop. It emits the event and closes the socket,
    so the session is over a tick later whatever the buttons say. The gating is
    kept because the protocol permits a host that DOES wait, and because a button
    that is live for one tick and then sends into a dead socket is worse than one
    that was never offered. }
  FDebugTerminal := AReason = psrException;

  FDebugLine := ALine;
  { The host echoes the path it was LAUNCHED with, and the editor already keeps
    that in FRunPath for exactly this reason -- resolving the echo against a
    working directory would be a second way to be wrong about the same file. }
  if FRunPath <> '' then
    FDebugPath := FRunPath
  else
    FDebugPath := APath;

  { The engine's own words go on the SAME line as the stop, not on one of their
    own. The host also writes `phosphor: file:line: division by zero` to stderr,
    which the Problems pane already parses, so a second full-width line saying
    only `> division by zero` was the same fact twice in two shapes. }
  if AText <> '' then
    AddOutput(Format('> stopped at line %d (%s): %s',
      [ALine, PdbpStopReasonName(AReason), AText]))
  else
    AddOutput(Format('> stopped at line %d (%s)',
      [ALine, PdbpStopReasonName(AReason)]));

  { Frame 0 is the only one there is today. Asking BY INDEX anyway is what stops
    this pane being rewritten when a call-stack pane arrives and frame 1 becomes
    selectable -- the answer already carries the frame it belongs to. }
  FDebug.RequestVariables(0);
  if not FVarShown then
  begin
    FVarShown := True;
    PagesOutput.ActivePage := TabVariables;
  end;

  GotoSource(FDebugPath, ALine);
  RepaintEditors;
  RefreshDebugActions;
  RefreshStatus;
end;

procedure TFrmMain.DebugExited(Sender: TObject; AExitCode: Integer);
begin
  { SILENTLY, because the process is about to say it better. `exited` is the
    protocol's account of an ending that the RUNNER also reports, a few
    milliseconds later, as `> the program failed (1)` -- with the numeric code,
    in the same words every non-debug run uses. Saying it twice in two phrasings
    read as two things going wrong. The event is still what ENDS the session; it
    just does not narrate it. }
  EndDebugSession('');
end;

procedure TFrmMain.DebugNote(Sender: TObject; const AText: String);
begin
  AddOutput('  debug: ' + AText);
end;

procedure TFrmMain.DebugLinesInstalled(Sender: TObject; const APath: String;
  const AInstalled: TPdbpLines);
var
  Doc: TEditorDoc;
  I: Integer;
  Dead: String;
begin
  { A line with no executable statement on it -- a blank, a comment, an `endif`,
    an `endfunction` -- comes back ABSENT, and that absence is the only
    verified/unverified marker the protocol has. }
  FInstalledPath := APath;
  FInstalledLines := AInstalled;

  { The document the PATH names, not whichever tab happens to be active. The user
    is free to switch tabs between pressing Debug and the answer arriving, and
    counting one file's breakpoints against another file's installed set is a
    wrong answer that looks like a right one. }
  Doc := DocByPath(APath);
  if Doc = nil then
    Doc := ActiveDoc;
  RepaintEditors;
  if Doc = nil then
    Exit;

  Dead := '';
  for I := 0 to Doc.BreakpointCount - 1 do
    if not BreakpointIsArmed(Doc, Doc.Breakpoints[I]) then
    begin
      if Dead <> '' then
        Dead := Dead + ', ';
      Dead := Dead + IntToStr(Doc.Breakpoints[I]);
    end;

  if Dead <> '' then
    AddOutput(Format('  debug: nothing will stop on line%s %s -- no statement ' +
      'there to stop at', [Copy('s', 1, Ord(Pos(',', Dead) > 0)), Dead]));
end;

procedure TFrmMain.SyncBreakpoints(ADoc: TEditorDoc);
var
  Lines: TPdbpLines;
  I: Integer;
begin
  { A BREAKPOINT SET DURING A SESSION IS THE NORMAL CASE, not an exotic one: the
    user runs, stops somewhere, reads the code and marks the line they now want.
    Both ends have always supported re-arming -- the protocol replaces the whole
    set per file and the host answers with what it installed -- and nothing here
    was calling it, so the mark appeared in the gutter and the program ran
    straight past it. The same defect as TrackEdit having no caller, and found
    the same way.

    Only for the file being debugged: a mark in another tab belongs to a program
    that is not running, and sending it under the debuggee's path would arm a
    line number against the wrong source. }
  if (not FDebugLive) or (ADoc = nil) or (FDebugPath = '') then
    Exit;
  if CompareFilenames(ADoc.FullDisplayName, FDebugPath) <> 0 then
    Exit;

  Lines := nil;
  SetLength(Lines, ADoc.BreakpointCount);
  for I := 0 to ADoc.BreakpointCount - 1 do
    Lines[I] := ADoc.Breakpoints[I];
  FDebug.SetBreakpoints(FDebugPath, Lines);
end;

function TFrmMain.DocByPath(const APath: String): TEditorDoc;
var
  I: Integer;
begin
  Result := nil;
  if APath = '' then
    Exit;
  for I := 0 to FDocs.Count - 1 do
    if CompareFilenames(TEditorDoc(FDocs[I]).FullDisplayName, APath) = 0 then
      Exit(TEditorDoc(FDocs[I]));
end;

function TFrmMain.BreakpointIsArmed(ADoc: TEditorDoc; ALine: Integer): Boolean;
var
  I: Integer;
begin
  { UNKNOWN IS NOT DEAD. Outside a session, and for any file the host has not
    reported on, nothing is known about which lines can be stopped at -- so the
    mark is drawn as the user meant it. Painting every breakpoint inert whenever
    the answer is missing would be a confident claim built on no information. }
  Result := True;
  if (Length(FInstalledLines) = 0) or (ADoc = nil) then
    Exit;
  if CompareFilenames(ADoc.FullDisplayName, FInstalledPath) <> 0 then
    Exit;
  for I := 0 to High(FInstalledLines) do
    if FInstalledLines[I] = ALine then
      Exit(True);
  Result := False;
end;

procedure TFrmMain.ClearVariables;
begin
  ListVariables.Items.Clear;
end;

procedure TFrmMain.DebugVariables(Sender: TObject; AFrame: Integer;
  const AVars: TPdbpVariables);

  procedure AddRow(const AVar: TPdbpVariable);
  var
    Item: TListItem;
  begin
    Item := ListVariables.Items.Add;
    { THE EDITOR FORMATS NOTHING. Every one of these four strings was rendered by
      the host, which rendered the value exactly as PRINT would. A second renderer
      here would be a second set of rules to keep in step with a language whose
      own rules are frozen elsewhere. }
    Item.Caption := AVar.Name;
    Item.SubItems.Add(AVar.Value);
    Item.SubItems.Add(AVar.Kind);
    Item.SubItems.Add(AVar.Scope);
  end;

var
  I: Integer;
begin
  ListVariables.Items.BeginUpdate;
  try
    ListVariables.Items.Clear;

    { LOCALS ABOVE GLOBALS, AND BOTH LABELLED. Not cosmetic: in this language an
      undeclared name inside a function IS a global (Phosphor's frozen decision,
      not an accident), so a pane that blurred the two would teach the reader
      something false about where their value lives. }
    for I := 0 to High(AVars) do
      if AVars[I].Scope = 'local' then
        AddRow(AVars[I]);
    for I := 0 to High(AVars) do
      if AVars[I].Scope <> 'local' then
        AddRow(AVars[I]);
  finally
    ListVariables.Items.EndUpdate;
  end;

  TabVariables.Caption := Format('Variables (%d)', [Length(AVars)]);
end;

procedure TFrmMain.ActDebugStartExecute(Sender: TObject);
begin
  StartDebugSession;
end;

procedure TFrmMain.ActDebugStopExecute(Sender: TObject);
begin
  { A process kill, deliberately. `disconnect` while the program is RUNNING is
    never answered -- the host is inside the program, not inside the protocol --
    so asking politely is asking into silence. }
  { The reason is announced FIRST. Stop's own return to dsIdle ends the session
    through DebugStateChanged, and the first ending is the one that gets to name
    a reason -- so ending it here, deliberately and with words, is what keeps the
    user's own Stop from being reported as an anonymous one. }
  EndDebugSession('debug session ended');
  FDebug.Stop(True);
  if FRunner.Running then
    FRunner.Kill;
end;

procedure TFrmMain.ActContinueExecute(Sender: TObject);
begin
  FDebug.Resume;
end;

{ The three steps. Each is one call: the session refuses anything the state
  forbids and says so through OnNote, so there is nothing to guard here that is
  not already guarded somewhere that can be tested without a window.

  One report that is NOT a bug, recorded so it is not chased twice: stepping can
  land on a `function f(n) local r` header line, because the compiler's jump over
  the function body sits on it. That is where execution genuinely is. }
procedure TFrmMain.ActStepOverExecute(Sender: TObject);
begin
  FDebug.StepOver;
end;

procedure TFrmMain.ActStepIntoExecute(Sender: TObject);
begin
  FDebug.StepInto;
end;

procedure TFrmMain.ActStepOutExecute(Sender: TObject);
begin
  FDebug.StepOut;
end;

{ ------------------------------------------------------------------ editor --- }

procedure TFrmMain.ApplyEditorSettings(ADoc: TEditorDoc);
var
  Ed: TSynEdit;
begin
  if ADoc = nil then
    Exit;
  Ed := ADoc.Edit;
  Ed.Font.Name := FSettings.FontName;
  Ed.Font.Size := FSettings.FontSize;
  Ed.TabWidth := FSettings.TabWidth;
  if FSettings.UseSpaces then
    Ed.Options := Ed.Options + [eoTabsToSpaces]
  else
    Ed.Options := Ed.Options - [eoTabsToSpaces];
  Ed.Gutter.LineNumberPart(0).Visible := FSettings.ShowLineNumbers;
  Ed.RightEdge := FSettings.RightMargin;

  if FSettings.DarkTheme then
  begin
    Ed.Color := clBlack;
    Ed.Font.Color := clWhite;
  end
  else
  begin
    Ed.Color := clWhite;
    Ed.Font.Color := clBlack;
  end;

  { The caret's line. SynEdit draws it whenever LineHighlightColor has a colour,
    and stops when it is clNone -- so the setting is turned OFF by clearing it,
    not by remembering a previous value somewhere. The shade has to be quiet: it
    is behind text on every line the caret visits, and a strong one fights the
    breakpoint markup that OnSpecialLineMarkup paints over the same rows. }
  if FSettings.HighlightCurrentLine then
  begin
    if FSettings.DarkTheme then
      Ed.LineHighlightColor.Background := $2A2A2A
    else
      Ed.LineHighlightColor.Background := $F4F4F4;
  end
  else
    Ed.LineHighlightColor.Background := clNone;
end;

procedure TFrmMain.ApplyAllEditorSettings;
var
  I: Integer;
begin
  for I := 0 to FDocs.Count - 1 do
    ApplyEditorSettings(TEditorDoc(FDocs[I]));
end;

procedure TFrmMain.SettingsChanged;
begin
  FHighlighter.ApplyTheme(FSettings.DarkTheme);
  ApplyAllEditorSettings;
  ResolveHost;
  RefreshStatus;
end;

procedure TFrmMain.EditorChange(Sender: TObject);
begin
  RefreshTabCaption(ActiveDoc);
end;

procedure TFrmMain.EditorStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
begin
  if (scCaretX in AChanges) or (scCaretY in AChanges) or (scModified in AChanges) then
    RefreshStatus;
end;

procedure TFrmMain.EditorSpecialLineMarkup(Sender: TObject; ALine: Integer;
  var ASpecial: Boolean; AMarkup: TSynSelectedColor);
var
  Doc: TEditorDoc;
begin
  { SynEdit asks this for every visible line, so it must stay cheap: it looks up
    a line number in a short sorted array and answers. }
  ASpecial := False;
  Doc := DocOfPage(PagesEditors.ActivePage);
  if Doc = nil then
    Exit;

  { THE STOP OUTRANKS THE BREAKPOINT. A line is usually both -- you stopped there
    because you marked it -- and the two paints answer different questions: the
    mark says "I asked to stop here", the stop says "you ARE here". Only the
    second one moves, so only the second one tells you anything while you step.
    Painting the mark on top would freeze the cursor at the first breakpoint for
    the rest of the session. }
  if (FDebugLine = ALine) and (FDebugLine > 0) and
     (CompareFilenames(Doc.FullDisplayName, FDebugPath) = 0) then
  begin
    ASpecial := True;
    AMarkup.Background := clNavy;
    AMarkup.Foreground := clWhite;
    Exit;
  end;

  if Doc.HasBreakpoint(ALine) then
  begin
    ASpecial := True;
    if BreakpointIsArmed(Doc, ALine) then
    begin
      AMarkup.Background := clMaroon;
      AMarkup.Foreground := clWhite;
    end
    else
    begin
      { ARMED AND INERT MUST NOT LOOK THE SAME. The host reported this line back
        as not installed: there is no statement on it to stop at, so the program
        will run past it forever and the user will conclude the debugger is
        broken. A grey row says "I heard you, and nothing will happen here".

        A hollow gutter ICON is the better answer and is not here, because it
        needs a TImageList, and the gtk2 image-list trap -- register 16x16 AND
        24x24 or the mark is blurry on one platform and missing on the other --
        is a piece of work with its own roadmap item. The row colour costs
        nothing and carries the same fact. }
      AMarkup.Background := clGray;
      AMarkup.Foreground := clWhite;
    end;
  end;
end;

procedure TFrmMain.EditorGutterClick(Sender: TObject; X, Y, ALine: Integer;
  AMark: TSynEditMark);
var
  Doc: TEditorDoc;
begin
  { Clicking the margin is how every other editor toggles a breakpoint, so it is
    how this one does too -- even while nothing stops at one. }
  Doc := DocOfPage(PagesEditors.ActivePage);
  if (Doc = nil) or (ALine < 1) then
    Exit;
  Doc.ToggleBreakpoint(ALine);
  SyncBreakpoints(Doc);
  Doc.Edit.Invalidate;
  RefreshStatus;
end;

procedure TFrmMain.PagesEditorsChange(Sender: TObject);
begin
  RefreshStatus;
end;

{ --------------------------------------------------------------- chrome ----- }

procedure TFrmMain.RefreshTabCaption(ADoc: TEditorDoc);
var
  Idx: Integer;
begin
  if ADoc = nil then
    Exit;
  Idx := FDocs.IndexOf(ADoc);
  if (Idx < 0) or (Idx >= PagesEditors.PageCount) then
    Exit;
  PagesEditors.Pages[Idx].Caption := ADoc.DisplayName;
end;

procedure TFrmMain.RefreshRecentMenu;
var
  I: Integer;
  Item: TMenuItem;
begin
  MnuRecent.Clear;
  for I := 0 to FSettings.RecentCount - 1 do
  begin
    Item := TMenuItem.Create(MnuRecent);
    Item.Caption := Format('&%d  %s', [I + 1, FSettings.Recent[I]]);
    Item.Tag := I;
    Item.OnClick := @RecentClick;
    MnuRecent.Add(Item);
  end;
  MnuRecent.Enabled := FSettings.RecentCount > 0;
end;

procedure TFrmMain.RecentClick(Sender: TObject);
var
  Idx: Integer;
  Path: String;
begin
  Idx := TMenuItem(Sender).Tag;
  if (Idx < 0) or (Idx >= FSettings.RecentCount) then
    Exit;
  Path := FSettings.Recent[Idx];
  if not FileExistsUTF8(Path) then
  begin
    FSettings.RemoveRecentFile(Path);
    RefreshRecentMenu;
    MessageDlg('PhosphorIDE', Format('%s is no longer there.', [Path]),
      mtInformation, [mbOK], 0);
    Exit;
  end;
  OpenPath(Path);
end;

procedure TFrmMain.RefreshStatus;
var
  Doc: TEditorDoc;
begin
  Doc := ActiveDoc;
  if Doc <> nil then
  begin
    StatusBar1.Panels[0].Text := Format('%d: %d', [Doc.CaretLine, Doc.CaretCol]);
    if Doc.Modified then
      StatusBar1.Panels[1].Text := 'modified'
    else
      StatusBar1.Panels[1].Text := '';
    Caption := Format('%s - PhosphorIDE', [Doc.DisplayName]);
  end
  else
  begin
    StatusBar1.Panels[0].Text := '';
    StatusBar1.Panels[1].Text := '';
    Caption := 'PhosphorIDE';
  end;

  if FHostPath = '' then
    StatusBar1.Panels[2].Text := 'no phosphor host'
  else if FHostVersion <> '' then
    StatusBar1.Panels[2].Text := FHostVersion
  else
    StatusBar1.Panels[2].Text := ExtractFileName(FHostPath);

  if FRunner.Running then
    StatusBar1.Panels[3].Text := FRunLabel + ' ...'
  else
    StatusBar1.Panels[3].Text := '';
end;

procedure TFrmMain.ActionList1Update(AAction: TBasicAction; var Handled: Boolean);
var
  Doc: TEditorDoc;
  Busy: Boolean;
begin
  Handled := False;
  Doc := ActiveDoc;
  Busy := FRunner.Running;

  ActSave.Enabled := Doc <> nil;
  ActSaveAs.Enabled := Doc <> nil;
  ActCloseTab.Enabled := Doc <> nil;
  ActUndo.Enabled := (Doc <> nil) and Doc.Edit.CanUndo;
  ActRedo.Enabled := (Doc <> nil) and Doc.Edit.CanRedo;
  ActCut.Enabled := (Doc <> nil) and Doc.Edit.SelAvail;
  ActCopy.Enabled := ActCut.Enabled;
  ActPaste.Enabled := Doc <> nil;
  ActFind.Enabled := Doc <> nil;
  ActFindNext.Enabled := (Doc <> nil) and (FLastSearch <> '');
  ActReplace.Enabled := Doc <> nil;
  ActGotoLine.Enabled := Doc <> nil;

  ActRun.Enabled := (Doc <> nil) and not Busy;
  ActCheck.Enabled := ActRun.Enabled;
  ActCompile.Enabled := ActRun.Enabled;
  ActPack.Enabled := ActRun.Enabled;
  ActStop.Enabled := Busy;

  ActToggleBreakpoint.Enabled := Doc <> nil;
  ActClearBreakpoints.Enabled := (Doc <> nil) and (Doc.BreakpointCount > 0);

  BtnSendInput.Enabled := Busy;
  EditInput.Enabled := Busy;
end;

{ ------------------------------------------------------------------- help ---- }

procedure TFrmMain.ActPreferencesExecute(Sender: TObject);
begin
  if FrmPreferences = nil then
    Application.CreateForm(TFrmPreferences, FrmPreferences);
  FrmPreferences.Edit(FSettings);
  if FrmPreferences.ShowModal = mrOK then
  begin
    FrmPreferences.Apply;
    FSettings.Save;
    SettingsChanged;
  end;
end;

procedure TFrmMain.ActAboutExecute(Sender: TObject);
begin
  if FrmAbout = nil then
    Application.CreateForm(TFrmAbout, FrmAbout);
  FrmAbout.Describe(FHostPath, FHostVersion, FSettings.FileName);
  FrmAbout.ShowModal;
end;

procedure TFrmMain.ActLangRefExecute(Sender: TObject);
begin
  OpenURL(UrlLanguageReference);
end;

procedure TFrmMain.ActFuncRefExecute(Sender: TObject);
begin
  OpenURL(UrlFunctionReference);
end;

end.
