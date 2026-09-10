unit uphosphorsettings;

{ What the editor remembers between runs.

  An INI file under the platform's per-user configuration directory, which is
  %APPDATA%\phosphoride\ on Windows and ~/.config/phosphoride/ on Linux. Not the
  registry, and not a file beside the executable: a portable-looking editor that
  writes next to itself fails the moment it is installed into Program Files, and
  that failure is silent.

  Every setting has a default that makes the editor work with nothing configured,
  because the first run happens before there is a file to read. Load never throws:
  a corrupt or half-written settings file leaves the defaults standing, since
  refusing to start over a preferences file is a worse outcome than losing a
  window position.

  HostPath is the interesting one. Empty means "find it" -- the search in
  uphosphorhost runs and whatever it turns up is used, without being written back.
  Writing a discovered path back would freeze a lucky guess into a decision the
  user never made, and the first thing that moves would then be wrong forever. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  MaxRecentFiles = 12;

type
  TPhosphorSettings = class
  private
    FFileName: String;
    FRecent: TStringList;
    function GetRecentCount: Integer;
    function GetRecent(AIndex: Integer): String;
  public
    { The phosphor binary to drive. Empty means "search for one on every start". }
    HostPath: String;

    { Editor appearance. }
    FontName: String;
    FontSize: Integer;
    TabWidth: Integer;
    UseSpaces: Boolean;
    ShowLineNumbers: Boolean;
    HighlightCurrentLine: Boolean;
    RightMargin: Integer;
    DarkTheme: Boolean;

    { Behaviour. }
    SaveBeforeRun: Boolean;
    ClearOutputOnRun: Boolean;
    UseSandbox: Boolean;
    { Where --sandbox points when UseSandbox is on. Empty means the directory the
      script itself is in, which is the only default that is not a surprise. }
    SandboxRoot: String;

    { Window geometry, restored on start. Width = 0 means "never saved yet". }
    WindowLeft, WindowTop, WindowWidth, WindowHeight: Integer;
    WindowMaximised: Boolean;
    OutputPaneHeight: Integer;

    constructor Create(const AFileName: String = '');
    destructor Destroy; override;

    procedure Load;
    procedure Save;
    procedure ResetToDefaults;

    procedure AddRecentFile(const APath: String);
    procedure RemoveRecentFile(const APath: String);
    procedure ClearRecentFiles;

    property FileName: String read FFileName;
    property RecentCount: Integer read GetRecentCount;
    property Recent[AIndex: Integer]: String read GetRecent;
  end;

{ The per-user settings path this program uses. Exposed so the About box can show
  it -- "where does it keep its settings" should not require reading the source. }
function DefaultSettingsFileName: String;

implementation

uses
  IniFiles, LazFileUtils;

function DefaultSettingsFileName: String;
begin
  { GetAppConfigDir(False) already answers per-platform: %APPDATA%\<app>\ on
    Windows, ~/.config/<app>/ on Linux. The application name is set in the .lpr. }
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'phosphoride.ini';
end;

constructor TPhosphorSettings.Create(const AFileName: String);
begin
  inherited Create;
  FRecent := TStringList.Create;
  if AFileName = '' then
    FFileName := DefaultSettingsFileName
  else
    FFileName := AFileName;
  ResetToDefaults;
end;

destructor TPhosphorSettings.Destroy;
begin
  FRecent.Free;
  inherited Destroy;
end;

procedure TPhosphorSettings.ResetToDefaults;
begin
  HostPath := '';

  { A fixed-pitch face that exists on a clean install of each platform. SynEdit
    will fall back to something monospaced if neither is there, but starting from
    a name that is actually present avoids a first impression rendered in a
    proportional font. }
  {$IFDEF WINDOWS}
  FontName := 'Consolas';
  {$ELSE}
  { A fontconfig alias, so it resolves to whatever monospaced face the
    distribution actually installed. A concrete name like 'DejaVu Sans Mono' is
    a guess about someone else's machine. }
  FontName := 'Monospace';
  {$ENDIF}
  FontSize := 10;
  TabWidth := 4;
  UseSpaces := True;
  ShowLineNumbers := True;
  HighlightCurrentLine := True;
  RightMargin := 0;         // off: Phosphor has no line-length convention
  DarkTheme := False;

  SaveBeforeRun := True;
  ClearOutputOnRun := True;
  UseSandbox := False;
  SandboxRoot := '';

  WindowLeft := 0;
  WindowTop := 0;
  WindowWidth := 0;
  WindowHeight := 0;
  WindowMaximised := False;
  OutputPaneHeight := 180;

  FRecent.Clear;
end;

procedure TPhosphorSettings.Load;
var
  Ini: TIniFile;
  I: Integer;
  Path: String;
begin
  if not FileExistsUTF8(FFileName) then
    Exit;
  try
    Ini := TIniFile.Create(FFileName);
    try
      HostPath := Ini.ReadString('host', 'path', HostPath);

      FontName := Ini.ReadString('editor', 'font', FontName);
      FontSize := Ini.ReadInteger('editor', 'fontsize', FontSize);
      TabWidth := Ini.ReadInteger('editor', 'tabwidth', TabWidth);
      UseSpaces := Ini.ReadBool('editor', 'usespaces', UseSpaces);
      ShowLineNumbers := Ini.ReadBool('editor', 'linenumbers', ShowLineNumbers);
      HighlightCurrentLine := Ini.ReadBool('editor', 'currentline', HighlightCurrentLine);
      RightMargin := Ini.ReadInteger('editor', 'rightmargin', RightMargin);
      DarkTheme := Ini.ReadBool('editor', 'dark', DarkTheme);

      SaveBeforeRun := Ini.ReadBool('run', 'savefirst', SaveBeforeRun);
      ClearOutputOnRun := Ini.ReadBool('run', 'clearoutput', ClearOutputOnRun);
      UseSandbox := Ini.ReadBool('run', 'sandbox', UseSandbox);
      SandboxRoot := Ini.ReadString('run', 'sandboxroot', SandboxRoot);

      WindowLeft := Ini.ReadInteger('window', 'left', WindowLeft);
      WindowTop := Ini.ReadInteger('window', 'top', WindowTop);
      WindowWidth := Ini.ReadInteger('window', 'width', WindowWidth);
      WindowHeight := Ini.ReadInteger('window', 'height', WindowHeight);
      WindowMaximised := Ini.ReadBool('window', 'maximised', WindowMaximised);
      OutputPaneHeight := Ini.ReadInteger('window', 'outputheight', OutputPaneHeight);

      FRecent.Clear;
      for I := 1 to MaxRecentFiles do
      begin
        Path := Ini.ReadString('recent', 'file' + IntToStr(I), '');
        if Path <> '' then
          FRecent.Add(Path);
      end;
    finally
      Ini.Free;
    end;
  except
    { A settings file that will not parse is not worth refusing to start over.
      The defaults are already in place; the next Save rewrites the file. }
    on E: Exception do
      ;
  end;
end;

procedure TPhosphorSettings.Save;
var
  Ini: TIniFile;
  I: Integer;
begin
  try
    if not ForceDirectoriesUTF8(ExtractFilePath(FFileName)) then
      Exit;
    Ini := TIniFile.Create(FFileName);
    try
      Ini.WriteString('host', 'path', HostPath);

      Ini.WriteString('editor', 'font', FontName);
      Ini.WriteInteger('editor', 'fontsize', FontSize);
      Ini.WriteInteger('editor', 'tabwidth', TabWidth);
      Ini.WriteBool('editor', 'usespaces', UseSpaces);
      Ini.WriteBool('editor', 'linenumbers', ShowLineNumbers);
      Ini.WriteBool('editor', 'currentline', HighlightCurrentLine);
      Ini.WriteInteger('editor', 'rightmargin', RightMargin);
      Ini.WriteBool('editor', 'dark', DarkTheme);

      Ini.WriteBool('run', 'savefirst', SaveBeforeRun);
      Ini.WriteBool('run', 'clearoutput', ClearOutputOnRun);
      Ini.WriteBool('run', 'sandbox', UseSandbox);
      Ini.WriteString('run', 'sandboxroot', SandboxRoot);

      Ini.WriteInteger('window', 'left', WindowLeft);
      Ini.WriteInteger('window', 'top', WindowTop);
      Ini.WriteInteger('window', 'width', WindowWidth);
      Ini.WriteInteger('window', 'height', WindowHeight);
      Ini.WriteBool('window', 'maximised', WindowMaximised);
      Ini.WriteInteger('window', 'outputheight', OutputPaneHeight);

      Ini.EraseSection('recent');
      for I := 0 to FRecent.Count - 1 do
        Ini.WriteString('recent', 'file' + IntToStr(I + 1), FRecent[I]);

      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      ;
  end;
end;

function TPhosphorSettings.GetRecentCount: Integer;
begin
  Result := FRecent.Count;
end;

function TPhosphorSettings.GetRecent(AIndex: Integer): String;
begin
  Result := FRecent[AIndex];
end;

procedure TPhosphorSettings.AddRecentFile(const APath: String);
begin
  if APath = '' then
    Exit;
  RemoveRecentFile(APath);
  FRecent.Insert(0, APath);
  while FRecent.Count > MaxRecentFiles do
    FRecent.Delete(FRecent.Count - 1);
end;

procedure TPhosphorSettings.RemoveRecentFile(const APath: String);
var
  I: Integer;
begin
  for I := FRecent.Count - 1 downto 0 do
    if CompareFilenames(FRecent[I], APath) = 0 then
      FRecent.Delete(I);
end;

procedure TPhosphorSettings.ClearRecentFiles;
begin
  FRecent.Clear;
end;

end.
