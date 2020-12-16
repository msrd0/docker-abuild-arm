FROM alpine:3.12 AS abuild
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

# install basic dependencies
RUN sed -i 's,http:,https:,g' /etc/apk/repositories \
 && apk add --no-cache alpine-sdk sudo util-linux

# create build user
ENV USERNAME=docker-abuild-aarch64
ENV USERHOME=/home/docker-abuild-aarch64
RUN adduser -D "$USERNAME" -h "$USERHOME" \
 && addgroup "$USERNAME" abuild \
 && echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers \
 && mkdir -p /var/cache/distfiles \
 && chgrp abuild /var/cache/distfiles \
 && chmod 775 /var/cache/distfiles
USER docker-abuild-aarch64
WORKDIR /home/docker-abuild-aarch64
RUN mkdir -p .abuild \
 && echo "$HOME/.abuild/docker-abuild-aarch64.rsa" | abuild-keygen -a -i -b 4096

# sysroot preparations
ENV CTARGET=aarch64
ENV CBUILDROOT=/home/docker-abuild-aarch64/sysroot-aarch64
COPY alpine-devel@lists.alpinelinux.org-524d27bb.rsa.pub /etc/apk/keys/
COPY alpine-devel@lists.alpinelinux.org-58199dcc.rsa.pub /etc/apk/keys/

# new stage for bootstrapping
FROM abuild AS bootstrap

ARG JOBS=

RUN abuild-apk update \
 && [ -n "$JOBS" ] || JOBS="$(lscpu -p | grep -E '^[^#]' | wc -l)" \
 && echo "export JOBS=$JOBS" >>.abuild/abuild.conf \
 && echo 'export MAKEFLAGS=-j$JOBS' >>.abuild/abuild.conf \
 && cat .abuild/abuild.conf

# create the sysroot
RUN mkdir -p "$CBUILDROOT/etc/apk/keys" \
 && cp /etc/apk/keys/* "$CBUILDROOT/etc/apk/keys/" \
 && echo "https://dl-cdn.alpinelinux.org/alpine/v3.12/main" >"$CBUILDROOT/etc/apk/repositories" \
 && echo "https://dl-cdn.alpinelinux.org/alpine/v3.12/community" >>"$CBUILDROOT/etc/apk/repositories" \
 && abuild-apk add --initdb --arch "$CTARGET" --root "$CBUILDROOT"

# download aports
RUN git clone --depth=1 --branch=3.12-stable https://gitlab.alpinelinux.org/alpine/aports.git

# cross-build binutils - patch builddir not set on 3.12 branch
RUN sed -i 's,build(),builddir="$srcdir/binutils-$pkgver"\nbuild(),g' aports/main/binutils/APKBUILD \
 && BOOTSTRAP=nobase APKBUILD=aports/main/binutils/APKBUILD abuild -r

# musl headers
RUN CHOST=aarch64 BOOTSTRAP=nocc APKBUILD=aports/main/musl/APKBUILD abuild -r

# minimal gcc - ada/gnat is broken for cross compile on 3.12 branch
ENV LANG_ADA=false
RUN sed -E -i 's,(makedepends_host="[^"]*)\s+\S+gnat\S+("),\1\2,g' aports/main/gcc/APKBUILD \
 && EXTRADEPENDS_HOST=musl-dev BOOTSTRAP=nolibc APKBUILD=aports/main/gcc/APKBUILD abuild -r

# cross-build musl
RUN EXTRADEPENDS_BUILD="gcc-pass2-$CTARGET" CHOST="$CTARGET" BOOTSTRAP=nolibc APKBUILD=aports/main/musl/APKBUILD abuild -r

# cross-build gcc
RUN EXTRADEPENDS_TARGET="musl musl-dev" BOOTSTRAP=nobase APKBUILD=aports/main/gcc/APKBUILD abuild -r

# cross-build base
RUN BOOTSTRAP=nobase APKBUILD=aports/main/build-base/APKBUILD abuild -r

# remove the aarch64 repo - those can come from the official alpine repo
RUN rm -r "$HOME/packages/main/aarch64"

# install build-base on our sysroot
RUN abuild-apk add --arch "$CTARGET" --root "$CBUILDROOT" build-base

# last stage - pull the packages and sysroot
FROM abuild

COPY --from=bootstrap /home/docker-abuild-aarch64/sysroot-aarch64 /home/docker-abuild-aarch64/sysroot-aarch64
COPY --from=bootstrap /home/docker-abuild-aarch64/packages /home/docker-abuild-aarch64/packages
