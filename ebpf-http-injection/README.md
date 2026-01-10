# eBPF HTTP/HTTPS 内容注入

使用 eBPF uprobe 技术在 SSL 加密前拦截并修改 HTTP 响应内容。

## 原理

### HTTP（明文）
- 使用 `kprobe` 或 `tc` 钩子拦截 `tcp_sendmsg`
- 直接修改数据包内容
- 需要处理 TCP 分片和重组

### HTTPS（加密）
- **无法在网络层修改**（数据已加密）
- 使用 `uprobe` 钩住用户态 SSL 库函数：
  - `SSL_write()` - OpenSSL
  - `SSL_Write()` - BoringSSL
  - `gnutls_record_send()` - GnuTLS
  - `security_write()` - NSS
- 在加密前读取/修改明文数据

## 架构

```
Web 应用
    │
    ▼ 明文 HTTP 响应
┌─────────────────┐
│  SSL_write()    │ ◄── eBPF uprobe 在这里拦截
└────────┬────────┘
         │ 加密
         ▼
    密文发送到网络
```

## 技术挑战

| 挑战 | 解决方案 |
|------|----------|
| SSL 库多样性 | 需要针对不同库写不同 hook |
| 修改数据长度 | 复杂，需要用户态程序配合 |
| 性能影响 | uprobe 有一定开销 |
| 多进程/线程 | 需要处理并发 |

## 文件结构

```
ebpf-http-injection/
├── src/
│   ├── inject.bpf.c       # eBPF 内核程序
│   ├── inject.c           # 用户态加载程序
│   └── inject.h           # 共享头文件
├── Makefile
└── README.md
```

## 依赖

```bash
# Ubuntu/Debian
apt install -y clang llvm libelf-dev libbpf-dev linux-headers-$(uname -r) bpftool

# CentOS/RHEL
yum install -y clang llvm elfutils-libelf-devel libbpf-devel kernel-devel bpftool
```

## 编译与运行

```bash
make
sudo ./inject --lib /usr/lib/x86_64-linux-gnu/libssl.so.3
```

## 限制

1. **只能读取，难以修改**: 直接在 eBPF 中修改 SSL_write 的缓冲区很复杂
2. **需要 root 权限**: 加载 eBPF 程序需要 CAP_BPF
3. **内核版本**: 需要 Linux 5.x+ 以获得更好的 eBPF 支持
