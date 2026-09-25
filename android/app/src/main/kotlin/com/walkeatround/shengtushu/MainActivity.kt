package com.walkeatround.shengtushu

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shengtushu/view_intent")
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "takeViewFile") {
                val uri = pendingUri
                pendingUri = null
                if (uri == null) {
                    result.success(null)
                } else {
                    // content:// 的读取必须走平台侧，复制到缓存后交给 Dart 导入
                    Thread {
                        val out = copyToCache(uri)
                        runOnUiThread { result.success(out) }
                    }.start()
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureViewIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureViewIntent(intent)
        // 热启动：活动已在栈顶，主动推给 Dart
        if (pendingUri != null) {
            channel?.invokeMethod("onViewIntent", null)
        }
    }

    private fun captureViewIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        pendingUri = uri
    }

    /** 把 VIEW intent 指向的文件复制到应用缓存，返回 {path, name}；失败返回 null */
    private fun copyToCache(uri: Uri): Map<String, String>? {
        return try {
            val name = queryDisplayName(uri) ?: "book_${System.currentTimeMillis()}"
            val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
            val dir = File(cacheDir, "import")
            dir.mkdirs()
            val f = File(dir, safe)
            contentResolver.openInputStream(uri)?.use { input ->
                f.outputStream().use { input.copyTo(it) }
            } ?: return null
            mapOf("path" to f.absolutePath, "name" to name)
        } catch (e: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) c.getString(idx) else null
            }
        } catch (e: Exception) {
            null
        }
    }
}
