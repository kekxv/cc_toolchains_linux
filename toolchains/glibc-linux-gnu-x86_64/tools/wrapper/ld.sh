#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 Linker Script (Wrapper)
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

# 5. 计算相对路径调用 (Bazel Hermetic)
if [[ "${REAL_GCC_ABS}" == "${EXECROOT}"* ]]; then
    REL_PATH="${REAL_GCC_ABS#$EXECROOT}"
    REAL_GCC_INVOKE="${REL_PATH#/}"
else
    REAL_GCC_INVOKE="${REAL_GCC_ABS}"
fi

# 6. 推导工具链相关路径
TOOLCHAIN_BIN_DIR=$(dirname "${REAL_GCC_ABS}")
TOOLCHAIN_ROOT_DIR=$(dirname "${TOOLCHAIN_BIN_DIR}")

# 查找 sysroot 目录
REAL_SYSROOT=$(find "${TOOLCHAIN_ROOT_DIR}" -type d -name "sysroot" -print -quit)

# ==========================================
# 7. [核心修复] 动态修补 Linker Script (.a 文件)
# ==========================================
# Buildroot 生成的 libm.a/libc.a 包含绝对路径 (如 /usr/lib64/libmvec.a)
# 我们创建一个临时目录，把这些文件复制出来，用 sed 去掉绝对路径，
# 然后用 -L 让 ld 优先读取修改后的文件。
# ==========================================

EXTRA_FLAGS=""

if [[ -n "${REAL_SYSROOT}" ]]; then
    # 1. 创建临时修补目录 (位于 execroot 下，确保 ld 能访问)
    # 使用 $$ 加入 PID 防止并发冲突
    FIX_DIR="${EXECROOT}/_bazel_fixed_libs_$$"
    mkdir -p "${FIX_DIR}"

    # 2. 需要检查和修复的库列表
    # 通常 libc.a, libm.a, libpthread.a 是 Linker Script
    LIBS_TO_FIX=("libc.a" "libm.a" "libpthread.a")

    for lib_name in "${LIBS_TO_FIX[@]}"; do
        # 在 sysroot 中查找该文件 (find 能够处理 lib vs lib64 的差异)
        found_lib=$(find "${REAL_SYSROOT}" -name "${lib_name}" -type f -print -quit)

        if [[ -n "${found_lib}" ]]; then
            # 检查是否为 Linker Script (包含 GROUP 关键字)
            if grep -q "GROUP" "${found_lib}"; then
                # 复制并修改:
                # 正则解释: s|/[^ ]*/([^/ ]+\.a)|\1|g
                # 将 "/usr/lib64/libmvec.a" 替换为 "libmvec.a"
                # 将 "/lib/libpthread.so.0" 替换为 "libpthread.so.0"
                sed -E 's|/[^ )]*/([^/ )]+\.[a|so][^ )]*)|\1|g' "${found_lib}" > "${FIX_DIR}/${lib_name}"
            fi
        fi
    done

    # 3. 设置 Flags
    # -B: 查找 crt*.o
    # --sysroot: 查找库的基础路径
    # -L: 优先在我们的 FIX_DIR 中查找 .a 文件 (以此劫持原始的坏文件)
    EXTRA_FLAGS="-B${REAL_SYSROOT} --sysroot=${REAL_SYSROOT} -L${FIX_DIR}"

    # 4. 注册清理函数 (Trap)，脚本退出时删除临时目录
    trap "rm -rf ${FIX_DIR}" EXIT
fi

# ==========================================
# 8. 执行 GCC
# ==========================================

# 将 EXTRA_FLAGS 放在 "$@" 之前或之后其实很讲究。
# 放在 "$@" 之后能确保我们的 -L 优先级更高(如果 Bazel 没有强制指定其他 -L)。
# 通常 GCC 遵循 "First match" 原则对于 -L，所以我们把 -L 放在最前面可能更稳妥？
# 不，库的搜索顺序是按 -L 出现的顺序。
# 我们希望 FIX_DIR 在 Sysroot 的隐式路径之前被搜索到。

# 构建最终命令
# 注意：我们将 EXTRA_FLAGS 分拆，确保 -L 能够生效
echo "${REAL_GCC_INVOKE}" \
    -no-canonical-prefixes \
    ${EXTRA_FLAGS} \
    "$@"

exec "${REAL_GCC_INVOKE}" \
    -no-canonical-prefixes \
    ${EXTRA_FLAGS} \
    "$@"