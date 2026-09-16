param([long]$H = 0)

# GetWindowText does NOT cross a process boundary for a control (documented), so
# the text comes back empty and the pane looks blank from out here. WM_GETTEXT
# sent explicitly does marshal the string. Paid for on 2026-09-16.

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Txt {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int SendMessageW(IntPtr h, int msg, IntPtr wp, StringBuilder lp);
  [DllImport("user32.dll", EntryPoint="SendMessageW")]
  public static extern IntPtr SendMessageP(IntPtr h, int msg, IntPtr wp, IntPtr lp);
  public static string Get(IntPtr h) {
    int n = (int)SendMessageP(h, 0x000E, IntPtr.Zero, IntPtr.Zero); // WM_GETTEXTLENGTH
    var sb = new StringBuilder(n + 2);
    SendMessageW(h, 0x000D, (IntPtr)(n + 1), sb);                   // WM_GETTEXT
    return sb.ToString();
  }
}
"@

Write-Output ([Txt]::Get([IntPtr]$H))
