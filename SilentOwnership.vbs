If WScript.Arguments.Count = 0 Then WScript.Quit

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' 🔵 Check for Elevation
Function IsAdmin()
    On Error Resume Next
    WshShell.RegRead "HKEY_USERS\S-1-5-19\Environment\TEMP"
    If Err.Number = 0 Then IsAdmin = True Else IsAdmin = False
    On Error GoTo 0
End Function

If Not IsAdmin() Then
    Set objShell = CreateObject("Shell.Application")
    Args = ""
    For Each arg In WScript.Arguments
        Args = Args & " " & Chr(34) & arg & Chr(34)
    Next
    objShell.ShellExecute "wscript.exe", Chr(34) & WScript.ScriptFullName & Chr(34) & Args, "", "runas", 0
    WScript.Quit
End If

' 🔵 Main Logic
TargetFile = WScript.Arguments(0)
Quote = Chr(34)

' 🔵 Paths
BaseDir = fso.GetParentFolderName(WScript.ScriptFullName)
RunAsTI_Script = BaseDir & "\assets\RunAsTI\RunAsTI.ps1"
Manage_Script  = BaseDir & "\Manage_Ownership.ps1"

If (Not fso.FileExists(RunAsTI_Script)) Or (Not fso.FileExists(Manage_Script)) Then
    MsgBox "Required TakeOwnership files are missing. Please reinstall.", 16, "TakeOwnership"
    WScript.Quit 1
End If

' 🔵 Calls RunAsTI.ps1 with -TargetFile AND -ScriptPath (Universal!)
TargetArgs = "-TargetFile " & Quote & TargetFile & Quote & " -ScriptPath " & Quote & Manage_Script & Quote

PsCmd = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File " & Quote & RunAsTI_Script & Quote & " " & TargetArgs

Command = "pwsh " & PsCmd

' 🔵 Debug Configuration (Set to True to enable logging)
Const DebugMode = False

If DebugMode Then
    Set logFile = fso.CreateTextFile(BaseDir & "\debug_vbs.txt", True)
    logFile.WriteLine "TimeStamp: " & Now
    logFile.WriteLine "TargetFile: " & TargetFile
    logFile.WriteLine "FullCommand: " & Command
    logFile.Close
End If

WshShell.Run Command, 0, False
