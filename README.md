# cc_toolchains_linux

## bazelrc config

```.bazelrc
build:linux-remote                --remote_default_exec_properties=OSFamily=linux
#build:linux-remote                --remote_default_exec_properties=container-image=docker://ghcr.io/catthehacker/ubuntu:act-22.04@sha256:5f9c35c25db1d51a8ddaae5c0ba8d3c163c5e9a4a6cc97acd409ac7eae239448
build:linux-remote                --remote_instance_name=fuse
```

## Installation

Add the following to your `MODULE.bazel` to use this toolchain:

```starlark
bazel_dep(name = "cc_toolchains_linux", version = "0.0.1")

git_override(
    module_name = "cc_toolchains_linux",
    commit = "e0a3d9da91e3ef34a3636f8a91fc9481ed500725", # Check for the latest commit hash
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
    # use musl
    # "@cc_toolchains_linux//:linux-aarch64-musl-toolchain",
    # use glibc
    # "@cc_toolchains_linux//:linux-aarch64-glibc-toolchain",
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
