ARG ALPINE_VERSION=3.16
FROM alpine:$ALPINE_VERSION AS abuild
ARG ALPINE_VERSION=3.16
ENV ALPINE_VERSION=$ALPINE_VERSION
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

ENV USERNAME=docker-abuild-arm
ENV USERHOME=/home/docker-abuild-arm
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
 && echo "$USERHOME/.abuild/$USERNAME.rsa" | abuild-keygen -i -b 4096 \
 && chown -R "$USERNAME:$USERNAME" "$USERHOME/.abuild"
USER docker-abuild-arm
WORKDIR /home/docker-abuild-arm

# sysroot preparations
ARG CTARGET=aarch64
ENV CTARGET=$CTARGET
ENV CBUILDROOT=/home/docker-abuild-arm/sysroot-arm
COPY alpine-devel@lists.alpinelinux.org-524d27bb.rsa.pub /etc/apk/keys/
COPY alpine-devel@lists.alpinelinux.org-58199dcc.rsa.pub /etc/apk/keys/

# new stage for bootstrapping
FROM abuild AS bootstrap

ARG JOBS=

RUN abuild-apk update \
 && [ -n "$JOBS" ] || JOBS="$(lscpu -p | grep -E '^[^#]' | wc -l)" \
 && echo 'REPODEST="$HOME/packages-arm"' >.abuild/abuild.conf \
 && echo "PACKAGER_PRIVKEY=\"$HOME/.abuild/$USERNAME.rsa\"" >>.abuild/abuild.conf \
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
RUN CHOST="$CTARGET" BOOTSTRAP=nocc APKBUILD=aports/main/musl/APKBUILD abuild -r

# minimal gcc
ENV LANG_ADA=false
RUN EXTRADEPENDS_HOST=musl-dev BOOTSTRAP=nolibc APKBUILD=aports/main/gcc/APKBUILD abuild -r

# cross-build musl
RUN EXTRADEPENDS_BUILD="gcc-pass2-$CTARGET" CHOST="$CTARGET" BOOTSTRAP=nolibc APKBUILD=aports/main/musl/APKBUILD abuild -r

# cross-build gcc
RUN EXTRADEPENDS_TARGET="musl musl-dev" BOOTSTRAP=nobase APKBUILD=aports/main/gcc/APKBUILD abuild -r

# cross-build base
RUN BOOTSTRAP=nobase APKBUILD=aports/main/build-base/APKBUILD abuild -r

# enable main repository for the community section
RUN echo "$USERHOME/packages-arm/main" | sudo tee -a /etc/apk/repositories

# build rust - slightly modified, but we'll put it in the community repo anyways
RUN mkdir community
COPY rust community/rust
RUN sudo chown -R docker-abuild-arm community/rust \
 && EXTRADEPENDS_TARGET="libgcc musl musl-dev" APKBUILD=community/rust/APKBUILD abuild -r

# cleanup arm packages - those come from the alpine repositories
RUN rm -r "$HOME/packages-arm/main/$CTARGET"

# remove cache from the sysroot
RUN sudo rm -r "$CBUILDROOT/var/cache"/*

# last stage - pull the packages and sysroot
FROM abuild

USER root
COPY --from=bootstrap /home/docker-abuild-arm/sysroot-arm /home/docker-abuild-arm/sysroot-arm
COPY --from=bootstrap /home/docker-abuild-arm/packages-arm /home/docker-abuild-arm/packages-arm
RUN echo "$USERHOME/packages-arm/main" >>/etc/apk/repositories \
 && echo "$USERHOME/packages-arm/community" >>/etc/apk/repositories

ENV CHOST=$CTARGET
ENV EXTRADEPENDS_TARGET="build-base"

USER docker-abuild-arm
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/ash"]
