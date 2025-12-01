# cc_toolchains_linux
## Installation

Add the following to your `MODULE.bazel` to use this toolchain:

```starlark
bazel_dep(name = "cc_toolchains_linux", version = "0.0.1")

git_override(
    module_name = "cc_toolchains_linux",
    commit = "067a58b93ef9610a2274faaffc5c9042b7226330", # Check for the latest commit hash
    remote = "https://github.com/kekxv/cc_toolchains_linux.git",
)
```