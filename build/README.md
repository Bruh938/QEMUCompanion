# Building QEMU for Android

Runs in WSL2 (Ubuntu), not Windows. See the header of `build-qemu.sh` for prereqs.

1. Copy the QEMU 11.1.2 tarball into WSL's home (`cp /mnt/c/Users/<you>/Desktop/qemu-11.1.2.tar.xz ~/ && tar xf ...`).
2. Download a **Linux** NDK (r27c or newer) inside WSL.
3. `NDK=~/android-ndk-r27c QEMU_SRC=~/qemu-11.1.2 ./build/build-qemu.sh`
4. The script writes `libqemu-{x86_64,i386,aarch64,img}.so` into `app/src/main/jniLibs/arm64-v8a/`
   and the firmware dir into `app/src/main/assets/qemu-share/`.

Binaries target API 28. Set `minSdk = 28` in `app/build.gradle.kts` (or build libiconv and drop to 26).
