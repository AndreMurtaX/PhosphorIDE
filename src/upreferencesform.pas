unit upreferencesform;

{ Preferences.

  Two tabs, because there are exactly two kinds of setting here: which phosphor
  binary to drive and how to drive it, and what the editor looks like.

  The host page shows what the search WOULD find when the box is empty, live, as
  the box is typed in. An empty field with a hidden fallback is the setting most
  likely to be wrong without anyone noticing -- "it is using some other phosphor"
  is a question the page should answer before it is asked. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  Spin, uphosphorsettings;

type

  { TFrmPreferences }

  TFrmPreferences = class(TForm)
    BtnBrowseHost: TButton;
    BtnBrowseSandbox: TButton;
    BtnCancel: TButton;
    BtnOK: TButton;
    ChkClearOutput: TCheckBox;
    ChkCurrentLine: TCheckBox;
    ChkDark: TCheckBox;
    ChkLineNumbers: TCheckBox;
    ChkSandbox: TCheckBox;
    ChkSaveBeforeRun: TCheckBox;
    ChkUseSpaces: TCheckBox;
    EditFontName: TEdit;
    EditHostPath: TEdit;
    EditSandboxRoot: TEdit;
    LblFont: TLabel;
    LblHost: TLabel;
    LblHostResolved: TLabel;
    LblRightMargin: TLabel;
    LblSandbox: TLabel;
    LblSize: TLabel;
    LblTabWidth: TLabel;
    OpenDialogHost: TOpenDialog;
    PageControl1: TPageControl;
    SelectDirectoryDialog1: TSelectDirectoryDialog;
    SpinFontSize: TSpinEdit;
    SpinRightMargin: TSpinEdit;
    SpinTabWidth: TSpinEdit;
    TabEditor: TTabSheet;
    TabHost: TTabSheet;
    procedure BtnBrowseHostClick(Sender: TObject);
    procedure BtnBrowseSandboxClick(Sender: TObject);
    procedure ChkSandboxChange(Sender: TObject);
    procedure EditHostPathChange(Sender: TObject);
  private
    FSettings: TPhosphorSettings;
    procedure RefreshHostResolution;
  public
    { Load ASettings into the controls. The object is kept so that a modal result
      of mrOK can write straight back to it -- there is no second copy to drift. }
    procedure Edit(ASettings: TPhosphorSettings);

    { Called by the caller after ShowModal returns mrOK. }
    procedure Apply;
  end;

var
  FrmPreferences: TFrmPreferences;

implementation

{$R *.lfm}

uses
  uphosphorhost;

procedure TFrmPreferences.Edit(ASettings: TPhosphorSettings);
begin
  FSettings := ASettings;
  if FSettings = nil then
    Exit;

  EditHostPath.Text := FSettings.HostPath;
  ChkSaveBeforeRun.Checked := FSettings.SaveBeforeRun;
  ChkClearOutput.Checked := FSettings.ClearOutputOnRun;
  ChkSandbox.Checked := FSettings.UseSandbox;
  EditSandboxRoot.Text := FSettings.SandboxRoot;

  EditFontName.Text := FSettings.FontName;
  SpinFontSize.Value := FSettings.FontSize;
  SpinTabWidth.Value := FSettings.TabWidth;
  ChkUseSpaces.Checked := FSettings.UseSpaces;
  ChkLineNumbers.Checked := FSettings.ShowLineNumbers;
  ChkCurrentLine.Checked := FSettings.HighlightCurrentLine;
  SpinRightMargin.Value := FSettings.RightMargin;
  ChkDark.Checked := FSettings.DarkTheme;

  ChkSandboxChange(nil);
  RefreshHostResolution;
end;

procedure TFrmPreferences.Apply;
begin
  if FSettings = nil then
    Exit;

  FSettings.HostPath := EditHostPath.Text;
  FSettings.SaveBeforeRun := ChkSaveBeforeRun.Checked;
  FSettings.ClearOutputOnRun := ChkClearOutput.Checked;
  FSettings.UseSandbox := ChkSandbox.Checked;
  FSettings.SandboxRoot := EditSandboxRoot.Text;

  FSettings.FontName := EditFontName.Text;
  FSettings.FontSize := SpinFontSize.Value;
  FSettings.TabWidth := SpinTabWidth.Value;
  FSettings.UseSpaces := ChkUseSpaces.Checked;
  FSettings.ShowLineNumbers := ChkLineNumbers.Checked;
  FSettings.HighlightCurrentLine := ChkCurrentLine.Checked;
  FSettings.RightMargin := SpinRightMargin.Value;
  FSettings.DarkTheme := ChkDark.Checked;
end;

procedure TFrmPreferences.RefreshHostResolution;
var
  Cands: TPhosphorHostCandidates;
begin
  Cands := LocateHostCandidates(EditHostPath.Text);
  if Length(Cands) = 0 then
    LblHostResolved.Caption := 'Nothing found. Programs cannot be run or compiled.'
  else
    LblHostResolved.Caption := Format('Will use: %s  (%s)',
      [Cands[0].Path, HostOriginText(Cands[0].Origin)]);
end;

procedure TFrmPreferences.EditHostPathChange(Sender: TObject);
begin
  RefreshHostResolution;
end;

procedure TFrmPreferences.BtnBrowseHostClick(Sender: TObject);
begin
  {$IFDEF WINDOWS}
  OpenDialogHost.Filter := 'phosphor.exe|phosphor.exe|Executables|*.exe|All files|*.*';
  {$ELSE}
  OpenDialogHost.Filter := 'phosphor|phosphor|All files|*';
  {$ENDIF}
  if EditHostPath.Text <> '' then
    OpenDialogHost.FileName := EditHostPath.Text;
  if OpenDialogHost.Execute then
    EditHostPath.Text := OpenDialogHost.FileName;
end;

procedure TFrmPreferences.BtnBrowseSandboxClick(Sender: TObject);
begin
  if EditSandboxRoot.Text <> '' then
    SelectDirectoryDialog1.FileName := EditSandboxRoot.Text;
  if SelectDirectoryDialog1.Execute then
    EditSandboxRoot.Text := SelectDirectoryDialog1.FileName;
end;

procedure TFrmPreferences.ChkSandboxChange(Sender: TObject);
begin
  EditSandboxRoot.Enabled := ChkSandbox.Checked;
  BtnBrowseSandbox.Enabled := ChkSandbox.Checked;
end;

end.
