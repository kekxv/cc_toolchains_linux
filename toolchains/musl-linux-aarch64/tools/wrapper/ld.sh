#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# (修复 Absolute Path Inclusion 问题)
# ==========================================

# 定义工具名称
GCC_NAME="aarch64-buildroot-linux-musl-g++.br_real"
LD_NAME="aarch64-buildroot-linux-musl-ld"

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
    echo "ERROR: [ld.sh] Could not locate 'external' directory." >&2
    exit 1
fi

# 3. 查找真正的编译器 (获取绝对路径以验证存在)
#    -maxdepth 5: 限制搜索深度，防止扫描太深
#    -print -quit: 找到第一个匹配项立即停止
REAL_GCC_ABS=$(find -L "${ROOT_PATH}" -maxdepth 8 -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REAL_GCC_ABS}" ]]; then
    echo "ERROR: [ld.sh] Could not find ${GCC_NAME} in ${ROOT_PATH}" >&2
    exit 1
fi

# 4. 【关键修复】将绝对路径转换为相对路径
#    Bazel 要求编译器产生的依赖文件(.d)必须包含相对路径。
#    如果这里用绝对路径调用 GCC，它生成的依赖就是绝对路径，导致构建失败。
if [[ "${REAL_GCC_ABS}" == "${EXECROOT}"* ]]; then
    # 移除 Execroot 前缀
    REL_PATH="${REAL_GCC_ABS#$EXECROOT}"
    # 移除开头的斜杠，得到 external/repo_name/.../g++
    REAL_GCC_INVOKE="${REL_PATH#/}"
else
    # 极其罕见的情况：编译器不在 execroot 下
    REAL_GCC_INVOKE="${REAL_GCC_ABS}"
fi

# 5. 推导 LD 的路径 (用于 Wrapper 内部欺骗)
#    这里可以使用绝对路径，因为它是被 GCC 内部调用的
TOOLCHAIN_BIN_DIR=$(dirname "${REAL_GCC_ABS}")
REAL_LD="${TOOLCHAIN_BIN_DIR}/${LD_NAME}"

# 检查 LD 是否存在
if [[ ! -f "${REAL_LD}" ]]; then
    echo "ERROR: [ld.sh] Found GCC at ${REAL_GCC_ABS} but LD not found at ${REAL_LD}" >&2
    exit 1
fi

# 6. 创建临时目录并建立软链接
#    这是为了欺骗 GCC (driver)，让它在 -B 目录下优先找到我们的 ld
TEMP_LD_DIR=$(mktemp -d)

# 注册清理函数：脚本无论如何退出(成功或失败)，都删除临时目录
trap 'rm -rf "${TEMP_LD_DIR}"' EXIT

# 创建软链接
ln -sf "${REAL_LD}" "${TEMP_LD_DIR}/ld"


# 4.1 解析参数找到 sysroot 路径
#     Parse arguments to find the sysroot path.
SYSROOT_PATH=""
for arg in "$@"; do
    if [[ "$arg" == --sysroot=* ]]; then
        SYSROOT_PATH="${arg#*=}"
        break
    fi
done

# 存放修复后库文件的目录
# Directory to store fixed library files.
FIXED_LIB_DIR="${TEMP_DIR}/fixed_lib"
mkdir -p "${FIXED_LIB_DIR}"

# 4.2 定义修复函数
#     Define the fix function.
fix_linker_script() {
    local src_file="$1"

    # 只有文件存在时才处理
    # Process only if the file exists.
    if [[ -f "${src_file}" ]]; then
        local file_name=$(basename "$src_file")
        local dst_file="${FIXED_LIB_DIR}/${file_name}"

        # 复制文件到临时目录 (避免修改只读的源文件)
        # Copy file to temp dir (avoid modifying read-only source files).
        cp "${src_file}" "${dst_file}"
        chmod +w "${dst_file}"

        # === 关键修正：按顺序替换路径 ===
        # === Critical Fix: Replace paths in specific order ===

        # 1. 先替换最长的路径前缀 (/usr/lib64/ 和 /usr/lib/)
        #    这样可以避免把 /usr/lib/xxx 错误地变成 /usrlib/xxx 或 /usrxxx
        # 1. Replace longest path prefixes first (/usr/lib64/ and /usr/lib/).
        #    This prevents corrupting paths like /usr/lib/xxx into /usrlib/xxx.
        sed -i 's|/usr/lib64/||g' "${dst_file}"
        sed -i 's|/usr/lib/||g' "${dst_file}"

        # 2. 再替换短的路径前缀 (/lib64/ 和 /lib/)
        # 2. Then replace shorter path prefixes (/lib64/ and /lib/).
        sed -i 's|/lib64/||g' "${dst_file}"
        sed -i 's|/lib/||g' "${dst_file}"
    fi
}

if [[ -n "${SYSROOT_PATH}" ]]; then
    # 尝试修复 libm.so (数学库)
    # Attempt to fix libm.so (Math library).
    fix_linker_script "${SYSROOT_PATH}/usr/lib/libm.so"
    fix_linker_script "${SYSROOT_PATH}/lib/libm.so"
    fix_linker_script "${SYSROOT_PATH}/usr/lib64/libm.so"

    # 尝试修复 libc.so (C 标准库)
    # Attempt to fix libc.so (C Standard library).
    fix_linker_script "${SYSROOT_PATH}/usr/lib/libc.so"
    fix_linker_script "${SYSROOT_PATH}/lib/libc.so"
    fix_linker_script "${SYSROOT_PATH}/usr/lib64/libc.so"
fi

# ==============================================================================
# 5. 调用 GCC 进行链接
#    Invoke GCC to perform linking.
# ==============================================================================

EXTRA_ARGS=()

# 如果有修复后的库，将该目录加入搜索路径 (-L)
# If fixed libraries exist, add their directory to the search path (-L).
if [[ -d "${FIXED_LIB_DIR}" ]]; then
    EXTRA_ARGS+=("-L${FIXED_LIB_DIR}")
fi

# -no-canonical-prefixes: 防止 GCC 将路径展开为绝对路径
# -no-canonical-prefixes: Prevents GCC from resolving paths to absolute paths.
# -B: 指向包含 'ld' 软链接的目录 / Points to the dir containing the 'ld' symlink.
exec "${REAL_GCC}" \
    -B "${TEMP_BIN_DIR}" \
    "${EXTRA_ARGS[@]}" \
    "$@"
