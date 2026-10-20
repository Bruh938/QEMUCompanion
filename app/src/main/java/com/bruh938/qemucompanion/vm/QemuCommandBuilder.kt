package com.bruh938.qemucompanion.vm

data class LaunchContext(
    val nativeLibDir: String,
    val dataDir: String,        // QEMU's -L dir
    val runtimeDir: String,     // short, app-private dir for sockets
    val hostAbi: String,
    val kvmUsable: Boolean,
)

object QemuCommandBuilder {

    /** QEMU treats ',' as an option separator; a literal comma is written ",,". */
    private fun esc(s: String) = s.replace(",", ",,")

    fun qmpSocketPath(cfg: VmConfig, ctx: LaunchContext) = "${ctx.runtimeDir}/${cfg.id}.qmp"

    fun build(cfg: VmConfig, ctx: LaunchContext): List<String> {
        val a = cfg.arch
        val kvm = cfg.accel == Accel.KVM
        if (kvm) {
            require(ctx.kvmUsable) { "KVM is not available on this device" }
            require(ctx.hostAbi in a.kvmHostAbis) { "KVM can't run ${a.id} guests on ${ctx.hostAbi} hosts" }
        }
        require(!(a.isArm && cfg.disks.any { it.bus == DiskBus.IDE })) { "IDE isn't available on the ARM virt machine" }
        require(cfg.cores >= 1 && cfg.ramMb >= 16) { "Invalid cores/RAM" }

        val v = mutableListOf<String>()
        v += "${ctx.nativeLibDir}/${a.soName}"
        v += listOf("-L", ctx.dataDir)
        v += listOf("-name", esc(cfg.name))
        v += listOf("-machine", cfg.machine)

        // x86 guests on ARM hosts: MTTCG is unsafe by default (memory ordering), so it's opt-in.
        val mttcg = cfg.mttcg ?: a.isArm
        v += listOf("-accel", when {
            kvm -> "kvm"
            mttcg -> "tcg,thread=multi"
            else -> "tcg"
        })
        v += listOf("-cpu", if (kvm) "host" else (cfg.cpu ?: a.defaultCpu))
        v += listOf("-smp", cfg.cores.toString())
        v += listOf("-m", cfg.ramMb.toString())
        cfg.firmwarePath?.let { v += listOf("-bios", it) }

        cfg.disks.forEachIndexed { i, d ->
            val ro = if (d.readOnly) ",readonly=on" else ""
            v += listOf("-drive", "file=${esc(d.path)},format=${d.format},if=none,id=disk$i$ro")
            v += listOf("-device", when (d.bus) {
                DiskBus.VIRTIO -> "virtio-blk-pci,drive=disk$i"
                DiskBus.IDE -> "ide-hd,drive=disk$i"
            })
        }
        if (cfg.snapshot) v += "-snapshot"

        cfg.cdromIso?.let {
            v += listOf("-drive", "file=${esc(it)},media=cdrom,if=none,id=cd0,readonly=on")
            if (a.isArm) v += listOf("-device", "virtio-scsi-pci,id=scsi0", "-device", "scsi-cd,drive=cd0")
            else v += listOf("-device", "ide-cd,drive=cd0")
            if (!a.isArm) v += listOf("-boot", if (cfg.disks.isEmpty()) "order=d" else "order=dc")
        }

        cfg.network?.let { n ->
            val fwd = n.forwards.joinToString("") { ",hostfwd=${it.proto}::${it.hostPort}-:${it.guestPort}" }
            v += listOf("-netdev", "user,id=net0$fwd")
            v += listOf("-device", "${n.model.qemu},netdev=net0")
        }

        v += listOf("-display", "none")
        v += listOf("-vnc", "127.0.0.1:${cfg.vnc.display}" + if (cfg.vnc.password) ",password=on" else "")
        v += listOf("-monitor", "none")
        if (a.isArm) v += listOf("-device", "virtio-gpu-pci") else v += listOf("-vga", "std")
        if (cfg.usbTablet) {
            if (cfg.machine.startsWith("pc")) v += listOf("-usb", "-device", "usb-tablet")
            else v += listOf("-device", "qemu-xhci", "-device", "usb-kbd", "-device", "usb-tablet")
        }

        if (cfg.qmp) {
            val sock = qmpSocketPath(cfg, ctx)
            require(sock.length < 104) { "QMP socket path too long ($sock)" }
            v += listOf("-qmp", "unix:${esc(sock)},server=on,wait=off")
        }

        v += cfg.extraArgs
        return v
    }
}
