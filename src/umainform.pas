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
  Classes, SysUtils, Math, Types, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  ActnList, ExtCtrls, StdCtrls, LCLType, SynEdit, SynEditTypes,
  SynEditMiscClasses, SynEditMarkupSpecialLine, SynEditMarks, SynGutter,
  ueditordoc, uphosphorhost, uphosphormsg, uphosphorrun, uphosphorsettings,
  SynEditHighlighter,
  usynphosphor, uphosphorlang, udebugproto, udebugsession, uphosphoricons,
  uphosphorcomplete, uphosphoroutline, uphosphorrepl, ufindinfiles, SynCompletion;

type

  { TFrmMain }

  TFrmMain = class(TForm)
    ActAbout: TAction;
    ActCheck: TAction;
    ActClearBreakpoints: TAction;
    ActComplete: TAction;
    ActFindInFiles: TAction;
    ActGotoDefinition: TAction;
    ActOutline: TAction;
    ActRepl: TAction;
    BtnReplEnd: TButton;
    BtnReplSend: TButton;
    EditRepl: TEdit;
    BtnFindBrowse: TButton;
    BtnFindGo: TButton;
    BtnFindStop: TButton;
    ChkFindCase: TCheckBox;
    EditFindMask: TEdit;
    EditFindRoot: TEdit;
    EditFindWhat: TEdit;
    LblFindMask: TLabel;
    LblFindRoot: TLabel;
    LblFindWhat: TLabel;
    ListFind: TListBox;
    ListOutline: TListBox;
    MnuFindInFiles: TMenuItem;
    MemoRepl: TMemo;
    MnuGotoDefinition: TMenuItem;
    MnuOutline: TMenuItem;
    MnuRepl: TMenuItem;
    PanelRepl: TPanel;
    SepR2: TMenuItem;
    PanelFind: TPanel;
    SelectDirectoryDialog1: TSelectDirectoryDialog;
    TabFind: TTabSheet;
    TabOutline: TTabSheet;
    TabRepl: TTabSheet;
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
    ImagesGutter: TImageList;
    ImagesToolbar: TImageList;
    TabProblems: TTabSheet;
    TabStack: TTabSheet;
    ListStack: TListView;
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
    procedure ActCompleteExecute(Sender: TObject);
    procedure ActFindInFilesExecute(Sender: TObject);
    procedure ActGotoDefinitionExecute(Sender: TObject);
    procedure ActOutlineExecute(Sender: TObject);
    procedure ActReplExecute(Sender: TObject);
    procedure BtnReplEndClick(Sender: TObject);
    procedure BtnReplSendClick(Sender: TObject);
    procedure EditReplKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure BtnFindBrowseClick(Sender: TObject);
    procedure BtnFindGoClick(Sender: TObject);
    procedure BtnFindStopClick(Sender: TObject);
    procedure EditFindWhatKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure ListFindDblClick(Sender: TObject);
    procedure ListOutlineClick(Sender: TObject);
    procedure ListOutlineDblClick(Sender: TObject);
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
    procedure ListStackDblClick(Sender: TObject);
    procedure ListStackSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
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

    { The frames of the current stop, exactly as the host reported them. Kept
      because two things need them after the fact: the variables pane names the
      frame it is showing, and a double-click needs the path and line of the row
      that was hit rather than of whatever is selected now.

      Emptied whenever the program is not stopped. A call stack is a description
      of a program standing still; keeping it on screen while one runs is the
      same defect as the current-line stripe that outlived its stop. }
    FStackFrames: TPdbpFrames;
    { Selecting a row asks the host for that frame's variables, and filling the
      list selects row 0 -- so without this the fill asks a question the stop
      already asked. }
    FStackFilling: Boolean;
    { The caller-has-no-line explanation is worth saying once per session and
      unbearable once per stop. }
    FStackLineNoted: Boolean;
    { Set by an exception stop. The session is still connected and still reports
      dsStopped, which is true and is not the whole truth: nothing may be sent. }
    FDebugTerminal: Boolean;

    { The completion popup, built in code for the same reason FDebugTimer is:
      it needs an Editor, and the editors are created per tab at run time.
      One popup serves every tab -- TSynCompletion is a multi-editor plugin. }
    FCompletion: TSynCompletion;
    { What is in FCompletion.ItemList, in the same order, so that OnPaintItem can
      name a row's tier and OnCodeCompletion can find the word behind a row. The
      popup FILTERS BY MOVING ITS SELECTION rather than by removing rows, so an
      index into one is an index into the other for as long as the popup is up. }
    FCompletionItems: TCompletionItems;
    { What the user had typed when the popup opened, and where it began. The
      popup's own idea of the token uses SynEdit's identifier characters; this
      uses the highlighter's rule, which is the one that knows a suffix is part
      of the name. They agree today and this does not depend on it.

      FCompletionStart is a BYTE column into the line, which is what
      PrefixAtCaret measures and what TSynCompletion's ASourceStart wants. }
    FCompletionTyped: String;
    FCompletionStart: Integer;
    FCompletionLine: Integer;

    { THE SECOND CHILD, and the second execution model this program has.

      A REPL is not a run. A run is handed a FILE and ends; a REPL is handed
      nothing, keeps its variables between lines, and ends only when its input
      does. So it gets its own runner rather than sharing FRunner's slot, and
      the two are told apart by WHICH RUNNER IS BOUND TO WHICH HANDLERS --
      FRepl's events go to ReplOutput/ReplFinished/ReplFailed and never to the
      three the run path uses. Nothing downstream of FRunner learns a new
      question, and ActionList1Update's `Busy := FRunner.Running` is deliberately
      left alone so that Run stays available for the whole life of a prompt.

      FReplOpen mirrors FOutputOpen for the REPL's own transcript: the prompt
      arrives without a newline, and whatever comes next continues its line. }
    FRepl: TPhosphorRunner;
    FReplLive: Boolean;
    FReplOpen: Boolean;
    FReplOpenKind: TRunStream;
    { The window is closing, so a 40 ms tick that fires between the Kill in
      FormCloseQuery and FormDestroy must not touch a pane that is going away. }
    FReplClosing: Boolean;
    { Which host this REPL was started with. Changing it in Preferences ends the
      session, because a prompt that answers from a binary the settings no
      longer name is a prompt lying about what it is. }
    FReplHostPath: String;
    FReplHistory: TReplHistory;

    { The outline of the active buffer, what it was scanned from, and the
      debounce that keeps it from being rescanned between keystrokes.

      FOutlineRows is `line|path` per row, the same shape FProblemLines and
      FFindRows carry and read by the same six lines. THE PATH IS THE POINT: a
      row holds no TEditorDoc and no index into FDocs, so a pane that has not
      caught up with a tab change cannot send the caret into the wrong file --
      GotoSource simply finds no document of that name and does nothing. }
    FOutline: TOutlineFuncs;
    FOutlineTimer: TTimer;
    FOutlineRows: TStringList;
    { The list is being refilled, so the selection changes it makes are ours and
      not the user's. Without this, Items.Clear fires OnClick and the caret goes
      somewhere nobody asked it to go. }
    FOutlineFilling: Boolean;

    { The search, its cadence, and where each row points.

      FFindRows is `line|path` per row, exactly the shape FProblemLines uses and
      for the same reason: a list box holds the text a person reads, and the
      thing a double-click needs is not in it. Parallel to ListFind by index. }
    FFind: TFindSearch;
    FFindTimer: TTimer;
    FFindRows: TStringList;

    { The signature hint. A THintWindow rather than a second TSynCompletion:
      nothing is being chosen here, so a list that takes the keyboard would be
      in the way of the typing it is meant to help. It follows the caret and
      disappears when the call closes, which is the only dismissal it needs. }
    FSigHint: THintWindow;
    { What the hint currently says, so that moving along one argument does not
      redraw an identical window on every keystroke. }
    FSigShown: String;

    { An edit moved the breakpoint set and the gutter has not caught up yet.
      See DocBreakpointsChanged for why it cannot catch up immediately. }
    FMarksDirty: Boolean;

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
    procedure SyncGutterMarks(ADoc: TEditorDoc);
    procedure DocBreakpointsChanged(Sender: TObject; AFromEdit: Boolean);
    procedure DocFoldsChanged(Sender: TObject);
    function CompletionTier: TPhosphorTier;
    procedure CompletionAccepted(var AValue: String; ASourceValue: String;
      var ASourceStart, ASourceEnd: TPoint; AKeyChar: TUTF8Char;
      AShift: TShiftState);
    function CompletionPaintItem(const AKey: String; ACanvas: TCanvas;
      AX, AY: Integer; ASelected: Boolean; AIndex: Integer): Boolean;
    procedure RefreshSignatureHint;
    procedure HideSignatureHint;
    procedure StartRepl;
    procedure EndRepl(const AWhy: String; AForce: Boolean);
    procedure SendReplLine;
    procedure AddReplText(AKind: TRunStream; const AText: String;
      ACompleteLine: Boolean);
    procedure AddReplNote(const AText: String);
    procedure TrimRepl;
    procedure ReplOutput(Sender: TObject; AKind: TRunStream; const AText: String;
      ACompleteLine: Boolean);
    procedure ReplFinished(Sender: TObject; AExitCode: Integer; AKilled: Boolean);
    procedure ReplFailed(Sender: TObject; const AReason: String);
    procedure ScheduleOutline;
    procedure OutlineTimerTick(Sender: TObject);
    procedure RebuildOutline;
    procedure SyncOutlineSelection;
    procedure JumpToOutlineRow(AIndex: Integer; AFocus: Boolean);
    procedure FindTimerTick(Sender: TObject);
    procedure FindHits(Sender: TObject; const AHits: TFindHits);
    procedure FindDone(Sender: TObject; AFilesSeen, AHitCount: Integer;
      ACancelled: Boolean; const AError: String);
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
    procedure DebugStack(Sender: TObject; const AFrames: TPdbpFrames);
    procedure ClearStack;
    function FrameName(AIndex: Integer): String;
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
    procedure GotoSource(const APath: String; ALine: Integer;
      AColumn: Integer = 1; AFocus: Boolean = True);

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

    { WHAT --SELFTEST ASKS ABOUT, and nothing else reads either of them. Folding
      is turned on by a CLASS TEST on the highlighter and by nothing else, so a
      highlighter that quietly stopped being a fold one would fold nothing with
      no error anywhere; and the fold column is one of the five gutter parts
      SynEdit creates by default, so a gutter that lost a part is the same class
      of silent defect as a status bar with no panels. }
    function Highlighter: TSynCustomHighlighter;
    function GutterPartCount: Integer;

    { AND WHAT --MEASURE-TYPING NEEDS, which is the editor a keystroke would
      arrive at. It is handed out rather than driven from in here because the
      measurement is not a feature of this window: it exists to time the path
      SynEdit takes, and the less of this unit sits between the two the fewer
      things the number could be about. }
    function ActiveEditor: TSynEdit;
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.lfm}

uses
  LCLIntf, LazFileUtils, uaboutform, upreferencesform;

type
  { A breakpoint's mark in the gutter, and OURS.

    A subclass with nothing in it, because the only question ever asked of it is
    "did this window put this here": SynEdit's mark list is shared -- bookmarks
    land in it too, and anything added later will -- and rebuilding the set by
    clearing every mark would quietly delete somebody else's. `is` answers that
    question and a flag on a shared base class would not. }
  TPhosphorBreakMark = class(TSynEditMark)
  end;

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
  { THE ICONS ARE DECODED, NOT STREAMED. ImagesToolbar is empty in the .lfm on
    purpose -- a TImageList streams its pictures as one binary blob, and a blob
    in a form file people edit by hand cannot be reviewed or diffed. The list is
    filled from uphosphoricons, which tools/gen-icons.py writes, with BOTH
    resolutions registered; the buttons' ImageIndex values are already streamed
    and point at slots that exist by the time anything paints.

    First, so that nothing drawn before this has an empty list to draw from. }
  InstallToolbarIcons(ImagesToolbar);
  InstallGutterMarks(ImagesGutter);

  { THE POPUP IS OURS TO OPEN. TSynCompletion can bind its own shortcut, and it
    is left unbound on purpose: the trigger is an ACTION, so it appears in the
    Edit menu with its key beside it, and so that the one rule the popup cannot
    know -- do not offer anything inside a string or a comment -- is asked
    before anything appears rather than after. }
  FCompletion := TSynCompletion.Create(Self);
  FCompletion.ShortCut := 0;
  FCompletion.OnCodeCompletion := @CompletionAccepted;
  FCompletion.OnPaintItem := @CompletionPaintItem;
  { On the FORM, not on the plugin: the plugin's property of the same name is
    deprecated, and this project treats a hint as a defect until proven
    cosmetic. The form exists from the constructor (syncompletion.pas:1397). }
  FCompletion.TheForm.NbLinesInWindow := 12;

  FSigHint := THintWindow.Create(Self);
  FSigHint.AutoHide := False;

  { NOT STARTED HERE. A child the user did not ask for is a child holding a
    lock on phosphor.exe that they cannot explain, and Phosphor's own rules
    record that a REPL nobody closes never exits. It starts on ActRepl and on
    nothing else. }
  FRepl := TPhosphorRunner.Create(Self);
  FRepl.OnOutput := @ReplOutput;
  FRepl.OnFinished := @ReplFinished;
  FRepl.OnStartFailed := @ReplFailed;
  FReplHistory := TReplHistory.Create;
  FReplLive := False;
  FReplClosing := False;

  FOutlineRows := TStringList.Create;
  { 250 ms, and NOT the 40 ms this program uses everywhere else. That one is a
    DRAIN cadence for things arriving from outside -- a pipe, a socket, a walker
    thread -- and it is one number with one reason. This is a DEBOUNCE on the
    user's own typing, which is a different quantity: rescanning between the
    keystrokes of a fast typist makes the list flicker and the selection jump,
    and on gtk2 that reads as the editor struggling. }
  FOutlineTimer := TTimer.Create(Self);
  FOutlineTimer.Enabled := False;
  FOutlineTimer.Interval := 250;
  FOutlineTimer.OnTimer := @OutlineTimerTick;

  FFindRows := TStringList.Create;
  FFind := TFindSearch.Create;
  FFind.OnHits := @FindHits;
  FFind.OnDone := @FindDone;
  { The same 40 ms the runner and the debug session use. It is not a number with
    a reason of its own -- it is the one cadence this program has, and a second
    would be a second thing to explain. }
  FFindTimer := TTimer.Create(Self);
  FFindTimer.Enabled := False;
  FFindTimer.Interval := 40;
  FFindTimer.OnTimer := @FindTimerTick;

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
  FDebug.OnStackTrace := @DebugStack;

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
  { The search FIRST, because its destructor joins the walker thread and that
    thread deposits into a buffer this object owns. Freeing the rows out from
    under a thread that is still walking is the one ordering mistake available
    here, and closing a window during a search is how it would be found. }
  FReplClosing := True;
  if (FRepl <> nil) and FRepl.Running then
    FRepl.Kill;
  FReplHistory.Free;
  if FOutlineTimer <> nil then
    FOutlineTimer.Enabled := False;
  FOutlineRows.Free;
  if FFindTimer <> nil then
    FFindTimer.Enabled := False;
  FFind.Free;
  FFindRows.Free;
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
  Busy: String;
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

  { ONE QUESTION FOR BOTH CHILDREN, asked before either is touched. The rule
    above is that nothing is ended until everything has agreed to end, and with
    two children it is easy to break by accident: killing the run and then
    asking about the REPL leaves somebody who answers No with their program
    already dead. }
  Busy := '';
  if FRunner.Running and FReplLive then
    Busy := Format('%s and the REPL are still running. Stop them and close?',
                   [FRunLabel])
  else if FRunner.Running then
    Busy := Format('%s is still running. Stop it and close?', [FRunLabel])
  else if FReplLive then
    Busy := 'The REPL is still running. Stop it and close?';

  if Busy <> '' then
  begin
    if MessageDlg('PhosphorIDE', Busy, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    begin
      CanClose := False;
      Exit;
    end;
    { THE REPL FIRST. FRunner may be a debuggee, and RunnerFinished's tail polls
      the debug session and empties the stack and variables panes; the longer
      teardown goes last and undisturbed. Kill and not CloseInput: a close path
      may not wait for a child to notice end-of-input, and the user has already
      said end it. }
    FReplClosing := True;
    if FReplLive then
      FRepl.Kill;
    if FRunner.Running then
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
  { WHERE THE GUTTER GETS ITS PICTURES. SynEdit draws a TSynEditMark from
    BookMarkOptions.BookmarkImages unless the mark names a list of its own, and
    without one it falls back to its built-in bookmark glyphs -- which are the
    numbered bookmarks 0..9, not anything this program means. }
  Result.Edit.BookMarkOptions.BookmarkImages := ImagesGutter;
  { One popup, every tab. }
  FCompletion.AddEditor(Result.Edit);
  { AND THE GUTTER FOLLOWS THE SET, WHATEVER MOVED IT. Subscribed rather than
    called after each toggle, because the case that needs it is the one nobody
    calls: typing above a breakpoint moves it, and a mark left on the old line
    is the defect TrackEdit exists to prevent, one layer out. }
  Result.OnBreakpointsChanged := @DocBreakpointsChanged;
  { A FOLD OPENING OR CLOSING CHANGES WHICH MARKS CAN BE DRAWN and changes
    nothing else, so it gets its own handler rather than a flag on the
    breakpoint one: there is no edit to wait for and nothing to defer. }
  Result.OnFoldsChanged := @DocFoldsChanged;
  ApplyEditorSettings(Result);

  PagesEditors.ActivePage := Page;
  RefreshTabCaption(Result);
  FocusEditor(Result);
  { EXPLICIT, and not left to PagesEditorsChange. A TPageControl fires OnChange
    for a PROGRAMMATIC ActivePage change on some widgetsets and not others, and
    LoadFromFile above runs BEFORE Edit.OnChange is assigned, so opening a file
    fires no EditorChange either. Neither of those may be the thing correctness
    rests on. }
  RebuildOutline;
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
  RebuildOutline;
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
      { The same reason as the one at the end of NewDoc, which this path never
        reaches: the tab changed programmatically. }
      RebuildOutline;
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
  { SAVE AS CHANGES THE DOCUMENT'S NAME AND NOT A CHARACTER OF ITS TEXT, so it
    fires no EditorChange and arms no debounce -- and every row in the pane is
    still pointing at a path this document no longer has. The rows would then
    match no open document and every click would be a silent no-op. }
  RebuildOutline;
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
  { AND THIS ONE STILL SWITCHES, even with the REPL on screen. Run is something
    the user just asked for, like Find in Files or the Outline, and every one of
    those brings its own pane forward; refusing to would be the one explicit
    action in the program that answers somewhere you cannot see. The switch that
    must NOT happen is the AUTOMATIC one in RunnerFinished. }
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
  else if (ListProblems.Items.Count > 0) and (PagesOutput.ActivePage <> TabRepl) then
    { NOT OVER THE REPL. This switch is the editor's own idea rather than the
      user's -- a run failed, so the diagnostics are probably what they want --
      and taking the pane away from somebody mid-sentence at a prompt is a
      guess that costs them their place. The Problems tab is one click away and
      the status bar already says the run failed. }
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

procedure TFrmMain.GotoSource(const APath: String; ALine: Integer;
  AColumn: Integer; AFocus: Boolean);
var
  I, Line: Integer;
  Doc, Was: TEditorDoc;
begin
  { WHICH DOCUMENT WAS ACTIVE BEFORE, because this is the one place in the
    program that changes it without the user touching a tab. }
  Was := ActiveDoc;
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

  { The column is 1 for everything that came from a diagnostic -- the host never
    reports one -- and the NAME's column for a jump that came from the outline,
    where two definitions can share a line (`function a() ... : function b() ...`
    is one legal line) and column 1 would be the wrong one of them. }
  if AColumn < 1 then
    AColumn := 1;
  { LOGICALCARETXY AND NOT CARETXY, for the third time in this file and the same
    reason: CaretXY is FCaret.LineCharPos, a DISPLAY position, and AColumn came
    from a scan over BYTES. They agree on column 1, which is what every caller
    but the outline passes -- and the outline's column is measured in an editor
    where a line may hold an accent, which is where they stop agreeing. }
  Doc.Edit.LogicalCaretXY := Point(AColumn, Line);
  Doc.Edit.EnsureCursorPosVisible;
  { AND THE FOCUS IS THE CALLER'S DECISION. A double-click in a results list is
    "take me there"; a single click in the outline is "show me", and moving the
    keyboard out of the list after one click makes the list unusable by arrow
    key -- which is how an outline is actually read. }
  if AFocus then
    FocusEditor(Doc);
  RefreshStatus;

  { AND THE OUTLINE FOLLOWS THE FILE, not the tab strip. A jump from the
    Problems pane, the Find pane or F12 into ANOTHER file switches the active
    page programmatically, and TPageControl fires OnChange for that on some
    widgetsets and not others -- so without this the pane would keep describing
    the file just left, and clicking one of its rows would jump back into it.

    Only when the document actually changed: the outline's own rows call this,
    and rebuilding there would clear the list and the selection out from under
    somebody walking it with the arrow keys. }
  if Doc <> Was then
    RebuildOutline;
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

function TFrmMain.CompletionTier: TPhosphorTier;
begin
  { The setting is an ordinal so that uphosphorsettings needs nothing from
    uphosphorlang; this is the one place that turns it back into the type. }
  case FSettings.CompletionTier of
    0: Result := ptCore;
    1: Result := ptPackage;
  else
    Result := ptGui;
  end;
end;

procedure TFrmMain.ActCompleteExecute(Sender: TObject);
var
  Doc: TEditorDoc;
  Line: String;
  I: Integer;
  P: TPoint;
begin
  Doc := ActiveDoc;
  if (Doc = nil) or (Doc.Edit = nil) then
    Exit;

  Line := Doc.Edit.LineText;
  { NOT INSIDE A STRING OR A COMMENT, and said out loud rather than ignored. A
    shortcut that silently does nothing is indistinguishable from one that is
    broken, and this is the only place in the editor where the right answer to a
    keypress is "no list". }
  { LOGICALCARETXY.X AND NOT CARETX. Both are "the caret's column" and they are
    not the same number: CaretX is FCaret.CharPos, which
    syneditpointclasses.pas:823 computes as LogicalToPhysical -- a DISPLAY
    column, with a tab counted out to its tab stop and a two-byte letter counted
    as one. LineText is the line's BYTES. Pairing them indexes a byte string
    with a display column, and the two agree only while the line is pure ASCII
    with no tabs.

    That is not an exotic input here: `x = "ola" : pri` with an accent in the
    string is a Portuguese comment or literal ahead of the caret, and it is what
    the person who wrote this editor types all day. LogicalCaretXY is
    FCaret.LineBytePos (synedit.pp:2935), which is the index this whole chain
    wants -- PrefixAtCaret measures a byte range, and TSynCompletion's
    ASourceStart/ASourceEnd are logical points too. Measured and corrected on
    2026-09-16; it had been latent since completion landed. }
  if InLiteralOrComment(Line, Doc.Edit.LogicalCaretXY.X) then
  begin
    StatusBar1.Panels[3].Text := 'no completion inside a string or a comment';
    Exit;
  end;

  FCompletionTyped := PrefixAtCaret(Line, Doc.Edit.LogicalCaretXY.X,
                                    FCompletionStart);
  FCompletionLine := Doc.Edit.CaretY;
  FCompletionItems := CompletionCandidates(FCompletionTyped, CompletionTier);
  if Length(FCompletionItems) = 0 then
  begin
    StatusBar1.Panels[3].Text :=
      Format('nothing this host knows begins with %s', [FCompletionTyped]);
    Exit;
  end;

  FCompletion.ItemList.BeginUpdate;
  try
    FCompletion.ItemList.Clear;
    for I := 0 to High(FCompletionItems) do
      FCompletion.ItemList.Add(FCompletionItems[I].Word);
  finally
    FCompletion.ItemList.EndUpdate;
  end;

  FCompletion.Editor := Doc.Edit;
  { Under the caret and one line down, so the popup does not cover the word
    being typed. }
  P := Doc.Edit.ClientToScreen(
    Point(Doc.Edit.CaretXPix, Doc.Edit.CaretYPix + Doc.Edit.LineHeight));
  FCompletion.Execute(FCompletionTyped, P.X, P.Y);
end;

procedure TFrmMain.CompletionAccepted(var AValue: String;
  ASourceValue: String; var ASourceStart, ASourceEnd: TPoint;
  AKeyChar: TUTF8Char; AShift: TShiftState);
begin
  { THE RANGE IS OURS, NOT THE POPUP'S. TSynCompletion works out what to replace
    from SynEdit's identifier characters; this replaces exactly what
    PrefixAtCaret measured, by the highlighter's rule. They agree today -- the
    highlighter publishes the suffixes through GetIdentChars -- and a completion
    that quietly depends on two scanners agreeing is one bad day from writing
    `left$$`. }
  if (FCompletionLine > 0) and (FCompletionStart > 0) then
  begin
    ASourceStart := Point(FCompletionStart, FCompletionLine);
    ASourceEnd := Point(FCompletionStart + Length(FCompletionTyped),
                        FCompletionLine);
  end;
  AValue := CompletionInsertion(FCompletionTyped, AValue);
end;

function TFrmMain.CompletionPaintItem(const AKey: String; ACanvas: TCanvas;
  AX, AY: Integer; ASelected: Boolean; AIndex: Integer): Boolean;
var
  Badge: String;
  W: Integer;
begin
  Result := True;
  ACanvas.TextOut(AX + 2, AY, AKey);
  if (AIndex < 0) or (AIndex > High(FCompletionItems)) then
    Exit;

  { THE TIER, ON EVERY ROW. Core is always there; a package name runs only where
    the host linked the package and a GUI name only where a graphical session was
    reachable when the program started. A list that does not say which is a list
    that recommends `form@` as confidently as `println`. }
  Badge := CompletionKindName(FCompletionItems[AIndex].Kind);
  W := ACanvas.TextWidth(Badge);
  if not ASelected then
    ACanvas.Font.Color := clGray;
  ACanvas.TextOut(FCompletion.TheForm.ClientWidth - W - 8, AY, Badge);
end;

{ ------------------------------------------------------- find in files ----- }

procedure TFrmMain.ActFindInFilesExecute(Sender: TObject);
var
  Doc: TEditorDoc;
begin
  PagesOutput.ActivePage := TabFind;

  { A ROOT THAT IS ALREADY THE RIGHT ONE, nine times in ten: the directory of
    the file being edited. Filled only when the box is empty, because a root the
    user typed is a choice and this is a guess. }
  if Trim(EditFindRoot.Text) = '' then
  begin
    Doc := ActiveDoc;
    if (Doc <> nil) and (Doc.FileName <> '') then
      EditFindRoot.Text := ExtractFileDir(Doc.FileName);
  end;

  { And the selection, for the same reason Find does it (ActFindExecute) -- but
    only a selection that is one line, because a search for three lines of text
    is a search that finds nothing and does not say why. }
  Doc := ActiveDoc;
  if (Doc <> nil) and Doc.Edit.SelAvail and
     (Pos(LineEnding, Doc.Edit.SelText) = 0) then
    EditFindWhat.Text := Doc.Edit.SelText;

  EditFindWhat.SetFocus;
  EditFindWhat.SelectAll;
end;

procedure TFrmMain.BtnFindBrowseClick(Sender: TObject);
begin
  if DirectoryExistsUTF8(EditFindRoot.Text) then
    SelectDirectoryDialog1.InitialDir := EditFindRoot.Text;
  if SelectDirectoryDialog1.Execute then
    EditFindRoot.Text := SelectDirectoryDialog1.FileName;
end;

procedure TFrmMain.EditFindWhatKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  { Enter searches, because a box with a Search button beside it that ignores
    Enter is a box people press Enter in twice. }
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    BtnFindGoClick(nil);
  end;
end;

procedure TFrmMain.BtnFindGoClick(Sender: TObject);
begin
  ListFind.Items.Clear;
  FFindRows.Clear;

  if not FFind.Start(EditFindWhat.Text, EditFindRoot.Text,
                     EditFindMask.Text, ChkFindCase.Checked) then
  begin
    { Start answers False for the two things a person can type wrongly, and says
      which rather than opening a dialog over a pane they are looking at. }
    if Trim(EditFindWhat.Text) = '' then
      ListFind.Items.Add('Nothing to look for.')
    else
      ListFind.Items.Add(Format('%s is not a directory.', [EditFindRoot.Text]));
    Exit;
  end;

  FFindTimer.Enabled := True;
  BtnFindGo.Enabled := False;
  BtnFindStop.Enabled := True;
  StatusBar1.Panels[3].Text := 'searching...';
end;

procedure TFrmMain.BtnFindStopClick(Sender: TObject);
begin
  { Stop joins the walker and then Poll delivers the ending, so the button does
    not have to know what a cancellation looks like. }
  FFind.Stop;
  FFind.Poll;
end;

procedure TFrmMain.FindTimerTick(Sender: TObject);
begin
  FFind.Poll;
end;

procedure TFrmMain.FindHits(Sender: TObject; const AHits: TFindHits);
var
  I: Integer;
begin
  ListFind.Items.BeginUpdate;
  try
    for I := 0 to High(AHits) do
    begin
      { WHAT THE EYE READS AND WHAT THE DOUBLE-CLICK NEEDS ARE DIFFERENT THINGS.
        The row shows a leaf name and the line; the full path rides in
        FFindRows, because a list box full of absolute paths is a list box
        nobody can read at a glance. }
      ListFind.Items.Add(Format('%s:%d: %s',
        [ExtractFileName(AHits[I].Path), AHits[I].Line, AHits[I].Text]));
      FFindRows.Add(Format('%d|%s', [AHits[I].Line, AHits[I].Path]));
    end;
  finally
    ListFind.Items.EndUpdate;
  end;
end;

procedure TFrmMain.FindDone(Sender: TObject; AFilesSeen, AHitCount: Integer;
  ACancelled: Boolean; const AError: String);
var
  What: String;

  { "1 matches in 1 files" is how a program announces that nobody read its
    output. Four lines, once, rather than a Format per sentence. }
  function Countable(ACount: Integer; const ASingular, APlural: String): String;
  begin
    if ACount = 1 then
      Result := Format('%d %s', [ACount, ASingular])
    else
      Result := Format('%d %s', [ACount, APlural]);
  end;

begin
  FFindTimer.Enabled := False;
  BtnFindGo.Enabled := True;
  BtnFindStop.Enabled := False;

  if AError <> '' then
    What := 'the search failed: ' + AError
  else if ACancelled then
    What := Format('stopped after %s, %s', [Countable(AFilesSeen, 'file', 'files'),
                                            Countable(AHitCount, 'match', 'matches')])
  else
    What := Format('%s in %s', [Countable(AHitCount, 'match', 'matches'),
                                Countable(AFilesSeen, 'file', 'files')]);
  StatusBar1.Panels[3].Text := What;
  { AND IN THE LIST TOO, because the status bar is at the other end of the
    window from the pane being read, and "no matches" is an answer that has to
    arrive somewhere the question was asked. }
  if (AHitCount = 0) or (AError <> '') or ACancelled then
    ListFind.Items.Add('-- ' + What);
end;

procedure TFrmMain.ListFindDblClick(Sender: TObject);
var
  Idx, Sep, Line, Code: Integer;
  Entry: String;
begin
  { THE SAME NAVIGATOR AS THE PROBLEMS PANE, deliberately: GotoSource is the one
    place that opens a file that is not open, finds the tab for one that is, and
    clamps a line past the end. A second one would be a second set of those. }
  Idx := ListFind.ItemIndex;
  if (Idx < 0) or (Idx >= FFindRows.Count) then
    Exit;
  Entry := FFindRows[Idx];
  Sep := Pos('|', Entry);
  if Sep < 1 then
    Exit;
  Val(Copy(Entry, 1, Sep - 1), Line, Code);
  if (Code <> 0) or (Line <= 0) then
    Exit;
  GotoSource(Copy(Entry, Sep + 1, MaxInt), Line);
end;

{ ----------------------------------------------------------------- REPL ---- }

procedure TFrmMain.ActReplExecute(Sender: TObject);
begin
  PagesOutput.ActivePage := TabRepl;
  if not FReplLive then
    StartRepl;
  if EditRepl.CanFocus then
    EditRepl.SetFocus;
end;

procedure TFrmMain.StartRepl;
var
  Doc: TEditorDoc;
  WorkDir: String;
begin
  if FReplLive then
    Exit;
  if not RequireHost then
    Exit;

  { NOT THROUGH StartHost. That method is FRunner's single spawn point and it
    carries FRunLabel, FRunPath, the armed pack and the clearing of the Problems
    pane -- none of which a REPL has. A bare `phosphor` with no arguments IS the
    REPL; there is no subcommand and, for the same reason, no --sandbox: the CLI
    contract attaches that flag to `phosphor [run] <file>`. }
  Doc := ActiveDoc;
  if (Doc <> nil) and (not Doc.IsUntitled) then
    WorkDir := ExtractFileDir(Doc.FileName)
  else
    WorkDir := '';

  MemoRepl.Lines.Clear;
  FReplOpen := False;
  FReplHistory.Clear;
  FReplHostPath := FHostPath;

  if not FRepl.Start(FHostPath, [], WorkDir) then
    Exit;                        { ReplFailed has already said why }
  FReplLive := True;
  RefreshStatus;
end;

procedure TFrmMain.EndRepl(const AWhy: String; AForce: Boolean);
begin
  if not FReplLive then
    Exit;
  if AWhy <> '' then
    AddReplNote('> ' + AWhy);

  { PRESS ONCE FOR END-OF-INPUT, PRESS AGAIN TO STOP IT. Closing stdin is how a
    REPL is meant to end -- it writes a newline and exits 0, measured -- and it
    is the polite ending: a block half-typed at the prompt is reported rather
    than discarded. But a child that is not reading its input will not notice,
    so InputOpen going False makes the second press mean something stronger.

    A forced end has no second press available: the window is closing, or the
    host changed under it. }
  if AForce or (not FRepl.InputOpen) then
  begin
    AddReplNote('> stopping it');
    FRepl.Kill;
  end
  else
  begin
    AddReplNote('> end of input');
    FRepl.CloseInput;
  end;
  RefreshStatus;
end;

procedure TFrmMain.SendReplLine;
var
  Line: String;
begin
  if not FReplLive then
  begin
    StatusBar1.Panels[3].Text := 'no REPL is running -- press Ctrl+Shift+R';
    Exit;
  end;
  Line := EditRepl.Text;

  { THE ECHO, AND IT CLOSES THE PROMPT'S LINE. The prompt arrived without a
    newline and the transcript left its line open, so the typed line belongs on
    the end of it -- which is what a terminal shows and what makes the record
    readable afterwards. Closing it matters: without that, the answer the child
    prints would be appended to the same line and `phosphor> println 6*742` is
    what somebody would read. }
  AddReplText(rsStdOut, Line, True);
  FReplHistory.Add(Line);
  FReplHistory.Reset;
  EditRepl.Text := '';
  FRepl.SendInput(Line);
end;

procedure TFrmMain.BtnReplSendClick(Sender: TObject);
begin
  SendReplLine;
end;

procedure TFrmMain.BtnReplEndClick(Sender: TObject);
begin
  EndRepl('', False);
end;

procedure TFrmMain.EditReplKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    SendReplLine;
    Exit;
  end;
  { UP AND DOWN WALK WHAT HAS BEEN TYPED, and the first Up stashes the
    half-typed line so Down brings it back -- see TReplHistory. A one-line edit
    has nothing else to do with these two keys. }
  if (Key = VK_UP) and (Shift = []) then
  begin
    Key := 0;
    EditRepl.Text := FReplHistory.Older(EditRepl.Text);
    EditRepl.SelStart := Length(EditRepl.Text);
    Exit;
  end;
  if (Key = VK_DOWN) and (Shift = []) then
  begin
    Key := 0;
    EditRepl.Text := FReplHistory.Newer;
    EditRepl.SelStart := Length(EditRepl.Text);
  end;
end;

procedure TFrmMain.AddReplText(AKind: TRunStream; const AText: String;
  ACompleteLine: Boolean);
var
  Last: Integer;
begin
  if FReplClosing then
    Exit;
  Last := MemoRepl.Lines.Count - 1;
  { The same rule AppendOutput follows, on the REPL's own transcript: an open
    line is continued, and only a complete one closes it. The prompt is the
    reason the rule exists here at all. }
  if FReplOpen and (FReplOpenKind = AKind) and (Last >= 0) then
    MemoRepl.Lines[Last] := MemoRepl.Lines[Last] + AText
  else
    MemoRepl.Lines.Add(AText);

  FReplOpen := not ACompleteLine;
  FReplOpenKind := AKind;
  TrimRepl;
end;

procedure TFrmMain.AddReplNote(const AText: String);
begin
  { A note is the EDITOR speaking, not the child, so it always starts its own
    line and never continues the child's. }
  if FReplClosing then
    Exit;
  FReplOpen := False;
  MemoRepl.Lines.Add(AText);
  TrimRepl;
end;

procedure TFrmMain.TrimRepl;
begin
  { MaxReplLines, for the reason MaxOutputLines exists: a program printing
    without end must not make the editor its memory problem. The oldest go
    first, and the caret is left alone -- see ScrollOutputToEnd for what reading
    SelStart on a long memo costs. }
  while MemoRepl.Lines.Count > MaxReplLines do
    MemoRepl.Lines.Delete(0);
  if MemoRepl.Lines.Count > 0 then
    MemoRepl.SelStart := MemoRepl.GetTextLen;
end;

procedure TFrmMain.ReplOutput(Sender: TObject; AKind: TRunStream;
  const AText: String; ACompleteLine: Boolean);
var
  Segs: TReplSegments;
  I: Integer;
begin
  if FReplClosing then
    Exit;

  { A LINE THAT PRINTED NOTHING PUTS TWO PROMPTS TOGETHER, and a block puts a
    prompt and its continuations together -- both measured. Split them so each
    one starts its own line and the transcript reads the way the session
    happened rather than the way the bytes arrived.

    Only on stdout: a prompt is never written to stderr, and running the splitter
    over a diagnostic would be looking for something that cannot be there. }
  if AKind = rsStdOut then
  begin
    Segs := SplitReplPrompts(AText);
    if Length(Segs) > 1 then
    begin
      for I := 0 to High(Segs) do
        AddReplText(AKind, Segs[I].Text,
                    (I < High(Segs)) or ACompleteLine);
      Exit;
    end;
  end;

  AddReplText(AKind, AText, ACompleteLine);
end;

procedure TFrmMain.ReplFinished(Sender: TObject; AExitCode: Integer;
  AKilled: Boolean);
begin
  FReplLive := False;
  if FReplClosing or (csDestroying in ComponentState) then
    Exit;
  FReplOpen := False;
  if AKilled then
    AddReplNote('> the REPL was stopped')
  else
    AddReplNote(Format('> the REPL ended, exit code %d', [AExitCode]));
  RefreshStatus;
end;

procedure TFrmMain.ReplFailed(Sender: TObject; const AReason: String);
begin
  FReplLive := False;
  if FReplClosing then
    Exit;
  AddReplNote('> could not start the REPL: ' + AReason);
  StatusBar1.Panels[3].Text := 'the REPL could not start';
end;

{ ------------------------------------------------------------ the outline --- }

procedure TFrmMain.ScheduleOutline;
begin
  { ENABLED := TRUE ON A TIMER THAT IS ALREADY RUNNING DOES NOTHING.
    TCustomTimer.SetEnabled is guarded by `if Value <> FEnabled`, so re-arming
    has to stop the OS timer and start a new one -- otherwise this is not a
    debounce at all, it is a 250 ms metronome that fires in the middle of
    typing, which is the very thing it exists to prevent. }
  FOutlineTimer.Enabled := False;
  FOutlineTimer.Enabled := True;
end;

procedure TFrmMain.OutlineTimerTick(Sender: TObject);
begin
  FOutlineTimer.Enabled := False;   { one shot, not a heartbeat }
  RebuildOutline;
end;

procedure TFrmMain.RebuildOutline;
var
  Doc: TEditorDoc;
  I: Integer;
  Row, Path: String;
begin
  FOutlineTimer.Enabled := False;
  Doc := ActiveDoc;
  if Doc = nil then
  begin
    FOutline := nil;
    Path := '';
  end
  else
  begin
    { THE BUFFER AND NOT THE FILE ON DISK. The outline exists to describe what is
      being typed, and the file on disk is a version of it that stopped being
      true at the first keystroke. }
    FOutline := ScanOutline(Doc.Edit.Lines);
    Path := Doc.FullDisplayName;
  end;

  { THE LIST AND ITS ROWS ARE CLEARED AND FILLED TOGETHER, ALWAYS, and while the
    flag is up: Items.Clear changes the selection, a selection change is a click
    on some widgetsets, and a click here moves somebody's caret. }
  FOutlineFilling := True;
  ListOutline.Items.BeginUpdate;
  try
    ListOutline.Items.Clear;
    FOutlineRows.Clear;
    for I := 0 to High(FOutline) do
    begin
      Row := Format('%d: %s', [FOutline[I].Line, OutlineRowText(FOutline[I])]);
      { Three things the pane knows that the build does not say, or does not say
        yet. An unterminated definition is what every function looks like while
        it is being written, so it is a note and not a complaint. }
      if FOutline[I].EndLine = 0 then
        Row := Row + '   (no endfunction yet)';
      if FOutline[I].Nested then
        Row := Row + '   (nested -- the host refuses this)';
      { AND THE ANNOTATION IS COMPUTED WITH THE LOOKUP F12 USES. A second
        definition of one name at one arity is unreachable -- the host takes the
        first -- and if these two ever disagreed the pane would say so.

        AN UNKNOWN ARITY IS NOT A COLLIDING ONE. A header whose parameter list
        has not been closed yet reports -1, FindOutlineFunc reads a negative
        count as "any arity" and so answers the FIRST definition of the name --
        which would accuse a line the user is still typing of shadowing one they
        finished. }
      if (FOutline[I].ParamCount >= 0) and
         (FindOutlineFunc(FOutline, FOutline[I].Name, FOutline[I].ParamCount) <> I) then
        Row := Row + '   (unreachable -- the first of this arity wins)';
      ListOutline.Items.Add(Row);
      FOutlineRows.Add(Format('%d|%s', [FOutline[I].Line, Path]));
    end;
    if Length(FOutline) = 0 then
    begin
      { A row that says so, with a line number the jump refuses -- the exact
        trick FProblemLines uses for a diagnostic that carries no location, so
        the two arrays can never fall out of step. "None" is an answer, and it
        has to arrive where the question was asked. }
      ListOutline.Items.Add('-- no function definitions in this buffer');
      FOutlineRows.Add('0|');
    end;
  finally
    ListOutline.Items.EndUpdate;
    FOutlineFilling := False;
  end;
  SyncOutlineSelection;
end;

procedure TFrmMain.SyncOutlineSelection;
var
  Doc: TEditorDoc;
  Idx: Integer;
begin
  Doc := ActiveDoc;
  if (Doc = nil) or (Length(FOutline) = 0) then
    Exit;
  Idx := FuncAtLine(FOutline, Doc.Edit.CaretY);
  if Idx >= ListOutline.Items.Count then
    Exit;
  if ListOutline.ItemIndex = Idx then
    Exit;
  { Assigning ItemIndex is a selection change, and a selection change is a click
    on some widgetsets. This one is the program's, not the user's. }
  FOutlineFilling := True;
  try
    ListOutline.ItemIndex := Idx;
  finally
    FOutlineFilling := False;
  end;
end;

procedure TFrmMain.JumpToOutlineRow(AIndex: Integer; AFocus: Boolean);
var
  Sep, Line, Code, Col: Integer;
  Entry: String;
begin
  if (AIndex < 0) or (AIndex >= FOutlineRows.Count) then
    Exit;
  Entry := FOutlineRows[AIndex];
  Sep := Pos('|', Entry);
  if Sep < 1 then
    Exit;
  Val(Copy(Entry, 1, Sep - 1), Line, Code);
  if (Code <> 0) or (Line <= 0) then
    Exit;
  { THE NAME'S COLUMN AND NOT COLUMN 1, because two definitions can share a line
    -- `function a() ... : function b() ...` is one legal line, measured -- and
    column 1 would be the wrong one of them for every row but the first. }
  Col := 1;
  if AIndex <= High(FOutline) then
    Col := FOutline[AIndex].Column;
  GotoSource(Copy(Entry, Sep + 1, MaxInt), Line, Col, AFocus);
end;

procedure TFrmMain.ListOutlineClick(Sender: TObject);
begin
  if FOutlineFilling then
    Exit;
  { A SINGLE CLICK MOVES THE CARET AND LEAVES THE KEYBOARD IN THE LIST. The
    roadmap asks for "clicking one moves the caret", and it is also how an
    outline is actually read -- arrowing down the list walks the file. Taking
    the focus on the first click would send the second arrow key into the text. }
  JumpToOutlineRow(ListOutline.ItemIndex, False);
end;

procedure TFrmMain.ListOutlineDblClick(Sender: TObject);
begin
  { And a double-click is "I have arrived": the same thing the Problems and Find
    panes do, and the way back to the text without reaching for the mouse. }
  JumpToOutlineRow(ListOutline.ItemIndex, True);
end;

procedure TFrmMain.ActOutlineExecute(Sender: TObject);
begin
  RebuildOutline;
  PagesOutput.ActivePage := TabOutline;
  if ListOutline.CanFocus then
    ListOutline.SetFocus;
end;

procedure TFrmMain.ActGotoDefinitionExecute(Sender: TObject);
var
  Doc: TEditorDoc;
  Funcs: TOutlineFuncs;
  Line, Nm, Extra, TierName: String;
  Col, Start, Idx, Args, Defined, I, Enclosing: Integer;
  Tier: TPhosphorTier;
begin
  Doc := ActiveDoc;
  if Doc = nil then
    Exit;

  Line := Doc.Edit.LineText;
  { The BYTE column, because LineText is bytes. See ActCompleteExecute. }
  Col := Doc.Edit.LogicalCaretXY.X;

  if InLiteralOrComment(Line, Col) then
  begin
    StatusBar1.Panels[3].Text := 'nothing to go to inside a string or a comment';
    Exit;
  end;

  Nm := WordAtCaret(Line, Col, Start);
  if Nm = '' then
  begin
    StatusBar1.Panels[3].Text := 'no name under the caret';
    Exit;
  end;

  { SCANNED FRESH, EVERY PRESS, and deliberately not read out of the pane. The
    pane's copy is up to one debounce old, and a jump a quarter of a second
    stale lands a few lines off while looking exactly like a jump that is right.
    One keypress, one pass over the buffer. }
  Funcs := ScanOutline(Doc.Edit.Lines);

  { IS THE CARET ON THE DEFINITION ITSELF? Answering "no definition found" with
    the caret sitting on the name in `function pick()` is how somebody decides
    the key is broken. }
  for I := 0 to High(Funcs) do
    if (Funcs[I].Line = Doc.Edit.CaretY) and (Funcs[I].Column = Start) then
    begin
      StatusBar1.Panels[3].Text :=
        Format('this is the definition of %s', [Funcs[I].Display]);
      Exit;
    end;

  { HOW MANY ARGUMENTS THIS CALL SITE PASSES, because the host resolves a call
    by name AND count: with `function len(a, b)` in the file, `len("abcd")` runs
    the BUILT-IN and prints 4. Measured. -1 means the site does not say, and
    then any arity will do. }
  Args := CallArgCount(Line, Start + Length(Nm));

  { A NAME THAT IS NOT A CALL AND IS THIS FUNCTION'S OWN PARAMETER IS A
    VARIABLE, whatever else the file defines. `function g(n)` with a
    `function n()` further down is legal, and inside g the word `n` is the
    parameter -- so jumping to `function n()` would be a confident wrong answer
    about the one thing this action exists to be right about.

    Only when it is NOT a call: a parameter shadows a name as a VALUE, and a
    call is resolved against the function tables and never against the locals,
    so `len(s)` inside a function whose parameter is called `len` still reaches
    the built-in. }
  Enclosing := FuncAtLine(Funcs, Doc.Edit.CaretY);
  if (Args < 0) and (Enclosing >= 0) and
     IsParamOrLocal(Funcs[Enclosing], Nm) then
  begin
    StatusBar1.Panels[3].Text := Format('%s is a name inside %s, not a function',
      [Nm, Funcs[Enclosing].Display]);
    Exit;
  end;

  Idx := FindOutlineFunc(Funcs, Nm, Args);
  if Idx >= 0 then
  begin
    GotoSource(Doc.FullDisplayName, Funcs[Idx].Line, Funcs[Idx].Column);
    StatusBar1.Panels[3].Text := Format('%s is defined on line %d',
      [Funcs[Idx].Display, Funcs[Idx].Line]);
    Exit;
  end;

  Defined := CountOutlineFunc(Funcs, Nm);

  { THE KEYWORD TEST COMES FIRST because a few words are both. `error` is a
    statement word (`on error ...`) and a registered built-in, and at a statement
    position it is the statement -- so offering a function reference for it would
    be answering about the wrong one of the two. }
  if IsPhosphorKeyword(Nm) or IsPhosphorOperatorWord(Nm) or
     IsPhosphorLiteralWord(Nm) then
  begin
    { And it may still have been a function name -- Phosphor has no keyword
      table, so `function if(a)` is legal and would have been found above.
      Reaching here means nobody defined one. }
    StatusBar1.Panels[3].Text :=
      Format('%s is a keyword here, not a function', [Nm]);
    Exit;
  end;

  if PhosphorBuiltinTier(Nm, Tier) then
  begin
    case Tier of
      ptCore: TierName := 'core';
      ptPackage: TierName := 'package';
    else
      TierName := 'GUI';
    end;
    Extra := '';
    if Defined > 0 then
      Extra := Format(' -- the %s in this file takes %s', [Nm, OutlineArities(Funcs, Nm)]);
    StatusBar1.Panels[3].Text :=
      Format('%s is a %s built-in%s', [Nm, TierName, Extra]);
    { THE ONE DIALOG THIS ACTION MAY OPEN, and only over a CALL. A bare mention
      of a word that happens to be a built-in name is usually a variable -- `len
      = 5` is legal Phosphor, and the caret on that `len` is not a question
      about the standard library. A window over somebody's text is too loud an
      answer to a guess, so a mention gets the status-bar line above and nothing
      else, and only `len(...)` gets the offer.

      It is an OFFER rather than a jump because a keypress that launches a
      browser unasked is a keypress people stop pressing. The shape is
      ActDebugWhyExecute's, for the same kind of answer. }
    if (Args >= 0) and (MessageDlg('PhosphorIDE',
      Format('%s is a %s built-in, not a function defined in this file.'#10#10 +
             'Open the function reference on GitHub?', [Nm, TierName]),
      mtInformation, [mbYes, mbNo], 0) = mrYes) then
      OpenURL(UrlFunctionReference);
    Exit;
  end;

  { DEFINED HERE, BUT NOT AT THIS ARITY -- and no built-in to fall through to,
    so this call fails at run time. Saying "not found" about a name plainly
    visible three lines up reads as a broken feature; saying which arities exist
    is the answer to the question actually being asked. }
  if Defined > 0 then
  begin
    Extra := OutlineArities(Funcs, Nm);
    { EVERY definition of it may still be a half-typed header with no parameter
      list, and then there is no arity to name. Saying "it is defined taking"
      and stopping is worse than not saying it. }
    if Extra = '' then
      StatusBar1.Panels[3].Text := Format(
        'the %s in this file has no parameter list yet', [Nm])
    else
      StatusBar1.Panels[3].Text := Format(
        'no %s taking %d argument(s) in this file -- it is defined taking %s',
        [Nm, Args, Extra]);
    Exit;
  end;

  { A CALL TO A NAME NOTHING DEFINES COMPILES, and fails only when it runs. So
    F12 finding nothing is an ordinary answer and not a diagnostic, and it
    belongs in the status bar rather than in a dialog. }
  StatusBar1.Panels[3].Text :=
    Format('no definition for %s in this file', [Nm]);
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

procedure TFrmMain.DocBreakpointsChanged(Sender: TObject; AFromEdit: Boolean);
begin
  if not (Sender is TEditorDoc) then
    Exit;

  { AN EDIT IS REBUILT LATER, AND THAT IS MEASURED RATHER THAN CAUTIOUS. SynEdit
    adjusts its OWN marks for an insertion through a handler on the same
    senrLineCount notification that brought us here, and the order of the two is
    not ours to choose. Rebuilding from inside it puts the new marks in BEFORE
    that adjustment runs, and the adjustment then shifts them a second time: one
    line typed above a breakpoint on line 10 left the mark on 12 while the
    statement itself went to 11. Measured on 2026-09-16, on the first edit
    anybody tried after the marks existed at all.

    So an edit raises a flag and EditorChange -- which SynEdit fires once the
    change is finished -- does the rebuild. A toggle is not an edit, produces no
    OnChange, and is rebuilt here and now. }
  if AFromEdit then
    FMarksDirty := True
  else
    SyncGutterMarks(TEditorDoc(Sender));
end;

{ A fold opened or closed: the SET is untouched and the PICTURE is stale. Unlike
  an edit, this needs no deferral -- SynEdit has already finished with the fold by
  the time the notification arrives, and there is no second handler on it whose
  order is not ours. See SyncGutterMarks for what the picture then becomes. }
procedure TFrmMain.DocFoldsChanged(Sender: TObject);
begin
  SyncGutterMarks(TEditorDoc(Sender));
  TEditorDoc(Sender).Edit.Invalidate;
end;

{ A BREAKPOINT INSIDE A COLLAPSED BLOCK IS SHOWN ON THE HEADER. Roadmap item 20,
  decided and built on 2026-09-17; what stood here before was the same problem
  recorded rather than fixed.

  TSynGutterMarks paints VISIBLE screen rows only (synguttermarks.pp:353-357), so
  a mark on a line hidden by a fold is not drawn at all. Nothing underneath was
  wrong -- the mark stayed in the set, BreakpointIsArmed still answered, the run
  still stopped -- and what was lost was the PICTURE. The cost of that was
  measured before anything was built, by performing the sequence the item
  describes: collapse a function, see an EMPTY gutter, click the header to set
  the breakpoint again, expand, and find TWO. Against the real host those two
  stop the run THREE times, and the extra stop lands on a line with no mark on
  it.

  SO THE COLLAPSED HEADER CARRIES A THIRD MARK, `markBreakHidden` -- a smaller
  disc with a triangle under it, "not here, below". The row is the OUTERMOST
  collapsed header, which is the one the user can still see: with a `for` inside
  a collapsed `function`, every line of the `for` answers the `function`'s
  header. `TEditorDoc.CollapsedHeaderFor` is the question and
  `CollapsedLineForFoldAtLine` is what answers it.

  EXACTLY ONE MARK PER LINE, AND THAT IS NOT A STYLE CHOICE. At 96 PPI this
  gutter's marks part is 24 px wide against a 16 px column, so ColumnCount is 1
  and a second mark on the same line is simply not drawn -- and WHICH of the two
  survives is decided by their heap addresses, so it changes between runs.
  (`Application.Scaled` is on, and at 150% the ratio becomes 2 and both appear:
  the picture would differ by MONITOR.) A header that hides breakpoints therefore
  shows the badge and NOTHING ELSE, including when it carries a breakpoint of its
  own -- the badge is the fact that cannot be recovered any other way, and one
  click recovers the rest.

  WHAT THE BADGE DOES NOT SAY is how many, or whether the host armed them. That
  is a deliberate loss and the reason it is acceptable is the click: a gutter
  click on a badged row REVEALS the block instead of toggling (see
  EditorGutterClick), after which every hidden mark is drawn exactly as it always
  was, solid or hollow, one per line. The badge is a door, not a summary. }
procedure TFrmMain.SyncGutterMarks(ADoc: TEditorDoc);
var
  I, J, Line, Header: Integer;
  Headers: array of Integer;
  Known: Boolean;
  Mark: TSynEditMark;
begin
  if (ADoc = nil) or (ADoc.Edit = nil) then
    Exit;

  { REBUILT, NOT PATCHED. The set changes for four different reasons -- a toggle,
    an edit that moved a line, the host answering which lines it installed, and a
    session ending and taking that answer with it -- and three of the four change
    more than one mark. Rebuilding a list of at most a few dozen is cheaper to
    write than four incremental paths and cannot drift from the truth.

    Only ours are removed. Marks.Remove takes a mark OUT of the list without
    freeing it (syneditmarks.pp:1127), and the list frees whatever is still in it
    when the editor goes (:990), so removing and freeing here is the pair. }
  for I := ADoc.Edit.Marks.Count - 1 downto 0 do
  begin
    Mark := ADoc.Edit.Marks[I];
    if Mark is TPhosphorBreakMark then
    begin
      ADoc.Edit.Marks.Remove(Mark);
      Mark.Free;
    end;
  end;

  { PASS ONE: which visible rows are standing in for hidden breakpoints. The
    list is tiny -- one entry per collapsed block that holds a breakpoint -- and
    building it first is what lets pass two know which rows to leave alone. }
  Headers := nil;
  for I := 0 to ADoc.BreakpointCount - 1 do
  begin
    Header := ADoc.CollapsedHeaderFor(ADoc.Breakpoints[I]);
    if Header < 1 then
      Continue;
    Known := False;
    for J := 0 to High(Headers) do
      if Headers[J] = Header then
        Known := True;
    if not Known then
    begin
      SetLength(Headers, Length(Headers) + 1);
      Headers[High(Headers)] := Header;
    end;
  end;

  { PASS TWO: the breakpoints that are drawn where they are. A hidden one is
    skipped because its row is not on screen, and one that sits ON a badged
    header is skipped because the badge has that row -- see the header comment
    for why two marks may not share it. }
  for I := 0 to ADoc.BreakpointCount - 1 do
  begin
    Line := ADoc.Breakpoints[I];
    if ADoc.CollapsedHeaderFor(Line) > 0 then
      Continue;
    Known := False;
    for J := 0 to High(Headers) do
      if Headers[J] = Line then
        Known := True;
    if Known then
      Continue;

    Mark := TPhosphorBreakMark.Create(ADoc.Edit);
    Mark.Line := Line;
    { SOLID IF THE HOST BOUND IT, HOLLOW IF IT COULD NOT. Outside a session
      nothing is known and BreakpointIsArmed answers True, which draws the mark
      the way the user meant it -- see its own comment: unknown is not dead. }
    if BreakpointIsArmed(ADoc, Line) then
      Mark.ImageIndex := markBreakArmed
    else
      Mark.ImageIndex := markBreakInert;
    Mark.Visible := True;
    ADoc.Edit.Marks.Add(Mark);
  end;

  { PASS THREE: one badge per collapsed header that hides something. }
  for J := 0 to High(Headers) do
  begin
    Mark := TPhosphorBreakMark.Create(ADoc.Edit);
    Mark.Line := Headers[J];
    Mark.ImageIndex := markBreakHidden;
    Mark.Visible := True;
    ADoc.Edit.Marks.Add(Mark);
  end;
end;

procedure TFrmMain.RepaintEditors;
var
  I: Integer;
begin
  { The stop can be in a file that is not the active tab, so every editor is
    asked to redraw rather than just this one. There are a handful of tabs. }
  for I := 0 to FDocs.Count - 1 do
    if TEditorDoc(FDocs[I]).Edit <> nil then
    begin
      SyncGutterMarks(TEditorDoc(FDocs[I]));
      TEditorDoc(FDocs[I]).Edit.Invalidate;
    end;
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
  FStackLineNoted := False;
  ClearVariables;
  ClearStack;
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
  ClearStack;
  FStackLineNoted := False;
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

  { AND NEITHER IS A VARIABLE OR A FRAME. Both panes describe a program standing
    still at one statement; the moment it resumes they are a photograph presented
    as a live view, and the host will not answer a question about either while it
    runs. Same rule as the stripe, one line further out. }
  if (FDebug.State <> dsStopped) and (Length(FStackFrames) > 0) then
  begin
    ClearStack;
    ClearVariables;
    TabVariables.Caption := 'Variables';
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

  { THE STACK FIRST, then frame 0's variables. Both answers carry what they are
    about, so the order on the wire does not matter -- but the stack arriving
    first means the variables pane can already name the frame it is showing
    instead of relabelling itself a moment later. }
  FDebug.RequestStackTrace;
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

procedure TFrmMain.ClearStack;
begin
  FStackFrames := nil;
  FStackFilling := True;
  try
    ListStack.Items.Clear;
  finally
    FStackFilling := False;
  end;
  TabStack.Caption := 'Call Stack';
end;

function TFrmMain.FrameName(AIndex: Integer): String;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FStackFrames)) then
    Result := FStackFrames[AIndex].Name;
end;

procedure TFrmMain.DebugStack(Sender: TObject; const AFrames: TPdbpFrames);
var
  I: Integer;
  Item: TListItem;
  Callerless: Boolean;
begin
  { AN ANSWER ABOUT A PROGRAM THAT HAS MOVED ON IS NOT AN ANSWER. Continue and
    the reply to a request made while stopped can cross on the wire; filling the
    pane with it would show the user a call stack the program no longer has. }
  if FDebug.State <> dsStopped then
    Exit;

  FStackFrames := AFrames;
  FStackFilling := True;
  try
    ListStack.Items.BeginUpdate;
    try
      ListStack.Items.Clear;
      Callerless := False;
      for I := 0 to High(AFrames) do
      begin
        Item := ListStack.Items.Add;
        Item.Caption := IntToStr(AFrames[I].Index);
        Item.SubItems.Add(AFrames[I].Name);
        { A LINE OF 0 IS NOT LINE ZERO, IT IS NO LINE. Printing `0` would read as
          a location; an empty cell reads as what it is.

          This was written because the host answered 0 for every caller -- it
          recorded no call site per frame -- and it is KEPT although Phosphor
          fixed that the same afternoon (`fce3db1`). A frame with no line is
          still a legal answer from a conformant host, and this editor is right
          about the protocol rather than about one implementation of it. The
          whole of what the fix changed on this side is that the cells now have
          something to put in them. }
        if AFrames[I].Line > 0 then
          Item.SubItems.Add(IntToStr(AFrames[I].Line))
        else
        begin
          Item.SubItems.Add('');
          if I > 0 then
            Callerless := True;
        end;
        Item.SubItems.Add(ExtractFileName(AFrames[I].Path));
      end;
      if ListStack.Items.Count > 0 then
        ListStack.Items[0].Selected := True;
    finally
      ListStack.Items.EndUpdate;
    end;
  finally
    FStackFilling := False;
  end;

  TabStack.Caption := Format('Call Stack (%d)', [Length(AFrames)]);

  if Callerless then
  begin
    ListStack.Hint := 'This host reports a line only for the innermost frame, ' +
      'so only that row can be jumped to.';
    if not FStackLineNoted then
    begin
      FStackLineNoted := True;
      AddOutput('  debug: this host reports a line only for the innermost ' +
        'frame; the callers are listed without one and cannot be jumped to');
    end;
  end
  else
    ListStack.Hint := 'Double-click a frame to go to it.';
end;

procedure TFrmMain.ListStackSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  { Filling the list selects row 0, which would otherwise re-ask for the frame
    the stop already asked for. And a DEselection is not a choice of anything. }
  if FStackFilling or (not Selected) or (Item = nil) then
    Exit;
  if FDebug.State <> dsStopped then
    Exit;
  { By index, which is what the protocol takes and what the answer carries back.
    A frame the host has since forgotten is refused with `no frame N`, and the
    session reports that through OnNote rather than guessing. }
  FDebug.RequestVariables(Item.Index);
end;

procedure TFrmMain.ListStackDblClick(Sender: TObject);
var
  Item: TListItem;
begin
  Item := ListStack.Selected;
  if (Item = nil) or (Item.Index > High(FStackFrames)) then
    Exit;
  { NOTHING HAPPENS FOR A FRAME WITH NO LINE, on purpose. The alternative --
    finding the function's header by searching the text for its name -- is the
    editor inventing a location, which is the defect GotoSource's own comment
    warns about one layer down: a plausible-looking jump to somewhere the
    program is not. The pane's hint says why, and so does one line of output. }
  if FStackFrames[Item.Index].Line <= 0 then
    Exit;
  GotoSource(FStackFrames[Item.Index].Path, FStackFrames[Item.Index].Line);
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
  { Same reason as the stack: a reply that crossed a Continue describes a moment
    that has passed. }
  if FDebug.State <> dsStopped then
    Exit;

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

  { WHICH FRAME, when it is not the innermost one. The stack pane shows the
    selection, but the two panes cannot both be on screen, and a list of locals
    with no frame attached is a list of locals belonging to nothing in
    particular. }
  if (AFrame > 0) and (FrameName(AFrame) <> '') then
    { WITH THE INDEX, because the name alone is ambiguous exactly where this
      pane earns its keep: four frames of `down` in a recursion are four
      different sets of locals and one name. }
    TabVariables.Caption := Format('Variables (%d) in %s #%d',
      [Length(AVars), FrameName(AFrame), AFrame])
  else
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

function TFrmMain.Highlighter: TSynCustomHighlighter;
begin
  Result := FHighlighter;
end;

function TFrmMain.ActiveEditor: TSynEdit;
var
  Doc: TEditorDoc;
begin
  Doc := ActiveDoc;
  if Doc = nil then
    Result := nil
  else
    Result := Doc.Edit;
end;

function TFrmMain.GutterPartCount: Integer;
var
  Doc: TEditorDoc;
begin
  Result := 0;
  Doc := ActiveDoc;
  if (Doc <> nil) and (Doc.Edit <> nil) then
    { Gutter.Parts.Count and not Gutter.PartCount: the second is protected in
      TSynGutterBase (syngutterbase.pp:78) and the first is the public list
      (syngutterbase.pp:115) that answers the same number. }
    Result := Doc.Edit.Gutter.Parts.Count;
end;

procedure TFrmMain.SettingsChanged;
begin
  { A PROMPT THAT ANSWERS FROM A BINARY THE SETTINGS NO LONGER NAME is a prompt
    lying about what it is, and the variables it is holding belong to the old
    one. Forced, because there is nobody to press End a second time. }
  if FReplLive and (FReplHostPath <> '') and
     (CompareFilenames(FReplHostPath, FSettings.HostPath) <> 0) and
     (FSettings.HostPath <> '') then
    EndRepl('the host changed', True);

  FHighlighter.ApplyTheme(FSettings.DarkTheme);
  ApplyAllEditorSettings;
  ResolveHost;
  RefreshStatus;
end;

procedure TFrmMain.EditorChange(Sender: TObject);
begin
  RefreshTabCaption(ActiveDoc);
  { The other half of the note in DocBreakpointsChanged: by here the edit is
    finished and SynEdit has already moved whatever it was going to move, so a
    rebuild from the breakpoint set is the last word rather than an early one. }
  if FMarksDirty then
  begin
    FMarksDirty := False;
    SyncGutterMarks(ActiveDoc);
  end;
  { NOT a rebuild: a rescan of the whole buffer on every keystroke is the storm
    the roadmap forbids. This arms the debounce. }
  ScheduleOutline;
end;

procedure TFrmMain.EditorStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
begin
  if (scCaretX in AChanges) or (scCaretY in AChanges) or (scModified in AChanges) then
  begin
    RefreshStatus;
    { AND THE OUTLINE FOLLOWS THE CARET, which is the difference between a list
      and an outline: it answers "where am I" without being asked. A walk over
      ten records, on the caret path, and nothing is rescanned here. }
    if scCaretY in AChanges then
      SyncOutlineSelection;
    { THE CARET IS THE ONLY TRIGGER THE HINT NEEDS. Typing `(` moves it, typing
      `)` moves it, and moving out of the call by any route -- arrow key, mouse,
      Go to Line -- moves it too. There is nothing to dismiss because there is
      nothing that stays up on its own. }
    RefreshSignatureHint;
  end;
end;

procedure TFrmMain.HideSignatureHint;
begin
  FSigShown := '';
  if FSigHint <> nil then
    FSigHint.Hide;
end;

procedure TFrmMain.RefreshSignatureHint;
var
  Doc: TEditorDoc;
  { Not Name and Text: TComponent publishes both, and a local that shadows a
    published property of the enclosing class is a duplicate identifier here. }
  CallName, Body: String;
  Arg, I: Integer;
  Sigs: TPhosphorWordList;
  R: TRect;
  P: TPoint;
begin
  Doc := ActiveDoc;
  if (Doc = nil) or (Doc.Edit = nil) or (not Doc.Edit.Focused) then
  begin
    HideSignatureHint;
    Exit;
  end;

  { The same byte-versus-display column as ActCompleteExecute, and the same
    fix: LineText is bytes, so the column that indexes it is LogicalCaretXY.X. }
  if not CallAtCaret(Doc.Edit.LineText, Doc.Edit.LogicalCaretXY.X,
                     CallName, Arg) then
  begin
    HideSignatureHint;
    Exit;
  end;

  { NOTHING KNOWN IS NOT AN EMPTY SIGNATURE, and the difference is why this asks
    for the length rather than for the first row. A name whose arities are built
    at run time, one of the four compiler special forms, or a user's own
    function: all three come back with no rows, and the honest hint for all three
    is no hint. }
  Sigs := PhosphorSignatures(CallName);
  if Length(Sigs) = 0 then
  begin
    HideSignatureHint;
    Exit;
  end;

  Body := '';
  Text := '';
  for I := 0 to High(Sigs) do
  begin
    if I > 0 then
      Body := Body + LineEnding;
    Body := Body + SignatureText(CallName, Sigs[I], Arg);
  end;

  { Redrawn only when it would say something different. The caret moves on every
    keystroke inside a call, and re-activating a hint window per character is a
    flicker the user reads as the editor struggling. }
  if Body = FSigShown then
    Exit;
  FSigShown := Body;

  P := Doc.Edit.ClientToScreen(
    Point(Doc.Edit.CaretXPix, Doc.Edit.CaretYPix + Doc.Edit.LineHeight + 2));
  R := FSigHint.CalcHintRect(0, Body, nil);
  Types.OffsetRect(R, P.X, P.Y);
  FSigHint.ActivateHint(R, Body);
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

  { AND THE BREAKPOINT IS NOT PAINTED HERE AT ALL ANY MORE. It used to colour
    the whole row -- maroon for armed, grey for a mark the host could not bind --
    and that comment said in as many words that a hollow gutter ICON was the
    better answer and was missing only because it needed a TImageList. It has
    one now (roadmap item 13), so the mark moved to the gutter where every other
    debugger puts it: SEE SyncGutterMarks.

    Which is not only convention. A full-width maroon band behind a line of code
    is a line of code that is harder to read, and a breakpoint is a thing you set
    and then read around. The stop above keeps its band, because a band is what
    "you are here" should be. }
end;

procedure TFrmMain.EditorGutterClick(Sender: TObject; X, Y, ALine: Integer;
  AMark: TSynEditMark);
var
  Doc: TEditorDoc;
  Hidden: Integer;
begin
  { Clicking the margin is how every other editor toggles a breakpoint, so it is
    how this one does too -- even while nothing stops at one. }
  Doc := DocOfPage(PagesEditors.ActivePage);
  if (Doc = nil) or (ALine < 1) then
    Exit;

  { EXCEPT ON A ROW THAT IS HIDING ONE, WHERE IT OPENS THE BLOCK INSTEAD.
    Roadmap item 20. SynEdit hands this handler the TEXT line, so on a collapsed
    header that line is the header's -- and a person who collapsed a function,
    saw an empty gutter and clicked to set the breakpoint again used to get a
    SECOND one, on a line they did not choose, which stopped the run an extra
    time. The badge SyncGutterMarks now draws says the block holds one; this
    makes the badge a door.

    IT IS THE ONLY ROW WHERE A GUTTER CLICK DOES ANYTHING ELSE, and only while
    it is badged: a collapsed header hiding nothing toggles like every other
    line. Nothing is refused and the caret does not move -- the block opens, the
    marks come back solid or hollow as they always were, and the next click is
    an ordinary one on the line the user actually wanted. }
  Hidden := Doc.HiddenBreakpointCount(ALine);
  if Hidden > 0 then
  begin
    Doc.RevealFoldAt(ALine);
    if Hidden = 1 then
      StatusBar1.Panels[3].Text := 'opened: this fold was hiding a breakpoint'
    else
      StatusBar1.Panels[3].Text :=
        Format('opened: this fold was hiding %d breakpoints', [Hidden]);
    Doc.Edit.Invalidate;
    Exit;
  end;

  Doc.ToggleBreakpoint(ALine);
  SyncBreakpoints(Doc);
  Doc.Edit.Invalidate;
  RefreshStatus;
end;

procedure TFrmMain.PagesEditorsChange(Sender: TObject);
begin
  RefreshStatus;
  { AT ONCE, not on the debounce: a list of another file's functions that can be
    clicked is a wrong jump waiting a quarter of a second to happen. }
  RebuildOutline;
  { A hint belongs to a caret, and the caret just changed file. }
  HideSignatureHint;
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
  ActGotoDefinition.Enabled := Doc <> nil;
  { Enabled whether or not one is live: the action shows the pane as well as
    starting a session, and a menu item that greys out once you are using it is
    a menu item nobody finds again. }
  BtnReplSend.Enabled := FReplLive;
  BtnReplEnd.Enabled := FReplLive;

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
