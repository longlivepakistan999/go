#ifndef __INJECT_H
#define __INJECT_H

#define MAX_DATA_SIZE 4096
#define TASK_COMM_LEN 16

// 事件类型
enum event_type {
    EVENT_SSL_WRITE = 1,
    EVENT_SSL_READ = 2,
};

// 传递给用户态的事件结构
struct event {
    __u32 pid;
    __u32 tid;
    __u32 uid;
    __u32 len;
    __u64 timestamp;
    enum event_type type;
    char comm[TASK_COMM_LEN];
    char data[MAX_DATA_SIZE];
};

// SSL_write 参数
struct ssl_write_args {
    void *ssl;
    void *buf;
    int num;
};

#endif /* __INJECT_H */
