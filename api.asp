<%@ Language="VBScript" CodePage="65001" %>
<% On Error Resume Next %>
<%
' Remote File Manager API - Classic ASP Version

Option Explicit
Response.Buffer = True
Response.ContentType = "application/json"
Response.Charset = "utf-8"

Dim fso, action, password, PASSWORD

Set fso = Server.CreateObject("Scripting.FileSystemObject")

action = GetParam("action", "")

' Return blank if no action provided
If action = "" Then
    Response.End
End If

' Get password from request
password = ""
If Request.ServerVariables("HTTP_X_PASSWORD") <> "" Then
    password = Request.ServerVariables("HTTP_X_PASSWORD")
ElseIf Request.Form("password") <> "" Then
    password = Request.Form("password")
ElseIf Request.QueryString("password") <> "" Then
    password = Request.QueryString("password")
End If

' Access token configuration
PASSWORD = "your_password_here"

' Verify access token
If PASSWORD <> "" And PASSWORD <> "your_password_here" Then
    If password <> PASSWORD Then
        Response.Status = "401 Unauthorized"
        Response.Write "{""success"":false,""data"":null,""message"":""Unauthorized""}"
        Response.End
    End If
End If

' Route actions
Select Case action
    Case "list"
        Call ListDirectory()
    Case "read"
        Call ReadFile()
    Case "write"
        Call WriteFile()
    Case "mkdir"
        Call CreateDirectory()
    Case "delete"
        Call DeleteItem()
    Case "rename"
        Call RenameItem()
    Case "download"
        Call DownloadFile()
    Case "touch"
        Call TouchFile()
    Case "info"
        Call GetFileInfo()
    Case "server"
        Call GetServerInfo()
    Case Else
        Call SendResponse(False, "", "Unknown action")
End Select

Set fso = Nothing

' ========== Helper Functions ==========

Function GetParam(key, defaultValue)
    If Request.QueryString(key) <> "" Then
        GetParam = Request.QueryString(key)
    ElseIf Request.Form(key) <> "" Then
        GetParam = Request.Form(key)
    Else
        GetParam = defaultValue
    End If
End Function

Function GetDefaultDir()
    GetDefaultDir = fso.GetParentFolderName(Request.ServerVariables("PATH_TRANSLATED"))
End Function

Function SafePath(path)
    path = Replace(path, "../", "")
    path = Replace(path, "..\", "")

    If path = "" Or path = "/" Then
        SafePath = GetDefaultDir()
    Else
        SafePath = path
    End If
End Function

Sub SendResponse(success, data, message)
    Dim json
    json = "{""success"":" & LCase(CStr(success)) & ","
    json = json & """data"":" & data & ","
    json = json & """message"":""" & EscapeJson(message) & """}"
    Response.Write json
    Response.End
End Sub

Function EscapeJson(str)
    str = Replace(str, "\", "\\")
    str = Replace(str, """", "\""")
    str = Replace(str, Chr(10), "\n")
    str = Replace(str, Chr(13), "\r")
    str = Replace(str, Chr(9), "\t")
    EscapeJson = str
End Function

Function FormatSize(bytes)
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

Function DateToTimestamp(dt)
    On Error Resume Next
    Dim d1970
    d1970 = DateSerial(1970, 1, 1)
    DateToTimestamp = DateDiff("s", d1970, dt)
    If Err.Number <> 0 Then DateToTimestamp = 0
    On Error GoTo 0
End Function

' ========== Action Handlers ==========

Sub ListDirectory()
    Dim path, folder, subfolder, file, items, itemJson
    path = SafePath(GetParam("path", "/"))

    If Not fso.FolderExists(path) Then
        Call SendResponse(False, "null", "Not a valid directory")
        Exit Sub
    End If

    Set folder = fso.GetFolder(path)
    items = "["

    ' Add parent directory
    If fso.GetParentFolderName(path) <> "" Then
        items = items & "{""name"":"".."",""path"":""" & EscapeJson(fso.GetParentFolderName(path)) & ""","
        items = items & """is_dir"":true,""size"":0,""size_formatted"":""-"","
        items = items & """mtime"":0,""perms"":""drwxr-xr-x"",""readable"":true,""writable"":true}"
    End If

    ' Add subdirectories
    For Each subfolder In folder.SubFolders
        If items <> "[" Then items = items & ","
        items = items & "{""name"":""" & EscapeJson(subfolder.Name) & ""","
        items = items & """path"":""" & EscapeJson(subfolder.Path) & ""","
        items = items & """is_dir"":true,""size"":0,""size_formatted"":""-"","
        items = items & """mtime"":" & DateToTimestamp(subfolder.DateLastModified) & ","
        items = items & """perms"":""drwxr-xr-x"",""readable"":true,""writable"":true}"
    Next

    ' Add files
    For Each file In folder.Files
        If items <> "[" Then items = items & ","
        items = items & "{""name"":""" & EscapeJson(file.Name) & ""","
        items = items & """path"":""" & EscapeJson(file.Path) & ""","
        items = items & """is_dir"":false,""size"":" & file.Size & ","
        items = items & """size_formatted"":""" & FormatSize(file.Size) & ""","
        items = items & """mtime"":" & DateToTimestamp(file.DateLastModified) & ","
        items = items & """perms"":""-rwxr-xr-x"",""readable"":true,""writable"":true}"
    Next

    items = items & "]"

    Set folder = Nothing

    Dim data
    data = "{""path"":""" & EscapeJson(path) & """,""items"":" & items & "}"
    Call SendResponse(True, data, "")
End Sub

Sub ReadFile()
    Dim path, ts, content
    path = SafePath(GetParam("path", ""))

    If Not fso.FileExists(path) Then
        Call SendResponse(False, "null", "File does not exist")
        Exit Sub
    End If

    On Error Resume Next
    Set ts = fso.OpenTextFile(path, 1, False, -1)
    If Err.Number <> 0 Then
        Call SendResponse(False, "null", "Read failed")
        Exit Sub
    End If

    content = ts.ReadAll()
    ts.Close
    Set ts = Nothing
    On Error GoTo 0

    Dim data
    data = "{""path"":""" & EscapeJson(path) & """,""content"":""" & EscapeJson(content) & """,""size"":" & Len(content) & "}"
    Call SendResponse(True, data, "")
End Sub

Sub WriteFile()
    Dim path, content, ts
    path = GetParam("path", "")
    content = Request.Form("content")

    If path = "" Then
        Call SendResponse(False, "null", "Path cannot be empty")
        Exit Sub
    End If

    On Error Resume Next
    Set ts = fso.CreateTextFile(path, True, True)
    If Err.Number <> 0 Then
        Call SendResponse(False, "null", "Write failed")
        Exit Sub
    End If

    ts.Write content
    ts.Close
    Set ts = Nothing
    On Error GoTo 0

    Dim data
    data = "{""bytes"":" & Len(content) & "}"
    Call SendResponse(True, data, "Saved successfully")
End Sub

Sub CreateDirectory()
    Dim path
    path = GetParam("path", "")

    If path = "" Then
        Call SendResponse(False, "null", "Path cannot be empty")
        Exit Sub
    End If

    If fso.FolderExists(path) Then
        Call SendResponse(False, "null", "Directory already exists")
        Exit Sub
    End If

    On Error Resume Next
    fso.CreateFolder(path)
    If Err.Number <> 0 Then
        Call SendResponse(False, "null", "Create failed")
        Exit Sub
    End If
    On Error GoTo 0

    Call SendResponse(True, "null", "Created successfully")
End Sub

Sub DeleteItem()
    Dim path
    path = SafePath(GetParam("path", ""))

    If path = "" Then
        Call SendResponse(False, "null", "Path cannot be empty")
        Exit Sub
    End If

    On Error Resume Next
    If fso.FolderExists(path) Then
        fso.DeleteFolder path, True
    ElseIf fso.FileExists(path) Then
        fso.DeleteFile path, True
    Else
        Call SendResponse(False, "null", "File does not exist")
        Exit Sub
    End If

    If Err.Number <> 0 Then
        Call SendResponse(False, "null", "Delete failed")
        Exit Sub
    End If
    On Error GoTo 0

    Call SendResponse(True, "null", "Deleted successfully")
End Sub

Sub RenameItem()
    Dim oldPath, newPath
    oldPath = SafePath(GetParam("old_path", ""))
    newPath = GetParam("new_path", "")

    If oldPath = "" Or newPath = "" Then
        Call SendResponse(False, "null", "Path cannot be empty")
        Exit Sub
    End If

    On Error Resume Next
    If fso.FolderExists(oldPath) Then
        fso.MoveFolder oldPath, newPath
    ElseIf fso.FileExists(oldPath) Then
        fso.MoveFile oldPath, newPath
    Else
        Call SendResponse(False, "null", "File does not exist")
        Exit Sub
    End If

    If Err.Number <> 0 Then
        Call SendResponse(False, "null", "Rename failed")
        Exit Sub
    End If
    On Error GoTo 0

    Call SendResponse(True, "null", "Renamed successfully")
End Sub

Sub DownloadFile()
    Dim path, stream
    path = SafePath(GetParam("path", ""))

    If Not fso.FileExists(path) Then
        Response.Status = "404 Not Found"
        Response.Write "File not found"
        Response.End
    End If

    Response.Clear
    Response.ContentType = "application/octet-stream"
    Response.AddHeader "Content-Disposition", "attachment; filename=""" & fso.GetFileName(path) & """"

    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.LoadFromFile path
    Response.BinaryWrite stream.Read
    stream.Close
    Set stream = Nothing

    Response.End
End Sub

Sub TouchFile()
    ' Note: Classic ASP cannot modify file timestamps directly
    ' This would require shell execution which we avoid for security
    Call SendResponse(False, "null", "Touch not supported in classic ASP")
End Sub

Sub GetFileInfo()
    Dim path, file, folder, isDir, size, mtime, ctime
    path = SafePath(GetParam("path", ""))

    isDir = False
    size = 0
    mtime = 0
    ctime = 0

    If fso.FolderExists(path) Then
        isDir = True
        Set folder = fso.GetFolder(path)
        mtime = DateToTimestamp(folder.DateLastModified)
        ctime = DateToTimestamp(folder.DateCreated)
        Set folder = Nothing
    ElseIf fso.FileExists(path) Then
        Set file = fso.GetFile(path)
        size = file.Size
        mtime = DateToTimestamp(file.DateLastModified)
        ctime = DateToTimestamp(file.DateCreated)
        Set file = Nothing
    Else
        Call SendResponse(False, "null", "File does not exist")
        Exit Sub
    End If

    Dim data
    data = "{""path"":""" & EscapeJson(path) & ""","
    data = data & """name"":""" & EscapeJson(fso.GetFileName(path)) & ""","
    data = data & """is_dir"":" & LCase(CStr(isDir)) & ","
    data = data & """size"":" & size & ","
    data = data & """size_formatted"":""" & FormatSize(size) & ""","
    data = data & """mtime"":" & mtime & ","
    data = data & """ctime"":" & ctime & ","
    data = data & """atime"":" & mtime & ","
    data = data & """perms"":""-rwxr-xr-x"","
    data = data & """perms_octal"":""0755"","
    data = data & """readable"":true,""writable"":true,"
    data = data & """owner"":0,""group"":0}"

    Call SendResponse(True, data, "")
End Sub

Sub GetServerInfo()
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

    currentUser = Request.ServerVariables("AUTH_USER")
    If currentUser = "" Then currentUser = Request.ServerVariables("LOGON_USER")
    If currentUser = "" Then currentUser = "Anonymous"

    Dim data
    data = "{""php_version"":""ASP Classic"","
    data = data & """server_software"":""" & EscapeJson(Request.ServerVariables("SERVER_SOFTWARE")) & ""","
    data = data & """document_root"":""" & EscapeJson(Request.ServerVariables("APPL_PHYSICAL_PATH")) & ""","
    data = data & """script_path"":""" & EscapeJson(Request.ServerVariables("PATH_TRANSLATED")) & ""","
    data = data & """upload_max"":""N/A"","
    data = data & """post_max"":""N/A"","
    data = data & """disk_free"":""" & FormatSize(diskFree) & ""","
    data = data & """disk_total"":""" & FormatSize(diskTotal) & ""","
    data = data & """current_user"":""" & EscapeJson(currentUser) & """}"

    Call SendResponse(True, data, "")
End Sub
%>
