unit uaboutform;

{ About, which is mostly a diagnostic panel wearing a nice hat.

  The three questions this window exists to answer are all of the "why is it
  behaving like that" kind: WHICH phosphor binary is it driving, WHAT version did
  that binary report, and WHERE are the settings it loaded. Every one of those has
  cost someone an afternoon in some editor or other, and none of them should
  require reading a source file or a config directory to find out. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls;

type

  { TFrmAbout }

  TFrmAbout = class(TForm)
    BtnClose: TButton;
    LblSubtitle: TLabel;
    LblTitle: TLabel;
    MemoDetails: TMemo;
    procedure BtnCloseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  public
    { Fill in what the main window knows. Called before ShowModal. }
    procedure Describe(const AHostPath, AHostVersion, ASettingsPath: String);
  end;

var
  FrmAbout: TFrmAbout;

const
  { Bumped by hand. There is no build number and no git hash baked in: this is a
    source tree, and a version that claims more precision than it has is worse
    than one that admits it is a name. }
  PhosphorIDEVersion = '0.1.1';

implementation

{$R *.lfm}

uses
  uphosphorlang;

procedure TFrmAbout.FormCreate(Sender: TObject);
begin
  LblTitle.Caption := 'PhosphorIDE ' + PhosphorIDEVersion;
end;

procedure TFrmAbout.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TFrmAbout.Describe(const AHostPath, AHostVersion, ASettingsPath: String);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('An editor for Phosphor BASIC. MIT licensed.');
    L.Add('');

    if AHostPath = '' then
    begin
      L.Add('phosphor host:   NOT FOUND');
      L.Add('  Nothing can be run or compiled until one is found. Set the path in');
      L.Add('  Tools > Preferences, put phosphor on PATH, or set $PHOSPHOR_HOST.');
    end
    else
    begin
      L.Add('phosphor host:   ' + AHostPath);
      if AHostVersion <> '' then
        L.Add('  reports:       ' + AHostVersion);
    end;

    L.Add('');
    L.Add('settings file:   ' + ASettingsPath);
    L.Add('');
    L.Add(Format('language tables: %d keywords, %d core built-ins,',
      [PhosphorKeywordCount, PhosphorBuiltinCoreCount]));
    L.Add(Format('                 %d from host packages, %d GUI.',
      [PhosphorBuiltinPackageCount, PhosphorBuiltinGuiCount]));
    L.Add('                 Generated from the Phosphor sources by');
    L.Add('                 tools/gen-keywords.py -- see that file for how.');
    L.Add('');
    L.Add('The interpreter is NOT linked into this program. Every run, compile');
    L.Add('and pack is the phosphor binary above, spawned as a child process, so');
    L.Add('a program that loops forever or faults the interpreter cannot take');
    L.Add('this window down with it.');

    MemoDetails.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

end.
