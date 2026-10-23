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
# TARGETS: comma-separated softmmu targets, or "all" (~30 emulators, ~800 MB of binaries).
TARGETS=${TARGETS:-x86_64-softmmu,i386-softmmu,aarch64-softmmu}
if [ "$TARGETS" = all ]; then TL_ARG=(); else TL_ARG=(--target-list="$TARGETS"); fi
# Extra disk image formats (users will bring VirtualBox/VMware/Hyper-V images). No extra deps needed.
FORMAT_FLAGS=(--enable-vmdk --enable-vdi --enable-vhdx --enable-vpc --enable-qed
              --enable-parallels --enable-qcow1 --enable-bochs --enable-cloop --enable-dmg --enable-vvfat)
# FEATURE_MODE=auto: enable everything the available deps allow, minus DENY (known-dead on Android).
# FEATURE_MODE=minimal: --without-default-features (only what we explicitly --enable below).
FEATURE_MODE=${FEATURE_MODE:-auto}
DENY=(vhost-net vhost-kernel vhost-user vhost-vdpa vhost-crypto vhost-user-blk-server vfio-user-server
      vduse-blk-export fuse linux-aio linux-io-uring seccomp cap-ng guest-agent modules plugins docs rust
      gtk sdl sdl-image opengl curses cocoa pa alsa jack pipewire oss sndio spice spice-protocol smartcard
      u2f canokey nitro libusb usb-redir xen xen-pci-passthrough selinux numa rdma qom-cast-debug)
BASE_FLAGS=()
if [ "$FEATURE_MODE" = minimal ]; then
  BASE_FLAGS=(--without-default-features)
else
  BASE_FLAGS=(--disable-user)
  for n in "${DENY[@]}"; do
    if grep -q "option('${n//-/_}'" "$QEMU_SRC/meson_options.txt"; then BASE_FLAGS+=("--disable-$n")
    else echo "note: '$n' is not a meson option in this QEMU; skipping"; fi
  done
fi
# Extra static libs (zstd, bzip2, libjpeg-turbo, libpng) and the QEMU features they enable. EXTRA_LIBS=0 to skip.
EXTRA_LIBS=${EXTRA_LIBS:-1}
EXTRA_FLAGS=()
if [ "$EXTRA_LIBS" = 1 ]; then EXTRA_FLAGS=(--enable-zstd --enable-bzip2 --enable-vnc-jpeg --enable-png); fi
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

build_slirp() {
  # QEMU 11.x needs libslirp >= 4.9 (slirp_pollfds_fill_socket). Build upstream's tag statically into $PREFIX.
  [ -f "$PREFIX/lib/libslirp.a" ] && return
  local src="$WORK/libslirp"
  [ -d "$src" ] || git clone --depth 1 --branch v4.9.1 https://gitlab.freedesktop.org/slirp/libslirp.git "$src"
  export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
  meson setup "$WORK/slirp-build" "$src" --cross-file "$WORK/android-arm64.cross" \
    --prefix "$PREFIX" --default-library static
  ninja -C "$WORK/slirp-build" install
  nm "$PREFIX/lib/libslirp.a" | grep -q slirp_pollfds_fill_socket || { echo "libslirp too old"; exit 1; }
}

# Generic CMake static-lib builder using the NDK's own toolchain file.
cmake_dep() { # name url archive srcdir [extra cmake args...]
  local name=$1 url=$2 ar=$3 srcdir=$4; shift 4
  [ -f "$WORK/.done-$name" ] && return
  fetch "$url" "$ar"
  tar -C "$WORK" -xf "$WORK/$ar"
  cmake -S "$WORK/$srcdir" -B "$WORK/$name-build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON "$@"
  cmake --build "$WORK/$name-build" --target install
  touch "$WORK/.done-$name"
}

build_bzip2() { # no build system worth using; compile the 7 files directly
  [ -f "$PREFIX/lib/libbz2.a" ] && return
  fetch https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz bzip2.tgz
  tar -C "$WORK" -xf "$WORK/bzip2.tgz"
  local d=$WORK/bzip2-1.0.8 objs=()
  for f in blocksort huffman crctable randtable compress decompress bzlib; do
    "$CC" -O2 -fPIC -D_FILE_OFFSET_BITS=64 -c "$d/$f.c" -o "$d/$f.o"; objs+=("$d/$f.o")
  done
  mkdir -p "$PREFIX/include" "$PREFIX/lib"
  "$TB/llvm-ar" rcs "$PREFIX/lib/libbz2.a" "${objs[@]}"
  cp "$d/bzlib.h" "$PREFIX/include/"
}

build_extra_libs() {
  # The NDK ships zlib in its sysroot but no zlib.pc, and libpng.pc "Requires: zlib".
  mkdir -p "$PREFIX/lib/pkgconfig"
  if [ ! -f "$PREFIX/lib/pkgconfig/zlib.pc" ]; then
    cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<'PC'
Name: zlib
Description: zlib from the Android NDK sysroot (system libz.so)
Version: 1.3.2.1
Libs: -lz
Cflags:
PC
  fi
  cmake_dep zstd https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-1.5.6.tar.gz zstd.tgz zstd-1.5.6/build/cmake \
    -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON
  build_bzip2
  cmake_dep libjpeg https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.0.4/libjpeg-turbo-3.0.4.tar.gz libjpeg.tgz libjpeg-turbo-3.0.4 \
    -DENABLE_SHARED=OFF -DWITH_TURBOJPEG=OFF
  cmake_dep libpng https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.44.tar.gz libpng.tgz libpng-1.6.44 \
    -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF
}

build_shm_shim() {
  # bionic has no shm_open/shm_unlink; QEMU's meson wants them (and a "librt"). Fake both.
  mkdir -p "$PREFIX/include" "$PREFIX/lib"
  cat > "$PREFIX/include/shm_shim.h" <<'H'
#pragma once
#include <sys/types.h>
int shm_open(const char *name, int oflag, mode_t mode);
int shm_unlink(const char *name);
/* bionic defines st_atime_nsec etc. as macros, clashing with QEMU's 9p struct fields */
#include <sys/stat.h>
#undef st_atime_nsec
#undef st_mtime_nsec
#undef st_ctime_nsec
H
  [ -f "$PREFIX/lib/librt.a" ] && return
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
  QBUILD=${QBUILD:-$WORK/qemu-build}   # use a different dir to compare configurations side by side
  mkdir -p "$QBUILD" && cd "$QBUILD"
  # libslirp is pulled in via QEMU's own subproject wrap (static) -- needs network on first run.
  if [ ! -f build.ninja ] || [ "${FORCE_CONFIGURE:-0}" = 1 ]; then
  "$QEMU_SRC/configure" \
    --prefix=/opt/qemu --cross-prefix=aarch64-linux-android- --cpu=aarch64 \
    --cc="$CC" --cxx="$CXX" --host-cc=cc \
    "${TL_ARG[@]}" "${FORMAT_FLAGS[@]}" "${EXTRA_FLAGS[@]}" \
    "${BASE_FLAGS[@]}" \
    --enable-system --enable-tools --enable-tcg --enable-kvm --enable-slirp --enable-vnc --enable-pixman \
    --disable-docs --disable-werror --disable-gio \
    --extra-cflags="-I$PREFIX/include -include $PREFIX/include/shm_shim.h" --extra-ldflags="-L$PREFIX/lib"
  fi
  if [ "${CONFIGURE_ONLY:-0}" = 1 ]; then
    echo "CONFIGURE_ONLY: summary above. Build dir: $QBUILD"; exit 0
  fi
  make -j"$JOBS"
  rm -rf "$STAGE" && make install DESTDIR="$STAGE"
}

install_into_project() {
  local bin=$STAGE/opt/qemu/bin
  local dst=$PROJECT/app/src/main/jniLibs/arm64-v8a
  mkdir -p "$dst"
  for f in "$bin"/qemu-system-*; do
    n=$(basename "$f"); cp "$f" "$dst/libqemu-${n#qemu-system-}.so"
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
build_slirp
if [ "$EXTRA_LIBS" = 1 ]; then build_extra_libs; fi
build_shm_shim
build_qemu
install_into_project
echo "Done. Sync Gradle and rebuild the app."
