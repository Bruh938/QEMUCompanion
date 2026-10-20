# QEMU Companion

A modern Android frontend for QEMU, for people who want the power of the command line without memorizing it.

Existing options like Limbo and Vectras are outdated or limited in how much you can customize. QEMU Companion bundles real, up-to-date QEMU binaries and builds the command line from structured VM configs, so every option is reachable and nothing is hidden.

> **Status: early development.** The core pipeline works end to end on a real phone: QEMU cross-compiles for Android, launches from the app, and boots guests over VNC. There is no VM editor yet, and VMs are still hardcoded presets. See the roadmap below.

## What works today

- QEMU **11.1.2**, cross-compiled for Android arm64 and bundled as `libqemu-<arch>.so`
- Guest architectures: **x86_64**, **i386**, **aarch64** (plus `qemu-img`)
- Three launch buttons, one per architecture, driven by presets in `Presets.kt`
- QEMU runs from a foreground service in its own `:vm` process, so it survives the UI being closed
- Display over VNC on loopback (`127.0.0.1:5901`), user-mode networking, TCG emulation
- A `VmConfig` model and `QemuCommandBuilder` that turn structured configs into QEMU arguments (unit tested)

## What doesn't work yet

- No VM editor UI; presets are edited in code
- No KVM. Stock phone kernels rarely ship it, and the planned optional root path is not implemented
- No graceful shutdown, pause or snapshots yet (QMP is enabled but not used by the UI)
- No built-in display viewer; use a VNC app such as bVNC

## Using it

1. Install the app and open it.
2. Tap **Grant file access**. QEMU opens disk images by raw path, which needs "All files access".
3. Put your disk images in `/sdcard/vms/`. The default presets expect names like `win98.qcow2`, `reactos.qcow2` and `honeycomb.qcow2`; edit `Presets.kt` to point at your own images.
4. Tap a **LAUNCH** button. The log pane shows the exact command line the app ran and any QEMU output.
5. Connect a VNC viewer on the phone to `127.0.0.1:5901`.

Presets boot with `-snapshot`, so writes go to a temporary file and your image is left untouched.

On first launch the app extracts QEMU's firmware and BIOS files from `assets/qemu-share` into its private storage. After rebuilding QEMU, clear the app's data (or delete `files/qemu-share`) so it re-extracts.

## Building the app

Requirements: a recent Android Studio, JDK 17 or 21 (the bundled JBR works), Android SDK 35.

Open the project folder in Android Studio and let Gradle sync, then run it on a device. Minimum SDK is **28** (Android 9), because the bundled binaries use bionic functions that older versions lack.

The prebuilt binaries are committed under `app/src/main/jniLibs/arm64-v8a/`, so you do not need to build QEMU to build the app.

## Building the QEMU binaries

`build/build-qemu.sh` cross-compiles QEMU with the Android NDK. It is meant to run on Linux, or under WSL2 on Windows.

| Component | Version |
| --- | --- |
| QEMU | 11.1.2 |
| Android NDK (Linux) | r30 |
| glib | 2.82.5 (static) |
| pixman | 0.43.4 (static) |
| libslirp | v4.9.1 (static) |
| API level | 28 |

Prerequisites on Ubuntu:

```bash
sudo apt install -y build-essential ninja-build python3-pip python3-venv pipx \
    pkg-config unzip wget git flex bison xz-utils
pipx install meson
```

Then download a **Linux** NDK, extract the QEMU 11.1.2 source onto the Linux filesystem (not `/mnt/c`, which is very slow), and run:

```bash
NDK=~/android-ndk-r30 QEMU_SRC=~/qemu-11.1.2 bash build/build-qemu.sh
```

The script builds the static dependencies, configures and builds QEMU for the `x86_64`, `i386` and `aarch64` system emulators, and copies the stripped results into `jniLibs/arm64-v8a/` as `libqemu-<arch>.so`, along with QEMU's firmware directory into `assets/qemu-share/`.

Notes on the Android port:

- Android's libc has no `shm_open`, so the script builds a tiny shim (backed by `memfd_create`) that satisfies QEMU's build. It ignores the shm name, which only matters for features like ivshmem.
- Everything except libc, libm and libz is linked statically, because the APK packager only picks up `lib*.so` files and Android will not find extra `.so.N` libraries.
- To check a rebuilt binary, run `llvm-readelf -d libqemu-x86_64.so | grep NEEDED`. It should list only system libraries.

## Roadmap

1. VM list and editor UI built on `VmConfig`, with simple and advanced modes sharing one model
2. JSON persistence and import/export of VM configs
3. Bound `:vm` service and QMP control: graceful shutdown, pause/resume, snapshots, media swapping
4. x86_64 Android host build (for emulators and x86 devices) and an optional root path with a `/dev/kvm` probe
5. Option registry generated from the bundled QEMU's own `-machine help`, `-cpu help` and `-device help`
6. Remaining guest architectures

## License

QEMU is licensed under the GNU GPL version 2, so this project is GPL-2.0 as well; see `LICENSE`. The binaries in this repository are built from unmodified QEMU 11.1.2 sources using the script in `build/`, together with these statically linked libraries under their own licenses: glib (LGPL-2.1-or-later), pixman (MIT), and libslirp (BSD-3-Clause). The bundled UEFI firmware images are from the EDK II project, and their licenses are listed in `assets/qemu-share/edk2-licenses.txt`.

QEMU is a trademark of Fabrice Bellard. This project is not affiliated with or endorsed by the QEMU project.
