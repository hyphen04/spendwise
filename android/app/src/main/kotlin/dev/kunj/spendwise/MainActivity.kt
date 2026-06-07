package dev.kunj.spendwise

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val channel = "dev.kunj.spendwise/install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        try {
                            val filePath = call.argument<String>("filePath")
                                ?: throw IllegalArgumentException("filePath is required")
                            val file = File(filePath)
                            val uri = FileProvider.getUriForFile(
                                this@MainActivity,
                                "dev.kunj.spendwise.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                                data = uri
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success("launched")
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
