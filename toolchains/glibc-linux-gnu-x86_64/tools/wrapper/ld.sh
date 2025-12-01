#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# (修复 Absolute Path Inclusion 问题)
# ==========================================

# 设置工具链名称 (根据你提供的脚本)
GCC_NAME="x86_64-buildroot-linux-gnu-g++"
LD_NAME="x86_64-buildroot-linux-gnu-ld"

# 1. 获取物理路径（解决符号链接和 /proc/self/cwd 问题）
#    EXECROOT: Bazel 执行时的根目录 (通常是 sandbox 的 execroot/_main)
EXECROOT=$(pwd -P)
#    CURRENT_DIR: 脚本文件所在的目录
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# 2. 智能查找 external 目录 (优化部分)
#    逻辑：从脚本所在目录开始向上遍历，直到找到一个包含 "external" 子目录的文件夹。
#    这兼容了脚本在 external 内部、外部、或者 toolchains 目录下的所有情况。
ROOT_PATH=""
SEARCH_DIR="${CURRENT_DIR}"

# 优先检查当前工作目录下的 external (最常见情况，速度最快)
if [[ -d "${EXECROOT}/external" ]]; then
    ROOT_PATH="${EXECROOT}/external"
else
    # 向上递归查找
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

# 3. 在 external 目录下查找真正的编译器 (获取绝对路径)
#    -maxdepth 5: 限制搜索深度，防止扫描整个目录树
#    -print -quit: 找到第一个匹配项立即停止
REAL_GCC_ABS=$(find "${ROOT_PATH}" -maxdepth 5 -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REAL_GCC_ABS}" ]]; then
    echo "ERROR: [ld.sh] Could not find ${GCC_NAME} in ${ROOT_PATH}" >&2
    exit 1
fi

# 4. 【关键修复】将绝对路径转换为相对路径
#    Bazel 为了保证构建的一致性(Hermetic)，要求编译器生成的依赖文件(.d)不能包含绝对路径。
#    如果通过绝对路径调用 GCC，它就会生成绝对路径依赖，导致报错。
#    因此，我们必须计算出 "external/..." 这样的相对路径来调用它。

if [[ "${REAL_GCC_ABS}" == "${EXECROOT}"* ]]; then
    # 从绝对路径中切掉 Execroot 前缀
    REL_PATH="${REAL_GCC_ABS#$EXECROOT}"
    # 去掉开头的 '/'
    REAL_GCC_INVOKE="${REL_PATH#/}"
else
    # 如果编译器不在 execroot 下（非常罕见），只能回退到绝对路径
    REAL_GCC_INVOKE="${REAL_GCC_ABS}"
fi

# 5. 推导 LD 的路径 (绝对路径即可，因为这是内部调用，Bazel 不关心)
TOOLCHAIN_BIN_DIR=$(dirname "${REAL_GCC_ABS}")
REAL_LD="${TOOLCHAIN_BIN_DIR}/${LD_NAME}"

# 检查 LD 是否存在
if [[ ! -f "${REAL_LD}" ]]; then
    echo "ERROR: [ld.sh] Found GCC at ${REAL_GCC_ABS} but LD not found at ${REAL_LD}" >&2
    exit 1
fi

# 6. 创建临时目录并建立 'ld' 软链接
#    这是为了欺骗 GCC (作为 driver)，让它在 -B 目录下能找到一个名字叫 'ld' 的文件
#    GCC 发现 -B 目录有 'ld'，就会调用它，而不是去调用系统的 /usr/bin/ld
TEMP_LD_DIR=$(mktemp -d)

# 注册清理函数：脚本退出时删除临时目录
trap 'rm -rf "${TEMP_LD_DIR}"' EXIT

# 创建软链接： ${TEMP_LD_DIR}/ld -> 真正的长名字 ld
ln -sf "${REAL_LD}" "${TEMP_LD_DIR}/ld"

# 7. 调用 GCC 进行链接
#    -B: 优先在临时目录查找工具（从而找到我们伪造的 ld 软链接）
#    使用相对路径 "${REAL_GCC_INVOKE}" 调用
exec "${REAL_GCC_INVOKE}" \
    -B "${TEMP_LD_DIR}" \
    "$@"