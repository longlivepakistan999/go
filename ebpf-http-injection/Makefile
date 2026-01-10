# eBPF HTTP 注入器 Makefile

CLANG ?= clang
LLC ?= llc
BPFTOOL ?= bpftool
CC ?= gcc

ARCH := $(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/')

# 目录
SRC_DIR := src
BUILD_DIR := build
VMLINUX_H := $(SRC_DIR)/vmlinux.h

# BPF 编译标志
BPF_CFLAGS := -g -O2 -target bpf -D__TARGET_ARCH_$(ARCH)
BPF_CFLAGS += -I$(SRC_DIR)

# 用户态编译标志
USER_CFLAGS := -g -O2 -Wall -I$(SRC_DIR) -I$(BUILD_DIR)
USER_LDFLAGS := -lbpf -lelf -lz

.PHONY: all clean vmlinux ld_preload

all: $(BUILD_DIR)/inject $(BUILD_DIR)/libinject.so

# 生成 vmlinux.h
$(VMLINUX_H):
	@echo "生成 vmlinux.h..."
	@mkdir -p $(SRC_DIR)
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

# 编译 BPF 程序
$(BUILD_DIR)/inject.bpf.o: $(SRC_DIR)/inject.bpf.c $(VMLINUX_H) $(SRC_DIR)/inject.h
	@mkdir -p $(BUILD_DIR)
	$(CLANG) $(BPF_CFLAGS) -c $< -o $@

# 生成 skeleton
$(BUILD_DIR)/inject.skel.h: $(BUILD_DIR)/inject.bpf.o
	bpftool gen skeleton $< > $@

# 编译用户态程序
$(BUILD_DIR)/inject: $(SRC_DIR)/inject.c $(BUILD_DIR)/inject.skel.h $(SRC_DIR)/inject.h
	$(CC) $(USER_CFLAGS) -I$(BUILD_DIR) $< -o $@ $(USER_LDFLAGS)

# 编译 LD_PRELOAD 库
$(BUILD_DIR)/libinject.so: $(SRC_DIR)/ld_preload_inject.c
	@mkdir -p $(BUILD_DIR)
	$(CC) -shared -fPIC -O2 -o $@ $< -ldl

ld_preload: $(BUILD_DIR)/libinject.so
	@echo "LD_PRELOAD 库已编译: $(BUILD_DIR)/libinject.so"
	@echo ""
	@echo "使用方法:"
	@echo "  LD_PRELOAD=$(BUILD_DIR)/libinject.so your_web_server"

vmlinux: $(VMLINUX_H)

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(VMLINUX_H)

# 安装依赖（Ubuntu/Debian）
install-deps:
	apt update
	apt install -y clang llvm libelf-dev libbpf-dev \
		linux-headers-$$(uname -r) bpftool \
		build-essential pkg-config

# 运行示例
run: $(BUILD_DIR)/inject
	@echo "需要 root 权限运行..."
	sudo $(BUILD_DIR)/inject

help:
	@echo "可用目标:"
	@echo "  all          - 编译所有程序"
	@echo "  ld_preload   - 只编译 LD_PRELOAD 注入库"
	@echo "  vmlinux      - 生成 vmlinux.h"
	@echo "  clean        - 清理编译产物"
	@echo "  install-deps - 安装依赖（Ubuntu/Debian）"
	@echo "  run          - 运行 eBPF 程序"
	@echo "  help         - 显示此帮助"
