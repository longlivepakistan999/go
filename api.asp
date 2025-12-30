<%
Response.Buffer = True
Response.ContentType = "application/json"
Response.Charset = "utf-8"

Dim fso
Set fso = Server.CreateObject("Scripting.FileSystemObject")

Dim action, password, PASSWORD, path

action = GetParam("action")
password = GetParam("password")

' Password config (line ~15)
PASSWORD = "your_password_here"

If PASSWORD <> "" And PASSWORD <> "your_password_here" Then
    If password <> PASSWORD Then
        Response.Write "{""success"":false,""data"":null,""message"":""Unauthorized""}"
        Response.End
    End If
End If

Select Case action
    Case "list"
        DoList
    Case "read"
        DoRead
    Case "write"
        DoWrite
    Case "mkdir"
        DoMkdir
    Case "delete"
        DoDelete
    Case "rename"
        DoRename
    Case "download"
        DoDownload
    Case "touch"
        DoTouch
    Case "info"
        DoInfo
    Case "server"
        DoServer
    Case Else
        Response.Write "{""success"":false,""data"":null,""message"":""Unknown action""}"
End Select

Set fso = Nothing

Public Function GetParam(key)
    GetParam = ""
    If Request.QueryString(key) <> "" Then
        GetParam = Request.QueryString(key)
    ElseIf Request.Form(key) <> "" Then
        GetParam = Request.Form(key)
    End If
End Function

Public Function SafePath(p)
    If p = "" Or p = "/" Then
        SafePath = fso.GetParentFolderName(Request.ServerVariables("PATH_TRANSLATED"))
    Else
        p = Replace(p, "../", "")
        p = Replace(p, "..\", "")
        SafePath = p
    End If
End Function

Public Function EscapeJson(s)
    If IsNull(s) Then s = ""
    s = Replace(s, "\", "\\")
    s = Replace(s, """", "\""")
    s = Replace(s, Chr(10), "\n")
    s = Replace(s, Chr(13), "\r")
    s = Replace(s, Chr(9), "\t")
    EscapeJson = s
End Function

Public Function FormatSize(bytes)
    Dim units, i, size
    units = Array("B", "KB", "MB", "GB", "TB")
    If bytes = 0 Then
        FormatSize = "0 B"
        Exit Function
    End If
    size = CDbl(bytes)
    i = 0
    Do While size >= 1024 And i < 4
        size = size / 1024
        i = i + 1
    Loop
    FormatSize = Round(size, 2) & " " & units(i)
End Function

Public Function ToTimestamp(dt)
    On Error Resume Next
    ToTimestamp = DateDiff("s", DateSerial(1970, 1, 1), dt)
    If Err.Number <> 0 Then ToTimestamp = 0
    On Error GoTo 0
End Function

Public Sub DoList()
    Dim p, folder, subfolder, file, items
    p = SafePath(GetParam("path"))

    If Not fso.FolderExists(p) Then
        Response.Write "{""success"":false,""data"":null,""message"":""Directory not found""}"
        Exit Sub
    End If

    Set folder = fso.GetFolder(p)
    items = "["

    If fso.GetParentFolderName(p) <> "" Then
        items = items & "{""name"":"".."",""path"":""" & EscapeJson(fso.GetParentFolderName(p)) & """,""is_dir"":true,""size"":0,""size_formatted"":""-"",""mtime"":0,""perms"":""drwxr-xr-x"",""readable"":true,""writable"":true}"
    End If

    For Each subfolder In folder.SubFolders
        If items <> "[" Then items = items & ","
        items = items & "{""name"":""" & EscapeJson(subfolder.Name) & """,""path"":""" & EscapeJson(subfolder.Path) & """,""is_dir"":true,""size"":0,""size_formatted"":""-"",""mtime"":" & ToTimestamp(subfolder.DateLastModified) & ",""perms"":""drwxr-xr-x"",""readable"":true,""writable"":true}"
    Next

    For Each file In folder.Files
        If items <> "[" Then items = items & ","
        items = items & "{""name"":""" & EscapeJson(file.Name) & """,""path"":""" & EscapeJson(file.Path) & """,""is_dir"":false,""size"":" & file.Size & ",""size_formatted"":""" & FormatSize(file.Size) & """,""mtime"":" & ToTimestamp(file.DateLastModified) & ",""perms"":""-rwxr-xr-x"",""readable"":true,""writable"":true}"
    Next

    items = items & "]"
    Set folder = Nothing

    Response.Write "{""success"":true,""data"":{""path"":""" & EscapeJson(p) & """,""items"":" & items & "},""message"":""""}"
End Sub

Public Sub DoRead()
    Dim p, ts, content
    p = SafePath(GetParam("path"))

    If Not fso.FileExists(p) Then
        Response.Write "{""success"":false,""data"":null,""message"":""File not found""}"
        Exit Sub
    End If

    On Error Resume Next
    Set ts = fso.OpenTextFile(p, 1, False, -1)
    content = ts.ReadAll()
    ts.Close
    Set ts = Nothing
    On Error GoTo 0

    Response.Write "{""success"":true,""data"":{""path"":""" & EscapeJson(p) & """,""content"":""" & EscapeJson(content) & """,""size"":" & Len(content) & "},""message"":""""}"
End Sub

Public Sub DoWrite()
    Dim p, content, ts
    p = GetParam("path")
    content = Request.Form("content")

    If p = "" Then
        Response.Write "{""success"":false,""data"":null,""message"":""Path empty""}"
        Exit Sub
    End If

    On Error Resume Next
    Set ts = fso.CreateTextFile(p, True, True)
    ts.Write content
    ts.Close
    Set ts = Nothing
    On Error GoTo 0

    Response.Write "{""success"":true,""data"":{""bytes"":" & Len(content) & "},""message"":""Saved""}"
End Sub

Public Sub DoMkdir()
    Dim p
    p = GetParam("path")

    If p = "" Then
        Response.Write "{""success"":false,""data"":null,""message"":""Path empty""}"
        Exit Sub
    End If

    If fso.FolderExists(p) Then
        Response.Write "{""success"":false,""data"":null,""message"":""Already exists""}"
        Exit Sub
    End If

    On Error Resume Next
    fso.CreateFolder(p)
    On Error GoTo 0

    Response.Write "{""success"":true,""data"":null,""message"":""Created""}"
End Sub

Public Sub DoDelete()
    Dim p
    p = SafePath(GetParam("path"))

    On Error Resume Next
    If fso.FolderExists(p) Then
        fso.DeleteFolder p, True
    ElseIf fso.FileExists(p) Then
        fso.DeleteFile p, True
    Else
        Response.Write "{""success"":false,""data"":null,""message"":""Not found""}"
        Exit Sub
    End If
    On Error GoTo 0

    Response.Write "{""success"":true,""data"":null,""message"":""Deleted""}"
End Sub

Public Sub DoRename()
    Dim oldP, newP
    oldP = SafePath(GetParam("old_path"))
    newP = GetParam("new_path")

    If newP = "" Then
        Response.Write "{""success"":false,""data"":null,""message"":""New path empty""}"
        Exit Sub
    End If

    On Error Resume Next
    If fso.FolderExists(oldP) Then
        fso.MoveFolder oldP, newP
    ElseIf fso.FileExists(oldP) Then
        fso.MoveFile oldP, newP
    Else
        Response.Write "{""success"":false,""data"":null,""message"":""Not found""}"
        Exit Sub
    End If
    On Error GoTo 0

    Response.Write "{""success"":true,""data"":null,""message"":""Renamed""}"
End Sub

Public Sub DoDownload()
    Dim p, stream
    p = SafePath(GetParam("path"))

    If Not fso.FileExists(p) Then
        Response.Status = "404 Not Found"
        Response.Write "Not found"
        Response.End
    End If

    Response.Clear
    Response.ContentType = "application/octet-stream"
    Response.AddHeader "Content-Disposition", "attachment; filename=""" & fso.GetFileName(p) & """"

    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.LoadFromFile p
    Response.BinaryWrite stream.Read
    stream.Close
    Set stream = Nothing
    Response.End
End Sub

Public Sub DoTouch()
    Response.Write "{""success"":false,""data"":null,""message"":""Touch not supported in Classic ASP""}"
End Sub

Public Sub DoInfo()
    Dim p, f, isDir, size, mtime, ctime
    p = SafePath(GetParam("path"))
    isDir = False
    size = 0
    mtime = 0
    ctime = 0

    If fso.FolderExists(p) Then
        isDir = True
        Set f = fso.GetFolder(p)
        mtime = ToTimestamp(f.DateLastModified)
        ctime = ToTimestamp(f.DateCreated)
        Set f = Nothing
    ElseIf fso.FileExists(p) Then
        Set f = fso.GetFile(p)
        size = f.Size
        mtime = ToTimestamp(f.DateLastModified)
        ctime = ToTimestamp(f.DateCreated)
        Set f = Nothing
    Else
        Response.Write "{""success"":false,""data"":null,""message"":""Not found""}"
        Exit Sub
    End If

    Response.Write "{""success"":true,""data"":{""path"":""" & EscapeJson(p) & """,""name"":""" & EscapeJson(fso.GetFileName(p)) & """,""is_dir"":" & LCase(CStr(isDir)) & ",""size"":" & size & ",""size_formatted"":""" & FormatSize(size) & """,""mtime"":" & mtime & ",""ctime"":" & ctime & ",""atime"":" & mtime & ",""perms"":""-rwxr-xr-x"",""perms_octal"":""0755"",""readable"":true,""writable"":true,""owner"":0,""group"":0},""message"":""""}"
End Sub

Public Sub DoServer()
    Dim drive, diskFree, diskTotal, currentUser
    diskFree = 0
    diskTotal = 0

    On Error Resume Next
    Set drive = fso.GetDrive(fso.GetDriveName(Request.ServerVariables("PATH_TRANSLATED")))
    If Err.Number = 0 Then
        diskFree = drive.FreeSpace
        diskTotal = drive.TotalSize
        Set drive = Nothing
    End If
    On Error GoTo 0

    currentUser = Request.ServerVariables("LOGON_USER")
    If currentUser = "" Then currentUser = "Anonymous"

    Response.Write "{""success"":true,""data"":{""php_version"":""ASP Classic"",""server_software"":""" & EscapeJson(Request.ServerVariables("SERVER_SOFTWARE")) & """,""document_root"":""" & EscapeJson(Request.ServerVariables("APPL_PHYSICAL_PATH")) & """,""script_path"":""" & EscapeJson(Request.ServerVariables("PATH_TRANSLATED")) & """,""upload_max"":""N/A"",""post_max"":""N/A"",""disk_free"":""" & FormatSize(diskFree) & """,""disk_total"":""" & FormatSize(diskTotal) & """,""current_user"":""" & EscapeJson(currentUser) & """},""message"":""""}"
End Sub
%>