Option Explicit

If WScript.Arguments.Count < 1 Then
    WScript.Quit 2
End If

Dim shell, command, i
Set shell = CreateObject("WScript.Shell")

command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " & Quote(WScript.Arguments(0))
For i = 1 To WScript.Arguments.Count - 1
    command = command & " " & Quote(WScript.Arguments(i))
Next
WScript.Quit shell.Run(command, 0, True)

Function Quote(value)
    Quote = """" & Replace(value, """", """""") & """"
End Function
