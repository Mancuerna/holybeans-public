package com.caffeinateddev.holybeans

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Answers the "holybeans/import-folder" channel: picking another app's
 * export folder (such as BeanConqueror's "Full export to directory"),
 * listing its files and reading them one at a time. Read only: nothing in
 * the folder is ever written, and access lasts only while the app runs.
 */
class ExportFolderBridge(private val activity: Activity) {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null
    private val resolver get() = activity.contentResolver

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "list" -> background(result) {
                val tree = Uri.parse(call.argument<String>("uri")!!)
                files(tree, DocumentsContract.getTreeDocumentId(tree), "", 0)
            }
            "read" -> background(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                resolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("Could not read $uri")
            }
            else -> result.notImplemented()
        }
    }

    /** True when the result belonged to this folder picker. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_EXPORT) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        result.success(if (resultCode == Activity.RESULT_OK && uri != null) uri.toString() else null)
        return true
    }

    fun dispose() {
        io.shutdown()
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A folder is already being picked", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            pendingPick = result
            activity.startActivityForResult(intent, PICK_EXPORT)
        } catch (error: ActivityNotFoundException) {
            pendingPick = null
            result.error("unavailable", error.message, null)
        }
    }

    /**
     * Every file under the folder [parentId], with its path from the picked
     * folder, its document URI and size. Subfolders are walked a few levels
     * down, enough for an export's "brews" folder.
     */
    private fun files(tree: Uri, parentId: String, prefix: String, depth: Int): List<Map<String, Any>> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        val found = mutableListOf<Map<String, Any>>()
        resolver.query(uri, columns, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0)
                val path = "$prefix${cursor.getString(1) ?: id}"
                if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                    if (depth < MAX_DEPTH) found += files(tree, id, "$path/", depth + 1)
                } else {
                    found += mapOf(
                        "path" to path,
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                        "size" to (if (cursor.isNull(3)) 0L else cursor.getLong(3)),
                    )
                }
            }
        }
        return found
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (error: Exception) {
                main.post { result.error("failed", error.message, null) }
            }
        }
    }

    companion object {
        private const val PICK_EXPORT = 4108
        private const val MAX_DEPTH = 2
    }
}
