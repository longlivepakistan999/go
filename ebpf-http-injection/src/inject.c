// 用户态程序：加载 eBPF 并处理事件
// 这里实现实际的 HTML 注入逻辑

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <bpf/libbpf.h>
#include <bpf/bpf.h>
#include "inject.h"
#include "inject.skel.h"

static volatile bool running = true;

// 要注入的 HTML 内容
static const char *inject_html =
    "<div style=\"background:#fffbe6;border-bottom:2px solid #ffe58f;"
    "padding:10px;text-align:center;position:fixed;top:0;left:0;right:0;"
    "z-index:999999;font-family:sans-serif;\">"
    "<b>此网址属于 XXX 拥有</b></div>";

static const char *owner_name = "XXX";

static void sig_handler(int sig)
{
    running = false;
}

// 检查数据是否包含 HTTP 响应
static bool is_http_response(const char *data, int len)
{
    if (len < 12)
        return false;
    return strncmp(data, "HTTP/1.", 7) == 0 ||
           strncmp(data, "HTTP/2", 6) == 0;
}

// 检查是否是 HTML 内容
static bool is_html_content(const char *data, int len)
{
    // 查找 Content-Type: text/html
    const char *ct = "Content-Type:";
    const char *html = "text/html";

    for (int i = 0; i < len - 20; i++) {
        if (strncasecmp(data + i, ct, strlen(ct)) == 0) {
            // 在这一行中查找 text/html
            for (int j = i; j < len - 9 && j < i + 100; j++) {
                if (data[j] == '\n')
                    break;
                if (strncasecmp(data + j, html, strlen(html)) == 0)
                    return true;
            }
        }
    }
    return false;
}

// 查找 <body> 标签位置
static int find_body_tag(const char *data, int len)
{
    for (int i = 0; i < len - 6; i++) {
        if (strncasecmp(data + i, "<body", 5) == 0) {
            // 找到 > 结束符
            for (int j = i + 5; j < len; j++) {
                if (data[j] == '>') {
                    return j + 1;
                }
            }
        }
    }
    return -1;
}

// 处理 ring buffer 事件
static int handle_event(void *ctx, void *data, size_t data_sz)
{
    struct event *e = data;

    // 只处理 SSL_write（发送的数据）
    if (e->type != EVENT_SSL_WRITE)
        return 0;

    // 检查是否是 HTTP 响应
    if (!is_http_response(e->data, e->len))
        return 0;

    // 检查是否是 HTML
    if (!is_html_content(e->data, e->len))
        return 0;

    // 查找 <body> 标签
    int body_pos = find_body_tag(e->data, e->len);

    printf("\n========================================\n");
    printf("[%s] PID: %d, TID: %d\n", e->comm, e->pid, e->tid);
    printf("检测到 HTML 响应, 长度: %d 字节\n", e->len);

    if (body_pos > 0) {
        printf("<body> 标签位置: %d\n", body_pos);
        printf(">>> 可在此位置注入内容 <<<\n");
        printf("注入内容: %s\n", inject_html);
    } else {
        printf("<body> 标签未找到\n");
    }

    printf("----------------------------------------\n");
    // 打印部分 HTTP 头
    int print_len = e->len > 500 ? 500 : e->len;
    printf("%.500s...\n", e->data);
    printf("========================================\n");

    /*
     * 重要说明：
     *
     * 在 eBPF 中直接修改 SSL_write 的数据非常困难，因为：
     * 1. 数据长度会变化（Content-Length 需要更新）
     * 2. 需要在用户空间的内存中修改（需要 ptrace 或类似机制）
     * 3. SSL 库可能不会重新读取修改后的数据
     *
     * 实际的修改方案：
     *
     * 方案 A: LD_PRELOAD 劫持
     *   - 预加载一个共享库来替换 SSL_write
     *   - 在替换函数中修改数据后再调用原始函数
     *
     * 方案 B: ptrace 注入
     *   - 使用 eBPF 检测目标调用
     *   - 通过 ptrace 暂停进程并修改内存
     *
     * 方案 C: 代理方式
     *   - eBPF 识别目标连接
     *   - 重定向到本地代理进行修改
     *
     * 下面的代码展示了 LD_PRELOAD 方式的思路
     */

    return 0;
}

static void print_usage(const char *prog)
{
    printf("Usage: %s [OPTIONS]\n", prog);
    printf("\nOptions:\n");
    printf("  -l, --lib PATH    SSL 库路径 (默认: /usr/lib/x86_64-linux-gnu/libssl.so.3)\n");
    printf("  -p, --pid PID     只跟踪指定进程\n");
    printf("  -o, --owner NAME  所有者名称 (默认: XXX)\n");
    printf("  -h, --help        显示帮助\n");
}

int main(int argc, char **argv)
{
    struct inject_bpf *skel;
    struct ring_buffer *rb = NULL;
    const char *ssl_lib = "/usr/lib/x86_64-linux-gnu/libssl.so.3";
    int target_pid = 0;
    int err;

    // 解析参数
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-l") == 0 || strcmp(argv[i], "--lib") == 0) {
            if (i + 1 < argc)
                ssl_lib = argv[++i];
        } else if (strcmp(argv[i], "-p") == 0 || strcmp(argv[i], "--pid") == 0) {
            if (i + 1 < argc)
                target_pid = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-o") == 0 || strcmp(argv[i], "--owner") == 0) {
            if (i + 1 < argc)
                owner_name = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        }
    }

    // 设置信号处理
    signal(SIGINT, sig_handler);
    signal(SIGTERM, sig_handler);

    // 打开并加载 BPF 程序
    skel = inject_bpf__open();
    if (!skel) {
        fprintf(stderr, "Failed to open BPF skeleton\n");
        return 1;
    }

    // 设置目标 PID
    skel->rodata->target_pid = target_pid;

    // 加载 BPF 程序
    err = inject_bpf__load(skel);
    if (err) {
        fprintf(stderr, "Failed to load BPF skeleton: %d\n", err);
        goto cleanup;
    }

    // 附加 uprobe 到 SSL_write
    skel->links.uprobe_ssl_write = bpf_program__attach_uprobe(
        skel->progs.uprobe_ssl_write,
        false,  // not retprobe
        -1,     // all PIDs
        ssl_lib,
        0       // offset - 需要通过 nm 获取符号偏移
    );

    if (!skel->links.uprobe_ssl_write) {
        fprintf(stderr, "Failed to attach uprobe to SSL_write\n");
        // 尝试使用符号名
        skel->links.uprobe_ssl_write = bpf_program__attach_uprobe_opts(
            skel->progs.uprobe_ssl_write,
            -1,
            ssl_lib,
            0,
            &(struct bpf_uprobe_opts){
                .sz = sizeof(struct bpf_uprobe_opts),
                .func_name = "SSL_write",
            }
        );
    }

    // 附加 uretprobe 到 SSL_write
    skel->links.uretprobe_ssl_write = bpf_program__attach_uprobe(
        skel->progs.uretprobe_ssl_write,
        true,   // retprobe
        -1,
        ssl_lib,
        0
    );

    // 创建 ring buffer
    rb = ring_buffer__new(bpf_map__fd(skel->maps.events), handle_event, NULL, NULL);
    if (!rb) {
        fprintf(stderr, "Failed to create ring buffer\n");
        err = -1;
        goto cleanup;
    }

    printf("eBPF HTTP/HTTPS 注入器已启动\n");
    printf("SSL 库: %s\n", ssl_lib);
    printf("目标 PID: %s\n", target_pid ? argv[2] : "全部");
    printf("所有者: %s\n", owner_name);
    printf("按 Ctrl+C 退出...\n\n");

    // 主循环
    while (running) {
        err = ring_buffer__poll(rb, 100);
        if (err == -EINTR) {
            err = 0;
            break;
        }
        if (err < 0) {
            fprintf(stderr, "Error polling ring buffer: %d\n", err);
            break;
        }
    }

cleanup:
    ring_buffer__free(rb);
    inject_bpf__destroy(skel);
    return err < 0 ? -err : 0;
}
