package com.bruh938.qemucompanion.vm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import java.io.File

/**
 * Runs in the ":vm" process. Temporary design: the UI talks to it via Intents and reads
 * vm.state / vm.log from filesDir (same UID, shared across processes). A bound interface comes later.
 */
class VmService : Service() {
    @Volatile private var proc: Process? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Virtual machines", NotificationManager.IMPORTANCE_LOW)
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = Notification.Builder(this, CHANNEL)
            .setContentTitle("QEMU Companion")
            .setContentText("A virtual machine is running")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .build()
        ServiceCompat.startForeground(this, 1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)

        when (intent?.action) {
            ACTION_START -> {
                val id = intent.getStringExtra(EXTRA_PRESET)
                if (proc == null) Thread { runVm(id) }.start()
            }
            ACTION_STOP -> if (proc != null) proc?.destroy() else stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun runVm(presetId: String?) {
        val logFile = File(filesDir, "vm.log").apply { writeText("") }
        val stateFile = File(filesDir, "vm.state")
        fun log(s: String) = logFile.appendText(s + "\n")
        try {
            val cfg = Presets.byId(presetId) ?: error("Unknown preset: $presetId")
            stateFile.writeText(cfg.id)

            val share = File(filesDir, "qemu-share")
            if (!File(share, ".extracted").exists()) {
                log("First run: extracting firmware files...")
                copyAssetDir("qemu-share", share)
                File(share, ".extracted").writeText("1")
            }

            val run = File(filesDir, "run").apply { mkdirs() }
            val ctx = LaunchContext(
                nativeLibDir = applicationInfo.nativeLibraryDir,
                dataDir = share.path,
                runtimeDir = run.path,
                hostAbi = Build.SUPPORTED_ABIS[0],
                kvmUsable = false, // root probe comes later
            )
            File(QemuCommandBuilder.qmpSocketPath(cfg, ctx)).delete() // stale socket from a previous run

            val args = QemuCommandBuilder.build(cfg, ctx)
            log("$ " + args.joinToString(" "))
            val pb = ProcessBuilder(args)
                .redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.appendTo(logFile))
            pb.environment()["TMPDIR"] = cacheDir.path // -snapshot temp files; Android has no /tmp
            proc = pb.start()
            log("started; VNC on 127.0.0.1:${5900 + cfg.vnc.display}")
            log("exited with code ${proc!!.waitFor()}")
        } catch (e: Exception) {
            log("Error: $e")
        } finally {
            proc = null
            stateFile.delete()
            stopSelf()
        }
    }

    private fun copyAssetDir(assetPath: String, dst: File) {
        val children = assets.list(assetPath).orEmpty()
        if (children.isEmpty()) { // a file
            dst.parentFile?.mkdirs()
            assets.open(assetPath).use { i -> dst.outputStream().use { o -> i.copyTo(o) } }
        } else {
            dst.mkdirs()
            children.forEach { copyAssetDir("$assetPath/$it", File(dst, it)) }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.bruh938.qemucompanion.START"
        const val ACTION_STOP = "com.bruh938.qemucompanion.STOP"
        const val EXTRA_PRESET = "preset"
        private const val CHANNEL = "vm"

        fun statePreset(ctx: Context): String? =
            File(ctx.filesDir, "vm.state").takeIf { it.exists() }?.readText()?.trim()

        fun logTail(ctx: Context, lines: Int = 40): String =
            File(ctx.filesDir, "vm.log").takeIf { it.exists() }?.readLines()?.takeLast(lines)?.joinToString("\n").orEmpty()
    }
}
