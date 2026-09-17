unit uphosphorclock;

{ A monotonic clock with enough resolution to time ONE keystroke.

  WHY THIS EXISTS, and it is roadmap item 19's first problem. `SysUtils.Now` is a
  TDateTime: a double counting days, read on Windows from the system time, whose
  step is the scheduler's tick -- 15.6 ms by default, and never better than 1 ms.
  Every number in `MeasureHighlighter` was taken with it, and they are honest
  only because each divides a LOOP of fifty or two thousand passes by its count.
  Ask the same clock what one edit cost and the answer is 0 or 15.6, and both are
  lies with three decimal places on them.

  AND IT MUST BE MONOTONIC, which `Now` also is not: it follows the wall clock,
  so an NTP step or a daylight-saving change lands in the middle of a measurement
  as a negative interval or an hour-long one. A number that can be negative is
  not a duration.

  WHAT IT IS ON EACH PLATFORM. `QueryPerformanceCounter` on Windows, which is
  documented monotonic and is typically the 10 MHz platform counter; and
  `clock_gettime(CLOCK_MONOTONIC)` on Linux, which is the same guarantee and
  nanosecond-denominated. Both are counted from an arbitrary origin, so only
  DIFFERENCES mean anything -- which is why there is no `ClockNow` returning a
  time of day here, and why nothing in this unit can be used to stamp a file.

  NO LCL IN HERE, like every other unit under `core/`, so
  `tests/phosphoridetest.lpr` can pin it without a window. What it pins is the
  two things a clock can silently fail at: that it never goes backwards, and that
  `ClockResolutionNs` is not a boast. A measurement finer than the clock's own
  step is arithmetic, not evidence, and the report that carries a number should
  carry what the clock could actually see beside it.

  MIT License. Copyright (c) 2026 Andre Murta.
}

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  {$IFDEF LINUX}Linux, UnixType,{$ENDIF}
  SysUtils;

{ A tick from a monotonic counter. The origin is arbitrary; subtract two. }
function ClockTicks: Int64;

{ Milliseconds between two ticks, ATo later than AFrom. }
function ClockMs(AFrom, ATo: Int64): Double;

{ The smallest interval this clock can represent, in nanoseconds. It is the
  counter's period and not the smallest interval it can MEASURE -- reading the
  clock costs more than one tick -- so `ClockOverheadNs` is the other half. }
function ClockResolutionNs: Double;

{ What one ClockTicks call costs, measured the first time it is asked and
  remembered. A duration of the same order as this number is noise. }
function ClockOverheadNs: Double;

{ A name for a report, so a number never appears without the clock that took
  it. }
function ClockName: String;

implementation

var
  FOverheadNs: Double = -1;
  {$IFDEF WINDOWS}
  FFreq: Int64 = 0;
  {$ENDIF}

function ClockTicks: Int64;
{$IFDEF LINUX}
var
  TS: TTimeSpec;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  QueryPerformanceCounter(Result);
  {$ELSE}
    {$IFDEF LINUX}
    clock_gettime(CLOCK_MONOTONIC, @TS);
    Result := Int64(TS.tv_sec) * 1000000000 + TS.tv_nsec;
    {$ELSE}
    { NOT A PLATFORM THIS REPOSITORY BUILDS FOR, and a wrong answer that looks
      right is worse than a build failure. }
    Result := 0;
    {$ENDIF}
  {$ENDIF}
end;

function ClockMs(AFrom, ATo: Int64): Double;
begin
  {$IFDEF WINDOWS}
  if FFreq = 0 then
    QueryPerformanceFrequency(FFreq);
  if FFreq = 0 then
    Exit(0);
  Result := (ATo - AFrom) * 1000.0 / FFreq;
  {$ELSE}
  Result := (ATo - AFrom) / 1000000.0;
  {$ENDIF}
end;

function ClockResolutionNs: Double;
begin
  {$IFDEF WINDOWS}
  if FFreq = 0 then
    QueryPerformanceFrequency(FFreq);
  if FFreq = 0 then
    Exit(0);
  Result := 1000000000.0 / FFreq;
  {$ELSE}
  { CLOCK_MONOTONIC is nanosecond-denominated. clock_getres would report the
    kernel's own answer, which on every configuration this runs on is 1 ns
    because the clocksource is read directly rather than ticked. }
  Result := 1.0;
  {$ENDIF}
end;

function ClockOverheadNs: Double;
const
  Reps = 20000;
var
  A, B: Int64;
  I: Integer;
  Sink: Int64;
begin
  if FOverheadNs < 0 then
  begin
    Sink := 0;
    A := ClockTicks;
    for I := 1 to Reps do
      Sink := Sink + ClockTicks;
    B := ClockTicks;
    { Sink exists so the loop cannot be optimised away, and is read so the
      compiler cannot drop it either. }
    if Sink = 0 then
      FOverheadNs := 0
    else
      FOverheadNs := ClockMs(A, B) * 1000000.0 / Reps;
  end;
  Result := FOverheadNs;
end;

function ClockName: String;
begin
  {$IFDEF WINDOWS}
  if FFreq = 0 then
    QueryPerformanceFrequency(FFreq);
  Result := Format('QueryPerformanceCounter, %.3f MHz', [FFreq / 1000000.0]);
  {$ELSE}
    {$IFDEF LINUX}
    Result := 'clock_gettime(CLOCK_MONOTONIC)';
    {$ELSE}
    Result := 'none -- this platform has no clock here';
    {$ENDIF}
  {$ENDIF}
end;

end.
