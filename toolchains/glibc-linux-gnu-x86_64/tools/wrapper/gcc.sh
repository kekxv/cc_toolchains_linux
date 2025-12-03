#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# (修复 Absolute Path Inclusion 问题)
# ==========================================

# 工具名称定义
GCC_NAME="x86_64-buildroot-linux-gnu-gcc.br_real"
AR_NAME="x86_64-buildroot-linux-gnu-ar"
LD_NAME="x86_64-buildroot-linux-gnu-ld"

# 1. 环境准备
#    EXECROOT: Bazel 执行时的根目录 (物理路径)
EXECROOT=$(pwd -P)
#    CURRENT_DIR: 脚本文件所在的目录 (物理路径)
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# 2. 智能查找 external 目录
#    逻辑：优先检查当前目录下的 external，如果没找到则从脚本目录向上遍历。
ROOT_PATH=""
SEARCH_DIR="${CURRENT_DIR}"

if [[ -d "${EXECROOT}/external" ]]; then
    ROOT_PATH="${EXECROOT}/external"
else
    # 向上递归查找，直到找到包含 external 的目录或到达根目录
    while [[ "${SEARCH_DIR}" != "/" ]]; do
        if [[ -d "${SEARCH_DIR}/external" ]]; then
            ROOT_PATH="${SEARCH_DIR}/external"
            break
        fi
        SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
    done
fi

if [[ -z "${ROOT_PATH}" ]]; then
    echo "ERROR: [gcc.sh] Could not locate 'external' directory." >&2
    exit 1
fi

# 3. 查找真正的编译器 (获取绝对路径以验证存在)
#    -maxdepth 5: 限制搜索深度，防止扫描太深
#    -print -quit: 找到第一个匹配项立即停止
REAL_GCC_ABS=$(find -L "${ROOT_PATH}" -maxdepth 8 -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REAL_GCC_ABS}" ]]; then
    echo "ERROR: [gcc.sh] Could not find ${GCC_NAME} in ${ROOT_PATH}" >&2
    exit 1
fi

# 4. 【关键修复】将绝对路径转换为相对路径
#    Bazel 要求编译器产生的依赖文件(.d)必须包含相对路径。
#    如果这里用绝对路径调用 GCC，它生成的依赖就是绝对路径，导致构建失败。
if [[ "${REAL_GCC_ABS}" == "${EXECROOT}"* ]]; then
    # 移除 Execroot 前缀
    REL_PATH="${REAL_GCC_ABS#$EXECROOT}"
    # 移除开头的斜杠，得到 external/repo_name/.../gcc
    REAL_GCC_INVOKE="${REL_PATH#/}"
else
    # 极其罕见的情况：编译器不在 execroot 下
    REAL_GCC_INVOKE="${REAL_GCC_ABS}"
fi

# 5. 推导 ar 和 ld 的路径 (用于 Wrapper 内部欺骗)
#    这里可以使用绝对路径，因为它们只是被 GCC 内部调用，不会出现在依赖文件中。
TOOLCHAIN_BIN_DIR=$(dirname "${REAL_GCC_ABS}")
REAL_LD="${TOOLCHAIN_BIN_DIR}/${LD_NAME}"
REAL_AR="${TOOLCHAIN_BIN_DIR}/${AR_NAME}"

# 检查 LD 是否存在
if [[ ! -f "${REAL_LD}" ]]; then
    echo "ERROR: [gcc.sh] Found GCC at ${REAL_GCC_ABS} but LD not found at ${REAL_LD}" >&2
    exit 1
fi

# 检查 AR 是否存在
if [[ ! -f "${REAL_AR}" ]]; then
    echo "ERROR: [gcc.sh] Found GCC at ${REAL_GCC_ABS} but AR not found at ${REAL_AR}" >&2
    exit 1
fi

# 6. 创建临时目录并建立软链接
#    这是为了欺骗 GCC (driver)，让它在 -B 目录下优先找到我们的 ld 和 ar
TEMP_LD_DIR=$(mktemp -d)

# 注册清理函数：脚本无论如何退出(成功或失败)，都删除临时目录
trap 'rm -rf "${TEMP_LD_DIR}"' EXIT

# 创建软链接
ln -sf "${REAL_LD}" "${TEMP_LD_DIR}/ld"
ln -sf "${REAL_AR}" "${TEMP_LD_DIR}/ar"

# 7. 调用 GCC
#    -B: 指定编译器查找工具(as, ld等)的搜索路径
#    "${REAL_GCC_INVOKE}": 使用相对路径调用
exec "${REAL_GCC_INVOKE}" \
    -B "${TEMP_LD_DIR}" \
    "$@"