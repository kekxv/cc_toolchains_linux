#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# ==========================================

# 1. 获取当前工作目录（Bazel execroot）
REPO_ROOT=$(pwd)
CURRENT_DIR=$(cd $(dirname $0); pwd)


# 2. 动态查找 GCC 编译器
GCC_NAME="aarch64-buildroot-linux-musl-g++.br_real"
AR_NAME="aarch64-buildroot-linux-musl-ar"
AS_NAME="aarch64-buildroot-linux-musl-as"

# 【修改点 1】：从 CURRENT_DIR 中提取出 external 根目录的绝对路径
# 逻辑：匹配直到 "external" 为止的路径，丢弃后面的部分
# 例如：/proc/self/cwd/external/my_repo/bin -> /proc/self/cwd/external
EXTERNAL_ROOT=$(echo "${CURRENT_DIR}" | sed 's|\(.*external\).*|\1|')

# 校验提取结果，如果路径里没有 external，回退到默认的相对路径 'external'
if [[ "${EXTERNAL_ROOT}" == "${CURRENT_DIR}" ]] && [[ "${CURRENT_DIR}" != *"external"* ]]; then
    EXTERNAL_ROOT="external"
fi

# 【修改点 2】：使用提取出的绝对路径进行查找
# 注意：因为 EXTERNAL_ROOT 是绝对路径，find 返回的也会是绝对路径
REAL_GCC=$(find -L "${EXTERNAL_ROOT}" -name "${GCC_NAME}" -prune -type f -print -quit)

if [[ -z "${REAL_GCC}" ]]; then
    echo "ERROR: [gcc.sh] Could not find ${GCC_NAME} in ${EXTERNAL_ROOT}" >&2
    exit 1
fi

# 3. 解析绝对路径
# 【修改点 3】：因为 find 返回的已经是绝对路径了，不再需要拼接 REPO_ROOT
# 原逻辑：REAL_GCC="${REPO_ROOT}/${REL_GCC_PATH}" -> 已废弃
TOOL_DIR=$(dirname "${REAL_GCC}")
REAL_AR="${TOOL_DIR}/${AR_NAME}"
REAL_AS="${TOOL_DIR}/${AS_NAME}"

# 检查 AR/AS 是否存在
if [[ ! -f "${REAL_AR}" ]]; then
    echo "ERROR: [gcc.sh] Found GCC at ${REAL_GCC} but AR not found at ${REAL_AR}" >&2
    exit 1
fi
if [[ ! -f "${REAL_AS}" ]]; then
    echo "ERROR: [gcc.sh] Found GCC at ${REAL_GCC} but AS not found at ${REAL_AS}" >&2
    exit 1
fi

# 4. 创建临时目录并建立 'ar'/'as' 软链接
TEMP_DIR=$(mktemp -d)

# 确保脚本退出时删除临时目录
cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

ln -sf "${REAL_AR}" "${TEMP_DIR}/ar"
ln -sf "${REAL_AS}" "${TEMP_DIR}/as"

# 5. 调用 GCC 进行编译/链接
"${REAL_GCC}" \
    -B "${TEMP_DIR}" \
    "$@"
RET_CODE=$?

# 如果编译失败，直接退出
if [ $RET_CODE -ne 0 ]; then
    exit $RET_CODE
fi

# ==========================================
# 6. 【关键修复】修复 .d 依赖文件中的绝对路径
# ==========================================

DEP_FILE=""
PREV_ARG=""

for arg in "$@"; do
    if [ "$PREV_ARG" == "-MF" ]; then
        DEP_FILE="$arg"
        break
    fi
    PREV_ARG="$arg"
done

if [ -n "$DEP_FILE" ] && [ -f "$DEP_FILE" ]; then
    # 路径修复逻辑保持不变
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i "" 's|/[^ ]*/external/|external/|g' "$DEP_FILE"
    else
        sed -i 's|/[^ ]*/external/|external/|g' "$DEP_FILE"
    fi
fi

exit $RET_CODE