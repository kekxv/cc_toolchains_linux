# cc_toolchains_linux
## Installation

Add the following to your `MODULE.bazel` to use this toolchain:

```starlark
bazel_dep(name = "cc_toolchains_linux", version = "0.0.1")

git_override(
    module_name = "cc_toolchains_linux",
    commit = "d97ccdf3a0252df672d93312fe4baefff74a6f30", # Check for the latest commit hash
    remote = "https://github.com/kekxv/cc_toolchains_linux.git",
)

# Except for the `linux x86_64`, you can register for the others if needed.
register_execution_platforms(
    "@cc_toolchains_linux//:linux-x86_64",
    "@cc_toolchains_linux//:linux-aarch64",
    "@cc_toolchains_linux//:linux-riscv64",
    "@cc_toolchains_linux//:linux-loongarch64",
    "@cc_toolchains_linux//:linux-armv7l-luckfox",
)

register_toolchains(
    "@cc_toolchains_linux//:linux-x86_64-toolchain",
    "@cc_toolchains_linux//:linux-aarch64-toolchain",
    "@cc_toolchains_linux//:linux-riscv64-licheerv-toolchain",
    "@cc_toolchains_linux//:linux-loongarch64-toolchain",
    "@cc_toolchains_linux//:linux-armv7l-luckfox-toolchain",
)
```

## Use

.bazelrc

```.bazelrc
build:linux                --platforms=@cc_toolchains_linux//:linux-x86_64
build:linux-aarch64        --platforms=@cc_toolchains_linux//:linux-aarch64
build:linux-luckfox        --platforms=@cc_toolchains_linux//:linux-armv7l-luckfox
build:linux-riscv64        --platforms=@cc_toolchains_linux//:linux-riscv64
build:linux-loongarch64    --platforms=@cc_toolchains_linux//:linux-loongarch64
```

shell:
```shell
bazel build --config=linux-luckfox ...
```
