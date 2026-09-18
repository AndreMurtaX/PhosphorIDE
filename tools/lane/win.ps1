# Helpers for driving the editor from outside.
#
# TRAP, paid for on 2026-09-16: Process.MainWindowHandle is NOT the form. The LCL
# creates a hidden top-level window carrying Application.Title, and Windows hands
# that one back as the "main" window -- so MoveWindow moved something invisible,
# GetWindowRect described it, and EnumChildWindows found it childless. Every
# helper here starts from the VISIBLE top-level window of the process instead.

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class Wnd {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextLengthW(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rr, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);

  public static IntPtr TopLevel(int pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p != (uint)pid || !IsWindowVisible(h)) return true;
      if (GetWindowTextLengthW(h) == 0) return true;
      found = h; return false;
    }, IntPtr.Zero);
    return found;
  }

  // THE LAST COLUMN IS NOT A CONTROL'S TEXT, and no caller in this directory
  // treats it as one. GetWindowTextLengthW does not cross a process boundary for
  // a control any more than GetWindowText does -- it is the same documented
  // limitation one API earlier, and it fails the same way, by answering 0. So the
  // read below is skipped and the column comes back EMPTY for exactly the panes
  // and edits a lane wants to assert on.
  //
  // Measured on 2026-09-17 against EditInput, whose hint was drawn in the
  // screenshot at the time: GetWindowTextLengthW said 0, an explicit
  // WM_GETTEXTLENGTH said 45. Believing the 0 cost an afternoon -- it read as a
  // hint that lived somewhere no message could reach, and sent lane-windows.ps1
  // through EM_GETCUEBANNER and UI Automation before the wrong API was the
  // suspect. Send WM_GETTEXT yourself; LaneWin.Text does.
  public static List<string> Kids(IntPtr top) {
    var outp = new List<string>();
    EnumChildWindows(top, delegate(IntPtr h, IntPtr l) {
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      int n = GetWindowTextLengthW(h);
      var t = new StringBuilder(n + 2); if (n > 0) GetWindowTextW(h, t, n + 1);
      R r; GetWindowRect(h, out r);
      outp.Add(h.ToInt64() + "\t" + c.ToString() + "\t" +
               r.L + "," + r.T + "," + r.Rr + "," + r.B + "\t" +
               (IsWindowVisible(h) ? "1" : "0") + "\t" +
               t.ToString().Replace("\r\n", "¶"));
      return true;
    }, IntPtr.Zero);
    return outp;
  }
}
"@
