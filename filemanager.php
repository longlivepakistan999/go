<?php
/**
 * PHP Web 文件管理器
 * 功能：目录浏览、文件增删改查、上传文件、服务器信息
 * 安全：不使用高危函数(exec, shell_exec, system, passthru等)
 */

// 配置
define('ROOT_PATH', '/'); // 允许浏览整个文件系统
define('DEFAULT_PATH', __DIR__); // 默认起始目录
define('MAX_UPLOAD_SIZE', 10 * 1024 * 1024); // 最大上传10MB

// 安全函数：规范化路径，防止目录穿越
function safePath($path) {
    // 过滤目录穿越字符
    $path = str_replace(['../', '..\\'], '', $path);

    // 如果路径为空，返回默认路径
    if (empty($path)) {
        return DEFAULT_PATH;
    }

    $realPath = realpath($path);

    // 如果路径不存在，返回默认路径
    if ($realPath === false) {
        return DEFAULT_PATH;
    }

    return $realPath;
}

// 获取当前目录
$currentDir = isset($_GET['dir']) ? $_GET['dir'] : DEFAULT_PATH;
$currentDir = safePath($currentDir);

// 格式化文件大小
function formatSize($bytes) {
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $i = 0;
    while ($bytes >= 1024 && $i < count($units) - 1) {
        $bytes /= 1024;
        $i++;
    }
    return round($bytes, 2) . ' ' . $units[$i];
}

// 格式化权限
function formatPerms($path) {
    $info = '';

    // 文件类型
    if (@is_link($path)) $info = 'l';
    elseif (@is_dir($path)) $info = 'd';
    else $info = '-';

    $perms = @fileperms($path);
    if ($perms === false) {
        return $info . '?????????';
    }

    // 所有者权限
    $info .= (($perms & 0x0100) ? 'r' : '-');
    $info .= (($perms & 0x0080) ? 'w' : '-');
    $info .= (($perms & 0x0040) ? 'x' : '-');

    // 组权限
    $info .= (($perms & 0x0020) ? 'r' : '-');
    $info .= (($perms & 0x0010) ? 'w' : '-');
    $info .= (($perms & 0x0008) ? 'x' : '-');

    // 其他权限
    $info .= (($perms & 0x0004) ? 'r' : '-');
    $info .= (($perms & 0x0002) ? 'w' : '-');
    $info .= (($perms & 0x0001) ? 'x' : '-');

    return $info;
}

// 获取权限的八进制表示
function getOctalPerms($path) {
    $perms = @fileperms($path);
    if ($perms === false) {
        return '????';
    }
    return substr(sprintf('%o', $perms), -4);
}

// 处理消息
$message = '';
$messageType = 'info';

// 处理文件上传
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['upload_file'])) {
    $uploadFile = $_FILES['upload_file'];

    if ($uploadFile['error'] === UPLOAD_ERR_OK) {
        if ($uploadFile['size'] <= MAX_UPLOAD_SIZE) {
            $targetPath = $currentDir . DIRECTORY_SEPARATOR . basename($uploadFile['name']);
            if (move_uploaded_file($uploadFile['tmp_name'], $targetPath)) {
                $message = '文件上传成功: ' . htmlspecialchars(basename($uploadFile['name']));
                $messageType = 'success';
            } else {
                $message = '文件上传失败';
                $messageType = 'error';
            }
        } else {
            $message = '文件大小超过限制 (' . formatSize(MAX_UPLOAD_SIZE) . ')';
            $messageType = 'error';
        }
    } else {
        $message = '上传错误: ' . $uploadFile['error'];
        $messageType = 'error';
    }
}

// 处理创建文件
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'create') {
    $newName = isset($_POST['new_name']) ? trim($_POST['new_name']) : '';
    $isDir = isset($_POST['is_dir']) && $_POST['is_dir'] === '1';

    if (!empty($newName) && !preg_match('/[\/\\\\:*?"<>|]/', $newName)) {
        $newPath = $currentDir . DIRECTORY_SEPARATOR . $newName;

        if (!file_exists($newPath)) {
            if ($isDir) {
                if (mkdir($newPath, 0755)) {
                    $message = '目录创建成功: ' . htmlspecialchars($newName);
                    $messageType = 'success';
                } else {
                    $message = '目录创建失败';
                    $messageType = 'error';
                }
            } else {
                if (file_put_contents($newPath, '') !== false) {
                    $message = '文件创建成功: ' . htmlspecialchars($newName);
                    $messageType = 'success';
                } else {
                    $message = '文件创建失败';
                    $messageType = 'error';
                }
            }
        } else {
            $message = '文件或目录已存在';
            $messageType = 'error';
        }
    } else {
        $message = '无效的文件名';
        $messageType = 'error';
    }
}

// 处理删除
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete') {
    $deletePath = isset($_POST['path']) ? safePath($_POST['path']) : '';

    if (!empty($deletePath) && $deletePath !== ROOT_PATH) {
        if (is_dir($deletePath)) {
            // 递归删除目录
            function deleteDir($dir) {
                if (!is_dir($dir)) return false;
                $items = scandir($dir);
                foreach ($items as $item) {
                    if ($item === '.' || $item === '..') continue;
                    $path = $dir . DIRECTORY_SEPARATOR . $item;
                    if (is_dir($path)) {
                        deleteDir($path);
                    } else {
                        unlink($path);
                    }
                }
                return rmdir($dir);
            }

            if (deleteDir($deletePath)) {
                $message = '目录删除成功';
                $messageType = 'success';
            } else {
                $message = '目录删除失败';
                $messageType = 'error';
            }
        } else {
            if (unlink($deletePath)) {
                $message = '文件删除成功';
                $messageType = 'success';
            } else {
                $message = '文件删除失败';
                $messageType = 'error';
            }
        }
    }
}

// 处理重命名
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'rename') {
    $oldPath = isset($_POST['old_path']) ? safePath($_POST['old_path']) : '';
    $newName = isset($_POST['new_name']) ? trim($_POST['new_name']) : '';

    if (!empty($oldPath) && !empty($newName) && !preg_match('/[\/\\\\:*?"<>|]/', $newName)) {
        $newPath = dirname($oldPath) . DIRECTORY_SEPARATOR . $newName;

        if (!file_exists($newPath)) {
            if (rename($oldPath, $newPath)) {
                $message = '重命名成功';
                $messageType = 'success';
            } else {
                $message = '重命名失败';
                $messageType = 'error';
            }
        } else {
            $message = '目标文件已存在';
            $messageType = 'error';
        }
    }
}

// 处理保存文件内容
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'save') {
    $filePath = isset($_POST['file_path']) ? safePath($_POST['file_path']) : '';
    $content = isset($_POST['content']) ? $_POST['content'] : '';

    if (!empty($filePath) && is_file($filePath)) {
        if (file_put_contents($filePath, $content) !== false) {
            $message = '文件保存成功';
            $messageType = 'success';
        } else {
            $message = '文件保存失败';
            $messageType = 'error';
        }
    }
}

// 编辑文件模式
$editMode = false;
$editContent = '';
$editPath = '';
if (isset($_GET['edit'])) {
    $editPath = safePath($_GET['edit']);
    if (is_file($editPath) && is_readable($editPath)) {
        $editMode = true;
        $editContent = file_get_contents($editPath);
    }
}

// 查看文件模式
$viewMode = false;
$viewContent = '';
$viewPath = '';
if (isset($_GET['view'])) {
    $viewPath = safePath($_GET['view']);
    if (is_file($viewPath) && is_readable($viewPath)) {
        $viewMode = true;
        $viewContent = file_get_contents($viewPath);
    }
}

// 服务器信息模式
$serverInfoMode = isset($_GET['serverinfo']);

// 获取目录内容
$items = [];
if (is_dir($currentDir) && is_readable($currentDir)) {
    $scanItems = scandir($currentDir);
    foreach ($scanItems as $item) {
        if ($item === '.') continue;

        $itemPath = $currentDir . DIRECTORY_SEPARATOR . $item;
        $items[] = [
            'name' => $item,
            'path' => $itemPath,
            'is_dir' => @is_dir($itemPath),
            'size' => @is_file($itemPath) ? @filesize($itemPath) : 0,
            'perms' => formatPerms($itemPath),
            'octal' => getOctalPerms($itemPath),
            'ctime' => @filectime($itemPath) ?: 0,
            'mtime' => @filemtime($itemPath) ?: 0,
            'readable' => @is_readable($itemPath),
            'writable' => @is_writable($itemPath)
        ];
    }

    // 排序：目录在前，文件在后
    usort($items, function($a, $b) {
        if ($a['is_dir'] && !$b['is_dir']) return -1;
        if (!$a['is_dir'] && $b['is_dir']) return 1;
        return strcasecmp($a['name'], $b['name']);
    });
}

// 生成面包屑导航
function getBreadcrumbs($path) {
    $crumbs = [];

    // 确保路径是绝对路径
    $path = realpath($path);
    if ($path === false) {
        $path = '/';
    }

    // 将路径分割成各个部分
    $parts = explode('/', trim($path, '/'));

    // 添加根目录
    $crumbs[] = [
        'name' => 'Root /',
        'path' => '/'
    ];

    // 逐级构建路径
    $buildPath = '';
    foreach ($parts as $part) {
        if ($part === '') continue;
        $buildPath .= '/' . $part;
        $crumbs[] = [
            'name' => $part,
            'path' => $buildPath
        ];
    }

    return $crumbs;
}

$breadcrumbs = getBreadcrumbs($currentDir);
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHP 文件管理器</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: #f5f7fa;
            color: #333;
            line-height: 1.6;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
        }

        .header-top {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }

        .header h1 {
            font-size: 24px;
        }

        .header-path {
            background: rgba(255,255,255,0.15);
            padding: 12px 18px;
            border-radius: 8px;
            font-family: 'Fira Code', 'Monaco', 'Consolas', monospace;
            font-size: 14px;
        }

        .header-path .path-icon {
            margin-right: 10px;
            font-size: 16px;
        }

        .header-path .current-path {
            font-weight: 600;
            font-size: 15px;
            display: block;
            margin-bottom: 8px;
            word-break: break-all;
        }

        .header-path .path-nav {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 2px;
        }

        .header-path .path-nav a {
            color: rgba(255,255,255,0.85);
            text-decoration: none;
            padding: 3px 6px;
            border-radius: 3px;
            font-size: 12px;
            transition: background 0.2s;
        }

        .header-path .path-nav a:hover {
            background: rgba(255,255,255,0.25);
            color: #fff;
        }

        .header-path .separator {
            color: rgba(255,255,255,0.5);
            font-size: 12px;
        }

        .header-actions a {
            color: white;
            text-decoration: none;
            padding: 8px 16px;
            background: rgba(255,255,255,0.2);
            border-radius: 5px;
            margin-left: 10px;
            transition: background 0.3s;
        }

        .header-actions a:hover {
            background: rgba(255,255,255,0.3);
        }

        .message {
            padding: 15px 20px;
            border-radius: 8px;
            margin-bottom: 20px;
        }

        .message.success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }

        .message.error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }

        .message.info {
            background: #d1ecf1;
            color: #0c5460;
            border: 1px solid #bee5eb;
        }

        .toolbar {
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            display: flex;
            gap: 20px;
            flex-wrap: wrap;
        }

        .toolbar-form {
            flex: 1;
            min-width: 280px;
        }

        .toolbar-form .form-group {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }

        .toolbar-form .form-label {
            font-size: 13px;
            color: #555;
            font-weight: 500;
        }

        .toolbar-form .form-label code {
            background: #e9ecef;
            padding: 3px 8px;
            border-radius: 4px;
            font-family: 'Fira Code', 'Monaco', 'Consolas', monospace;
            font-size: 12px;
            color: #667eea;
            word-break: break-all;
        }

        .toolbar-form .form-row {
            display: flex;
            gap: 10px;
            align-items: center;
            flex-wrap: wrap;
        }

        .toolbar-form .checkbox-label {
            display: flex;
            align-items: center;
            gap: 5px;
            font-size: 14px;
            color: #555;
            white-space: nowrap;
        }

        .toolbar input[type="text"],
        .toolbar input[type="file"] {
            padding: 8px 12px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
        }

        .toolbar input[type="text"] {
            flex: 1;
            min-width: 150px;
        }

        .toolbar input[type="file"] {
            padding: 5px;
            flex: 1;
            min-width: 180px;
        }

        .btn {
            padding: 8px 16px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.3s;
        }

        .btn-primary {
            background: #667eea;
            color: white;
        }

        .btn-primary:hover {
            background: #5a6fd6;
        }

        .btn-success {
            background: #28a745;
            color: white;
        }

        .btn-success:hover {
            background: #218838;
        }

        .btn-danger {
            background: #dc3545;
            color: white;
        }

        .btn-danger:hover {
            background: #c82333;
        }

        .btn-secondary {
            background: #6c757d;
            color: white;
        }

        .btn-secondary:hover {
            background: #5a6268;
        }

        .file-table {
            width: 100%;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            overflow: hidden;
        }

        .file-table table {
            width: 100%;
            border-collapse: collapse;
        }

        .file-table th,
        .file-table td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid #eee;
        }

        .file-table th {
            background: #f8f9fa;
            font-weight: 600;
            color: #555;
        }

        .file-table tr:hover {
            background: #f8f9fa;
        }

        .file-table .icon {
            width: 24px;
            display: inline-block;
            text-align: center;
            margin-right: 8px;
        }

        .file-table .dir {
            color: #667eea;
        }

        .file-table .file {
            color: #28a745;
        }

        .file-table a {
            color: #333;
            text-decoration: none;
        }

        .file-table a:hover {
            color: #667eea;
        }

        .file-table .actions {
            white-space: nowrap;
        }

        .file-table .actions a,
        .file-table .actions button {
            padding: 4px 8px;
            margin: 0 2px;
            font-size: 12px;
            border-radius: 3px;
            text-decoration: none;
            display: inline-block;
            border: none;
            cursor: pointer;
        }

        .file-table .actions .edit {
            background: #17a2b8;
            color: white;
        }

        .file-table .actions .view {
            background: #6c757d;
            color: white;
        }

        .file-table .actions .delete {
            background: #dc3545;
            color: white;
        }

        .file-table .actions .rename {
            background: #ffc107;
            color: #333;
        }

        .perms {
            font-family: monospace;
            font-size: 13px;
        }

        .perms-octal {
            color: #666;
            font-size: 12px;
        }

        .editor {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        .editor h2 {
            margin-bottom: 15px;
            color: #333;
        }

        .editor textarea {
            width: 100%;
            height: 500px;
            padding: 15px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-family: 'Fira Code', 'Monaco', 'Consolas', monospace;
            font-size: 14px;
            line-height: 1.5;
            resize: vertical;
        }

        .editor .actions {
            margin-top: 15px;
            display: flex;
            gap: 10px;
        }

        .viewer {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        .viewer h2 {
            margin-bottom: 15px;
            color: #333;
        }

        .viewer pre {
            background: #2d2d2d;
            color: #f8f8f2;
            padding: 20px;
            border-radius: 5px;
            overflow-x: auto;
            font-family: 'Fira Code', 'Monaco', 'Consolas', monospace;
            font-size: 14px;
            line-height: 1.5;
            max-height: 600px;
            overflow-y: auto;
        }

        .server-info {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        .server-info h2 {
            margin-bottom: 20px;
            color: #333;
        }

        .server-info table {
            width: 100%;
            border-collapse: collapse;
        }

        .server-info th,
        .server-info td {
            padding: 10px 15px;
            text-align: left;
            border-bottom: 1px solid #eee;
        }

        .server-info th {
            background: #f8f9fa;
            width: 30%;
            font-weight: 600;
        }

        .server-info tr:hover {
            background: #f8f9fa;
        }

        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.5);
            z-index: 1000;
            justify-content: center;
            align-items: center;
        }

        .modal.active {
            display: flex;
        }

        .modal-content {
            background: white;
            padding: 25px;
            border-radius: 10px;
            min-width: 400px;
            max-width: 90%;
        }

        .modal-content h3 {
            margin-bottom: 20px;
        }

        .modal-content input[type="text"] {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            margin-bottom: 15px;
        }

        .modal-content .actions {
            display: flex;
            gap: 10px;
            justify-content: flex-end;
        }

        .status-badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 11px;
        }

        .status-badge.readable {
            background: #d4edda;
            color: #155724;
        }

        .status-badge.writable {
            background: #cce5ff;
            color: #004085;
        }

        .status-badge.no-access {
            background: #f8d7da;
            color: #721c24;
        }

        @media (max-width: 768px) {
            .toolbar {
                flex-direction: column;
                align-items: stretch;
            }

            .toolbar {
                flex-direction: column;
            }

            .toolbar-form {
                width: 100%;
                min-width: auto;
            }

            .toolbar-form .form-row {
                flex-direction: column;
                align-items: stretch;
            }

            .toolbar input[type="text"],
            .toolbar input[type="file"] {
                width: 100%;
            }

            .file-table {
                overflow-x: auto;
            }

            .header-top {
                flex-direction: column;
                gap: 10px;
            }

            .header-path {
                font-size: 12px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="header-top">
                <h1>PHP 文件管理器</h1>
                <div class="header-actions">
                    <a href="?dir=<?php echo urlencode(DEFAULT_PATH); ?>">文件列表</a>
                    <a href="?serverinfo=1">服务器信息</a>
                </div>
            </div>
            <?php if (!$serverInfoMode): ?>
            <div class="header-path">
                <span class="path-icon">📂</span>
                <span class="current-path"><?php echo htmlspecialchars($currentDir); ?></span>
                <span class="path-nav">
                    <?php foreach ($breadcrumbs as $i => $crumb): ?>
                        <a href="?dir=<?php echo urlencode($crumb['path']); ?>" title="跳转到 <?php echo htmlspecialchars($crumb['path']); ?>"><?php echo htmlspecialchars($crumb['name']); ?></a>
                        <?php if ($i < count($breadcrumbs) - 1): ?><span class="separator">/</span><?php endif; ?>
                    <?php endforeach; ?>
                </span>
            </div>
            <?php endif; ?>
        </div>

        <?php if ($message): ?>
        <div class="message <?php echo $messageType; ?>">
            <?php echo $message; ?>
        </div>
        <?php endif; ?>

        <?php if ($serverInfoMode): ?>
        <!-- 服务器信息 -->
        <div class="server-info">
            <h2>服务器信息</h2>
            <table>
                <tr>
                    <th>PHP 版本</th>
                    <td><?php echo phpversion(); ?></td>
                </tr>
                <tr>
                    <th>操作系统</th>
                    <td><?php echo php_uname(); ?></td>
                </tr>
                <tr>
                    <th>服务器软件</th>
                    <td><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'N/A'; ?></td>
                </tr>
                <tr>
                    <th>服务器名称</th>
                    <td><?php echo $_SERVER['SERVER_NAME'] ?? 'N/A'; ?></td>
                </tr>
                <tr>
                    <th>服务器IP</th>
                    <td><?php echo $_SERVER['SERVER_ADDR'] ?? 'N/A'; ?></td>
                </tr>
                <tr>
                    <th>服务器端口</th>
                    <td><?php echo $_SERVER['SERVER_PORT'] ?? 'N/A'; ?></td>
                </tr>
                <tr>
                    <th>文档根目录</th>
                    <td><?php echo $_SERVER['DOCUMENT_ROOT'] ?? 'N/A'; ?></td>
                </tr>
                <tr>
                    <th>当前脚本路径</th>
                    <td><?php echo __FILE__; ?></td>
                </tr>
                <tr>
                    <th>PHP SAPI</th>
                    <td><?php echo php_sapi_name(); ?></td>
                </tr>
                <tr>
                    <th>最大上传大小</th>
                    <td><?php echo ini_get('upload_max_filesize'); ?></td>
                </tr>
                <tr>
                    <th>最大POST大小</th>
                    <td><?php echo ini_get('post_max_size'); ?></td>
                </tr>
                <tr>
                    <th>内存限制</th>
                    <td><?php echo ini_get('memory_limit'); ?></td>
                </tr>
                <tr>
                    <th>最大执行时间</th>
                    <td><?php echo ini_get('max_execution_time'); ?>秒</td>
                </tr>
                <tr>
                    <th>磁盘总空间</th>
                    <td><?php echo formatSize(disk_total_space('/')); ?></td>
                </tr>
                <tr>
                    <th>磁盘可用空间</th>
                    <td><?php echo formatSize(disk_free_space('/')); ?></td>
                </tr>
                <tr>
                    <th>当前用户</th>
                    <td><?php echo get_current_user(); ?></td>
                </tr>
                <tr>
                    <th>时区</th>
                    <td><?php echo date_default_timezone_get(); ?></td>
                </tr>
                <tr>
                    <th>当前时间</th>
                    <td><?php echo date('Y-m-d H:i:s'); ?></td>
                </tr>
                <tr>
                    <th>已加载扩展</th>
                    <td><?php echo implode(', ', get_loaded_extensions()); ?></td>
                </tr>
            </table>
        </div>

        <?php elseif ($editMode): ?>
        <!-- 编辑文件 -->
        <div class="editor">
            <h2>编辑文件</h2>
            <form method="post" action="?dir=<?php echo urlencode($currentDir); ?>">
                <input type="hidden" name="action" value="save">
                <input type="hidden" name="file_path" value="<?php echo htmlspecialchars($editPath); ?>">
                <textarea name="content"><?php echo htmlspecialchars($editContent); ?></textarea>
                <div class="actions">
                    <button type="submit" class="btn btn-success">保存文件</button>
                    <a href="?dir=<?php echo urlencode($currentDir); ?>" class="btn btn-secondary">返回</a>
                </div>
            </form>
        </div>

        <?php elseif ($viewMode): ?>
        <!-- 查看文件 -->
        <div class="viewer">
            <h2>文件内容</h2>
            <pre><?php echo htmlspecialchars($viewContent); ?></pre>
            <div style="margin-top: 15px;">
                <a href="?edit=<?php echo urlencode($viewPath); ?>&dir=<?php echo urlencode($currentDir); ?>" class="btn btn-primary">编辑</a>
                <a href="?dir=<?php echo urlencode($currentDir); ?>" class="btn btn-secondary">返回</a>
            </div>
        </div>

        <?php else: ?>
        <!-- 文件列表 -->
        <div class="toolbar">
            <!-- 上传文件 -->
            <form method="post" enctype="multipart/form-data" class="toolbar-form">
                <div class="form-group">
                    <label class="form-label">上传到: <code><?php echo htmlspecialchars($currentDir); ?>/</code></label>
                    <div class="form-row">
                        <input type="file" name="upload_file" required>
                        <button type="submit" class="btn btn-primary">上传文件</button>
                    </div>
                </div>
            </form>

            <!-- 创建文件/目录 -->
            <form method="post" class="toolbar-form">
                <input type="hidden" name="action" value="create">
                <div class="form-group">
                    <label class="form-label">创建到: <code><?php echo htmlspecialchars($currentDir); ?>/</code></label>
                    <div class="form-row">
                        <input type="text" name="new_name" placeholder="新文件/目录名" required>
                        <label class="checkbox-label">
                            <input type="checkbox" name="is_dir" value="1"> 目录
                        </label>
                        <button type="submit" class="btn btn-success">创建</button>
                    </div>
                </div>
            </form>
        </div>

        <div class="file-table">
            <table>
                <thead>
                    <tr>
                        <th>名称</th>
                        <th>大小</th>
                        <th>权限</th>
                        <th>创建时间</th>
                        <th>修改时间</th>
                        <th>状态</th>
                        <th>操作</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($items as $item): ?>
                    <tr>
                        <td>
                            <?php if ($item['is_dir']): ?>
                                <span class="icon dir">📁</span>
                                <a href="?dir=<?php echo urlencode($item['path']); ?>"><?php echo htmlspecialchars($item['name']); ?></a>
                            <?php else: ?>
                                <span class="icon file">📄</span>
                                <?php echo htmlspecialchars($item['name']); ?>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php echo $item['is_dir'] ? '-' : formatSize($item['size']); ?>
                        </td>
                        <td>
                            <span class="perms"><?php echo $item['perms']; ?></span>
                            <span class="perms-octal">(<?php echo $item['octal']; ?>)</span>
                        </td>
                        <td>
                            <?php echo $item['ctime'] ? date('Y-m-d H:i:s', $item['ctime']) : '-'; ?>
                        </td>
                        <td>
                            <?php echo $item['mtime'] ? date('Y-m-d H:i:s', $item['mtime']) : '-'; ?>
                        </td>
                        <td>
                            <?php if ($item['readable']): ?>
                                <span class="status-badge readable">可读</span>
                            <?php endif; ?>
                            <?php if ($item['writable']): ?>
                                <span class="status-badge writable">可写</span>
                            <?php endif; ?>
                            <?php if (!$item['readable'] && !$item['writable']): ?>
                                <span class="status-badge no-access">无权限</span>
                            <?php endif; ?>
                        </td>
                        <td class="actions">
                            <?php if ($item['name'] !== '..'): ?>
                                <?php if (!$item['is_dir'] && $item['readable']): ?>
                                    <a href="?view=<?php echo urlencode($item['path']); ?>&dir=<?php echo urlencode($currentDir); ?>" class="view">查看</a>
                                    <?php if ($item['writable']): ?>
                                        <a href="?edit=<?php echo urlencode($item['path']); ?>&dir=<?php echo urlencode($currentDir); ?>" class="edit">编辑</a>
                                    <?php endif; ?>
                                <?php endif; ?>

                                <button class="rename" onclick="showRenameModal('<?php echo htmlspecialchars(addslashes($item['path'])); ?>', '<?php echo htmlspecialchars(addslashes($item['name'])); ?>')">重命名</button>

                                <form method="post" style="display: inline;" onsubmit="return confirm('确定要删除 <?php echo htmlspecialchars(addslashes($item['name'])); ?> 吗？');">
                                    <input type="hidden" name="action" value="delete">
                                    <input type="hidden" name="path" value="<?php echo htmlspecialchars($item['path']); ?>">
                                    <button type="submit" class="delete">删除</button>
                                </form>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>
    </div>

    <!-- 重命名模态框 -->
    <div class="modal" id="renameModal">
        <div class="modal-content">
            <h3>重命名</h3>
            <form method="post" id="renameForm">
                <input type="hidden" name="action" value="rename">
                <input type="hidden" name="old_path" id="renameOldPath">
                <input type="text" name="new_name" id="renameNewName" placeholder="新名称" required>
                <div class="actions">
                    <button type="button" class="btn btn-secondary" onclick="hideRenameModal()">取消</button>
                    <button type="submit" class="btn btn-primary">确定</button>
                </div>
            </form>
        </div>
    </div>

    <script>
        function showRenameModal(path, name) {
            document.getElementById('renameOldPath').value = path;
            document.getElementById('renameNewName').value = name;
            document.getElementById('renameModal').classList.add('active');
        }

        function hideRenameModal() {
            document.getElementById('renameModal').classList.remove('active');
        }

        // 点击模态框外部关闭
        document.getElementById('renameModal').addEventListener('click', function(e) {
            if (e.target === this) {
                hideRenameModal();
            }
        });
    </script>
</body>
</html>
