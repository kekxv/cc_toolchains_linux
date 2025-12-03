#!/bin/bash

# ==========================================
# 动态查找 AR 路径 Wrapper
# ==========================================

# 定义工具名称 (注意这里变量名改为了 AR_NAME 以避免混淆)
AR_NAME="x86_64-buildroot-linux-gnu-ar"

# 1. 环境准备
#    EXECROOT: Bazel 执行时的根目录 (物理路径)
EXECROOT=$(pwd -P)
#    CURRENT_DIR: 脚本文件所在的目录 (物理路径)
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# 2. 智能查找 external 目录
#    逻辑：优先检查当前目录下的 external (最快)，如果没找到则从脚本目录向上遍历。
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
    echo "ERROR: [ar.sh] Could not locate 'external' directory." >&2
    exit 1
fi

# 3. 查找真正的 AR 工具 (获取绝对路径以验证存在)
#    -maxdepth 5: 限制搜索深度，防止扫描太深
#    -print -quit: 找到第一个匹配项立即停止
REAL_AR_ABS=$(find -L "${ROOT_PATH}" -maxdepth 8 -name "${AR_NAME}" -type f -print -quit)

if [[ -z "${REAL_AR_ABS}" ]]; then
    echo "ERROR: [ar.sh] Could not find ${AR_NAME} in ${ROOT_PATH}" >&2
    exit 1
fi

# 4. 将绝对路径转换为相对路径
#    虽然 ar 不像 gcc 那样敏感，但保持相对路径调用符合 Bazel 的 Hermetic 规范，
#    避免构建日志中出现绝对路径。
if [[ "${REAL_AR_ABS}" == "${EXECROOT}"* ]]; then
    # 移除 Execroot 前缀
    REL_PATH="${REAL_AR_ABS#$EXECROOT}"
    # 移除开头的斜杠，得到 external/repo_name/.../ar
    REAL_AR_INVOKE="${REL_PATH#/}"
else
    # 极其罕见的情况：工具不在 execroot 下
    REAL_AR_INVOKE="${REAL_AR_ABS}"
fi

# 5. 调用 AR
#    ar 不需要 -B 参数，也不需要配合 ld，直接透传参数即可
exec "${REAL_AR_INVOKE}" "$@"