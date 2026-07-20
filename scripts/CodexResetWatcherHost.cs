using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class CodexResetWatcherHost
{
    private const string MutexName = @"Local\CodexResetWatcher.LowMemoryHost";
    private const int PollIntervalMilliseconds = 2500;
    private const uint ProcessQueryLimitedInformation = 0x1000;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, int processId);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder path, ref int size);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [STAThread]
    private static void Main(string[] args)
    {
        string showScript = args.Length > 0 ? Path.GetFullPath(args[0]) : string.Empty;
        if (!File.Exists(showScript)) return;

        bool ownsMutex = false;
        using (var mutex = new Mutex(false, MutexName))
        {
            try
            {
                try { ownsMutex = mutex.WaitOne(0, false); }
                catch (AbandonedMutexException) { ownsMutex = true; }
                if (!ownsMutex) return;
                Watch(showScript);
            }
            finally
            {
                if (ownsMutex) { try { mutex.ReleaseMutex(); } catch { } }
            }
        }
    }

    private static void Watch(string showScript)
    {
        Process widget = null;
        bool wasRunning = false;
        try
        {
            while (true)
            {
                bool isRunning = IsCodexRunning();
                if (isRunning && !wasRunning) widget = StartWidget(showScript);
                else if (!isRunning && wasRunning) { StopWidget(widget); widget = null; }

                // If the user explicitly exits the widget, leave it closed until
                // the next Codex launch instead of immediately reopening it.
                if (widget != null && widget.HasExited) { widget.Dispose(); widget = null; }
                wasRunning = isRunning;
                Thread.Sleep(PollIntervalMilliseconds);
            }
        }
        finally { StopWidget(widget); }
    }

    private static bool IsCodexRunning()
    {
        Process[] processes;
        try { processes = Process.GetProcessesByName("ChatGPT"); }
        catch { return false; }

        foreach (Process process in processes)
        {
            try
            {
                string path = GetProcessPath(process.Id);
                if (path.IndexOf("OpenAI.Codex", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            }
            catch { }
            finally { process.Dispose(); }
        }
        return false;
    }

    private static string GetProcessPath(int processId)
    {
        IntPtr handle = OpenProcess(ProcessQueryLimitedInformation, false, processId);
        if (handle == IntPtr.Zero) return string.Empty;
        try
        {
            var path = new StringBuilder(1024);
            int size = path.Capacity;
            return QueryFullProcessImageName(handle, 0, path, ref size) ? path.ToString() : string.Empty;
        }
        finally { CloseHandle(handle); }
    }

    private static Process StartWidget(string showScript)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = FindPowerShell(),
            Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File " + Quote(showScript) + " -StartCollapsed",
            WorkingDirectory = Path.GetDirectoryName(showScript),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        try { return Process.Start(startInfo); }
        catch { return null; }
    }

    private static string FindPowerShell()
    {
        string pwsh = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe");
        if (File.Exists(pwsh)) return pwsh;
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
    }

    private static string Quote(string value) { return "\"" + value.Replace("\"", "\\\"") + "\""; }

    private static void StopWidget(Process widget)
    {
        if (widget == null) return;
        try
        {
            if (!widget.HasExited) { widget.Kill(); widget.WaitForExit(1500); }
        }
        catch { }
        finally { widget.Dispose(); }
    }
}
