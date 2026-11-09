package com.example.visor_markdown

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Receives the actual document, including content:// URIs with temporary grants. */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var dartReady = false
    private val pending = mutableListOf<Map<String, Any>>()
    private val reader = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "io.github.julio_viera.VisorMarkdown/file_open")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialDocuments" -> {
                    val documents = pending.toList()
                    pending.clear()
                    dartReady = true
                    result.success(documents)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        receiveDocument(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveDocument(intent)
    }

    private fun receiveDocument(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        if (uri.scheme != "content" && uri.scheme != "file") return
        reader.execute {
            val document: Map<String, Any> = try {
                val name = displayName(uri)
                val bytes = contentResolver.openInputStream(uri)?.use { stream ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > 2 * 1024 * 1024) {
                            throw IllegalArgumentException("Document limit: 2 MiB")
                        }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray() }
                    ?: throw IllegalArgumentException("Cannot read $name")
                mapOf("name" to name, "bytes" to bytes, "sourceId" to uri.toString())
            } catch (error: Exception) {
                mapOf("error" to (error.message ?: "Cannot open document"))
            }
            main.post {
                if (!isDestroyed) {
                    if (dartReady) channel?.invokeMethod("openDocument", document)
                    else pending.add(document)
                }
            }
        }
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) {
                            val name = cursor.getString(index)
                            if (!name.isNullOrBlank()) return name.substringAfterLast('/')
                        }
                    }
                }
            } catch (_: Exception) {
                // Some providers can read content but do not expose metadata.
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "document.md"
    }

    override fun onDestroy() {
        reader.shutdown()
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }
}
