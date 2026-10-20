package com.bruh938.qemucompanion.vm

/** Hardcoded test VMs for now; later these come from saved JSON configs. */
object Presets {
    // "none" audio backend: the guest sees a sound card but nothing is played or written to disk.
    private val audio = listOf("-audiodev", "none,id=aud0", "-device", "ac97,audiodev=aud0")
    private val localtime = listOf("-rtc", "base=localtime")
    private val bios = listOf("-bios", "/data/user/0/com.bruh938.qemucompanion/files/qemu-share/edk2-aarch64-code.fd")

    val x86_64 = VmConfig(
        id = "x86_64", name = "ReactOS x86_64", arch = Arch.X86_64,
        machine = "pc", cpu = "qemu64", cores = 2, ramMb = 2048,
        disks = listOf(Disk("/sdcard/vms/reactos.qcow2", bus = DiskBus.IDE)),
        network = Network(NicModel.E1000),
        vnc = Vnc(display = 1), snapshot = true,
        extraArgs = audio + localtime,
    )

    val i386 = VmConfig(
        id = "i386", name = "Win98 i386", arch = Arch.I386,
        machine = "pc", cpu = "qemu32", cores = 1, ramMb = 128,
        disks = listOf(Disk("/sdcard/vms/win98.qcow2", bus = DiskBus.IDE)),
        network = Network(NicModel.PCNET),
        vnc = Vnc(display = 1), snapshot = true, usbTablet = false,
        extraArgs = audio + localtime,
    )

    val aarch64 = VmConfig(
        id = "aarch64", name = "Alpine aarch64", arch = Arch.AARCH64,
        machine = "virt", cpu = "cortex-a72", cores = 4, ramMb = 2048,
        disks = listOf(Disk("/sdcard/vms/honeycomb.qcow2", bus = DiskBus.VIRTIO)),
        network = Network(NicModel.E1000),
        vnc = Vnc(display = 1), snapshot = true,
        extraArgs = audio + localtime + bios,
    )

    fun byId(id: String?): VmConfig? = listOf(x86_64, i386, aarch64).firstOrNull { it.id == id }
}
