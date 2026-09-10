unit uphosphorrun;

{ Running the phosphor host as a child process without ever blocking the UI.

  THE SHAPE, AND WHY IT IS THIS SHAPE.

  One thread per pipe -- two readers and a writer -- plus a timer on the main
  thread that drains what the readers collected. Not the obvious single-threaded
  `while Running do if NumBytesAvailable > 0 then Read`, and not one thread
  reading both pipes:

  - ONE THREAD READING BOTH PIPES DEADLOCKS. A blocking read on stdout does not
    return while the child is writing to stderr, and once the stderr pipe's buffer
    fills the child blocks on the write -- so neither side moves again. The child
    that provokes this is an ordinary one: a program that prints a lot and then
    fails. Two threads, each blocked on its own pipe, cannot get into that state.

  - POLLING NumBytesAvailable WORKS BUT LIES ABOUT WHEN THE CHILD IS DONE. It
    also spends the interval asleep, so output arrives in visible jerks. A
    blocking read delivers the moment the child writes.

  - AND THE UI THREAD MUST NOT WRITE STDIN EITHER, for the mirror-image reason: a
    pipe write blocks when its 1 KB buffer is full, which is what happens after a
    couple of dozen sends to a program that is not reading. TPipeWriterThread has
    the details; the short version is that the editor would be hung by the program
    it exists to stay outside of.

  The threads never touch the LCL. They append bytes to a guarded buffer, and
  DrainTimer -- on the main thread, where the VCL/LCL rule is that the UI is
  touched from one thread only -- turns those bytes into whole lines and fires the
  events. No TThread.Synchronize, no TThread.Queue: a timer that drains a buffer
  has one obvious order of operations and no re-entrancy to reason about.

  LINES, NOT BYTES. A pipe read returns whatever happened to be in the buffer, so
  a single read can end mid-line and a diagnostic can arrive in two pieces. Every
  consumer here wants lines -- the output pane appends them, the diagnostic parser
  matches them whole -- so the partial tail is held until its newline arrives, and
  flushed unterminated only when the stream ends. A parser fed half of
  `phosphor: x.bas:2: unexpected token` finds no error at all.

  ENCODING IS A NON-EVENT, DELIBERATELY. The host emits UTF-8 and the LCL wants
  UTF-8, so the bytes are passed through untouched. Any "helpful" conversion here
  (SysToUTF8, CP1252 round-trips) would corrupt exactly the strings Phosphor is
  careful about. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ExtCtrls, Process, UTF8Process, syncobjs;

type
  TRunStream = (rsStdOut, rsStdErr);

  { ACompleteLine is False for a PROMPT: text the child wrote without a newline
    and then stopped, because it is waiting for the answer. The consumer must
    show it now and append whatever comes next to the same line -- and must not
    try to parse it as a diagnostic, because it is not a whole line yet. }
  TRunOutputEvent = procedure(Sender: TObject; AKind: TRunStream;
    const AText: String; ACompleteLine: Boolean) of object;
  TRunFinishedEvent = procedure(Sender: TObject; AExitCode: Integer;
    AKilled: Boolean) of object;
  TRunFailedEvent = procedure(Sender: TObject; const AReason: String) of object;

  TPhosphorRunner = class;

  { One blocking reader. Owns nothing; it reads until the pipe reports end of
    file, which happens when the child exits, and then finishes. }
  TPipeReaderThread = class(TThread)
  private
    FRunner: TPhosphorRunner;
    FStream: TStream;
    FKind: TRunStream;
  protected
    procedure Execute; override;
  public
    constructor Create(ARunner: TPhosphorRunner; AStream: TStream; AKind: TRunStream);
  end;

  { The writer. THE UI THREAD MUST NOT WRITE TO THE CHILD'S STDIN.

    A pipe write blocks when the buffer is full, and fcl-process gives the pipe
    1024 bytes by default. A program that is not reading -- most of them, most of
    the time -- fills that after a couple of dozen sends, and the next write parks
    the main thread inside SendInput. The window stops repainting, Stop stops
    working, and the only way out is the task manager: the editor is hung by the
    program it was supposed to be safely outside of.

    So SendInput hands the text to this thread and returns. A full pipe stalls the
    writer, which is a thread nobody is looking at. }
  TPipeWriterThread = class(TThread)
  private
    FRunner: TPhosphorRunner;
    FStream: TStream;
    FWake: TSimpleEvent;
    FLock: TCriticalSection;
    FQueue: String;          // guarded by FLock
    FCloseWhenDrained: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ARunner: TPhosphorRunner; AStream: TStream);
    destructor Destroy; override;
    procedure Post(const AText: String);
    procedure RequestClose;
    procedure Stop;
  end;

  { TPhosphorRunner }

  TPhosphorRunner = class(TComponent)
  private
    FProcess: TProcessUTF8;
    FOut: TPipeReaderThread;
    FErr: TPipeReaderThread;
    FIn: TPipeWriterThread;
    FTimer: TTimer;
    FLock: TCriticalSection;

    FPendingOut: String;    // guarded by FLock: bytes the threads have read
    FPendingErr: String;
    FPartialOut: String;    // main thread only: a line without its newline yet
    FPartialErr: String;
    { How many drain ticks each stream has gone without new bytes while holding an
      unterminated line. A prompt is exactly that: `print "name? "` and then a
      wait. Holding it until the newline arrives shows the question AFTER the
      answer, which is worse than useless -- measured 2026-09-10 against a program
      whose first line is a LINE INPUT. }
    FIdleOut: Integer;
    FIdleErr: Integer;

    FKilled: Boolean;
    FExitCode: Integer;
    FCommandLine: String;

    FOnOutput: TRunOutputEvent;
    FOnFinished: TRunFinishedEvent;
    FOnStartFailed: TRunFailedEvent;

    procedure Deposit(AKind: TRunStream; const AText: String);
    procedure FlushPrompt(AKind: TRunStream; var APartial: String;
      var AIdleTicks: Integer);
    procedure DrainTimer(Sender: TObject);
    procedure EmitLines(AKind: TRunStream; var APartial: String;
      const AChunk: String; AFlush: Boolean);
    procedure Cleanup;
    function GetRunning: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Spawn AExe with AArgs. Answers False and fires OnStartFailed when the child
      could not be started at all -- a missing binary, a directory, no permission.
      A child that starts and then fails is not a start failure: that is an exit
      code, and it arrives through OnFinished. }
    function Start(const AExe: String; const AArgs: array of String;
      const AWorkDir: String): Boolean;

    { Write one line to the child's standard input, with a line terminator. What a
      program reads with INPUT, LINE INPUT or INPUT$. }
    procedure SendInput(const ALine: String);

    { Close the child's standard input. A program blocked in INPUT sees end of
      input; INPUT reads as empty from then on. }
    procedure CloseInput;

    { Kill the child. On Windows this is TerminateProcess, which does not walk a
      process tree -- the phosphor host spawns nothing, so there is no tree, but a
      packed executable that shells out would leave its own children behind. }
    procedure Kill;

    property Running: Boolean read GetRunning;
    property ExitCode: Integer read FExitCode;
    property CommandLine: String read FCommandLine;

    property OnOutput: TRunOutputEvent read FOnOutput write FOnOutput;
    property OnFinished: TRunFinishedEvent read FOnFinished write FOnFinished;
    property OnStartFailed: TRunFailedEvent read FOnStartFailed write FOnStartFailed;
  end;

implementation

{$IFDEF UNIX}
uses
  BaseUnix;
{$ENDIF}

const
  { How often the main thread turns collected bytes into lines. Small enough that
    output feels live, large enough that a program printing in a tight loop does
    not spend the UI's whole budget on repaints. }
  DrainIntervalMs = 40;

  ReadBufferSize = 4096;

  { Drain ticks a stream may hold an unterminated line before it is shown anyway.
    Two is ~80 ms: long enough that a program printing a line in several writes is
    not split across two visual lines, short enough that a prompt appears before
    anyone has finished reading it. }
  IdleTicksBeforePrompt = 2;

{ ---------------------------------------------------------------- the reader - }

constructor TPipeReaderThread.Create(ARunner: TPhosphorRunner; AStream: TStream;
  AKind: TRunStream);
begin
  FRunner := ARunner;
  FStream := AStream;
  FKind := AKind;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TPipeReaderThread.Execute;
var
  Buffer: array[0..ReadBufferSize - 1] of Byte;
  Count: LongInt;
  Chunk: String;
begin
  Chunk := '';
  FillChar(Buffer{%H-}, SizeOf(Buffer), 0);
  while not Terminated do
  begin
    try
      Count := FStream.Read(Buffer[0], SizeOf(Buffer));
    except
      { The pipe went away under us -- the child was killed mid-read. Not an
        error to report; the exit code is the story. }
      Break;
    end;
    if Count <= 0 then
      Break;
    SetLength(Chunk, Count);
    Move(Buffer[0], Chunk[1], Count);
    FRunner.Deposit(FKind, Chunk);
  end;
end;

{ ---------------------------------------------------------------- the writer - }

constructor TPipeWriterThread.Create(ARunner: TPhosphorRunner; AStream: TStream);
begin
  FRunner := ARunner;
  FStream := AStream;
  FQueue := '';
  FCloseWhenDrained := False;
  FLock := TCriticalSection.Create;
  FWake := TSimpleEvent.Create;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TPipeWriterThread.Destroy;
begin
  inherited Destroy;
  FWake.Free;
  FLock.Free;
end;

procedure TPipeWriterThread.Post(const AText: String);
begin
  FLock.Acquire;
  try
    FQueue := FQueue + AText;
  finally
    FLock.Release;
  end;
  FWake.SetEvent;
end;

procedure TPipeWriterThread.RequestClose;
begin
  FLock.Acquire;
  try
    FCloseWhenDrained := True;
  finally
    FLock.Release;
  end;
  FWake.SetEvent;
end;

procedure TPipeWriterThread.Stop;
begin
  Terminate;
  FWake.SetEvent;
end;

procedure TPipeWriterThread.Execute;
var
  Chunk: String;
  Closing: Boolean;
begin
  Chunk := '';
  while not Terminated do
  begin
    { A one-second cap rather than an infinite wait, so a thread whose event was
      set and cleared in a race still notices Terminate. }
    FWake.WaitFor(1000);
    FWake.ResetEvent;

    FLock.Acquire;
    try
      Chunk := FQueue;
      FQueue := '';
      Closing := FCloseWhenDrained;
    finally
      FLock.Release;
    end;

    if (Chunk <> '') and (FStream <> nil) then
      try
        { THIS is the call that may block, and it blocks HERE. }
        FStream.WriteBuffer(Chunk[1], Length(Chunk));
      except
        { The child closed its input or exited. On Unix the write returns EPIPE
          because SIGPIPE is ignored (see TPhosphorRunner.Create); on Windows it
          is ERROR_NO_DATA. Either way there is nothing to report: the run's
          outcome is its exit code. }
        on E: Exception do
          FStream := nil;
      end;

    if Closing then
      Break;
  end;
end;

{ ---------------------------------------------------------------- the runner - }

constructor TPhosphorRunner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  {$IFDEF UNIX}
  { WRITING TO A PIPE WHOSE READER IS GONE RAISES SIGPIPE, AND THE DEFAULT
    DISPOSITION OF SIGPIPE IS TO TERMINATE THE PROCESS.

    Which process? THIS one -- the editor. The window, the tabs and every unsaved
    buffer, killed by a signal, because the user pressed Send a moment after the
    program they were answering happened to finish. There is no exception to catch
    and nothing in the except block below would ever run.

    Ignored here rather than in the .lpr, because this is the unit that owns the
    only pipe the editor writes to. SIG_IGN turns the signal into an ordinary
    EPIPE error return, which the write below already handles by doing nothing. }
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}

  FLock := TCriticalSection.Create;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := DrainIntervalMs;
  FTimer.OnTimer := @DrainTimer;
  FExitCode := 0;
end;

destructor TPhosphorRunner.Destroy;
begin
  if (FProcess <> nil) and FProcess.Running then
    Kill;
  Cleanup;
  FLock.Free;
  inherited Destroy;
end;

function TPhosphorRunner.GetRunning: Boolean;
begin
  { The drain timer counts. A child can exit up to one tick before DrainTimer
    notices, and in that window the process is gone but the run is NOT over: the
    last output has not been delivered and OnFinished has not fired. Reporting
    "not running" there lets the UI enable Run, and a second Start then replaces
    FProcess before the first run is finalised -- so the first run's OnFinished
    never arrives, its final lines are dropped, and a compile-then-pack chain
    stops halfway with no message. A run is over when the drain says so. }
  Result := ((FProcess <> nil) and FProcess.Running) or FTimer.Enabled;
end;

function TPhosphorRunner.Start(const AExe: String; const AArgs: array of String;
  const AWorkDir: String): Boolean;
var
  I: Integer;
begin
  Result := False;

  if Running then
  begin
    if Assigned(FOnStartFailed) then
      FOnStartFailed(Self, 'a program is already running');
    Exit;
  end;

  Cleanup;
  FKilled := False;
  FExitCode := 0;
  FPartialOut := '';
  FPartialErr := '';
  FPendingOut := '';
  FPendingErr := '';
  FIdleOut := 0;
  FIdleErr := 0;

  FCommandLine := AExe;
  for I := Low(AArgs) to High(AArgs) do
    FCommandLine := FCommandLine + ' ' + AArgs[I];

  { TProcessUTF8, not TProcess. On Windows TProcess.Executable is an AnsiString
    that fcl-process converts for CreateProcessW through the SYSTEM code page,
    which is 1252 here and not UTF-8 -- so a path holding a non-ASCII character
    is mangled before the OS ever sees it, and the answer is `file not found`
    for a file that is plainly there. TProcessUTF8 does the conversion the
    LCL's way. On Linux it is a pass-through. }
  FProcess := TProcessUTF8.Create(nil);
  try
    FProcess.Executable := AExe;
    for I := Low(AArgs) to High(AArgs) do
      FProcess.Parameters.Add(AArgs[I]);
    if AWorkDir <> '' then
      FProcess.CurrentDirectory := AWorkDir;

    { poUsePipes gives all three streams. poNoConsole keeps Windows from flashing
      a console window for a console child; the child's output comes down the
      pipes either way, and a window nobody asked for is the difference between a
      tool and a nuisance. }
    FProcess.Options := [poUsePipes];
    {$IFDEF WINDOWS}
    { Both are Windows-only in effect and keep a console child from flashing a
      window; the output comes down the pipes either way. On Linux a GUI parent
      has no console to give away, so neither has anything to do. }
    FProcess.Options := FProcess.Options + [poNoConsole];
    FProcess.ShowWindow := swoHide;
    {$ENDIF}

    FProcess.Execute;
  except
    on E: Exception do
    begin
      FreeAndNil(FProcess);
      if Assigned(FOnStartFailed) then
        FOnStartFailed(Self, E.Message);
      Exit;
    end;
  end;

  FOut := TPipeReaderThread.Create(Self, FProcess.Output, rsStdOut);
  FErr := TPipeReaderThread.Create(Self, FProcess.Stderr, rsStdErr);
  FIn := TPipeWriterThread.Create(Self, FProcess.Input);
  FTimer.Enabled := True;
  Result := True;
end;

procedure TPhosphorRunner.Deposit(AKind: TRunStream; const AText: String);
begin
  { Called from a reader thread. Touches nothing but the buffer. }
  FLock.Acquire;
  try
    if AKind = rsStdOut then
      FPendingOut := FPendingOut + AText
    else
      FPendingErr := FPendingErr + AText;
  finally
    FLock.Release;
  end;
end;

procedure TPhosphorRunner.EmitLines(AKind: TRunStream; var APartial: String;
  const AChunk: String; AFlush: Boolean);
var
  Buf, Line: String;
  P: Integer;
begin
  Buf := APartial + AChunk;
  APartial := '';

  P := Pos(#10, Buf);
  while P > 0 do
  begin
    Line := Copy(Buf, 1, P - 1);
    { A CRLF pipe leaves the CR on the line. Dropping it here means every consumer
      downstream -- the output pane, the diagnostic parser -- sees the same thing
      on both platforms. }
    if (Line <> '') and (Line[Length(Line)] = #13) then
      SetLength(Line, Length(Line) - 1);
    if Assigned(FOnOutput) then
      FOnOutput(Self, AKind, Line, True);
    Delete(Buf, 1, P);
    P := Pos(#10, Buf);
  end;

  if AFlush then
  begin
    { The stream ended without a final newline. `phosphor --version` does end with
      one, but a program that ends with PRINT rather than PRINTLN does not, and
      dropping its last line would be a silent loss. }
    if Buf <> '' then
    begin
      if (Buf <> '') and (Buf[Length(Buf)] = #13) then
        SetLength(Buf, Length(Buf) - 1);
      { The stream has ended, so this IS the whole line -- there is nothing left
        to append to it. }
      if Assigned(FOnOutput) then
        FOnOutput(Self, AKind, Buf, True);
    end;
  end
  else
    APartial := Buf;
end;

procedure TPhosphorRunner.FlushPrompt(AKind: TRunStream; var APartial: String;
  var AIdleTicks: Integer);
begin
  if (APartial = '') or (AIdleTicks < IdleTicksBeforePrompt) then
    Exit;
  if Assigned(FOnOutput) then
    FOnOutput(Self, AKind, APartial, False);
  { Cleared, not kept: whatever arrives next continues the same visual line, and
    the consumer knows that because the emission above said ACompleteLine=False. }
  APartial := '';
  AIdleTicks := 0;
end;

procedure TPhosphorRunner.DrainTimer(Sender: TObject);
var
  ChunkOut, ChunkErr: String;
  ReadersDone, ProcDone: Boolean;
begin
  { ORDER MATTERS, and it is the opposite of the obvious one. Ask whether the
    readers have finished BEFORE taking what they left, never after: a reader that
    deposits a chunk between the sampling and the question, and then finishes, has
    its last bytes sitting in the buffer while this method concludes that
    everything has arrived -- and the timer stops with them still there. Asking
    first is safe in the other direction: if the readers were done a moment ago,
    nothing can be added afterwards. }
  ReadersDone := ((FOut = nil) or FOut.Finished) and ((FErr = nil) or FErr.Finished);
  ProcDone := (FProcess = nil) or (not FProcess.Running);

  FLock.Acquire;
  try
    ChunkOut := FPendingOut;
    ChunkErr := FPendingErr;
    FPendingOut := '';
    FPendingErr := '';
  finally
    FLock.Release;
  end;

  { The last drain flushes any unterminated tail. Both conditions matter: the
    child can have exited while a reader still has buffered bytes to hand over,
    and a reader can finish while the child is still winding down. }
  if ChunkOut = '' then
    Inc(FIdleOut)
  else
    FIdleOut := 0;
  if ChunkErr = '' then
    Inc(FIdleErr)
  else
    FIdleErr := 0;

  EmitLines(rsStdOut, FPartialOut, ChunkOut, ReadersDone and ProcDone);
  EmitLines(rsStdErr, FPartialErr, ChunkErr, ReadersDone and ProcDone);

  if not (ReadersDone and ProcDone) then
  begin
    { Still running, and one of the streams has been sitting on an unterminated
      line. That is what a prompt looks like from out here. }
    FlushPrompt(rsStdOut, FPartialOut, FIdleOut);
    FlushPrompt(rsStdErr, FPartialErr, FIdleErr);
    Exit;
  end;

  FTimer.Enabled := False;
  if FProcess <> nil then
    { ExitCode, not ExitStatus. On Unix ExitStatus is the RAW wait status, so a
      program that exited 1 reads back as 256 and a program killed by a signal
      reads back as the signal number -- and the status bar would then explain
      exit code 256 to a user whose program failed with 1. ExitCode is the decoded
      one, and on Windows the two are the same. }
    FExitCode := FProcess.ExitCode;
  Cleanup;

  if Assigned(FOnFinished) then
    FOnFinished(Self, FExitCode, FKilled);
end;

procedure TPhosphorRunner.SendInput(const ALine: String);
begin
  { Queued, never written from here. See TPipeWriterThread's header: a 1 KB pipe
    that the child is not reading turns a write on this thread into a frozen
    editor. }
  if (FIn = nil) or (FProcess = nil) or (not FProcess.Running) then
    Exit;
  FIn.Post(ALine + LineEnding);
end;

procedure TPhosphorRunner.CloseInput;
begin
  { Drains what is queued first, then closes. Closing underneath a queued line
    would lose the answer the user has already typed. }
  if FIn <> nil then
    FIn.RequestClose;
end;

procedure TPhosphorRunner.Kill;
begin
  if (FProcess = nil) or (not FProcess.Running) then
    Exit;
  FKilled := True;
  try
    FProcess.Terminate(1);
  except
    on E: Exception do
      ;
  end;
end;

procedure TPhosphorRunner.Cleanup;
begin
  { THE WRITER GOES FIRST, and the child's input is closed before waiting on it:
    a writer parked inside a blocking write would never see Terminate, and WaitFor
    would then hang the main thread -- the exact failure the writer thread exists
    to prevent, moved one place along. Closing the pipe makes that write fail
    instead. }
  if FIn <> nil then
  begin
    FIn.Stop;
    if FProcess <> nil then
      try
        FProcess.CloseInput;
      except
        on E: Exception do
          ;
      end;
    FIn.WaitFor;
    FreeAndNil(FIn);
  end;

  { The reader threads end on their own when their pipes report end of file, which
    the child's exit guarantees. Terminate is set anyway so that a reader still
    blocked on a pipe that never closes is asked to stop, and WaitFor makes the
    handover explicit rather than leaving a thread reading a stream this method is
    about to free. }
  if FOut <> nil then
  begin
    FOut.Terminate;
    FOut.WaitFor;
    FreeAndNil(FOut);
  end;
  if FErr <> nil then
  begin
    FErr.Terminate;
    FErr.WaitFor;
    FreeAndNil(FErr);
  end;
  FreeAndNil(FProcess);
end;

end.
