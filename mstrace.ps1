# Date: 02-06-2026
# Notes: written for powershell 5.1 and Windows
# Usage: .\MS Trace.exe

$WindowTitle = "MS Trace"
$Host.UI.RawUI.WindowTitle = $WindowTitle

Add-Type -AssemblyName System.Windows.Forms

if (-not ([System.Management.Automation.PSTypeName]'LogParser').Type) {
    $CSharpCode = @"
    using System;
    using System.Collections.Generic;
    using System.Text.RegularExpressions;
    using System.IO;

    public class LogEntry {
        public DateTime Timestamp { get; set; }
        public string Component { get; set; }
        public string Severity { get; set; }
        public string Message { get; set; }
    }

    public class LogParser {
        private static Regex cmRegex = new Regex(@"<!\[LOG\[(?<Msg>.*?)\]LOG\]!>.*?time=""(?<Time>.*?)"".*?date=""(?<Date>.*?)"".*?component=""(?<Comp>.*?)"".*?type=""(?<Type>.*?)""", RegexOptions.Singleline | RegexOptions.Compiled);
        private static Regex flatRegex = new Regex(@"^(?<Date>\d{4}-\d{2}-\d{2})\s+(?<Time>\d{2}:\d{2}:\d{2}),\s+(?<Sev>\w+)\s+(?<Msg>.*)", RegexOptions.Multiline | RegexOptions.Compiled);

        public static List<LogEntry> Parse(string content) {
            var results = new List<LogEntry>();
            if (string.IsNullOrEmpty(content)) return results;
            if (content.Contains("<![LOG[")) {
                foreach (Match m in cmRegex.Matches(content)) {
                    DateTime dt; DateTime.TryParse(m.Groups["Date"].Value + " " + m.Groups["Time"].Value, out dt);
                    string sev = m.Groups["Type"].Value == "2" ? "Warning" : (m.Groups["Type"].Value == "3" ? "Error" : "Info");
                    results.Add(new LogEntry { Timestamp = dt, Component = m.Groups["Comp"].Value, Severity = sev, Message = m.Groups["Msg"].Value.Trim() });
                }
            } else {
                foreach (Match m in flatRegex.Matches(content)) {
                    DateTime dt; DateTime.TryParse(m.Groups["Date"].Value + " " + m.Groups["Time"].Value, out dt);
                    results.Add(new LogEntry { Timestamp = dt, Component = "Standard", Severity = m.Groups["Sev"].Value, Message = m.Groups["Msg"].Value.Trim() });
                }
            }
            return results;
        }
    }
"@
    Add-Type -TypeDefinition $CSharpCode
}

function Write-LogEntry {
    param($Entry)
    $color = if ($Entry.Severity -match "Error|Fail") { "Red" } elseif ($Entry.Severity -match "Warn") { "Yellow" } else { "White" }
    Write-Host ("[{0:HH:mm:ss}] [{1}] {2}" -f $Entry.Timestamp, $Entry.Severity, $Entry.Message) -ForegroundColor $color
}

function Start-LiveTail {
    param($Path)
    Write-Host "`n--- LIVE TAIL: $Path ---`n(Press CTRL+C to return to Menu)" -ForegroundColor Cyan
    [Console]::TreatControlCAsInput = $true
    $lastSize = (Get-Item $Path).Length
    try {
        while ($true) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Modifiers -eq 'Control' -and $key.Key -eq 'C') { break }
            }
            $currentSize = (Get-Item $Path).Length
            if ($currentSize -gt $lastSize) {
                $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
                $stream.Seek($lastSize, 'Begin')
                $reader = New-Object System.IO.StreamReader($stream)
                
                $newEntries = [LogParser]::Parse($reader.ReadToEnd())
                foreach ($e in $newEntries) { 
                    $color = if ($e.Severity -match "Error|Fail") { "Red" } elseif ($e.Severity -match "Warn") { "Yellow" } else { "White" }
                    Write-Host ("[{0:HH:mm:ss}] [{1}] {2}" -f $e.Timestamp, $e.Severity, $e.Message) -ForegroundColor $color
                }
                
                $lastSize = $currentSize
                $reader.Dispose(); $stream.Dispose()
            }
            Start-Sleep -Milliseconds 500
        }
    } finally { [Console]::TreatControlCAsInput = $false }
}


function Show-Log {
    param($LogData, [switch]$VirtualScroll, [string]$Path)
    if ($null -eq $LogData -or $LogData.Count -eq 0) { return }
    if ($VirtualScroll) {
        $pageSize = 75
        for ($i = 0; $i -lt $LogData.Count; $i += $pageSize) {
            $end = [Math]::Min($i + $pageSize - 1, $LogData.Count - 1)
            foreach ($line in $LogData[$i..$end]) { Write-LogEntry -Entry $line }
            $cmd = (Read-Host "`n[Enter] Next 75 | [T] Tail | [M] Menu").ToUpper()
            if ($cmd -eq "M") { return }; if ($cmd -eq "T") { Start-LiveTail -Path $Path; return }
        }
    } else { $LogData | ForEach-Object { Write-LogEntry -Entry $_ } }
}

# script start
$currentLog = [System.Collections.Generic.List[LogEntry]]::new()
$currentPath = ""
Clear-Host

while ($true) {
    Write-Host "`n[O] Open [L] Live Tail [S] Search [E] Errors [T] Time [R] Reset [Q] Exit" -ForegroundColor Cyan
    $choice = (Read-Host "Command").ToUpper()
    switch ($choice) {
        "O" {
            $fd = New-Object System.Windows.Forms.OpenFileDialog -Property @{ Filter = "Logs|*.log|All|*.*" }
            if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $currentPath = $fd.FileName
                $currentLog = [LogParser]::Parse([System.IO.File]::ReadAllText($currentPath))
                $act = (Read-Host "Loaded $($currentLog.Count) lines. [A] All, [V] Virtual Scroll, [L] Live Tail?").ToUpper()
                if ($act -eq "A") { Show-Log -LogData $currentLog }
                elseif ($act -eq "V") { Show-Log -LogData $currentLog -VirtualScroll -Path $currentPath }
                elseif ($act -eq "L") { Start-LiveTail -Path $currentPath }
            }
        }
        "L" { if ($currentPath) { Start-LiveTail -Path $currentPath } }
        "S" {
            $s = Read-Host "Search"
            Show-Log -LogData ($currentLog.FindAll({ $args.Message.IndexOf($s, [StringComparison]::OrdinalIgnoreCase) -ge 0 })) -VirtualScroll -Path $currentPath
        }
        "E" { Show-Log -LogData ($currentLog.FindAll({ $args.Severity -match "Error|Fail|Warn" })) -VirtualScroll -Path $currentPath }
        "T" {
            if ($m = Read-Host "Minutes back") {
                $cut = (Get-Date).AddMinutes(-[int]$m)
                Show-Log -LogData ($currentLog.FindAll({ $args.Timestamp -ge $cut })) -VirtualScroll -Path $currentPath
            }
        }
        "R" { Show-Log -LogData $currentLog -VirtualScroll -Path $currentPath }
        "Q" { exit }
    }
}
