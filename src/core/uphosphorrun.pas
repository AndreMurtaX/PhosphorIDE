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
  {$IFDEF WINDOWS}
  Windows,      // SetHandleInformation; see MakeHandlePrivate
  {$ENDIF}
  {$IFDEF UNIX}
  BaseUnix,     // FpFcntl and F_SetFd, same reason
  {$ENDIF}
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
    { CloseInput was asked for and the writer thread has not finished yet; and
      the handle has since been closed. Two flags rather than one because
      "asked" and "done" are different answers to the caller. }
    FCloseInputPending: Boolean;
    FInputClosed: Boolean;

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
    function GetInputOpen: Boolean;
    function GetHandlesArePrivate: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Drain the child's output NOW rather than at the next tick.

      There are two timers in this program and nothing orders them. Measured on
      2026-09-16: a breakpoint stop arrived on the debug socket and was printed
      ABOVE the PRINT output of the lines that led to it, because the socket tick
      fell between the child writing and this timer reading. The debug tick
      therefore drains here first and the transcript reads in the order the
      program produced it.

      Does nothing when no run is in flight, so a caller cannot manufacture an
      OnFinished for a child that was never started. }
    procedure Drain;

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
    { Ask the child to see end-of-input. It does NOT close the handle here: the
      writer thread may be parked inside a blocking WriteBuffer, and closing the
      stream under it is a free while a worker is using it. The close happens on
      the next drain tick, once that thread has actually finished -- so this is a
      REQUEST, and InputOpen is how a caller knows it has been granted. }
    procedure CloseInput;

    { Kill the child. On Windows this is TerminateProcess, which does not walk a
      process tree -- the phosphor host spawns nothing, so there is no tree, but a
      packed executable that shells out would leave its own children behind. }
    procedure Kill;

    { False once the child's stdin has actually been closed. A caller that offers
      "end the session" twice uses this to tell the first press from the second:
      the first asks, and if nothing happens the second may insist. }
    property InputOpen: Boolean read GetInputOpen;

    { Were this run's three pipe handles taken out of the set a LATER child
      inherits? Only the test asks. It is a property and not a hidden detail
      because deleting the one line in Start that does it is otherwise a silent
      regression whose only symptom is a REPL that will not end. }
    property HandlesArePrivate: Boolean read GetHandlesArePrivate;

    property Running: Boolean read GetRunning;
    property ExitCode: Integer read FExitCode;
    property CommandLine: String read FCommandLine;

    property OnOutput: TRunOutputEvent read FOnOutput write FOnOutput;
    property OnFinished: TRunFinishedEvent read FOnFinished write FOnFinished;
    property OnStartFailed: TRunFailedEvent read FOnStartFailed write FOnStartFailed;
  end;

{ Take one handle out of the set a LATER child process inherits, and read the
  flag back.

  Free functions rather than methods because `tests/phosphoridetest.lpr` has to
  be able to call them, and it cannot construct a TPhosphorRunner: Create builds
  a TTimer, and that program links the LCL without ever creating a widgetset.
  A pipe it opens itself is all they need. }
function MakeHandlePrivate(AHandle: THandle): Boolean;
function HandleIsPrivate(AHandle: THandle): Boolean;

implementation

{ BaseUnix is in the INTERFACE's uses now, for MakeHandlePrivate. It used to be
  here, for the SIGPIPE call in Create, and having it in both is `Duplicate
  identifier "BaseUnix"` -- an error that only exists on Unix, so a Windows
  build is perfectly happy with it. Measured on the VM on 2026-09-16, which is
  the whole reason the fifth gate is "green on Linux too". }

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

{ ------------------------------------------------------- close-on-exec ------ }

{$IFDEF UNIX}
const
  { The same constant udebugtransport declares, for the same reason: FPC's
    linux/ostypes.inc defines F_SetFd and does NOT define FD_CLOEXEC. Spelled
    this way so that on a BSD, where the RTL's own constant IS in scope, this
    declaration shadows nothing. }
  CloseOnExecFlag = 1;
{$ENDIF}

{ Take one handle out of the set a LATER child inherits.

  THIS IS THE SECOND PLACE THIS REPOSITORY HAS NEEDED IT, and the first was a
  socket (udebugtransport's MakeSocketPrivate): the editor's own descriptors
  travelling into a program the editor started. Here they are the three pipe
  ends of a child that is still running when the next one is spawned.

  On Unix it is the repair and not a tidiness measure. FPC creates a pipe with
  a bare `AssignPipe`, which is `pipe()` with no CLOEXEC
  (fcl-process unix/pipes.inc:20-24), and TProcess forks with InheritHandles
  True (processbody.inc:258). So with one child already live, the NEXT child
  inherits the first one's stdin WRITE end -- and after that, closing this
  process's copy delivers no end-of-input at all, for as long as that second
  child lives. A REPL that is ended while a program is running would simply not
  end, silently, and the editor would leave it behind.

  On Windows there is nothing to repair and the call still happens: FPC creates
  the pair with `piNonInheritablePipe` (win/pipes.inc:19-35) and makes only the
  child's own end inheritable, so this is an assertion of what is already true
  rather than a change -- and an assertion is what keeps the two platforms'
  answers to HandlesArePrivate the same.

  BEST EFFORT, and the result is returned rather than raised on, exactly as
  MakeSocketPrivate does: a handle that could not be marked still works, and
  failing a run over a hygiene measure would trade a feature the user asked for
  against one they did not. }
function MakeHandlePrivate(AHandle: THandle): Boolean;
begin
  Result := False;
  if AHandle = 0 then
    Exit;
  {$IFDEF WINDOWS}
  Result := SetHandleInformation(AHandle, HANDLE_FLAG_INHERIT, 0);
  {$ENDIF}
  {$IFDEF UNIX}
  if LongInt(AHandle) < 0 then
    Exit;
  Result := FpFcntl(LongInt(AHandle), F_SetFd, CloseOnExecFlag) = 0;
  {$ENDIF}
end;

{ Read the flag back. Only the test asks; it is here rather than there so that
  the two platforms' answers sit next to the two platforms' questions. }
function HandleIsPrivate(AHandle: THandle): Boolean;
{$IFDEF WINDOWS}
var
  flags: DWord;
{$ENDIF}
{$IFDEF UNIX}
var
  flags: LongInt;
{$ENDIF}
begin
  Result := False;
  if AHandle = 0 then
    Exit;
  {$IFDEF WINDOWS}
  flags := 0;
  if not GetHandleInformation(AHandle, @flags) then
    Exit;
  Result := (flags and HANDLE_FLAG_INHERIT) = 0;
  {$ENDIF}
  {$IFDEF UNIX}
  if LongInt(AHandle) < 0 then
    Exit;
  flags := FpFcntl(LongInt(AHandle), F_GetFd);
  if flags < 0 then
    Exit;
  Result := (flags and CloseOnExecFlag) <> 0;
  {$ENDIF}
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

function TPhosphorRunner.GetInputOpen: Boolean;
begin
  Result := (FProcess <> nil) and (not FInputClosed);
end;

function TPhosphorRunner.GetHandlesArePrivate: Boolean;
begin
  Result := (FProcess <> nil) and
            HandleIsPrivate(FProcess.Input.Handle) and
            HandleIsPrivate(FProcess.Output.Handle) and
            HandleIsPrivate(FProcess.Stderr.Handle);
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
  FCloseInputPending := False;
  FInputClosed := False;

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

  { BEFORE THE THREADS, and before anything else can be spawned. Three handles
    this process now holds that the NEXT child must not inherit -- see
    MakeHandlePrivate for what happens on Unix when it does. The results are
    ignored at the call site for the reason stated there. }
  MakeHandlePrivate(FProcess.Input.Handle);
  MakeHandlePrivate(FProcess.Output.Handle);
  MakeHandlePrivate(FProcess.Stderr.Handle);

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

  { THE GRANT OF A CloseInput, and the gate is TThread.Finished rather than
    Terminated: the RTL sets Finished after Execute has RETURNED
    (classes.inc, ThreadProc), so no WriteBuffer can still be in flight on the
    stream about to be freed. It is the same question DrainTimer already asks of
    the two readers one line above, asked of the writer. }
  if FCloseInputPending and (FIn <> nil) and FIn.Finished then
  begin
    FCloseInputPending := False;
    FInputClosed := True;
    if FProcess <> nil then
      try
        FProcess.CloseInput;
      except
        { Already closed, or the child is gone. Either way the child will not be
          waiting on it. }
        on E: Exception do
          ;
      end;
  end;

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

procedure TPhosphorRunner.Drain;
begin
  { FTimer.Enabled is the run's own liveness flag -- Start sets it, the final
    tick clears it -- so guarding on it is what keeps this from reaching the tail
    of DrainTimer (Cleanup, then OnFinished) on a runner that has already
    finished, which would deliver a second exit code for one run. }
  if FTimer.Enabled then
    DrainTimer(nil);
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
  { ASKS. Does not close.

    Drains what is queued first, because closing underneath a queued line would
    lose the answer the user has already typed -- and then waits for the writer
    thread to be FINISHED before touching the handle, because that thread blocks
    inside WriteBuffer and does not look at its Closing flag again until the
    write returns. Closing the stream from here would free it under a worker.

    The grant is in DrainTimer, one tick later at most, and InputOpen says
    whether it has happened. Before 2026-09-16 this method closed nothing at
    all: RequestClose only ends the thread's LOOP, and the child's stdin handle
    stayed open for the life of the runner -- so a child waiting on end-of-input
    waited forever, which is the whole of how a REPL is supposed to end. }
  if (FIn = nil) or (FProcess = nil) or FInputClosed or FCloseInputPending then
    Exit;
  FCloseInputPending := True;
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
