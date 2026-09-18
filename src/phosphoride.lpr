program phosphoride;

{ PhosphorIDE -- an editor for Phosphor BASIC.

  This program never links the Phosphor engine. It edits text and it spawns the
  `phosphor` binary as a child process; a script that loops forever, exhausts
  memory or faults the interpreter takes its own process down and leaves the
  editor holding the user's unsaved work. That is the whole reason the interpreter
  is not in here, and it is the one design decision the rest of the program is not
  allowed to trade away for convenience. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,   // TProcess reads its pipes on a thread; without this, on Unix, the
              // RTL has no threading and those reads deadlock the UI.
  {$ENDIF}
  Interfaces, Forms, Classes, SysUtils,
  SynEditHighlighterFoldBase, SynEdit, SynEditKeyCmds, LCLType, uphosphorfold,
  umainform, uaboutform, upreferencesform,
  uphosphorlang, uphosphormsg, uphosphorhost, uphosphorsettings,
  uphosphorrun, usynphosphor, udebugproto, udebugsession, uphosphorcomplete,
  uphosphoricons, uphosphorclock;

{$IFDEF WINDOWS}
{ A Windows GUI subsystem binary has no console, so WriteLn hits an invalid handle
  and the RTL's I/O error surfaces as a modal dialog nobody is there to dismiss --
  which is a hang, not a message. Measured on 2026-09-10: a --selftest that merely
  wrote its result to stdout hung the process until it was killed. So the selftest
  reports through a FILE and its exit code, and this program writes to a console
  stream nowhere. }
{$ENDIF}

var
  ReportPath, RealFile: String;
  ExitStatus: Integer;

{ Construct every form once and report whether it worked.

  A hand-written .lfm that names a component the .pas does not publish streams
  fine right up until the form is created, and then throws where a user is
  looking. This check runs the same construction from the command line, so a
  mismatch is a red build rather than a bug report. It is what scripts/build.ps1
  runs after lazbuild.

  Exit codes: 0 every form built, 1 one of them did not. }
function SelfTest(const AReportPath: String): Integer;
var
  Report: TStringList;
  Failure, IconSizes: String;
  I: Integer;
begin
  { A STREAMING ERROR IS A MODAL DIALOG, NOT A FAILURE, unless this flag is set.

    LCL's TApplication.ShowException (lcl/include/application.inc:1598) answers an
    exception with a PromptUser box -- "Press OK to ignore and risk data
    corruption. Press Abort to kill the program." -- and waits. In a build script
    that is not a red test, it is a hang, with the dialog sitting on whatever
    machine happened to run it. Measured on 2026-09-10: an .lfm naming a property
    its .pas does not publish did exactly this.

    AppNoExceptionMessages makes ShowException return without drawing anything
    (application.inc:1604), so a mismatch reaches the try/except below and becomes
    an exit code. scripts/build.ps1 additionally runs this with a timeout, because
    a flag only covers the dialogs LCL knows it is showing. }
  Application.Flags := Application.Flags + [AppNoExceptionMessages];

  Report := TStringList.Create;
  try
    Failure := '';
    try
      Application.CreateForm(TFrmMain, FrmMain);
      Report.Add(Format('main form: ok, %d components', [FrmMain.ComponentCount]));
      { A collection inside an .lfm streams separately from the components, so a
        `Panels = <...>` that fails to arrive leaves a status bar that is present,
        sized and completely blank -- which is exactly what it looked like on both
        platforms on 2026-09-10 before anyone counted them. Reported here because
        "it is there but says nothing" is not a thing a screenshot can diagnose. }
      Report.Add(Format('status bar: %d panels, simple=%s, %d tabs',
        [FrmMain.StatusBar1.Panels.Count,
         BoolToStr(FrmMain.StatusBar1.SimplePanel, True),
         FrmMain.PagesEditors.PageCount]));
      { The same reason the panels are counted. A TListView whose Columns
        collection failed to stream is a pane that is present, sized, and shows
        nothing -- and no screenshot distinguishes that from a pane with no rows
        in it yet. }
      Report.Add(Format('variables pane: %d columns, %d output tabs',
        [FrmMain.ListVariables.Columns.Count, FrmMain.PagesOutput.PageCount]));
      Report.Add(Format('call stack pane: %d columns',
        [FrmMain.ListStack.Columns.Count]));
      { AND THE WATCH PANE, which has an input row the other two do not. Both
        halves are counted: a list whose columns did not stream shows nothing,
        and an edit that did not stream is a pane you cannot add a watch to --
        and neither is a failure anywhere, which is the whole reason for
        counting rather than looking. }
      Report.Add(Format('watch pane: %d columns, input=%s, buttons=%d',
        [FrmMain.ListWatch.Columns.Count,
         BoolToStr(FrmMain.EditWatch <> nil, True),
         FrmMain.PanelWatch.ControlCount - 1]));
      { AND THE STDIN ROW, WITH ITS HINT SPELLED OUT rather than counted. The
        defect this line exists for is not a control that failed to stream: it is
        a control that streamed perfectly and says nothing, which is what this row
        was until 2026-09-17, when the author of the editor met his own program's
        `Name? ` prompt and killed it rather than answer it. A TextHint that
        arrived empty puts the window straight back there, with no error anywhere
        and nothing a screenshot of an unshown form could show -- and the hint is
        the only thing in this row a person reads, so the text is printed and not
        its length. See the WHY block above TFrmMain.BtnSendInputClick. }
      Report.Add(Format('stdin row: %d controls, hint "%s"',
        [FrmMain.PanelInput.ControlCount, FrmMain.EditInput.TextHint]));
      { AN IMAGE LIST THAT STREAMED EMPTY IS A TOOLBAR OF BLANK BUTTONS, and
        that is not a failure anywhere: the buttons still have captions, the
        form still builds, and only a screenshot would show it. Counted here
        with its RESOLUTIONS, because the trap the roadmap named is a list with
        one of them -- the widgetset then scales, differently on each platform,
        and the blur arrives from the machine nobody is looking at. }
      IconSizes := '';
      for I := 0 to FrmMain.ImagesToolbar.ResolutionCount - 1 do
      begin
        if IconSizes <> '' then
          IconSizes := IconSizes + '+';
        IconSizes := IconSizes +
          IntToStr(FrmMain.ImagesToolbar.ResolutionByIndex[I].Width);
      end;
      { THE WIDTHS, not just the count. Two resolutions of 16 would count as two
        and be the very defect this line exists to catch: a list the widgetset
        then scales, differently on each platform, with the blur arriving from
        the machine nobody is looking at. }
      Report.Add(Format('toolbar icons: %d images at %s px',
        [FrmMain.ImagesToolbar.Count, IconSizes]));
      Report.Add(Format('gutter marks: %d images, %d resolutions',
        [FrmMain.ImagesGutter.Count, FrmMain.ImagesGutter.ResolutionCount]));
      { THE SHORTCUT AND THE DEFAULT MASK, for the third time the same reason: a
        TAction whose ShortCut streamed as 0 still draws its menu item, still
        runs when clicked, and answers Ctrl+Shift+F with nothing at all -- and an
        EditFindMask that arrived without its Text searches every file in the
        tree instead of the .bas files. Neither is visible in a screenshot of a
        pane that looks exactly right. 24646 is Ctrl+Shift+F. }
      Report.Add(Format('find in files: shortcut %d, default mask %s',
        [FrmMain.ActFindInFiles.ShortCut, FrmMain.EditFindMask.Text]));
      { THE TWO SHORTCUTS, AND THE ROW COUNT THAT PROVES THE LIST STREAMED. The
        TAB is not reported here because the `output tabs` number above already
        counts it, and a second copy would be a second thing to keep in step.
        What nothing else covers is a TAction whose ShortCut streamed as 0 --
        which still draws its menu item, still runs when clicked, and answers
        F12 with silence -- and a ListOutline that streamed but was never
        filled, which is the "present but blank" defect class this report line
        exists for. 123 is F12, 24655 is Ctrl+Shift+O, and one row is the
        "no function definitions" line of an empty untitled buffer. }
      Report.Add(Format('outline: F12 %d, pane %d, rows %d',
        [FrmMain.ActGotoDefinition.ShortCut, FrmMain.ActOutline.ShortCut,
         FrmMain.ListOutline.Items.Count]));
      { THE TRANSCRIPT MUST BE EMPTY HERE, and that is the interesting half. A
        REPL is a child that never exits on its own and, on Windows, holds a
        lock on phosphor.exe; one started at form creation would be a process
        the user did not ask for and cannot explain. Zero lines is the proof
        that constructing the window starts nothing. 24658 is Ctrl+Shift+R. }
      Report.Add(Format('repl: shortcut %d, transcript %d lines',
        [FrmMain.ActRepl.ShortCut, FrmMain.MemoRepl.Lines.Count]));
      { FOLDING IS TURNED ON BY A CLASS TEST AND NOTHING ELSE.
        TSynEditFoldedView.SetHighLighter drops any highlighter that is not a
        TSynCustomFoldHighlighter (syneditfoldedview.pp:3570-3576) -- there is no
        capability flag and no eo* option involved -- so a highlighter that
        quietly stopped being one would fold nothing, with no error anywhere and
        no change a screenshot could show. The gutter part count is reported
        beside it because the fold column is one of the five parts SynEdit
        creates by default, and a gutter that lost a part is the same class of
        silent defect as a status bar with no panels. }
      Report.Add(Format('folding: highlighter folds=%s, gutter parts=%d',
        [BoolToStr(FrmMain.Highlighter is TSynCustomFoldHighlighter, True),
         FrmMain.GutterPartCount]));

      Application.CreateForm(TFrmAbout, FrmAbout);
      Report.Add(Format('about form: ok, %d components', [FrmAbout.ComponentCount]));

      Application.CreateForm(TFrmPreferences, FrmPreferences);
      Report.Add(Format('preferences form: ok, %d components', [FrmPreferences.ComponentCount]));

      Report.Add(Format('language tables: %d keywords, %d core, %d package, %d gui',
        [PhosphorKeywordCount, PhosphorBuiltinCoreCount,
         PhosphorBuiltinPackageCount, PhosphorBuiltinGuiCount]));
    except
      on E: Exception do
      begin
        Failure := E.ClassName + ': ' + E.Message;
        Report.Add('FAILED: ' + Failure);
      end;
    end;

    if AReportPath <> '' then
      try
        Report.SaveToFile(AReportPath);
      except
        on E: Exception do
          ;   // the exit code still carries the verdict
      end;

    if Failure = '' then
      Result := 0
    else
      Result := 1;
  finally
    Report.Free;
  end;
end;


{ ---------------------------------------------------------- measure-typing --- }

{ WHAT A KEYSTROKE COSTS, IN THE EDITOR, which is roadmap item 19.

  Item 17 shipped folding and answered its own performance clause with a number:
  an edit that opens or closes a block at the top of a 5000-line buffer went from
  0.040 ms to 66 ms. That was taken in `MeasureHighlighter`, a loop in the test
  program calling ScanRanges on an attached line store, and item 19 says -- it is
  right -- that it is not yet a fact about a person typing. Three things were
  unknown: when SynEdit does the work, how much of it is ours, and whether the
  file sizes that exist are affected at all.

  THIS GOES THROUGH THE REAL PATH. `CommandProcessor(ecChar, ...)` is what
  TCustomSynEdit.KeyDown calls (synedit.pp:1011); nothing here calls ScanRanges,
  or the highlighter, or anything of ours. What is timed is the call a keystroke
  makes and then the paint that follows it, separately, because they are
  different costs to a person: the first is the editor not responding and the
  second is the character not being there yet.

  AND THE WINDOW MUST BE REAL. TCustomSynEdit.WaitingForInitialSize is true while
  the handle is unallocated (synedit.pp:4972-4976), and ScanChangedLines then
  takes the CHUNKED IDLE path instead of scanning synchronously
  (synedit.pp:5594-5599) -- so a measurement taken on an unshown form would
  measure the wrong branch and report a small number under the right name. The
  form is shown, the flag is checked, and the report says what it found.

  THE STATISTIC IS THE MINIMUM, and the median beside it. A mean over a dozen
  passes on a desktop describes the machine's other work as much as this
  program's: the first run of this reported a quiet edit at 0.74 ms and the next,
  with a build running, at 2.4 ms for the same code. Noise only ever ADDS, so the
  minimum is the honest estimate of what the work costs and the median is what a
  person would typically wait; a number that moves between them is a number about
  the machine.

  AND THE CASCADE IS PROVEN, NOT ASSUMED. Each size reports the fold depth of a
  line in the middle of the buffer in both states. If those two numbers are equal
  the edit did not cascade and every timing beside them is measuring something
  else -- which is exactly what the first cut of this did, with a fixture whose
  stray terminators swallowed the opener ten lines down and gave a flat 1 ms from
  100 lines to 5000.

  Exit codes: 0 it measured, 1 it could not. }
function MeasureTyping(const AReportPath, ARealFile: String): Integer;
const
  Sizes: array[0..5] of Integer = (100, 250, 500, 1000, 2000, 5000);
  Reps = 21;
type
  TSamples = array[1..Reps] of Double;
var
  Report: TStringList;
  Failure: String;
  Ed: TSynEdit;

  { The minimum and the median of what was collected, with the first pass
    dropped: it is the one that finds the caches cold, and a person is only ever
    in that state once per file. }
  procedure Stats(var ASamples: TSamples; ACount: Integer;
    out AMin, AMedian, AMax: Double);
  var
    I, J: Integer;
    T: Double;
  begin
    for I := 2 to ACount do
      for J := I + 1 to ACount do
        if ASamples[J] < ASamples[I] then
        begin
          T := ASamples[I]; ASamples[I] := ASamples[J]; ASamples[J] := T;
        end;
    AMin := ASamples[2];
    AMedian := ASamples[2 + (ACount - 1) div 2];
    AMax := ASamples[ACount];
  end;

  { A buffer that looks like Phosphor and folds like it: one BALANCED definition
    every ten lines, a loop and an `if` inside it, a comment holding the word
    `function` and a string holding `endif` -- the two shapes that would fool a
    scanner reading words rather than positions.

    BALANCED IS THE WHOLE POINT, and the first cut of this was not. It put the
    incomplete word inside the groups, which left every group carrying an
    `endfunction` that closed nothing -- so the opener the measurement typed was
    swallowed by the very first stray terminator ten lines down, the depth of
    line 11 onwards never changed, and the scan settled there.

    So the groups close themselves, and the one incomplete word is on LINE 1,
    ABOVE ALL OF THEM. Completing it opens a block that nothing in the file
    closes, every line below it moves one level deeper, no line's range can match
    the stored one again, and the scan runs to the end of the buffer. That is the
    cascade, and it is the worst case the language permits. }
  procedure Fill(ACount: Integer);
  var
    Buf: TStringList;
    I: Integer;
  begin
    Buf := TStringList.Create;
    try
      { Line 1: the cascade site, one character short of a definition.
        Line 2: the quiet site, a comment with nothing structural in it. }
      Buf.Add('functio measured()');
      Buf.Add('rem an ordinary comment with the word function in it');
      I := 0;
      while Buf.Count < ACount do
      begin
        Inc(I);
        Buf.Add(Format('rem block %d -- a comment with the word function in it', [I]));
        Buf.Add(Format('function f%d(a, b) local acc', [I]));
        Buf.Add('  acc = 0');
        Buf.Add(Format('  for i = 1 to %d', [I mod 7 + 1]));
        Buf.Add('    if a > b then');
        Buf.Add(Format('      acc = acc + left$("a string with endif in it", %d)', [I mod 5]));
        Buf.Add('    endif');
        Buf.Add('  next');
        Buf.Add('  return acc');
        Buf.Add('endfunction');
      end;
      while Buf.Count > ACount do
        Buf.Delete(Buf.Count - 1);
      Ed.Lines.Assign(Buf);
    finally
      Buf.Free;
    end;
    Application.ProcessMessages;
  end;

  { AND A REAL PROGRAM, because every row above is a shape this function chose.
    The synthetic buffer has a fold node every three lines and lines of a length
    this function picked; a Phosphor program written by a person has neither, and
    the per-line cost is driven by what is ON the line -- an identifier costs
    more to classify than a comment does. The one line added at the top is the
    definition being typed, which is what a person adding a function to an
    existing file does. }
  function FillFromFile(const APath: String): Integer;
  var
    Buf: TStringList;
  begin
    Buf := TStringList.Create;
    try
      Buf.LoadFromFile(APath);
      Buf.Insert(0, 'functio measured()');
      Buf.Insert(1, 'rem an ordinary comment');
      Ed.Lines.Assign(Buf);
      Result := Buf.Count;
    finally
      Buf.Free;
    end;
    Application.ProcessMessages;
  end;

  { How deep a line in the MIDDLE of the buffer sits. Not the last one:
    TSynCustomFoldHighlighter.FoldBlockEndLevel returns 0 for any index
    `>= CurrentLines.Count - 1` (synedithighlighterfoldbase.pas:1787-1788), so
    the genuinely last line answers zero whatever is open above it -- which read,
    the first time, as a cascade that was not happening on top of one that was.
    The middle is also past every truncation the fixture's last group can have. }
  function DepthInTheMiddle: Integer;
  begin
    Result := (FrmMain.Highlighter as TSynCustomFoldHighlighter)
                .FoldBlockEndLevel(Ed.Lines.Count div 2);
  end;

  procedure Settle(ALine, ACol: Integer);
  begin
    Ed.CaretXY := Point(ACol, ALine);
    Ed.Invalidate;
    Application.ProcessMessages;
  end;

  { One command through the real entry point. ASync is the time the call itself
    took -- the editor not responding -- and APaint the time from there to the
    end of the message processing that draws the result. }
  procedure OneEdit(ACommand: TSynEditorCommand; const AChar: TUTF8Char;
    out ASync, APaint: Double);
  var
    T0, T1, T2: Int64;
  begin
    T0 := ClockTicks;
    Ed.CommandProcessor(ACommand, AChar, nil);
    T1 := ClockTicks;
    Application.ProcessMessages;
    T2 := ClockTicks;
    ASync := ClockMs(T0, T1);
    APaint := ClockMs(T1, T2);
  end;

  { The edit almost every keystroke actually is: one that changes no block at
    all. It is the baseline the cascading number means nothing without. }
  function Quiet(ASize: Integer): Double;
  var
    P: Integer;
    S, Pa, Lo, Mid, Hi, PLo, PMid, PHi: Double;
    Sync, Paint: TSamples;
  begin
    S := 0; Pa := 0;
    for P := 1 to Reps do
    begin
      Settle(2, 12);
      OneEdit(ecChar, 'x', S, Pa);
      Sync[P] := S;
      Paint[P] := Pa;
      Settle(2, 13);
      OneEdit(ecDeleteLastChar, '', S, Pa);
    end;
    Stats(Sync, Reps, Lo, Mid, Hi);
    Stats(Paint, Reps, PLo, PMid, PHi);
    Report.Add(Format('  quiet    %5d lines   %6.2f min %6.2f med %6.2f max ms   ' +
                      'paint %5.2f med',
                      [ASize, Lo, Mid, Hi, PMid]));
    Result := Lo;
  end;

  { The keystroke that opens a block nothing closes, and the backspace that takes
    it away again. Two directions, because they are different work. }
  function Cascade(ASize: Integer; AQuietMin: Double): Double;
  var
    P, DOpen, DClosed: Integer;
    S, Pa, Lo, Mid, Hi, PLo, PMid, PHi: Double;
    Sync, Paint: TSamples;
  begin
    S := 0; Pa := 0; DOpen := -1; DClosed := -1;
    for P := 1 to Reps do
    begin
      Settle(1, 8);
      OneEdit(ecChar, 'n', S, Pa);             // `functio` -> `function`: opens
      Sync[P] := S;
      Paint[P] := Pa;
      if P = 1 then
        DOpen := DepthInTheMiddle;
      Settle(1, 9);
      OneEdit(ecDeleteLastChar, '', S, Pa);    // and back: closes
      if P = 1 then
        DClosed := DepthInTheMiddle;
    end;
    Stats(Sync, Reps, Lo, Mid, Hi);
    Stats(Paint, Reps, PLo, PMid, PHi);
    Report.Add(Format('  cascade  %5d lines   %6.2f min %6.2f med %6.2f max ms   ' +
                      'paint %5.2f med   %5.1f x quiet   [depth %d open, %d closed]',
                      [ASize, Lo, Mid, Hi, PMid, Lo / AQuietMin, DOpen, DClosed]));
    if DOpen = DClosed then
      Report.Add('           ^^ THE DEPTH DID NOT MOVE: this row is not a cascade');
    Result := Lo;
  end;

  { AND THE ONE A PERSON ACTUALLY DOES. Typing the word `function` is eight
    keystrokes and item 17's number is for one, so the question this answers is
    whether the cost is paid once or eight times. Only the eighth completes the
    word -- `f`, `fu`, `func` are identifiers and open nothing. }
  procedure Word(ASize: Integer; AQuietMin: Double);
  var
    I, P, Expensive: Integer;
    S, Pa, Total, Worst, Lo, Mid, Hi: Double;
    Totals: TSamples;
  begin
    S := 0; Pa := 0; Worst := 0; Expensive := 0;
    for P := 1 to Reps do
    begin
      Ed.Lines[0] := ' measured()';
      Application.ProcessMessages;
      Settle(1, 1);
      Total := 0;
      for I := 1 to 8 do
      begin
        OneEdit(ecChar, Copy('function', I, 1), S, Pa);
        Total := Total + S;
        if P > 1 then
        begin
          if S > Worst then
            Worst := S;
          if S > 4 * AQuietMin then
            Inc(Expensive);
        end;
      end;
      Totals[P] := Total;
    end;
    Stats(Totals, Reps, Lo, Mid, Hi);
    Report.Add(Format('  word     %5d lines   the eight keystrokes total %6.2f min ' +
                      '%6.2f med ms, worst one %6.2f ms, %d of %d above 4x quiet',
                      [ASize, Lo, Mid, Worst, Expensive, 8 * (Reps - 1)]));
  end;

  { AND THE STATE THAT BEATS THE TOP OF THE FILE. Every fold collapsed is not an
    exotic state -- it is what a person does to find their way around a long
    file -- and the same keystroke then costs more, because
    TSynEditFoldedView.FixFolding re-queries every collapsed node and each query
    scans one more line through the highlighter. This row is here because
    everything above it measures a file nobody has folded. }
  procedure Collapsed(ASize: Integer; AOpenMs: Double);
  var
    P: Integer;
    S, Pa, Lo, Mid, Hi: Double;
    Sync: TSamples;
  begin
    S := 0; Pa := 0;
    { The command Alt+Shift+1 sends, not the deprecated TCustomSynEdit.FoldAll:
      the same entry point as every other edit here, and the one a person's
      keyboard reaches. }
    OneEdit(EcFoldLevel1, '', S, Pa);
    for P := 1 to Reps do
    begin
      Settle(1, 8);
      OneEdit(ecChar, 'n', S, Pa);
      Sync[P] := S;
      Settle(1, 9);
      OneEdit(ecDeleteLastChar, '', S, Pa);
    end;
    Stats(Sync, Reps, Lo, Mid, Hi);
    Report.Add(Format('collapsed%5d lines   %6.2f min %6.2f med %6.2f max ms   ' +
                      '%.2f x the same edit unfolded',
                      [ASize, Lo, Mid, Hi, Lo / AOpenMs]));
    OneEdit(EcFoldLevel0, '', S, Pa);
  end;

  { HOW MUCH OF IT IS OURS, which is the second of the three things item 19
    says were unknown. The rescan runs the whole highlighter over every line
    below the edit, and ScanFoldLine is one pass over each of those lines -- so
    the share is measurable directly, on the same buffer, in the same binary and
    at the same optimisation level, which is the only way the division means
    anything. Both halves at -O3 or neither. }
  procedure Share(ASize: Integer; ACascadeMs, AQuietMs: Double);
  var
    P, I, Events: Integer;
    T0, T1: Int64;
    FoldUs, TotalUs: Double;
  begin
    Events := 0;
    T0 := ClockTicks;
    for P := 1 to 5 do
      for I := 0 to Ed.Lines.Count - 1 do
        Inc(Events, Length(ScanFoldLine(Ed.Lines[I])));
    T1 := ClockTicks;
    FoldUs := ClockMs(T0, T1) * 1000.0 / (5 * ASize);
    TotalUs := (ACascadeMs - AQuietMs) * 1000.0 / ASize;
    Report.Add(Format('share    %5d lines   the cascade costs %5.2f us per line; ' +
                      'ScanFoldLine is %5.2f us of it (%.0f%%, %d events)',
                      [ASize, TotalUs, FoldUs, 100 * FoldUs / TotalUs, Events div 5]));
    Report.Add('                        the rest is the base highlighter tokenising ' +
               'lines the scan no');
    Report.Add('                        longer stops before -- folding did not make a ' +
               'line dearer,');
    Report.Add('                        it made the number of lines large.');
  end;

var
  I: Integer;
  QuietMin, CascadeMin: Double;
begin
  Application.Flags := Application.Flags + [AppNoExceptionMessages];
  Report := TStringList.Create;
  try
    Failure := '';
    try
      Application.CreateForm(TFrmMain, FrmMain);
      { A REAL WINDOW OR THE WRONG BRANCH. See the header. }
      FrmMain.Show;
      Application.ProcessMessages;

      Ed := FrmMain.ActiveEditor;
      if Ed = nil then
        raise Exception.Create('no active editor');
      if not Ed.HandleAllocated then
        raise Exception.Create('the editor has no handle: every number below ' +
          'would be the chunked idle path and not the keystroke');

      { A WHOLE SET THROWN AWAY BEFORE THE FIRST REAL ONE, AT THE LARGEST SIZE.
        The window has just been shown: the first paints allocate a back buffer,
        the font cache is empty, and the gutter measures itself. Without any
        warm-up the smallest buffer -- measured first -- came back SLOWER per
        keystroke than the largest, which is not a fact about buffers.

        AND THE WARM-UP IS THE HEAVIEST SIZE, not the lightest, because the first
        attempt warmed at 100 lines and the artefact survived: a quiet edit read
        2.4 ms at 100 lines and 0.68 ms at 5000, in that order, for the same
        work. A hundred lines of keystrokes is not enough work to bring a
        desktop CPU up to speed, so what the early rows were measuring was the
        machine still idling. Five thousand is. }
      Fill(Sizes[High(Sizes)]);
      QuietMin := Quiet(Sizes[High(Sizes)]);
      CascadeMin := Cascade(Sizes[High(Sizes)], QuietMin);
      Word(Sizes[High(Sizes)], QuietMin);
      Report.Clear;

      Report.Add(Format('clock: %s, resolution %.1f ns, one read %.1f ns',
        [ClockName, ClockResolutionNs, ClockOverheadNs]));
      Report.Add(Format('editor: handle=%s, folding=%s, %d gutter parts',
        [BoolToStr(Ed.HandleAllocated, True),
         BoolToStr(FrmMain.Highlighter is TSynCustomFoldHighlighter, True),
         FrmMain.GutterPartCount]));
      Report.Add(Format('%d passes each, the first dropped, and one whole set ' +
                        'discarded before any of these', [Reps]));
      Report.Add('');
      Report.Add('quiet    a character typed inside a comment: no block opens or closes.');
      Report.Add('cascade  the `n` that completes `function` on line 1, which opens a');
      Report.Add('         block nothing in the file closes, and the backspace after it.');
      Report.Add('word     all eight keystrokes of `function`, typed one at a time.');
      Report.Add('');

      for I := Low(Sizes) to High(Sizes) do
      begin
        Fill(Sizes[I]);
        QuietMin := Quiet(Sizes[I]);
        CascadeMin := Cascade(Sizes[I], QuietMin);
        Collapsed(Sizes[I], CascadeMin);
        Word(Sizes[I], QuietMin);
        Report.Add('');
      end;
      Share(Sizes[High(Sizes)], CascadeMin, QuietMin);
      Report.Add('');

      if ARealFile <> '' then
      begin
        I := FillFromFile(ARealFile);
        Report.Add(Format('a real program: %s, %d lines',
                          [ExtractFileName(ARealFile), I]));
        QuietMin := Quiet(I);
        CascadeMin := Cascade(I, QuietMin);
        Collapsed(I, CascadeMin);
        Word(I, QuietMin);
        Report.Add('');
      end;

      { WHAT THE SIZES MEAN, because 5000 was chosen by an item and not by
        evidence. Measured 2026-09-17 over every `.bas` in this repository and in
        ../Phosphor: 176 files, median 58 lines, p90 252, and the largest in
        either repository is 872. }
      Report.Add('context: 176 real Phosphor programs across this repository and');
      Report.Add('         ../Phosphor: median 58 lines, p90 252, largest 872.');
      Report.Add('         Nothing anybody has written reaches 1000.');
    except
      on E: Exception do
      begin
        Failure := E.ClassName + ': ' + E.Message;
        Report.Add('FAILED: ' + Failure);
      end;
    end;

    if AReportPath <> '' then
      try
        Report.SaveToFile(AReportPath);
      except
        on E: Exception do
          ;   // the exit code still carries the verdict
      end;

    if Failure = '' then
      Result := 0
    else
      Result := 1;
  finally
    Report.Free;
  end;
end;

begin
  Application.Title := 'PhosphorIDE';
  { The per-user configuration directory is named from the EXECUTABLE, not from
    this title -- GetAppConfigDir asks ApplicationName, which defaults to the
    binary's own name. So settings live in %APPDATA%\phosphoride on Windows and
    ~/.config/phosphoride on Linux for as long as the binary is called
    phosphoride, and renaming the binary moves them. Recorded because it is the
    kind of thing that is discovered by losing a settings file. }
  Application.Scaled := True;
  RequireDerivedFormResource := True;
  Application.Initialize;

  if (ParamCount >= 1) and
     ((ParamStr(1) = '--selftest') or (ParamStr(1) = '--measure-typing')) then
  begin
    if ParamCount >= 2 then
      ReportPath := ParamStr(2)
    else
      ReportPath := '';
    if ParamCount >= 3 then
      RealFile := ParamStr(3)
    else
      RealFile := '';
    if ParamStr(1) = '--selftest' then
      ExitStatus := SelfTest(ReportPath)
    else
      ExitStatus := MeasureTyping(ReportPath, RealFile);
    Halt(ExitStatus);
  end;

  Application.CreateForm(TFrmMain, FrmMain);
  Application.Run;
end.
