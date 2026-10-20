#!/usr/bin/env bash
# Cross-compile QEMU for Android arm64 and drop the results into the Android project.
# Run inside WSL2 (Ubuntu), from the Linux filesystem (~/), NOT from /mnt/c (very slow).
#
# Prereqs (Ubuntu): sudo apt install -y build-essential ninja-build python3-pip python3-venv \
#     pkg-config unzip wget git flex bison meson
#   Need a LINUX NDK in WSL -- the Windows one in C:\Android won't run here.
#   e.g. wget https://dl.google.com/android/repository/android-ndk-r27c-linux.zip && unzip it, then:
#   export NDK=$HOME/android-ndk-r27c
#
# Usage: NDK=~/android-ndk-r27c QEMU_SRC=~/qemu-11.1.2 ./build-qemu.sh
set -euo pipefail

: "${NDK:?set NDK to a Linux NDK dir}"
: "${QEMU_SRC:?set QEMU_SRC to the extracted qemu-11.1.2 dir}"
API=28                       # bionic has iconv from API 28; avoids building libiconv for glib
JOBS=$(nproc)
GLIB_VER=2.82.5
PIXMAN_VER=0.43.4

HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(dirname "$HERE")
WORK=$HOME/qemu-android-work
PREFIX=$WORK/deps            # static deps install here
STAGE=$WORK/stage            # QEMU "make install" lands here
TB=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
CC=$TB/aarch64-linux-android${API}-clang
CXX=$TB/aarch64-linux-android${API}-clang++
mkdir -p "$WORK" "$PREFIX" "$STAGE"

# ---- meson cross file (for glib + pixman) ----
cat > "$WORK/android-arm64.cross" <<CROSS
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$TB/llvm-ar'
strip = '$TB/llvm-strip'
pkg-config = 'pkg-config'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
pkg_config_libdir = '$PREFIX/lib/pkgconfig'
CROSS

fetch() { [ -f "$WORK/$2" ] || wget -q -O "$WORK/$2" "$1"; }

build_pixman() {
  [ -f "$PREFIX/lib/libpixman-1.a" ] && return
  fetch "https://cairographics.org/releases/pixman-$PIXMAN_VER.tar.gz" pixman.tgz
  tar -C "$WORK" -xf "$WORK/pixman.tgz"
  meson setup "$WORK/pixman-build" "$WORK/pixman-$PIXMAN_VER" --cross-file "$WORK/android-arm64.cross" \
    --prefix "$PREFIX" --default-library static -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled
  ninja -C "$WORK/pixman-build" install
}

build_glib() {
  [ -f "$PREFIX/lib/libglib-2.0.a" ] && return
  fetch "https://download.gnome.org/sources/glib/${GLIB_VER%.*}/glib-$GLIB_VER.tar.xz" glib.txz
  tar -C "$WORK" -xf "$WORK/glib.txz"
  # pcre2/libffi come from meson wraps (needs network the first time)
  meson setup "$WORK/glib-build" "$WORK/glib-$GLIB_VER" --cross-file "$WORK/android-arm64.cross" \
    --prefix "$PREFIX" --default-library static --wrap-mode=default \
    -Dtests=false -Dintrospection=disabled -Dnls=disabled -Dlibmount=disabled \
    -Dselinux=disabled -Dxattr=false -Dglib_debug=disabled -Dman-pages=disabled -Dsysprof=disabled
  ninja -C "$WORK/glib-build" install
}

build_shm_shim() {
  # bionic has no shm_open/shm_unlink; QEMU's meson wants them (and a "librt"). Fake both.
  [ -f "$PREFIX/lib/librt.a" ] && return
  mkdir -p "$PREFIX/include" "$PREFIX/lib"
  cat > "$PREFIX/include/shm_shim.h" <<'H'
#pragma once
#include <sys/types.h>
int shm_open(const char *name, int oflag, mode_t mode);
int shm_unlink(const char *name);
H
  cat > "$WORK/shm_shim.c" <<'C'
#define _GNU_SOURCE
#include <sys/syscall.h>
#include <unistd.h>
#include "shm_shim.h"
/* Name is ignored: each call returns a fresh anonymous memfd. */
int shm_open(const char *name, int oflag, mode_t mode) {
    (void)oflag; (void)mode;
    return (int)syscall(__NR_memfd_create, name, 0);
}
int shm_unlink(const char *name) { (void)name; return 0; }
C
  "$CC" -c -fPIC -O2 -I"$PREFIX/include" "$WORK/shm_shim.c" -o "$WORK/shm_shim.o"
  "$TB/llvm-ar" rcs "$PREFIX/lib/librt.a" "$WORK/shm_shim.o"
}

build_qemu() {
  export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
  export PKG_CONFIG="$(command -v pkg-config)"
  export AR=$TB/llvm-ar NM=$TB/llvm-nm RANLIB=$TB/llvm-ranlib STRIP=$TB/llvm-strip \
         OBJCOPY=$TB/llvm-objcopy LD=$TB/ld.lld
  mkdir -p "$WORK/qemu-build" && cd "$WORK/qemu-build"
  # libslirp is pulled in via QEMU's own subproject wrap (static) -- needs network on first run.
  "$QEMU_SRC/configure" \
    --prefix=/opt/qemu --cross-prefix=aarch64-linux-android- --cpu=aarch64 \
    --cc="$CC" --cxx="$CXX" --host-cc=cc \
    --target-list=x86_64-softmmu,i386-softmmu,aarch64-softmmu \
    --without-default-features \
    --enable-system --enable-tools --enable-tcg --enable-kvm --enable-slirp --enable-vnc --enable-pixman \
    --disable-docs --disable-werror --disable-gio \
    --extra-cflags="-I$PREFIX/include -include $PREFIX/include/shm_shim.h" --extra-ldflags="-L$PREFIX/lib"
  make -j"$JOBS"
  rm -rf "$STAGE" && make install DESTDIR="$STAGE"
}

install_into_project() {
  local bin=$STAGE/opt/qemu/bin
  local dst=$PROJECT/app/src/main/jniLibs/arm64-v8a
  mkdir -p "$dst"
  for a in x86_64 i386 aarch64; do
    cp "$bin/qemu-system-$a" "$dst/libqemu-$a.so"
  done
  cp "$bin/qemu-img" "$dst/libqemu-img.so"
  "$TB/llvm-strip" "$dst"/libqemu-*.so
  # Firmware/keymaps (-L dir). The app extracts this to its files dir on first run.
  rm -rf "$PROJECT/app/src/main/assets/qemu-share"
  mkdir -p "$PROJECT/app/src/main/assets"
  cp -r "$STAGE/opt/qemu/share/qemu" "$PROJECT/app/src/main/assets/qemu-share"
  ls -lh "$dst"
}

build_pixman
build_glib
build_shm_shim
build_qemu
install_into_project
echo "Done. Sync Gradle and rebuild the app."
