# cc_toolchains_linux
## Installation

Add the following to your `MODULE.bazel` to use this toolchain:

```starlark
bazel_dep(name = "cc_toolchains_linux", version = "0.0.1")

git_override(
    module_name = "cc_toolchains_linux",
    commit = "114efdc4e63ec3c4e30796259bcff51678bf68c6", # Check for the latest commit hash
    remote = "https://github.com/kekxv/cc_toolchains_linux.git",
)
```