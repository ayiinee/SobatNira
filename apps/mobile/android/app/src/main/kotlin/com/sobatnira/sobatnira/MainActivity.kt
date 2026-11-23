package com.sobatnira.sobatnira

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private data class PendingSave(val bytes: ByteArray, val result: MethodChannel.Result)
    private var pendingSave: PendingSave? = null
    private val saveRequestCode = 5103

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sobatnira/report-file")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("filename")
                val mime = call.argument<String>("mime")
                if (bytes == null || name == null || mime == null || pendingSave != null) {
                    result.error("save_unavailable", "File belum dapat disimpan.", null)
                    return@setMethodCallHandler
                }
                pendingSave = PendingSave(bytes, result)
                try {
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mime
                        putExtra(Intent.EXTRA_TITLE, name)
                    }, saveRequestCode)
                } catch (error: Exception) {
                    pendingSave = null
                    result.error("save_unavailable", "Pemilih lokasi tidak tersedia.", null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequestCode) return
        val pending = pendingSave ?: return
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            pendingSave = null
            pending.result.success(false)
            return
        }
        Thread {
            val saved = runCatching {
                checkNotNull(contentResolver.openOutputStream(destination)).use {
                    it.write(pending.bytes)
                }
            }.isSuccess
            runOnUiThread {
                pendingSave = null
                if (saved) pending.result.success(true)
                else pending.result.error("save_failed", "File belum dapat disimpan.", null)
            }
        }.start()
    }
}
