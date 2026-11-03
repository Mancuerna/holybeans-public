package com.caffeinateddev.holybeans

import org.junit.Assert.*
import org.junit.Test

class BackupDocumentWriterTest {
    private class Store : BackupDocumentWriter.Documents {
        val files = mutableMapOf("old" to "valid old copy")
        val events = mutableListOf<String>()
        var failAt: String? = null
        var renameSupported = true
        var created = 0
        var copied = 0
        var verified = 0
        var cleanupErrors = 0
        private fun step(name: String) {
            events += name
            if (failAt == name) error(name)
        }
        override fun create(name: String): String {
            step("create${++created}")
            files[name] = ""
            return name
        }
        override fun copy(id: String) {
            files[id] = "partial"
            step("copy${++copied}")
            files[id] = "valid new copy"
        }
        override fun verify(id: String) {
            step("verify${++verified}")
            check(files[id] == "valid new copy")
        }
        override fun rename(id: String, name: String): String? {
            step("rename")
            if (!renameSupported) return null
            files[name] = files.remove(id)!!
            return name
        }
        override fun delete(id: String) {
            step(if (id == "old") "deleteOld" else "cleanup")
            if (id == "old") assertTrue(events.count { it.startsWith("verify") } >= 2)
            files.remove(id)
        }
        override fun cleanupFailed(error: Exception) { cleanupErrors++ }
        fun write() = BackupDocumentWriter(this).write("holybeans-backup-2026-10-18.zip", "abc", listOf("old"))
    }

    @Test fun failuresBeforePublicationKeepThePreviousBytes() {
        for (phase in listOf("create1", "copy1", "verify1", "rename", "verify2")) {
            val store = Store().apply { failAt = phase }
            try { store.write(); fail("Expected $phase") } catch (_: IllegalStateException) {}
            assertEquals(phase, "valid old copy", store.files["old"])
            assertEquals(phase, 1, store.files.size)
        }
    }

    @Test fun unsupportedRenameFailuresKeepThePreviousBytes() {
        for (phase in listOf("create2", "copy2", "verify2")) {
            val store = Store().apply { renameSupported = false; failAt = phase }
            try { store.write(); fail("Expected $phase") } catch (_: IllegalStateException) {}
            assertEquals(phase, mapOf("old" to "valid old copy"), store.files)
        }
    }

    @Test fun bothProvidersRetireOldOnlyAfterReadback() {
        for (rename in listOf(true, false)) {
            val store = Store().apply { renameSupported = rename }
            store.write()
            assertEquals(listOf("valid new copy"), store.files.values.toList())
            assertTrue(store.files.keys.single().endsWith("-abc.zip"))
        }
    }

    @Test fun cleanupFailureDoesNotLoseOrRejectCommittedCopy() {
        val store = Store().apply { failAt = "deleteOld" }
        store.write()
        assertEquals(setOf("valid old copy", "valid new copy"), store.files.values.toSet())
        assertEquals(1, store.cleanupErrors)
    }
}
