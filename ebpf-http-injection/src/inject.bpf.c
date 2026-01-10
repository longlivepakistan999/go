// SPDX-License-Identifier: GPL-2.0
// eBPF 程序：拦截 SSL_write 获取 HTTPS 明文内容

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>
#include "inject.h"

// 用于临时存储 SSL_write 参数
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 10240);
    __type(key, __u64);   // pid_tgid
    __type(value, struct ssl_write_args);
} ssl_write_args_map SEC(".maps");

// Ring buffer 用于向用户态发送事件
struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024);
} events SEC(".maps");

// 目标进程 PID 过滤（0 表示所有进程）
const volatile __u32 target_pid = 0;

// 目标 UID 过滤（-1 表示所有用户）
const volatile __u32 target_uid = -1;

// 检查是否应该跟踪此进程
static __always_inline int should_trace()
{
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;
    __u32 uid = bpf_get_current_uid_gid() & 0xFFFFFFFF;

    if (target_pid != 0 && target_pid != pid)
        return 0;

    if (target_uid != (__u32)-1 && target_uid != uid)
        return 0;

    return 1;
}

// uprobe: SSL_write 入口
// int SSL_write(SSL *ssl, const void *buf, int num);
SEC("uprobe/SSL_write")
int BPF_UPROBE(uprobe_ssl_write, void *ssl, void *buf, int num)
{
    if (!should_trace())
        return 0;

    __u64 pid_tgid = bpf_get_current_pid_tgid();

    // 保存参数供 uretprobe 使用
    struct ssl_write_args args = {
        .ssl = ssl,
        .buf = buf,
        .num = num,
    };
    bpf_map_update_elem(&ssl_write_args_map, &pid_tgid, &args, BPF_ANY);

    return 0;
}

// uretprobe: SSL_write 返回
SEC("uretprobe/SSL_write")
int BPF_URETPROBE(uretprobe_ssl_write, int ret)
{
    if (!should_trace())
        return 0;

    __u64 pid_tgid = bpf_get_current_pid_tgid();

    // 获取之前保存的参数
    struct ssl_write_args *args = bpf_map_lookup_elem(&ssl_write_args_map, &pid_tgid);
    if (!args)
        return 0;

    // 写入失败则跳过
    if (ret <= 0)
        goto cleanup;

    // 分配事件
    struct event *e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
    if (!e)
        goto cleanup;

    // 填充事件数据
    e->pid = pid_tgid >> 32;
    e->tid = (__u32)pid_tgid;
    e->uid = bpf_get_current_uid_gid() & 0xFFFFFFFF;
    e->timestamp = bpf_ktime_get_ns();
    e->type = EVENT_SSL_WRITE;
    e->len = ret;

    bpf_get_current_comm(&e->comm, sizeof(e->comm));

    // 读取写入的数据（加密前的明文）
    int read_len = ret < MAX_DATA_SIZE ? ret : MAX_DATA_SIZE;
    bpf_probe_read_user(&e->data, read_len, args->buf);

    bpf_ringbuf_submit(e, 0);

cleanup:
    bpf_map_delete_elem(&ssl_write_args_map, &pid_tgid);
    return 0;
}

// 同样的方式处理 SSL_read（接收的数据）
SEC("uprobe/SSL_read")
int BPF_UPROBE(uprobe_ssl_read, void *ssl, void *buf, int num)
{
    if (!should_trace())
        return 0;

    __u64 pid_tgid = bpf_get_current_pid_tgid();

    struct ssl_write_args args = {
        .ssl = ssl,
        .buf = buf,
        .num = num,
    };
    bpf_map_update_elem(&ssl_write_args_map, &pid_tgid, &args, BPF_ANY);

    return 0;
}

SEC("uretprobe/SSL_read")
int BPF_URETPROBE(uretprobe_ssl_read, int ret)
{
    if (!should_trace())
        return 0;

    __u64 pid_tgid = bpf_get_current_pid_tgid();

    struct ssl_write_args *args = bpf_map_lookup_elem(&ssl_write_args_map, &pid_tgid);
    if (!args)
        return 0;

    if (ret <= 0)
        goto cleanup;

    struct event *e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
    if (!e)
        goto cleanup;

    e->pid = pid_tgid >> 32;
    e->tid = (__u32)pid_tgid;
    e->uid = bpf_get_current_uid_gid() & 0xFFFFFFFF;
    e->timestamp = bpf_ktime_get_ns();
    e->type = EVENT_SSL_READ;
    e->len = ret;

    bpf_get_current_comm(&e->comm, sizeof(e->comm));

    int read_len = ret < MAX_DATA_SIZE ? ret : MAX_DATA_SIZE;
    bpf_probe_read_user(&e->data, read_len, args->buf);

    bpf_ringbuf_submit(e, 0);

cleanup:
    bpf_map_delete_elem(&ssl_write_args_map, &pid_tgid);
    return 0;
}

char LICENSE[] SEC("license") = "GPL";
