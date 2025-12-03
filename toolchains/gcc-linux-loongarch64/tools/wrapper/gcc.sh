#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 as/ar 调用的 Wrapper
# (修复 Absolute Path Inclusion 问题 )
# ==========================================

# 定义工具名称
GCC_NAME="loongarch64-linux-gnu-g++"
AR_NAME="loongarch64-linux-gnu-ar"
AS_NAME="loongarch64-linux-gnu-as"

# 1. 环境准备
EXECROOT=$(pwd -P)
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# 2. 智能查找 external 目录
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
    echo "ERROR: [g++.sh] Could not locate 'external' directory." >&2
    exit 1
fi

# 3. 查找真正的编译器
REAL_GCC_ABS=$(find -L "${ROOT_PATH}" -maxdepth 8 -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REAL_GCC_ABS}" ]]; then
    echo "ERROR: [g++.sh] Could not find ${GCC_NAME} in ${ROOT_PATH}" >&2
    exit 1
fi

# 4. 路径转换 (相对路径调用)
if [[ "${REAL_GCC_ABS}" == "${EXECROOT}"* ]]; then
    REL_PATH="${REAL_GCC_ABS#$EXECROOT}"
    REAL_GCC_INVOKE="${REL_PATH#/}"
else
    REAL_GCC_INVOKE="${REAL_GCC_ABS}"
fi

# 5. 推导 ar 和 as 并建立软链接
TOOLCHAIN_BIN_DIR=$(dirname "${REAL_GCC_ABS}")
REAL_AR="${TOOLCHAIN_BIN_DIR}/${AR_NAME}"
REAL_AS="${TOOLCHAIN_BIN_DIR}/${AS_NAME}"

if [[ ! -f "${REAL_AR}" ]] || [[ ! -f "${REAL_AS}" ]]; then
    echo "ERROR: [g++.sh] Helper tools not found." >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

ln -sf "${REAL_AR}" "${TEMP_DIR}/ar"
ln -sf "${REAL_AS}" "${TEMP_DIR}/as"

# 6. 参数处理 & 捕获依赖文件路径 (-MF)
# 我们需要找到 Bazel 传递给 GCC 的 -MF 参数，以便后续修改生成的 .d 文件
ARGS=()
DEP_FILE=""
NEXT_IS_DEP=false

for arg in "$@"; do
    # 捕获依赖文件路径
    if [[ "$NEXT_IS_DEP" == "true" ]]; then
        DEP_FILE="$arg"
        NEXT_IS_DEP=false
    elif [[ "$arg" == "-MF" ]]; then
        NEXT_IS_DEP=true
    elif [[ "$arg" == -MF* ]]; then
        # 处理 -MFfilename 这种连在一起的情况
        DEP_FILE="${arg#-MF}"
    fi

    case "$arg" in
        -std=c++20)
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

# 7. 调用 GCC (注意：这里去掉了 exec)
# 我们需要等待 GCC 执行完毕，才能处理它生成的文件
"${REAL_GCC_INVOKE}" \
    -B "${TEMP_DIR}" \
    "${ARGS[@]}"

# 捕获 GCC 的返回值
RET_CODE=$?

# 8. 【核心修复】后期处理依赖文件
# 如果编译成功，且存在依赖文件，则替换掉里面的绝对路径
if [[ $RET_CODE -eq 0 && -n "${DEP_FILE}" && -f "${DEP_FILE}" ]]; then
    # 你的报错路径前缀是: /worker/build/276122af1c2ebd83/root/
    # 我们将其替换为空，这样剩下的就是 external/... 开头的相对路径了

    # 检测操作系统以兼容 sed (MacOS vs Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # MacOS sed 需要一个空字符串作为备份扩展名
        sed -i '' 's|/worker/build/[a-f0-9]*/root/||g' "${DEP_FILE}"
    else
        # Linux sed
        sed -i 's|/worker/build/[a-f0-9]*/root/||g' "${DEP_FILE}"
    fi
fi

# 9. 返回 GCC 的原始退出码
exit $RET_CODE