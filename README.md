# abuild-aarch64 Docker Image [![Docker](https://github.com/msrd0/docker-abuild-aarch64/workflows/Docker/badge.svg)](https://github.com/msrd0/docker-abuild-aarch64/actions?query=workflow%3ADocker)

**Docker Images:**
 - [`ghcr.io/msrd0/abuild-aarch64`](https://github.com/users/msrd0/packages/container/package/abuild-aarch64) (Pi 2 v1.2, Pi 3, Pi 4)
 - [`ghcr.io/msrd0/abuild-armv7`](https://github.com/users/msrd0/packages/container/package/abuild-armv7) (Pi 2)
 - [`ghcr.io/msrd0/abuild-armhf`](https://github.com/users/msrd0/packages/container/package/abuild-armhf) (Pi 1, Pi Zero)

This image can be used to cross-compile Alpine Linux packages for an arm-based system like a Raspberry Pi on an x86_64 host.

## Cross-Compiling Alpine Linux Packages

At the time of writing, there is no good documentation available on how to cross compile packages for Alpine Linux. The
best I could find are some posts and questions that point to
[this bootstrapping script](https://github.com/alpinelinux/aports/blob/master/scripts/bootstrap.sh)
which I then converted into a docker image - except I'm using as much precompiled stuff as possible.

This docker image has the environment variables `CHOST`, `CTARGET`, `CBUILDROOT` and `EXTRADEPENDS_TARGET` are set for
you. That means your cross-enabled package should be able to compile just fine, if you are using one of the languages
supported by GCC. Also, a custom built Rust compiler is available, but will need some adjustment to the `APKBUILD` files
on your end. If you need any other compilers, feel free to create a PR that adds support for your programming language.
