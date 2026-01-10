<?php
/**
 * PHP HTML 注入器
 *
 * 使用 PHP 的 auto_prepend_file 功能自动注入内容
 *
 * 安装方法（任选一种）：
 *
 * 1. php.ini:
 *    auto_prepend_file = /path/to/injector.php
 *
 * 2. PHP-FPM pool 配置:
 *    php_admin_value[auto_prepend_file] = /path/to/injector.php
 *
 * 3. .htaccess (如果用 Apache):
 *    php_value auto_prepend_file /path/to/injector.php
 *
 * 4. 命令行:
 *    php -d auto_prepend_file=/path/to/injector.php -S 0.0.0.0:8080
 */

// ============== 配置 ==============

// 所有者名称
define('INJECT_OWNER', getenv('INJECT_OWNER') ?: '我的公司');

// 要注入的路径（留空 = 所有路径）
// 示例: ['/news/', '/blog/', '/articles/']
define('INJECT_PATHS', array_filter(
    explode(',', getenv('INJECT_PATH') ?: ''),
    'strlen'
));

// 排除的路径（API 接口等）
define('EXCLUDE_PATHS', [
    '/api/',
    '/ajax/',
    '/admin/',
]);

// 排除的文件类型
define('EXCLUDE_EXTENSIONS', [
    'json', 'xml', 'txt', 'css', 'js',
    'png', 'jpg', 'gif', 'svg', 'ico',
    'woff', 'woff2', 'ttf', 'eot',
]);

// 调试模式
define('INJECT_DEBUG', getenv('INJECT_DEBUG') === '1');

// ============== 注入逻辑 ==============

class HtmlInjector
{
    private static $enabled = true;

    /**
     * 初始化注入器
     */
    public static function init()
    {
        // 检查是否应该注入
        if (!self::shouldInject()) {
            self::$enabled = false;
            return;
        }

        // 注册输出缓冲
        ob_start([__CLASS__, 'processOutput']);

        // 注册关闭函数确保输出被处理
        register_shutdown_function([__CLASS__, 'shutdown']);

        if (INJECT_DEBUG) {
            error_log("[inject] 已启用，路径: " . $_SERVER['REQUEST_URI']);
        }
    }

    /**
     * 检查当前请求是否应该注入
     */
    private static function shouldInject()
    {
        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $path = parse_url($uri, PHP_URL_PATH) ?: '/';

        // 检查文件扩展名
        $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
        if ($ext && in_array($ext, EXCLUDE_EXTENSIONS)) {
            if (INJECT_DEBUG) {
                error_log("[inject] 跳过：文件类型 .$ext");
            }
            return false;
        }

        // 检查排除路径
        foreach (EXCLUDE_PATHS as $exclude) {
            if (strpos($path, $exclude) === 0) {
                if (INJECT_DEBUG) {
                    error_log("[inject] 跳过：排除路径 $exclude");
                }
                return false;
            }
        }

        // 检查包含路径（如果配置了的话）
        if (!empty(INJECT_PATHS)) {
            $matched = false;
            foreach (INJECT_PATHS as $includePath) {
                $includePath = trim($includePath);
                if ($includePath && strpos($path, $includePath) === 0) {
                    $matched = true;
                    break;
                }
            }
            if (!$matched) {
                if (INJECT_DEBUG) {
                    error_log("[inject] 跳过：路径不匹配 $path");
                }
                return false;
            }
        }

        return true;
    }

    /**
     * 处理输出内容
     */
    public static function processOutput($buffer)
    {
        if (!self::$enabled) {
            return $buffer;
        }

        // 检查是否是 HTML 内容
        $contentType = '';
        foreach (headers_list() as $header) {
            if (stripos($header, 'content-type:') === 0) {
                $contentType = strtolower($header);
                break;
            }
        }

        // 如果没有设置 Content-Type，检查内容是否像 HTML
        $isHtml = strpos($contentType, 'text/html') !== false;
        if (!$isHtml && empty($contentType)) {
            // 简单检测 HTML
            $trimmed = ltrim($buffer);
            $isHtml = (
                stripos($trimmed, '<!DOCTYPE') === 0 ||
                stripos($trimmed, '<html') === 0 ||
                stripos($trimmed, '<head') === 0
            );
        }

        if (!$isHtml) {
            if (INJECT_DEBUG) {
                error_log("[inject] 跳过：非 HTML 内容");
            }
            return $buffer;
        }

        // 生成注入内容
        $injectHtml = self::getInjectHtml();

        // 查找 <body> 标签并注入
        $pattern = '/(<body[^>]*>)/i';
        if (preg_match($pattern, $buffer)) {
            $buffer = preg_replace($pattern, '$1' . $injectHtml, $buffer, 1);

            if (INJECT_DEBUG) {
                error_log("[inject] 注入成功！");
            }
        } else {
            if (INJECT_DEBUG) {
                error_log("[inject] 未找到 <body> 标签");
            }
        }

        return $buffer;
    }

    /**
     * 生成注入的 HTML
     */
    private static function getInjectHtml()
    {
        $owner = htmlspecialchars(INJECT_OWNER, ENT_QUOTES, 'UTF-8');

        return <<<HTML
<div id="ownership-banner" style="
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 12px 20px;
    text-align: center;
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    z-index: 999999;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 14px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.2);
">
    <b>此网址属于 {$owner} 拥有</b>
</div>
<div style="height: 44px;"></div>
HTML;
    }

    /**
     * 关闭时确保输出
     */
    public static function shutdown()
    {
        if (ob_get_level() > 0) {
            ob_end_flush();
        }
    }
}

// 自动初始化
HtmlInjector::init();
