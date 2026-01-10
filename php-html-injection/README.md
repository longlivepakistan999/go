# PHP HTML 注入器

无需 eBPF，使用 PHP 原生功能实现 HTML 内容注入。

## 快速开始

### 方法 1: PHP 内置服务器

```bash
# 注入所有页面
php -d auto_prepend_file=injector.php -S 0.0.0.0:8080

# 只注入特定路径
INJECT_PATH="/news/,/blog/" \
INJECT_OWNER="我的公司" \
php -d auto_prepend_file=injector.php -S 0.0.0.0:8080
```

### 方法 2: 修改 php.ini

```ini
; 在 php.ini 中添加
auto_prepend_file = /var/www/injector.php
```

### 方法 3: PHP-FPM 配置

```ini
; 在 /etc/php/8.x/fpm/pool.d/www.conf 中添加
php_admin_value[auto_prepend_file] = /var/www/injector.php

; 或者针对特定网站
php_value[auto_prepend_file] = /var/www/site1/injector.php
```

### 方法 4: .user.ini（虚拟主机）

在网站根目录创建 `.user.ini`：

```ini
auto_prepend_file = /var/www/injector.php
```

## 环境变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `INJECT_OWNER` | 显示的所有者名称 | `我的公司` |
| `INJECT_PATH` | 要注入的路径（逗号分隔） | `/news/,/blog/` |
| `INJECT_DEBUG` | 启用调试日志 | `1` |

## 配置说明

### 路径过滤

```php
// 只注入这些路径
define('INJECT_PATHS', ['/news/', '/blog/']);

// 排除这些路径
define('EXCLUDE_PATHS', ['/api/', '/admin/']);
```

### 排除文件类型

```php
define('EXCLUDE_EXTENSIONS', ['json', 'xml', 'css', 'js']);
```

## 工作原理

```
PHP 请求
    │
    ▼
┌─────────────────────┐
│ auto_prepend_file   │ ← injector.php 自动加载
│ (请求开始前)         │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ ob_start() 开始缓冲  │ ← 捕获所有输出
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ 你的 PHP 应用执行    │ ← 正常执行
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ processOutput()     │ ← 检测 HTML，注入内容
└──────────┬──────────┘
           │
           ▼
    返回给用户
```

## 效果预览

页面顶部会显示一个紫色渐变的横幅：

```
┌────────────────────────────────────────────────────┐
│           此网址属于 我的公司 拥有                   │
└────────────────────────────────────────────────────┘
```

## 与 eBPF 方案对比

| 特性 | PHP 方案 | eBPF 方案 |
|------|----------|-----------|
| 复杂度 | ⭐ 简单 | ⭐⭐⭐⭐⭐ 复杂 |
| 性能 | 好 | 更好 |
| 维护性 | 容易 | 困难 |
| 依赖 | 无 | 需要内核支持 |
| HTTPS | ✅ 自动支持 | 需要 uprobe |
| 推荐度 | ⭐⭐⭐⭐⭐ | ⭐⭐ |

**结论**：对于 PHP 应用，使用 `auto_prepend_file` 是最简单有效的方案。

## 注意事项

- 仅用于您拥有和控制的网站
- 生产环境建议关闭调试模式
- 确保 injector.php 文件权限正确
