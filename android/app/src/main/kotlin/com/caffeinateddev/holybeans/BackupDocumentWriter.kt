package com.caffeinateddev.holybeans

/** Publishes a verified new document before retiring any previous copy. */
internal class BackupDocumentWriter(private val documents: Documents) {
    interface Documents {
        fun create(name: String): String
        fun copy(id: String)
        fun verify(id: String)
        fun rename(id: String, name: String): String?
        fun delete(id: String)
        fun cleanupFailed(error: Exception)
    }

    fun write(name: String, token: String, previous: List<String>) {
        var pending: String? = null
        var published: String? = null
        try {
            pending = documents.create(".holybeans-partial-$token")
            documents.copy(pending)
            documents.verify(pending)
            val finalName = name.removeSuffix(".zip") + "-$token.zip"
            published = documents.rename(pending, finalName)
            if (published == null) {
                // Providers without rename still keep the old copy until both
                // writing and reading back the uniquely named new one succeed.
                published = documents.create(finalName)
                documents.copy(published)
            } else {
                pending = null
            }
            documents.verify(published)
        } catch (error: Exception) {
            published?.let(::cleanup)
            pending?.let(::cleanup)
            throw error
        }
        // From here cleanup failure must not turn a committed copy into failure.
        pending?.let(::cleanup)
        previous.filter { it != published }.forEach(::cleanup)
    }

    private fun cleanup(id: String) {
        try {
            documents.delete(id)
        } catch (error: Exception) {
            documents.cleanupFailed(error)
        }
    }
}
