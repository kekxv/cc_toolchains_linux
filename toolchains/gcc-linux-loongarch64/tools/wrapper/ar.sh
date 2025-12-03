#!/bin/bash

# ==========================================
# 动态查找 AR 路径并过滤参数的 Wrapper
# ==========================================

# 1. 定义工具名称
AR_NAME="loongarch64-linux-gnu-ar"

# 2. 环境准备
#    EXECROOT: Bazel 执行时的根目录 (物理路径)
EXECROOT=$(pwd -P)
#    CURRENT_DIR: 脚本文件所在的目录 (物理路径)
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# 3. 智能查找 external 目录
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

# 4. 查找真正的工具 (获取绝对路径以验证存在)
#    -maxdepth 5: 限制搜索深度，防止扫描太深
#    -print -quit: 找到第一个匹配项立即停止
REAL_AR_ABS=$(find -L "${ROOT_PATH}" -maxdepth 8 -name "${AR_NAME}" -type f -print -quit)

if [[ -z "${REAL_AR_ABS}" ]]; then
    echo "ERROR: [ar.sh] Could not find ${AR_NAME} in ${ROOT_PATH}" >&2
    exit 1
fi

# 5. 将绝对路径转换为相对路径
#    保持 Bazel 构建的一致性 (Hermeticity)
if [[ "${REAL_AR_ABS}" == "${EXECROOT}"* ]]; then
    # 移除 Execroot 前缀
    REL_PATH="${REAL_AR_ABS#$EXECROOT}"
    # 移除开头的斜杠，得到 external/repo_name/.../ar
    REAL_AR_INVOKE="${REL_PATH#/}"
else
    # 极其罕见的情况：工具不在 execroot 下
    REAL_AR_INVOKE="${REAL_AR_ABS}"
fi

# 6. 参数处理
#    构建新的参数数组，移除不兼容的 flag (如 -EL)
ARGS=()
for arg in "$@"; do
    case "$arg" in
        # 忽略大小端参数，ar 通常不需要，或者是误传进来的
        -EL)
            ;;
        *)
            # 其他参数原样保留
            ARGS+=("$arg")
            ;;
    esac
done

# 7. 调用 AR
exec "${REAL_AR_INVOKE}" "${ARGS[@]}"