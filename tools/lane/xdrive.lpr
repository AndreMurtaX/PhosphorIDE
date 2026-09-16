program xdrive;

{ Press keys at an X11 window, from a script on standard input.

  The Ubuntu VM that is this project's Linux half has no xdotool, no xte and no
  ydotool, and installing packages there needs its owner's say-so. It does have
  libXtst, which is all the tooling above is wrapping: XTestFakeKeyEvent asks the
  X server to inject an event at the driver level, so the receiving toolkit cannot
  tell it from a keyboard. That matters -- GTK ignores a synthetic XSendEvent
  (send_event is true on it), which is why the naive approach produces a window
  that visibly has focus and answers nothing.

  Usage:  xdrive <window-id> < script
  where window-id is what `xwininfo -root -tree` prints for the window, and the
  script is one command per line:

      key ctrl+g            one chord; modifiers are shift, ctrl, alt
      type 10               literal characters, each sent by KEYSYM NAME rather
                            than by a shifted keycode, so the layout does not
                            decide what arrives
      wait 400              milliseconds
      raise                 focus and raise the window again

  Exit codes: 0 ran, 1 the display or the window was not usable, 2 a bad script. }

{$mode objfpc}{$H+}

uses
  ctypes, x, xlib, SysUtils, Classes;

{ Not in FPC's x11 package, and one line to declare. libXtst is present on any
  desktop that has an on-screen keyboard or an accessibility stack, which is
  every GNOME install. }
function XTestFakeKeyEvent(dpy: PDisplay; keycode: cuint; is_press: cint;
  delay: culong): cint; cdecl; external 'Xtst';
function XTestFakeMotionEvent(dpy: PDisplay; screen: cint; x, y: cint;
  delay: culong): cint; cdecl; external 'Xtst';
function XTestFakeButtonEvent(dpy: PDisplay; button: cuint; is_press: cint;
  delay: culong): cint; cdecl; external 'Xtst';

var
  Dpy: PDisplay;
  Win: TWindow;

{ THE KEYCODE IS NOT THE WHOLE ANSWER, AND BELIEVING IT COST A RUN. XTest
  injects a KEYCODE, and a keycode is a physical key carrying several symbols at
  different shift LEVELS. XKeysymToKeycode says which key `dollar` lives on and
  says nothing about how to reach it -- on the Brazilian map that key is `4`
  unshifted, so pressing it bare typed `mid4(` where the script said `mid$(`, and
  `quotedbl` came out as an apostrophe the same way. Measured on 2026-09-16,
  under a comment of mine claiming the opposite.

  So the level is asked for too: index 0 is the bare key, 1 is with Shift, 2 and
  3 are the AltGr pair. XKeycodeToKeysym is deprecated in favour of the Xkb call
  and is what FPC's x11 package exports; for reading a level off a key it is
  exact. }
function CodeOf(const AName: String; out AMod: String): TKeyCode;
var
  Sym: TKeySym;
  Level: Integer;
begin
  AMod := '';
  Sym := XStringToKeysym(PChar(AName));
  if Sym = 0 then
  begin
    WriteLn(StdErr, 'xdrive: no keysym called ', AName);
    Halt(2);
  end;
  Result := XKeysymToKeycode(Dpy, Sym);
  if Result = 0 then
  begin
    WriteLn(StdErr, 'xdrive: keysym ', AName, ' is not on this keyboard map');
    Halt(2);
  end;
  for Level := 0 to 3 do
    if XKeycodeToKeysym(Dpy, Result, Level) = Sym then
    begin
      case Level of
        1: AMod := 'Shift_L';
        2, 3: AMod := 'ISO_Level3_Shift';
      end;
      Exit;
    end;
  { On the key but at no level this knows. Saying so beats typing whatever the
    bare key happens to carry. }
  WriteLn(StdErr, 'xdrive: keysym ', AName,
          ' is on a shift level this driver cannot reach');
  Halt(2);
end;

function PlainCodeOf(const AName: String): TKeyCode;
var
  Ignored: String;
begin
  Result := CodeOf(AName, Ignored);
end;

procedure Tap(const AName: String; const AMods: array of String);
var
  I: Integer;
  ModCodes: array of TKeyCode;
  Code: TKeyCode;
  Needed: String;
begin
  Code := CodeOf(AName, Needed);
  SetLength(ModCodes, Length(AMods));
  for I := 0 to High(AMods) do
    ModCodes[I] := PlainCodeOf(AMods[I]);
  { The level the symbol sits at is a modifier the CALLER did not ask for and
    cannot know: `type $` says nothing about Shift, and on one keyboard it needs
    it and on another it does not. }
  if Needed <> '' then
  begin
    SetLength(ModCodes, Length(ModCodes) + 1);
    ModCodes[High(ModCodes)] := PlainCodeOf(Needed);
  end;

  for I := 0 to High(ModCodes) do
    XTestFakeKeyEvent(Dpy, ModCodes[I], 1, 0);
  { A BEAT BETWEEN THE MODIFIER AND THE KEY. GTK arms a menu bar's mnemonics on
    seeing Alt, and Alt+D delivered in the same millisecond reached the editor as
    a literal `d` instead of opening the Debug menu -- measured on 2026-09-16
    under gtk2, where the same chord works first time on Windows. }
  if Length(ModCodes) > 0 then
  begin
    XFlush(Dpy);
    Sleep(60);
  end;
  XTestFakeKeyEvent(Dpy, Code, 1, 0);
  XTestFakeKeyEvent(Dpy, Code, 0, 0);
  { Released in reverse, which costs nothing and is what a hand does. }
  for I := High(ModCodes) downto 0 do
    XTestFakeKeyEvent(Dpy, ModCodes[I], 0, 0);
  XFlush(Dpy);
  Sleep(40);
end;

{ 'ctrl+shift+g' -> mods ['Control_L','Shift_L'], key 'g'. The X names are the
  long ones; the script gets to use the short ones. }
procedure Chord(const ASpec: String);
var
  Parts: TStringList;
  Mods: array of String;
  I: Integer;
  Part: String;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := '+';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := ASpec;
    if Parts.Count = 0 then
      Exit;
    SetLength(Mods, 0);
    for I := 0 to Parts.Count - 2 do
    begin
      Part := LowerCase(Trim(Parts[I]));
      SetLength(Mods, Length(Mods) + 1);
      if Part = 'shift' then Mods[High(Mods)] := 'Shift_L'
      else if Part = 'ctrl' then Mods[High(Mods)] := 'Control_L'
      else if Part = 'alt' then Mods[High(Mods)] := 'Alt_L'
      else
      begin
        WriteLn(StdErr, 'xdrive: unknown modifier ', Part);
        Halt(2);
      end;
    end;
    Tap(Trim(Parts[Parts.Count - 1]), Mods);
  finally
    Parts.Free;
  end;
end;

{ Enough of a keyboard for line numbers and file names. A character this does not
  know is a script error rather than a silent skip: a driver that quietly drops a
  keystroke produces a test that fails somewhere else. }
procedure TypeText(const AText: String);
var
  I: Integer;
  C: Char;
begin
  for I := 1 to Length(AText) do
  begin
    C := AText[I];
    if C in ['a'..'z', '0'..'9'] then
      Tap(C, [])
    else if C in ['A'..'Z'] then
      { By its own keysym -- `A` is a keysym, and CodeOf works out that it needs
        Shift. Naming Shift here as well would press it twice, which is
        harmless, but the point is that the caller does not have to know. }
      Tap(C, [])
    else if C = ' ' then
      Tap('space', [])
    else if C = '.' then
      Tap('period', [])
    else if C = '/' then
      Tap('slash', [])
    else if C = '_' then
      Tap('underscore', [])
    else if C = '-' then
      Tap('minus', [])
    { BY KEYSYM NAME, and CodeOf works out which shift level it is on -- see
      there for why naming the keysym alone was not enough. The Windows side of
      this lane has the mirror-image problem: SendKeys types CHARACTERS, and on
      the same Brazilian layout a `"` is a DEAD KEY that composes with the vowel
      after it and eats both. }
    else if C = '(' then
      Tap('parenleft', [])
    else if C = ')' then
      Tap('parenright', [])
    else if C = '"' then
      Tap('quotedbl', [])
    else if C = ',' then
      Tap('comma', [])
    else if C = '=' then
      Tap('equal', [])
    else if C = '$' then
      Tap('dollar', [])
    else if C = '%' then
      Tap('percent', [])
    else if C = '+' then
      Tap('plus', [])
    else if C = ':' then
      Tap('colon', [])
    else if C = ';' then
      Tap('semicolon', [])
    else if C = '*' then
      Tap('asterisk', [])
    else if C = '/' then
      Tap('slash', [])
    else if C = '?' then
      Tap('question', [])
    else if C = '@' then
      Tap('at', [])
    else if C = '<' then
      Tap('less', [])
    else if C = '>' then
      Tap('greater', [])
    else if C = '#' then
      Tap('numbersign', [])
    else
    begin
      WriteLn(StdErr, 'xdrive: cannot type ', C);
      Halt(2);
    end;
    Sleep(25);
  end;
end;

{ Absolute screen coordinates, because that is what xwininfo reports and what a
  screenshot is measured in. `click 25 771` is the same arithmetic on both
  platforms. }
procedure ClickAt(AX, AY: Integer; ATwice: Boolean);
begin
  XTestFakeMotionEvent(Dpy, -1, AX, AY, 0);
  XFlush(Dpy);
  Sleep(120);
  XTestFakeButtonEvent(Dpy, 1, 1, 0);
  XTestFakeButtonEvent(Dpy, 1, 0, 0);
  if ATwice then
  begin
    { Inside any sane double-click interval, and the flush matters: two presses
      delivered in one batch can reach the toolkit as one. }
    XFlush(Dpy);
    Sleep(80);
    XTestFakeButtonEvent(Dpy, 1, 1, 0);
    XTestFakeButtonEvent(Dpy, 1, 0, 0);
  end;
  XFlush(Dpy);
  Sleep(250);
end;

procedure RaiseWindow;
begin
  XRaiseWindow(Dpy, Win);
  XSetInputFocus(Dpy, Win, RevertToParent, CurrentTime);
  XSync(Dpy, False);
  Sleep(250);
end;

var
  Line, Cmd, Arg: String;
  P: Integer;
begin
  if ParamCount < 1 then
  begin
    WriteLn(StdErr, 'usage: xdrive <window-id> < script');
    Halt(2);
  end;

  Dpy := XOpenDisplay(nil);
  if Dpy = nil then
  begin
    WriteLn(StdErr, 'xdrive: cannot open the display. DISPLAY and XAUTHORITY?');
    Halt(1);
  end;
  Win := TWindow(StrToInt64(ParamStr(1)));

  { `nofocus` because a GTK menu holds a keyboard grab, and XSetInputFocus on the
    form takes it away -- so the invocation that was supposed to click a menu ROW
    closed the menu instead. Measured on 2026-09-16, twice, each time reading as
    "the menu never opened". }
  if (ParamCount < 2) or (ParamStr(2) <> 'nofocus') then
    RaiseWindow;

  while not Eof(Input) do
  begin
    ReadLn(Input, Line);
    Line := Trim(Line);
    if (Line = '') or (Line[1] = '#') then
      Continue;
    P := Pos(' ', Line);
    if P = 0 then
    begin
      Cmd := Line;
      Arg := '';
    end
    else
    begin
      Cmd := Copy(Line, 1, P - 1);
      Arg := Trim(Copy(Line, P + 1, Length(Line)));
    end;

    if Cmd = 'key' then
      Chord(Arg)
    else if Cmd = 'type' then
      TypeText(Arg)
    else if Cmd = 'wait' then
      Sleep(StrToIntDef(Arg, 0))
    else if (Cmd = 'click') or (Cmd = 'dblclick') then
    begin
      P := Pos(' ', Arg);
      if P = 0 then
      begin
        WriteLn(StdErr, 'xdrive: ', Cmd, ' needs two coordinates');
        Halt(2);
      end;
      ClickAt(StrToIntDef(Copy(Arg, 1, P - 1), 0),
              StrToIntDef(Trim(Copy(Arg, P + 1, Length(Arg))), 0),
              Cmd = 'dblclick');
    end
    else if Cmd = 'raise' then
      RaiseWindow
    else if Cmd = 'echo' then
      WriteLn(Arg)
    else
    begin
      WriteLn(StdErr, 'xdrive: unknown command ', Cmd);
      Halt(2);
    end;
  end;

  XCloseDisplay(Dpy);
end.
