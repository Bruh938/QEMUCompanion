package com.bruh938.qemucompanion.vm

/** Guest architectures. [kvmHostAbis] = Android ABIs on which KVM can run this guest natively. */
enum class Arch(
    val id: String,
    val soName: String,
    val defaultMachine: String,
    val defaultCpu: String,
    val kvmHostAbis: Set<String>,
) {
    X86_64("x86_64", "libqemu-x86_64.so", "q35", "qemu64", setOf("x86_64")),
    I386("i386", "libqemu-i386.so", "pc", "qemu32", setOf("x86_64", "x86")),
    AARCH64("aarch64", "libqemu-aarch64.so", "virt", "cortex-a72", setOf("arm64-v8a"));

    val isArm: Boolean get() = this == AARCH64
}

enum class Accel { TCG, KVM }
enum class DiskBus { VIRTIO, IDE }
enum class NicModel(val qemu: String) {
    VIRTIO("virtio-net-pci"), E1000("e1000"), RTL8139("rtl8139"), PCNET("pcnet")
}

data class Disk(
    val path: String,
    val format: String = "qcow2",
    val bus: DiskBus = DiskBus.VIRTIO,
    val readOnly: Boolean = false,
)

data class PortForward(val hostPort: Int, val guestPort: Int, val proto: String = "tcp")

data class Network(
    val model: NicModel = NicModel.VIRTIO,
    val forwards: List<PortForward> = emptyList(),
)

/** VNC bound to loopback only. Port = 5900 + [display]. */
data class Vnc(val display: Int = 0, val password: Boolean = false)

data class VmConfig(
    val id: String,                       // keep short: used in the QMP socket path
    val name: String,
    val arch: Arch,
    val machine: String = arch.defaultMachine,
    val cpu: String? = null,              // null -> arch default (or "host" under KVM)
    val cores: Int = 2,
    val ramMb: Int = 1024,
    val accel: Accel = Accel.TCG,
    val disks: List<Disk> = emptyList(),
    val cdromIso: String? = null,
    val firmwarePath: String? = null,     // -bios; required for aarch64 "virt" (UEFI)
    val network: Network? = Network(),
    val vnc: Vnc = Vnc(),
    val qmp: Boolean = true,
    val snapshot: Boolean = false,        // -snapshot: writes go to a temp file, image untouched
    val usbTablet: Boolean = true,        // off for guests without USB HID drivers (Win98)
    val mttcg: Boolean? = null,           // null = auto (multi-threaded TCG for ARM guests only)
    val extraArgs: List<String> = emptyList(), // already tokenized, appended last
)
