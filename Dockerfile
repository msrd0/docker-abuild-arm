ARG ALPINE_VERSION=3.13
FROM alpine:$ALPINE_VERSION AS abuild
ARG ALPINE_VERSION=3.13
ENV ALPINE_VERSION=$ALPINE_VERSION
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

ENV USERNAME=docker-abuild-aarch64
ENV USERHOME=/home/docker-abuild-aarch64
RUN env && test -n "$ALPINE_VERSION" \
 && sed -i 's,http:,https:,g' /etc/apk/repositories \
 && apk add --no-cache alpine-sdk sudo util-linux \
 && adduser -D "$USERNAME" -h "$USERHOME" \
 && addgroup "$USERNAME" abuild \
 && echo "root ALL=(ALL) ALL" >/etc/sudoers \
 && echo "%abuild ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers \
 && mkdir -p /var/cache/distfiles \
 && chgrp abuild /var/cache/distfiles \
 && chmod 775 /var/cache/distfiles \
 && mkdir -p "$USERHOME/.abuild" \
 && echo "$USERHOME/.abuild/docker-abuild-aarch64.rsa" | abuild-keygen -i -b 4096 \
 && chown -R "$USERNAME:$USERNAME" "$USERHOME/.abuild"
USER docker-abuild-aarch64
WORKDIR /home/docker-abuild-aarch64

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
 && echo 'REPODEST="$HOME/packages-aarch64"' >.abuild/abuild.conf \
 && echo "PACKAGER_PRIVKEY=\"$HOME/.abuild/docker-abuild-aarch64.rsa\"" >>.abuild/abuild.conf \
 && echo "export JOBS=$JOBS" >>.abuild/abuild.conf \
 && echo 'export MAKEFLAGS=-j$JOBS' >>.abuild/abuild.conf \
 && cat .abuild/abuild.conf

# create the sysroot
RUN mkdir -p "$CBUILDROOT/etc/apk/keys" \
 && cp /etc/apk/keys/* "$CBUILDROOT/etc/apk/keys/" \
 && echo "https://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/main" >"$CBUILDROOT/etc/apk/repositories" \
 && echo "https://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/community" >>"$CBUILDROOT/etc/apk/repositories" \
 && abuild-apk add --initdb --arch "$CTARGET" --root "$CBUILDROOT"

# download aports
RUN git clone --depth=1 --branch=$ALPINE_VERSION-stable https://gitlab.alpinelinux.org/alpine/aports.git

# cross-build binutils
RUN BOOTSTRAP=nobase APKBUILD=aports/main/binutils/APKBUILD abuild -r

# musl headers
RUN CHOST=aarch64 BOOTSTRAP=nocc APKBUILD=aports/main/musl/APKBUILD abuild -r

# minimal gcc
ENV LANG_ADA=false
RUN EXTRADEPENDS_HOST=musl-dev BOOTSTRAP=nolibc APKBUILD=aports/main/gcc/APKBUILD abuild -r

# cross-build musl
RUN EXTRADEPENDS_BUILD="gcc-pass2-$CTARGET" CHOST="$CTARGET" BOOTSTRAP=nolibc APKBUILD=aports/main/musl/APKBUILD abuild -r

# cross-build gcc
RUN EXTRADEPENDS_TARGET="musl musl-dev" BOOTSTRAP=nobase APKBUILD=aports/main/gcc/APKBUILD abuild -r

# cross-build base
RUN BOOTSTRAP=nobase APKBUILD=aports/main/build-base/APKBUILD abuild -r

# cleanup aarch64 packages - those come from the alpine repositories
RUN rm -r "$HOME/packages-aarch64/main/aarch64"

# last stage - pull the packages and sysroot
FROM abuild

USER root
COPY --from=bootstrap /home/docker-abuild-aarch64/sysroot-aarch64 /home/docker-abuild-aarch64/sysroot-aarch64
COPY --from=bootstrap /home/docker-abuild-aarch64/packages-aarch64 /home/docker-abuild-aarch64/packages-aarch64
RUN echo "/home/docker-abuild-aarch64/packages-aarch64/main" >>/etc/apk/repositories

ENV CHOST=aarch64
ENV EXTRADEPENDS_TARGET="build-base"

USER docker-abuild-aarch64
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/ash"]
