Drop PIE ELF builds of QEMU here, per HOST ABI:

  arm64-v8a/libqemu-x86_64.so
  arm64-v8a/libqemu-i386.so
  arm64-v8a/libqemu-aarch64.so
  (same set under x86_64/ if you want emulator support)

Names must start with "lib" and end with ".so" or the packager ignores them.
