# cc_toolchains_linux
## Installation

Add the following to your `MODULE.bazel` to use this toolchain:

```starlark
bazel_dep(name = "cc_toolchains_linux", version = "0.0.1")

git_override(
    module_name = "cc_toolchains_linux",
    commit = "7db840ec7744b62884e6f6a0e8ec087b8587c8fe", # Check for the latest commit hash
    remote = "https://github.com/kekxv/cc_toolchains_linux.git",
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
