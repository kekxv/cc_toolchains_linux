#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# (修复 Linker Script 绝对路径解析问题)
# ==========================================

# 1. 设置工具链名称
GCC_NAME="x86_64-buildroot-linux-gnu-g++"
LD_NAME="x86_64-buildroot-linux-gnu-ld"

# 2. 获取基础环境路径
EXECROOT=$(pwd -P)
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# 3. 智能查找 external 目录
ROOT_PATH=""
SEARCH_DIR="${CURRENT_DIR}"

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

# ==========================================
# 7. 自动提取并强制应用 Sysroot 绝对路径
# ==========================================
TOOLCHAIN_ROOT_DIR=$(dirname "${TOOLCHAIN_BIN_DIR}")

# 查找 sysroot 目录
REAL_SYSROOT=$(find "${TOOLCHAIN_ROOT_DIR}" -type d -name "sysroot" -print -quit)

EXTRA_FLAGS=""
if [[ -n "${REAL_SYSROOT}" ]]; then
    # -B: 告诉 GCC 在这个目录下找 crt1.o, crti.o 以及 ld 本身
    # --sysroot: 告诉 ld 所有以 / 开头的库路径都要在这个目录下找
    # 关键点：这里必须传【绝对路径】，否则 Linker Script 里的 /usr/lib64 会解析到宿主机
    EXTRA_FLAGS="-B${REAL_SYSROOT} --sysroot=${REAL_SYSROOT}"
fi
# ==========================================

# 9. 调用 GCC
# 注意：我们将 ${EXTRA_FLAGS} 放在 "$@" 之后。
# 这样我们的绝对路径 --sysroot 会覆盖 Bazel 传入的相对路径 --sysroot。
echo "${REAL_GCC_INVOKE}" \
    -no-canonical-prefixes \
    "$@" \
    ${EXTRA_FLAGS}

exec "${REAL_GCC_INVOKE}" \
    -no-canonical-prefixes \
    "$@" \
    ${EXTRA_FLAGS}