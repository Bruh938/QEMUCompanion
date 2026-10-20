package com.bruh938.qemucompanion.vm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QemuCommandBuilderTest {
    private val ctx = LaunchContext("/lib", "/data/share", "/run", "arm64-v8a", kvmUsable = false)
    private val x86 = VmConfig(id = "a1", name = "Win XP", arch = Arch.X86_64)

    private fun List<String>.after(flag: String) = this[indexOf(flag) + 1]

    @Test fun x86_usesTcgWithoutMttcg() {
        val v = QemuCommandBuilder.build(x86, ctx)
        assertEquals("/lib/libqemu-x86_64.so", v.first())
        assertEquals("tcg", v.after("-accel"))
    }

    @Test fun mttcgCanBeForcedOnX86() {
        val v = QemuCommandBuilder.build(x86.copy(mttcg = true), ctx)
        assertEquals("tcg,thread=multi", v.after("-accel"))
    }

    @Test fun commasInPathsAreDoubled() {
        val cfg = x86.copy(disks = listOf(Disk("/sd/a,b.qcow2")))
        assertTrue(QemuCommandBuilder.build(cfg, ctx).any { it.contains("file=/sd/a,,b.qcow2") })
    }

    @Test fun aarch64_withoutFirmwareIsAllowed_andGetsMttcg() {
        val cfg = VmConfig(id = "b2", name = "arm", arch = Arch.AARCH64)
        val v = QemuCommandBuilder.build(cfg, ctx)
        assertEquals("tcg,thread=multi", v.after("-accel"))
        assertFalse(v.contains("-bios"))
    }

    @Test fun kvmRejectedWhenUnavailableOrWrongArch() {
        val cfg = x86.copy(accel = Accel.KVM)
        assertFalse(runCatching { QemuCommandBuilder.build(cfg, ctx) }.isSuccess)
        assertFalse(runCatching { QemuCommandBuilder.build(cfg, ctx.copy(kvmUsable = true)) }.isSuccess)
    }

    @Test fun qmpCanBeDisabled() {
        assertTrue(QemuCommandBuilder.build(x86, ctx).contains("-qmp"))
        assertFalse(QemuCommandBuilder.build(x86.copy(qmp = false), ctx).contains("-qmp"))
    }

    @Test fun snapshotAndUsbTabletFlags() {
        val v = QemuCommandBuilder.build(x86.copy(snapshot = true, usbTablet = false), ctx)
        assertTrue(v.contains("-snapshot"))
        assertFalse(v.contains("usb-tablet"))
        assertTrue(QemuCommandBuilder.build(x86, ctx).contains("usb-tablet"))
    }

    @Test fun presetsBuildWithoutErrors() {
        listOf(Presets.x86_64, Presets.i386, Presets.aarch64).forEach { QemuCommandBuilder.build(it, ctx) }
    }
}
