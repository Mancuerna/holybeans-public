package com.caffeinateddev.holybeans

/** UI-thread ownership of results and pending authorization resolutions. */
internal class DriveOperations<T> {
    private var generation = 0L
    private var active: T? = null
    private data class Resolution(val owner: Any, val operation: Long)
    private companion object {
        val resolutions = mutableMapOf<Int, Resolution>()
        var nextCode = 24000
    }
    private val owner = Any()
    val busy get() = active != null

    fun begin(result: T): Long {
        check(!busy)
        active = result
        return ++generation
    }
    fun isCurrent(operation: Long) = active != null && operation == generation
    fun runIfCurrent(operation: Long, action: () -> Unit) {
        if (isCurrent(operation)) action()
    }
    fun take(operation: Long): T? =
        if (isCurrent(operation)) active.also { active = null } else null
    fun cancel(): T? { generation++; return active.also { active = null } }

    fun reserveResolution(operation: Long): Int {
        check(isCurrent(operation))
        // Stay within Android's 16-bit request codes, away from other bridges.
        // Pending cancelled resolutions retain their code until consumed.
        repeat(1000) {
            val code = nextCode
            nextCode = if (code == 24999) 24000 else code + 1
            if (!resolutions.containsKey(code)) {
                resolutions[code] = Resolution(owner, operation)
                return code
            }
        }
        error("Too many pending Drive authorizations")
    }
    fun consumeResolution(code: Int): Long? {
        val resolution = resolutions.remove(code) ?: return null
        // Recognize results belonging to an activity that was destroyed, but
        // never associate them with this bridge's operation counters.
        return if (resolution.owner === owner) resolution.operation else -1L
    }
}
