#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# (修复 Absolute Path Inclusion & Sysroot 问题)
# ==========================================

# 1. 设置工具链名称
GCC_NAME="x86_64-buildroot-linux-gnu-g++"
LD_NAME="x86_64-buildroot-linux-gnu-ld"

# 2. 获取基础环境路径
#    EXECROOT: Bazel 执行时的根目录
EXECROOT=$(pwd -P)
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# 3. 智能查找 external 目录
#    从脚本目录向上查找，直到找到 external 目录
ROOT_PATH=""
SEARCH_DIR="${CURRENT_DIR}"

# 优先检查当前目录下的 external (最快)
if [[ -d "${EXECROOT}/external" ]]; then
    ROOT_PATH="${EXECROOT}/external"
else
    while [[ "${SEARCH_DIR}" != "/" ]]; do
        if [[ -d "${SEARCH_DIR}/external" ]]; then
            ROOT_PATH="${SEARCH_DIR}/external"
            break
        fi
        SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
    done
fi

if [[ -z "${ROOT_PATH}" ]]; then
    echo "ERROR: [ld.sh] Could not locate 'external' directory." >&2
    exit 1
fi

# 4. 查找真正的编译器 (绝对路径)
#    注意：这里增加了排除逻辑，防止找到脚本自己(如果脚本同名)或死循环
REAL_GCC_ABS=$(find -L "${ROOT_PATH}" -maxdepth 8 -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REAL_GCC_ABS}" ]]; then
    echo "ERROR: [ld.sh] Could not find ${GCC_NAME} in ${ROOT_PATH}" >&2
    exit 1
fi

# 5. 计算相对路径调用 (满足 Bazel Hermetic 要求)
if [[ "${REAL_GCC_ABS}" == "${EXECROOT}"* ]]; then
    REL_PATH="${REAL_GCC_ABS#$EXECROOT}"
    REAL_GCC_INVOKE="${REL_PATH#/}"
else
    REAL_GCC_INVOKE="${REAL_GCC_ABS}"
fi

# 6. 推导 LD 路径 (绝对路径)
TOOLCHAIN_BIN_DIR=$(dirname "${REAL_GCC_ABS}")
REAL_LD="${TOOLCHAIN_BIN_DIR}/${LD_NAME}"

if [[ ! -f "${REAL_LD}" ]]; then
    echo "ERROR: [ld.sh] Found GCC at ${REAL_GCC_ABS} but LD not found at ${REAL_LD}" >&2
    exit 1
fi

# 7. 【关键修复 1】处理参数：将相对路径 Sysroot 转换为绝对路径
#    这解决了 Linker Script 中绝对路径 (/usr/lib/...) 无法被相对路径 Sysroot 正确重定位的问题
FINAL_ARGS=()
for arg in "$@"; do
    if [[ "$arg" == --sysroot=* ]]; then
        SYSROOT_VAL="${arg#--sysroot=}"
        # 如果不是以 / 开头，说明是相对路径，加上 EXECROOT
        if [[ "$SYSROOT_VAL" != /* ]]; then
            FINAL_ARGS+=("--sysroot=${EXECROOT}/${SYSROOT_VAL}")
        else
            FINAL_ARGS+=("$arg")
        fi
    else
        FINAL_ARGS+=("$arg")
    fi
done

# 9. 调用 GCC
#    -no-canonical-prefixes: 防止 GCC 解析软链接后的物理路径，保持相对路径调用结构
#    -B: 指向包含伪造 ld 的目录
exec "${REAL_GCC_INVOKE}" \
    -no-canonical-prefixes \
    "${FINAL_ARGS[@]}"