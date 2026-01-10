/*
 * LD_PRELOAD SSL 注入库 - 支持路径过滤
 *
 * 通过劫持 SSL_write 函数来修改发送的数据
 * 只对特定 URL 路径进行注入
 *
 * 编译:
 *   gcc -shared -fPIC -o libinject.so ld_preload_inject.c -ldl
 *
 * 使用:
 *   # 注入所有 HTML 页面
 *   LD_PRELOAD=./libinject.so your_web_server
 *
 *   # 只注入特定路径
 *   INJECT_PATH="/news/" LD_PRELOAD=./libinject.so your_web_server
 *
 *   # 多个路径（逗号分隔）
 *   INJECT_PATH="/news/,/blog/,/articles/" LD_PRELOAD=./libinject.so your_web_server
 *
 * 环境变量:
 *   INJECT_PATH   - 要注入的路径前缀（支持多个，逗号分隔）
 *   INJECT_OWNER  - 所有者名称
 *   INJECT_DEBUG  - 设为 1 启用调试输出
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <ctype.h>
#include <pthread.h>

// 原始 SSL 函数指针
typedef int (*ssl_write_func)(void *ssl, const void *buf, int num);
static ssl_write_func original_ssl_write = NULL;

// 配置
static char *inject_paths[32] = {NULL};  // 最多 32 个路径
static int inject_paths_count = 0;
static const char *owner_name = "XXX";
static int debug_mode = 0;

// 线程安全的请求上下文
typedef struct {
    char last_request_path[256];
    int should_inject;
} thread_context_t;

static __thread thread_context_t thread_ctx = {0};

// 生成注入的 HTML
static void get_inject_html(char *buf, size_t size, const char *owner)
{
    snprintf(buf, size,
        "<div style=\"background:#fffbe6;border-bottom:2px solid #ffe58f;"
        "padding:10px;text-align:center;position:fixed;top:0;left:0;right:0;"
        "z-index:999999;font-family:sans-serif;\">"
        "<b>此网址属于 %s 拥有</b></div>", owner);
}

// 查找子字符串（不区分大小写）
static char *strcasestr_impl(const char *haystack, const char *needle)
{
    if (!*needle) return (char *)haystack;

    for (; *haystack; haystack++) {
        const char *h = haystack;
        const char *n = needle;

        while (*h && *n && tolower((unsigned char)*h) == tolower((unsigned char)*n)) {
            h++;
            n++;
        }

        if (!*n) return (char *)haystack;
    }
    return NULL;
}

// 解析路径配置
static void parse_inject_paths(void)
{
    char *paths = getenv("INJECT_PATH");
    if (!paths || strlen(paths) == 0) {
        // 默认：注入所有页面
        return;
    }

    // 复制字符串以便修改
    char *paths_copy = strdup(paths);
    char *token = strtok(paths_copy, ",");

    while (token && inject_paths_count < 32) {
        // 去除首尾空格
        while (*token == ' ') token++;
        char *end = token + strlen(token) - 1;
        while (end > token && *end == ' ') *end-- = '\0';

        if (strlen(token) > 0) {
            inject_paths[inject_paths_count++] = strdup(token);
        }
        token = strtok(NULL, ",");
    }

    free(paths_copy);
}

// 检查路径是否匹配
static int path_matches(const char *request_path)
{
    // 如果没有配置路径过滤，则匹配所有
    if (inject_paths_count == 0)
        return 1;

    for (int i = 0; i < inject_paths_count; i++) {
        if (strncmp(request_path, inject_paths[i], strlen(inject_paths[i])) == 0) {
            return 1;
        }
    }
    return 0;
}

// 从 HTTP 请求中提取路径
static int extract_request_path(const char *data, int len, char *path, size_t path_size)
{
    // 查找请求行: GET /path HTTP/1.1
    if (len < 10) return 0;

    // 跳过方法
    const char *p = data;
    while (*p && *p != ' ' && p < data + len) p++;
    if (*p != ' ') return 0;
    p++; // 跳过空格

    // 提取路径
    const char *path_start = p;
    while (*p && *p != ' ' && *p != '?' && p < data + len) p++;

    int path_len = p - path_start;
    if (path_len <= 0 || path_len >= (int)path_size) return 0;

    memcpy(path, path_start, path_len);
    path[path_len] = '\0';

    return 1;
}

// 检查是否是 HTTP 请求（用于记录当前请求路径）
static int is_http_request(const char *data, int len)
{
    if (len < 4) return 0;
    return (strncmp(data, "GET ", 4) == 0 ||
            strncmp(data, "POST ", 5) == 0 ||
            strncmp(data, "PUT ", 4) == 0 ||
            strncmp(data, "HEAD ", 5) == 0);
}

// 检查是否是 HTML 响应
static int is_html_response(const char *data, int len)
{
    if (len < 50) return 0;

    // 检查是否是 HTTP 响应
    if (strncmp(data, "HTTP/1.", 7) != 0 && strncmp(data, "HTTP/2", 6) != 0)
        return 0;

    // 查找 Content-Type: text/html
    char *ct = strcasestr_impl(data, "content-type:");
    if (!ct) return 0;

    char *end = strchr(ct, '\n');
    if (!end) end = (char *)data + len;

    char *html = strcasestr_impl(ct, "text/html");
    return (html && html < end);
}

// 查找 <body> 标签
static char *find_body_tag(char *data, int len)
{
    for (int i = 0; i < len - 6; i++) {
        if (strncasecmp(data + i, "<body", 5) == 0) {
            for (int j = i + 5; j < len; j++) {
                if (data[j] == '>') {
                    return data + j + 1;
                }
            }
        }
    }
    return NULL;
}

// 更新 Content-Length 头
static int update_content_length(char *data, int len, int added_len)
{
    char *cl = strcasestr_impl(data, "content-length:");
    if (!cl) return 0;

    char *val_start = cl + 15;
    while (*val_start == ' ') val_start++;

    char *val_end = val_start;
    while (*val_end >= '0' && *val_end <= '9') val_end++;

    int old_len = atoi(val_start);
    int new_len = old_len + added_len;

    char new_val[20];
    int new_val_len = snprintf(new_val, sizeof(new_val), "%d", new_len);
    int old_val_len = val_end - val_start;

    if (new_val_len == old_val_len) {
        memcpy(val_start, new_val, new_val_len);
        return 0;
    }

    int diff = new_val_len - old_val_len;
    memmove(val_end + diff, val_end, len - (val_end - data));
    memcpy(val_start, new_val, new_val_len);

    return diff;
}

// 劫持的 SSL_write 函数
int SSL_write(void *ssl, const void *buf, int num)
{
    // 确保获取原始函数
    if (!original_ssl_write) {
        original_ssl_write = (ssl_write_func)dlsym(RTLD_NEXT, "SSL_write");
        if (!original_ssl_write) {
            fprintf(stderr, "[inject] Failed to get original SSL_write\n");
            return -1;
        }
    }

    const char *data = (const char *)buf;

    // 检查是否是 HTTP 请求（记录路径以供后续响应使用）
    // 注意：对于服务端，请求是通过 SSL_read 接收的，这里主要处理响应
    // 这个逻辑需要根据你的具体服务器架构调整

    // 检查是否是 HTML 响应
    if (!is_html_response(data, num)) {
        return original_ssl_write(ssl, buf, num);
    }

    // 检查是否应该注入（基于配置的路径）
    // 对于服务端响应，我们可能需要其他方式来获取请求路径
    // 这里简化处理：如果配置了路径，检查响应中是否有路径相关信息
    // 或者总是注入（如果没有配置路径过滤）
    if (inject_paths_count > 0 && !thread_ctx.should_inject) {
        if (debug_mode) {
            fprintf(stderr, "[inject] 跳过：路径不匹配\n");
        }
        return original_ssl_write(ssl, buf, num);
    }

    // 查找 <body> 标签
    char *body_tag = find_body_tag((char *)data, num);
    if (!body_tag) {
        return original_ssl_write(ssl, buf, num);
    }

    // 生成注入内容
    char inject_html[1024];
    get_inject_html(inject_html, sizeof(inject_html), owner_name);
    int inject_len = strlen(inject_html);

    // 创建新的缓冲区
    int new_size = num + inject_len + 100;
    char *new_buf = malloc(new_size);
    if (!new_buf) {
        return original_ssl_write(ssl, buf, num);
    }

    // 复制 body 标签之前的内容
    int prefix_len = body_tag - data;
    memcpy(new_buf, buf, prefix_len);

    // 插入注入内容
    memcpy(new_buf + prefix_len, inject_html, inject_len);

    // 复制剩余内容
    int suffix_len = num - prefix_len;
    memcpy(new_buf + prefix_len + inject_len, body_tag, suffix_len);

    int new_len = num + inject_len;

    // 更新 Content-Length
    int cl_diff = update_content_length(new_buf, new_len, inject_len);
    new_len += cl_diff;

    if (debug_mode) {
        fprintf(stderr, "[inject] 注入成功！原长度: %d, 新长度: %d\n", num, new_len);
    }

    // 发送修改后的数据
    int ret = original_ssl_write(ssl, new_buf, new_len);

    free(new_buf);

    // 重置状态
    thread_ctx.should_inject = 0;

    return ret > 0 ? num : ret;
}

// 同时劫持 SSL_read 来捕获请求路径
typedef int (*ssl_read_func)(void *ssl, void *buf, int num);
static ssl_read_func original_ssl_read = NULL;

int SSL_read(void *ssl, void *buf, int num)
{
    if (!original_ssl_read) {
        original_ssl_read = (ssl_read_func)dlsym(RTLD_NEXT, "SSL_read");
        if (!original_ssl_read) {
            return -1;
        }
    }

    int ret = original_ssl_read(ssl, buf, num);

    if (ret > 0 && inject_paths_count > 0) {
        // 检查是否是 HTTP 请求
        if (is_http_request((const char *)buf, ret)) {
            char path[256];
            if (extract_request_path((const char *)buf, ret, path, sizeof(path))) {
                strncpy(thread_ctx.last_request_path, path, sizeof(thread_ctx.last_request_path) - 1);
                thread_ctx.should_inject = path_matches(path);

                if (debug_mode) {
                    fprintf(stderr, "[inject] 请求路径: %s, 匹配: %s\n",
                            path, thread_ctx.should_inject ? "是" : "否");
                }
            }
        }
    }

    return ret;
}

// 构造函数 - 库加载时执行
__attribute__((constructor))
static void init(void)
{
    // 读取配置
    char *owner = getenv("INJECT_OWNER");
    if (owner && strlen(owner) > 0) {
        owner_name = owner;
    }

    char *debug = getenv("INJECT_DEBUG");
    if (debug && strcmp(debug, "1") == 0) {
        debug_mode = 1;
    }

    parse_inject_paths();

    fprintf(stderr, "[inject] HTML 注入库已加载\n");
    fprintf(stderr, "[inject] 所有者: %s\n", owner_name);

    if (inject_paths_count > 0) {
        fprintf(stderr, "[inject] 路径过滤已启用，只注入以下路径:\n");
        for (int i = 0; i < inject_paths_count; i++) {
            fprintf(stderr, "[inject]   - %s\n", inject_paths[i]);
        }
    } else {
        fprintf(stderr, "[inject] 将注入所有 HTML 页面\n");
    }

    if (debug_mode) {
        fprintf(stderr, "[inject] 调试模式已启用\n");
    }
}

// 析构函数
__attribute__((destructor))
static void fini(void)
{
    for (int i = 0; i < inject_paths_count; i++) {
        free(inject_paths[i]);
    }
    fprintf(stderr, "[inject] HTML 注入库已卸载\n");
}
