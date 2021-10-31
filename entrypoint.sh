#!/bin/ash
set -e
set -o pipefail

# setup the abuild file
if [ -n "$PACKAGER_PRIVKEY" ]; then
	echo "PACKAGER_PRIVKEY=\"$PACKAGER_PRIVKEY\"" >~/.abuild/abuild.conf
else
	test ! -e ~/.abuild/abuild.conf || rm ~/.abuild/abuild.conf
	echo | abuild-keygen -a -i -b 4096
fi
[ -n "$JOBS" ] || JOBS="$(lscpu -p | grep -E '^[^#]' | wc -l)"
echo "export JOBS=$JOBS" >>~/.abuild/abuild.conf
echo 'export MAKEFLAGS=-j$JOBS' >>~/.abuild/abuild.conf

echo
echo
echo 'To install packages for aarch64, use the following command:'
echo
echo '    abuild-apk add --root $CBUILDROOT --arch $CTARGET <package>'
echo

# run whatever the user wants
exec "$@"
