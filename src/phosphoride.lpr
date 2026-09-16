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
  umainform, uaboutform, upreferencesform,
  uphosphorlang, uphosphormsg, uphosphorhost, uphosphorsettings,
  uphosphorrun, usynphosphor, udebugproto, udebugsession, uphosphorcomplete,
  uphosphoricons;

{$IFDEF WINDOWS}
{ A Windows GUI subsystem binary has no console, so WriteLn hits an invalid handle
  and the RTL's I/O error surfaces as a modal dialog nobody is there to dismiss --
  which is a hang, not a message. Measured on 2026-09-10: a --selftest that merely
  wrote its result to stdout hung the process until it was killed. So the selftest
  reports through a FILE and its exit code, and this program writes to a console
  stream nowhere. }
{$ENDIF}

var
  ReportPath: String;

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

  if (ParamCount >= 1) and (ParamStr(1) = '--selftest') then
  begin
    if ParamCount >= 2 then
      ReportPath := ParamStr(2)
    else
      ReportPath := '';
    Halt(SelfTest(ReportPath));
  end;

  Application.CreateForm(TFrmMain, FrmMain);
  Application.Run;
end.
