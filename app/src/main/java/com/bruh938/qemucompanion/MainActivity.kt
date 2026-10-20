package com.bruh938.qemucompanion

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.bruh938.qemucompanion.vm.VmService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { Surface(Modifier.fillMaxSize()) { Screen() } } }
    }

    private fun hasAllFiles() =
        Build.VERSION.SDK_INT < 30 || Environment.isExternalStorageManager()

    private fun send(action: String, preset: String? = null) {
        val i = Intent(this, VmService::class.java).setAction(action)
        preset?.let { i.putExtra(VmService.EXTRA_PRESET, it) }
        ContextCompat.startForegroundService(this, i)
    }

    @androidx.compose.runtime.Composable
    private fun Screen() {
        var allFiles by remember { mutableStateOf(hasAllFiles()) }
        var running by remember { mutableStateOf<String?>(null) }
        var log by remember { mutableStateOf("") }

        // Poll the :vm process's state files once a second.
        LaunchedEffect(Unit) {
            while (true) {
                allFiles = hasAllFiles()
                withContext(Dispatchers.IO) {
                    running = VmService.statePreset(this@MainActivity)
                    log = VmService.logTail(this@MainActivity)
                }
                delay(1000)
            }
        }

        Column(
            Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("QEMU Companion", style = MaterialTheme.typography.headlineSmall)

            if (!allFiles) {
                Text("Needs \"All files access\" to read /sdcard/vms.")
                Button(onClick = {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName"))
                    )
                }, modifier = Modifier.fillMaxWidth()) { Text("Grant file access") }
            }

            val canLaunch = allFiles && running == null
            listOf("x86_64", "i386", "aarch64").forEach { id ->
                Button(
                    onClick = { send(VmService.ACTION_START, id) },
                    enabled = canLaunch,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("LAUNCH $id") }
            }
            OutlinedButton(
                onClick = { send(VmService.ACTION_STOP) },
                enabled = running != null,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("STOP") }

            Text(if (running != null) "Running: $running  (VNC 127.0.0.1:5901)" else "No VM running")
            Text(
                log,
                fontFamily = FontFamily.Monospace, fontSize = 11.sp,
                modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()),
            )
        }
    }
}
