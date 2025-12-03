#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 as/ar 调用的 Wrapper
# (修复 Absolute Path Inclusion 问题)
# ==========================================

# 定义工具名称
GCC_NAME="arm-rockchip830-linux-uclibcgnueabihf-g++"
AR_NAME="arm-rockchip830-linux-uclibcgnueabihf-ar"
AS_NAME="arm-rockchip830-linux-uclibcgnueabihf-as"

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
    echo "ERROR: [g++.sh] Could not locate 'external' directory." >&2
    exit 1
fi

# 3. 查找真正的编译器 (获取绝对路径以验证存在)
#    -maxdepth 5: 限制搜索深度，防止扫描太深
#    -print -quit: 找到第一个匹配项立即停止
REAL_GCC_ABS=$(find -L "${ROOT_PATH}" -maxdepth 8 -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REAL_GCC_ABS}" ]]; then
    echo "ERROR: [g++.sh] Could not find ${GCC_NAME} in ${ROOT_PATH}" >&2
    exit 1
fi

# 4. 【关键修复】将绝对路径转换为相对路径
#    这是解决 .d 文件包含绝对路径的根本方法。
#    只要用 "external/repo/.../g++" 这种相对路径调用编译器，
#    GCC 就会在依赖文件中输出相对路径，因此不再需要脚本最后那段 sed 替换逻辑。
if [[ "${REAL_GCC_ABS}" == "${EXECROOT}"* ]]; then
    # 移除 Execroot 前缀
    REL_PATH="${REAL_GCC_ABS#$EXECROOT}"
    # 移除开头的斜杠，得到 external/repo_name/.../g++
    REAL_GCC_INVOKE="${REL_PATH#/}"
else
    # 极其罕见的情况：编译器不在 execroot 下
    REAL_GCC_INVOKE="${REAL_GCC_ABS}"
fi

# 5. 推导 ar 和 as 的路径
#    用于在临时目录创建软链接，欺骗 GCC 驱动程序
TOOLCHAIN_BIN_DIR=$(dirname "${REAL_GCC_ABS}")
REAL_AR="${TOOLCHAIN_BIN_DIR}/${AR_NAME}"
REAL_AS="${TOOLCHAIN_BIN_DIR}/${AS_NAME}"

# 检查 AR/AS 是否存在
if [[ ! -f "${REAL_AR}" ]]; then
    echo "ERROR: [g++.sh] Found GCC at ${REAL_GCC_ABS} but AR not found at ${REAL_AR}" >&2
    exit 1
fi
if [[ ! -f "${REAL_AS}" ]]; then
    echo "ERROR: [g++.sh] Found GCC at ${REAL_GCC_ABS} but AS not found at ${REAL_AS}" >&2
    exit 1
fi

# 6. 创建临时目录并建立软链接
#    这是为了让 GCC 在 -B 路径下找到名字叫 'ar' 和 'as' 的工具
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

# 创建软链接 (短名字 -> 长名字)
ln -sf "${REAL_AR}" "${TEMP_DIR}/ar"
ln -sf "${REAL_AS}" "${TEMP_DIR}/as"


# 6. 参数处理
#    构建新的参数数组，移除不兼容的 flag (如 -EL)
ARGS=()
for arg in "$@"; do
    case "$arg" in
        # 忽略大小端参数，ar 通常不需要，或者是误传进来的
        -std=c++20)
            ;;
        *)
            # 其他参数原样保留
            ARGS+=("$arg")
            ;;
    esac
done

# 7. 调用 GCC
#    -B: 指定编译器查找辅助工具(as, ld等)的优先搜索路径
#    使用相对路径 "${REAL_GCC_INVOKE}" 调用，无需后续处理 .d 文件
exec "${REAL_GCC_INVOKE}" \
    -B "${TEMP_DIR}" \
    "${ARGS[@]}"