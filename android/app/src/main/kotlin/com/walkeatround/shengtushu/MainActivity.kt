package com.walkeatround.shengtushu

import android.app.Activity
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
    private var saveResult: MethodChannel.Result? = null
    private var saveSource: File? = null
    private val saveRequestCode = 4102

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shengtushu/document_export")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveDocument") {
                    result.notImplemented()
                } else if (saveResult != null) {
                    result.error("busy", "另一个文件仍在另存中", null)
                } else {
                    try {
                        val source = File(call.argument<String>("path") ?: "").canonicalFile
                        val allowed = source.path.startsWith(cacheDir.canonicalPath + File.separator)
                        require(allowed && source.isFile) { "导出文件不存在或不在临时目录" }
                        val name = call.argument<String>("name") ?: source.name
                        saveResult = result
                        saveSource = source
                        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = call.argument<String>("mimeType") ?: "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, name)
                        }, saveRequestCode)
                    } catch (e: Exception) {
                        saveResult = null
                        saveSource = null
                        result.error("save_failed", e.message, null)
                    }
                }
            }
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
        captureViewIntent(intent)
        // 引擎默认把 ACTION_VIEW 的 data 当命名路由 pushRoute，Dart 侧并无该路由会抛异常；
        // 文件交给上面的 MethodChannel 处理，传给引擎的 intent 清掉 action/data
        setIntent(Intent(intent).setData(null).setAction(null))
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        captureViewIntent(intent)
        super.onNewIntent(Intent(intent).setData(null).setAction(null))
        // 热启动：活动已在栈顶，主动推给 Dart
        if (pendingUri != null) {
            channel?.invokeMethod("onViewIntent", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequestCode) return
        val result = saveResult ?: return
        val source = saveSource
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || source == null) {
            saveResult = null
            saveSource = null
            result.success(null)
            return
        }
        Thread {
            try {
                val output = contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("无法写入所选位置")
                output.use { target -> source.inputStream().use { it.copyTo(target) } }
                runOnUiThread {
                    saveResult = null
                    saveSource = null
                    result.success(queryDisplayName(uri) ?: uri.toString())
                }
            } catch (e: Exception) {
                runOnUiThread {
                    saveResult = null
                    saveSource = null
                    result.error("save_failed", "另存失败，所选位置可能留有不完整文件：${e.message}", null)
                }
            }
        }.start()
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
