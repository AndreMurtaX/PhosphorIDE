unit udebugtransport;

{ The PDBP socket: the editor listens, the debuggee connects.

  THE DIRECTION IS THE THING IMPLEMENTERS GET BACKWARDS FIRST, and the
  specification says it in as many words (docs/debug-protocol.md): the EDITOR
  listens on loopback, and `phosphor debug --port N file.bas` connects back to it.
  So this is a server, not a client, and the port it binds is ephemeral -- bind 0,
  ask the kernel what it gave us, and pass that number on the child's command line.

  WHY NOT fcl-net's TInetServer. Measured in the RTL rather than assumed, because
  this project has lost patches to assumptions about the RTL twice:

    ssockets.pp:863-873  TInetServer.Bind calls fpBind and sets FBound. It never
                         calls fpGetSockName, and Port is read-only (:202). So a
                         bind on port 0 leaves Port reading 0 and the number we
                         must hand the child is simply unobtainable.
    ssockets.pp:911-916  Accept CLOSES the socket it just accepted unless
                         FAccepting is true, and only StartAccepting sets that.
                         The obvious bind/listen/accept-once therefore accepts the
                         debuggee and drops it on the floor.

  Unit `Sockets` directly, then. Also read rather than assumed: its Windows half
  (rtl-extra/src/win/sockets.pp:278-280) calls WSAStartUp in its own
  initialization, so `uses Sockets` is the whole of the Winsock ceremony, and
  fpSocket / fpBind / fpListen / fpAccept / fpGetSockName / CloseSocket all exist
  under those names on both platforms.

  THE THREADING IS uphosphorrun.pas's, because that shape is already paid for.
  An accept thread and a reader thread deposit into a lock-guarded buffer, and
  Poll -- called on the main thread -- turns that buffer into whole lines and
  fires the events. No TThread.Synchronize and no TThread.Queue: draining a buffer
  has one obvious order of operations and no re-entrancy to reason about. The UI
  thread never blocks, which is this repository's first rule.

  THE TIMER BELONGS TO THE CALLER, NOT TO THIS UNIT, and that is not tidiness. A
  TTimer needs a widgetset: `phosphoridetest` links the LCL and deliberately never
  creates one, so constructing a timer here killed the test program the moment the
  transport was first exercised -- the group header printed and nothing after it,
  exit 0, no summary. Owning the timer would have made this unit the only one in
  src/core that cannot be tested headless. The owner calls Poll on whatever cadence
  it likes; uphosphorrun.pas uses 40 ms and there is no reason to differ.

  WHAT IS DELIBERATELY NOT COPIED FROM THERE: FlushPrompt. The runner emits an
  unterminated tail after about 80 ms of quiet, because a program that ends in
  PRINT rather than PRINTLN would otherwise lose its last line. That is right for
  a program's stdout and fatal for a protocol: half a frame handed to a JSON
  parser is not a prompt, it is a session that ends with "not JSON". A partial
  line waits here for its newline however long that takes.

  FRAMING. One JSON object per line, UTF-8, terminated by a BARE #10 -- never
  LineEnding, which is CRLF on Windows and which the specification forbids on
  output (docs/debug-protocol.md:64-65). A #13 before the #10 is tolerated on
  input. The accumulated line is capped: the peer is on loopback and is trusted,
  but trusted is not unbounded, and a peer that never sends a newline would
  otherwise grow a String until the editor died. The host caps its own side the
  same way and at the same size.

  NO SOCKET OF OURS TRAVELS INTO A CHILD. The editor calls Listen and THEN spawns
  the debuggee, and a descriptor that is open at the moment of the spawn is
  inherited by it unless it is marked otherwise. Measured on 2026-09-16 with
  `ss -ltnp` on Linux, with a session live:

    LISTEN 127.0.0.1:35685  users:(("phosphor",pid=5381,fd=18),
                                   ("phosphoride",pid=5343,fd=18))

  -- the debuggee holding, on the same descriptor number, the listener it was
  only ever meant to CONNECT to. It could have accepted on it. Every socket this
  unit opens is therefore taken out of the inherit set as soon as it exists; see
  MakeSocketPrivate.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}
  Windows,      // SetHandleInformation; see MakeSocketPrivate
  {$ENDIF}
  {$IFDEF UNIX}
  BaseUnix,     // FpFcntl and F_SetFd, same reason
  {$ENDIF}
  Classes, SysUtils, Sockets, syncobjs;

const
  { A protocol frame is a few hundred bytes; a megabyte is far past any honest one
    and short of anything that hurts. The host uses the same number, which is not
    a coincidence -- both ends refuse the same shape of peer. }
  MaxFrameBytes = 1024 * 1024;

type
  TDebugFrameEvent = procedure(Sender: TObject; const AFrame: String) of object;
  TDebugLinkEvent = procedure(Sender: TObject) of object;

  TDebugTransport = class;

  { Parked in fpAccept until the debuggee connects or the listening socket is
    closed under it. Closing the listener is how Stop wakes this thread; the
    accept then fails and the loop ends, which is the same wake-and-join
    discipline uphosphorrun.pas:616-655 uses on the child's pipes. }
  TDebugAcceptThread = class(TThread)
  private
    FOwner: TDebugTransport;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TDebugTransport);
  end;

  { Blocking reads on the accepted socket. Deposits bytes and nothing else. }
  TDebugReadThread = class(TThread)
  private
    FOwner: TDebugTransport;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TDebugTransport);
  end;

  TDebugTransport = class
  private
    FListenSock: LongInt;
    FPeerSock: LongInt;
    FPort: Word;
    FLock: TCriticalSection;
    FPending: String;        // bytes the reader has delivered, not yet split
    FPartial: String;        // a line whose newline has not arrived
    FAccepter: TDebugAcceptThread;
    FReader: TDebugReadThread;
    FConnected: Boolean;     // guarded by FLock: the accept succeeded
    FEnded: Boolean;         // guarded by FLock: the peer went away
    FRaisedLink: Boolean;    // the main thread has reported the connection
    FRaisedEnd: Boolean;     // ...and the disconnection
    FOverflow: Boolean;      // guarded by FLock: the cap was hit
    FOverflowBytes: Int64;   // guarded by FLock: HOW MUCH was thrown away
    FDraining: Boolean;      // main thread only: Drain is on the stack
    FOnFrame: TDebugFrameEvent;
    FOnConnect: TDebugLinkEvent;
    FOnDisconnect: TDebugLinkEvent;
    procedure Drain;
    procedure Deposit(const AChunk: String);
    procedure NotePeer(ASock: LongInt);
    procedure NoteEnd;
    function TakePending: String;
  public
    constructor Create;
    destructor Destroy; override;
    { Bind loopback on an ephemeral port and start listening. Returns the port the
      kernel gave us -- the number to put on the child's command line -- or 0 if
      the socket could not be made. }
    function Listen: Word;
    { Stop everything: wake the threads, join them, close both sockets. Safe to
      call more than once, and safe to call when Listen failed. }
    procedure Stop;
    { Send one frame. The terminator is added here so no caller can get it wrong. }
    function SendFrame(const AFrame: String): Boolean;
    { Drain now, from the calling thread, instead of waiting for the timer. The
      timer's only purpose is to arrive on the main thread; a caller that IS the
      main thread -- a headless test, a host with its own loop -- can say so. }
    procedure Poll;
    { True when every socket this transport currently owns is out of the set a
      child process would inherit. It is a question rather than an accessor
      because the answer is the invariant and the handle is nobody's business.
      Pinned in phosphoridetest: without it, deleting one call in Listen would
      be a silent regression with a symptom only `ss` can see. }
    function HandlesArePrivate: Boolean;

    { WHY THE LINK ENDED, or '' when it ended the way a link is supposed to.

      A CLOSED SOCKET AND A DISCARDED MEGABYTE ARRIVE AT THE SAME CALLBACK, and
      until 2026-09-18 they were indistinguishable: OnDisconnect fired for both
      and TDebugSession.HandleDisconnect treats a close as "the end of a session,
      not an error", because a program that finished perfectly well ends this way
      too. So the overflow path -- which throws bytes away and then ends the
      session -- looked exactly like a clean exit, with no diagnostic anywhere.
      Measured in a harness on 2026-09-18: 38 183 frames gone in one cut, and the
      only way to know was to instrument the unit.

      A caller that reports this is telling somebody the truth about a session
      that ended badly. One that ignores it is where this started. }
    function EndReason: String;

    property Port: Word read FPort;
    property OnFrame: TDebugFrameEvent read FOnFrame write FOnFrame;
    property OnConnect: TDebugLinkEvent read FOnConnect write FOnConnect;
    property OnDisconnect: TDebugLinkEvent read FOnDisconnect write FOnDisconnect;
  end;

implementation

const
  ReadBufferSize  = 4096;

{ ------------------------------------------------------------ accept thread - }

constructor TDebugAcceptThread.Create(AOwner: TDebugTransport);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

{ ------------------------------------------------------- close-on-exec ------ }

{$IFDEF UNIX}
const
  { FPC's linux/ostypes.inc defines F_SetFd (:378) and does NOT define
    FD_CLOEXEC; only bsd/ostypes.inc does (:365). Spelled differently here so
    that on a BSD, where the RTL's own constant IS in scope, this declaration
    shadows nothing. }
  CloseOnExecFlag = 1;
{$ENDIF}

{ Take one socket out of the set a child process inherits.

  On Unix that is FD_CLOEXEC, and there is no race to worry about here: the only
  spawn in this program happens on the main thread, after Listen has returned to
  it, so nothing can fork between fpSocket and this call.

  WINDOWS HAS THE SAME HOLE AND DOES NOT SHOW IT. netstat reports one owning PID
  per socket, so the doubled ownership that `ss` printed on Linux is simply
  invisible there -- but TProcess sets InheritHandles := True
  (fcl-process processbody.inc:258) and hands it to CreateProcessW as
  bInheritHandles (win/process.inc:283), and a Winsock socket is an inheritable
  handle by default. SetHandleInformation with HANDLE_FLAG_INHERIT cleared
  (wininc/func.inc:191, defines.inc:1711) is the same fix under another name.

  BEST EFFORT, and the result is returned rather than raised on. A socket that
  could not be marked still works; it is only untidy, and failing a debug session
  over a hygiene measure would trade a feature the user asked for against one
  they did not. }
function MakeSocketPrivate(ASock: LongInt): Boolean;
begin
  Result := False;
  if ASock < 0 then
    Exit;
  {$IFDEF WINDOWS}
  Result := SetHandleInformation(THandle(ASock), HANDLE_FLAG_INHERIT, 0);
  {$ENDIF}
  {$IFDEF UNIX}
  Result := FpFcntl(ASock, F_SetFd, CloseOnExecFlag) = 0;
  {$ENDIF}
end;

{ Read the flag back. Only the test asks; it is here rather than there so that
  the two platforms' answers are written next to the two platforms' questions. }
function SocketIsPrivate(ASock: LongInt): Boolean;
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
  if ASock < 0 then
    Exit;
  {$IFDEF WINDOWS}
  flags := 0;
  if not GetHandleInformation(THandle(ASock), @flags) then
    Exit;
  Result := (flags and HANDLE_FLAG_INHERIT) = 0;
  {$ENDIF}
  {$IFDEF UNIX}
  flags := FpFcntl(ASock, F_GetFd);
  if flags < 0 then
    Exit;
  Result := (flags and CloseOnExecFlag) <> 0;
  {$ENDIF}
end;

procedure TDebugAcceptThread.Execute;
var
  addr: TInetSockAddr;
  len: TSockLen;
  h: LongInt;
begin
  FillChar(addr{%H-}, SizeOf(addr), 0);
  len := SizeOf(addr);
  h := fpAccept(FOwner.FListenSock, @addr, @len);
  if Terminated then
  begin
    { Stop closed the listener under us. If an accept still slipped through, the
      socket is ours and nobody will ever read it. }
    if h >= 0 then CloseSocket(h);
    Exit;
  end;
  if h < 0 then
  begin
    FOwner.NoteEnd();   // the listener was closed, or the accept failed outright
    Exit;
  end;
  { An accepted socket does NOT inherit the listener's flag -- POSIX says so and
    Windows agrees -- so it is marked in its own right. It is created after the
    debuggee was spawned, so that child never had it; the one that would is the
    next process this editor starts, and Tools > Preferences probing a host is
    exactly that. }
  MakeSocketPrivate(h);
  FOwner.NotePeer(h);
end;

{ -------------------------------------------------------------- read thread - }

constructor TDebugReadThread.Create(AOwner: TDebugTransport);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TDebugReadThread.Execute;
var
  buf: array[0..ReadBufferSize - 1] of Byte;
  n: LongInt;
  chunk: String;
begin
  FillChar(buf{%H-}, SizeOf(buf), 0);
  while not Terminated do
  begin
    n := fpRecv(FOwner.FPeerSock, @buf[0], SizeOf(buf), 0);
    if n <= 0 then Break;      // the debuggee closed, or the socket went away
    SetLength(chunk, n);
    Move(buf[0], chunk[1], n);
    FOwner.Deposit(chunk);
  end;
  FOwner.NoteEnd();
end;

{ ---------------------------------------------------------------- transport - }

constructor TDebugTransport.Create;
begin
  inherited Create();
  FListenSock := -1;
  FPeerSock := -1;
  FLock := TCriticalSection.Create();
end;

destructor TDebugTransport.Destroy;
begin
  Stop();
  FLock.Free;
  inherited Destroy;
end;

function TDebugTransport.Listen: Word;
var
  addr: TInetSockAddr;
  len: TSockLen;
begin
  Result := 0;
  FListenSock := fpSocket(AF_INET, SOCK_STREAM, 0);
  if FListenSock < 0 then Exit;
  { BEFORE the bind, and long before the caller spawns anything. }
  MakeSocketPrivate(FListenSock);

  FillChar(addr{%H-}, SizeOf(addr), 0);
  addr.sin_family := AF_INET;
  addr.sin_port := 0;                              // the kernel picks
  addr.sin_addr.s_addr := htonl($7F000001);        // 127.0.0.1, loopback only
  if fpBind(FListenSock, @addr, SizeOf(addr)) <> 0 then
  begin
    CloseSocket(FListenSock); FListenSock := -1; Exit;
  end;
  if fpListen(FListenSock, 1) <> 0 then
  begin
    CloseSocket(FListenSock); FListenSock := -1; Exit;
  end;

  { THE STEP TInetServer DOES NOT TAKE. Without it the bind above is useless:
    port 0 means "give me one", and this is the only way to learn which. }
  FillChar(addr, SizeOf(addr), 0);
  len := SizeOf(addr);
  if fpGetSockName(FListenSock, @addr, @len) <> 0 then
  begin
    CloseSocket(FListenSock); FListenSock := -1; Exit;
  end;
  FPort := ntohs(addr.sin_port);
  if FPort = 0 then
  begin
    CloseSocket(FListenSock); FListenSock := -1; Exit;
  end;

  FAccepter := TDebugAcceptThread.Create(Self);
  Result := FPort;
end;

function TDebugTransport.HandlesArePrivate: Boolean;
var
  lsock, psock: LongInt;
begin
  FLock.Acquire();
  try
    lsock := FListenSock;
    psock := FPeerSock;
  finally
    FLock.Release();
  end;
  { A socket this transport does not have cannot be leaked, so -1 is not a
    failure. Vacuously true before Listen and after Stop, which is the honest
    answer to "is anything of ours reachable from a child". }
  Result := ((lsock < 0) or SocketIsPrivate(lsock))
        and ((psock < 0) or SocketIsPrivate(psock));
end;

procedure TDebugTransport.NotePeer(ASock: LongInt);
begin
  FLock.Acquire();
  try
    FPeerSock := ASock;
    FConnected := True;
  finally
    FLock.Release();
  end;
  { Started from the accept thread, which is about to end. The reader owns the
    socket from here; the drain timer reports the connection on the main thread. }
  FReader := TDebugReadThread.Create(Self);
end;

procedure TDebugTransport.NoteEnd;
begin
  FLock.Acquire();
  try
    FEnded := True;
  finally
    FLock.Release();
  end;
end;

procedure TDebugTransport.Deposit(const AChunk: String);
begin
  { Called from the reader thread. Touches nothing but the buffer. }
  FLock.Acquire();
  try
    if Length(FPending) + Length(FPartial) > MaxFrameBytes then
    begin
      { COUNTED, NOT JUST FLAGGED. The reader goes on reading and discarding until
        the main thread next drains, so "the cap was hit" says nothing about how
        much went. EndReason reports the total, because a number is what tells a
        reader whether a frame was clipped or a session was lost. }
      FOverflow := True;
      Inc(FOverflowBytes, Length(AChunk));
    end
    else
      FPending := FPending + AChunk;
  finally
    FLock.Release();
  end;
end;

function TDebugTransport.EndReason: String;
var
  over: Boolean;
  bytes: Int64;
begin
  FLock.Acquire();
  try
    over := FOverflow;
    bytes := FOverflowBytes;
  finally
    FLock.Release();
  end;
  if not over then
    Exit('');
  Result := Format('the debug link sent more than %d bytes with no newline in ' +
    'them and was dropped; %d byte(s) were discarded', [MaxFrameBytes, bytes]);
end;

function TDebugTransport.TakePending: String;
begin
  FLock.Acquire();
  try
    Result := FPending;
    FPending := '';
  finally
    FLock.Release();
  end;
end;

procedure TDebugTransport.Drain;
var
  buf, line: String;
  p: Integer;
  connected, ended, over: Boolean;
begin
  { ASK WHETHER THE PEER FINISHED BEFORE TAKING WHAT IT LEFT -- the ordering rule
    at uphosphorrun.pas:527-535. The other way round loses the last frames: the
    reader can deposit and end between the two reads, and a drain that checked
    "ended" first would then return without collecting them. }
  FLock.Acquire();
  try
    connected := FConnected;
    ended := FEnded;
    over := FOverflow;
  finally
    FLock.Release();
  end;

  { A RE-ENTRY IS A NO-OP, NOT A NESTED DRAIN, and this is a guard against a
    defect that is latent rather than live. Everything below runs with the
    UNDELIVERED REMAINDER in a local and FPartial already emptied, so a second
    Drain entered from inside a frame handler takes the NEWER bytes and delivers
    them BEFORE the older frames still sitting in the outer buffer -- and the
    outer's closing assignment then clobbers whatever the inner left. Measured in
    a harness on 2026-09-18 by re-entering from every seventh frame: 119
    reorderings in 20 000, and in a real session an out-of-order stopped/response
    pair is a Desync.

    Nothing in the hot loop re-enters TODAY -- DebugStopped shows no dialog and
    pumps no messages -- so this costs nothing now and is here for the first
    MessageDlg somebody adds to a stop handler. The new bytes are not lost by
    returning: they stay in FPending and the next Drain takes them, in order. }
  if FDraining then
    Exit;
  FDraining := True;
  try
    if connected and (not FRaisedLink) then
    begin
      FRaisedLink := True;
      if Assigned(FOnConnect) then FOnConnect(Self);
    end;

    buf := FPartial + TakePending();
    FPartial := '';
    try
      p := Pos(#10, buf);
      while p > 0 do
      begin
        line := Copy(buf, 1, p - 1);
        { A #13 before the #10 is tolerated on input and never produced on output
          -- the specification's own words. }
        if (line <> '') and (line[Length(line)] = #13) then
          SetLength(line, Length(line) - 1);
        Delete(buf, 1, p);
        if (line <> '') and Assigned(FOnFrame) then FOnFrame(Self, line);
        p := Pos(#10, buf);
      end;
    finally
      { NO FLUSH, AND THE REMAINDER GOES BACK WHATEVER HAPPENED. An unterminated
        tail is held however long it takes -- half a frame is not a frame -- and
        the try/finally is what makes that true of an exception too. Without it,
        a handler that raises discards every complete frame still in the buffer
        AND the tail, and leaves FPartial empty so the next drain resumes
        mid-frame. In an ordinary build that exception draws a modal box, so it is
        visible rather than silent; AppNoExceptionMessages is set only under
        --selftest and --measure-typing, where it would not be. }
      FPartial := buf;
    end;

    if over then
    begin
      { A peer that will not end a line is not a peer worth keeping -- and
        EndReason is what says so out loud, because this path and a clean close
        both arrive at OnDisconnect. }
      FPartial := '';
      NoteEnd();
      ended := True;
    end;

    if ended and (not FRaisedEnd) then
    begin
      FRaisedEnd := True;
      if Assigned(FOnDisconnect) then FOnDisconnect(Self);
    end;
  finally
    FDraining := False;
  end;
end;

procedure TDebugTransport.Poll;
begin
  Drain();
end;

function TDebugTransport.SendFrame(const AFrame: String): Boolean;
var
  wire: String;
  sock: LongInt;
  sent: LongInt;
begin
  Result := False;
  FLock.Acquire();
  try
    sock := FPeerSock;
  finally
    FLock.Release();
  end;
  if sock < 0 then Exit;
  { BARE #10, never LineEnding: CRLF on output is forbidden by the specification,
    and writing it here is the single easiest way to break a conformant host. }
  wire := AFrame + #10;
  { A request frame is tens of bytes and the host reads continuously, so this is
    written from the calling thread. If it is ever made to carry bulk -- a
    setVariable with a long string, say -- it needs a writer thread, for the
    reason uphosphorrun.pas:81-108 gives about a full pipe buffer. }
  sent := fpSend(sock, @wire[1], Length(wire), 0);
  Result := sent = Length(wire);
end;

procedure TDebugTransport.Stop;
var
  lsock, psock: LongInt;
begin
  { WAKE BEFORE JOIN, both threads, and by closing the socket each is parked on.
    The accept thread is inside fpAccept and the reader inside fpRecv; neither
    returns for a Terminate alone. Terminated is set first so that a thread woken
    by the close knows it was asked to stop rather than that the peer went away. }
  if FAccepter <> nil then FAccepter.Terminate();
  if FReader <> nil then FReader.Terminate();

  FLock.Acquire();
  try
    lsock := FListenSock; FListenSock := -1;
    psock := FPeerSock;   FPeerSock := -1;
  finally
    FLock.Release();
  end;
  if lsock >= 0 then CloseSocket(lsock);
  if psock >= 0 then CloseSocket(psock);

  if FAccepter <> nil then
  begin
    FAccepter.WaitFor();
    FreeAndNil(FAccepter);
  end;
  if FReader <> nil then
  begin
    FReader.WaitFor();
    FreeAndNil(FReader);
  end;
  FPartial := '';
  FPending := '';
end;

end.
