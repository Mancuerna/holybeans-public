package com.caffeinateddev.holybeans

import java.io.ByteArrayInputStream
import java.io.IOException
import java.util.concurrent.Executor
import org.junit.Assert.*
import org.junit.Test

class IncomingCardsTest {
    private val cards = IncomingCards(setOf("app.clipboard", "app.files"))
    @Test fun linksHaveAnEightKiBUtf8Limit() {
        val boundary = "holybeans://bean?d=".padEnd(8192, 'A')
        assertEquals(boundary, cards.text(boundary))
        assertNull(cards.text(boundary + "A"))
        assertNull(cards.text("  HOLYBEANS://bean?d=" + "é".repeat(4096)))
        assertEquals("holybeans://shortcut/beans", cards.text("holybeans://shortcut/beans"))
        assertNull(cards.text("x".repeat(1024 * 1024 + 1)))
    }
    @Test fun privateUrisNeverOpenAStream() {
        for ((scheme, authority) in listOf("file" to null, "content" to "app.clipboard",
            "content" to "0@app.clipboard", "content" to "APP.FILES", "https" to "example.org")) {
            assertNull(cards.read(scheme, authority, "ignored") { fail("Private URI opened"); null })
        }
    }
    @Test fun externalStreamsAreBoundedAndAlwaysClosed() {
        for (size in listOf(1024 * 1024, 1024 * 1024 + 1)) {
            var closed = false
            val stream = object : ByteArrayInputStream(ByteArray(size) { 65 }) {
                override fun close() { closed = true; super.close() }
            }
            val result = cards.read("content", "app.test.external", "ignored") { stream }
            if (size == 1024 * 1024) assertEquals(size, result!!.length) else assertNull(result)
            assertTrue(closed)
        }
        assertNull(cards.read("content", "external", "ignored") { throw IOException() })
        assertNull(cards.read("content", "external", "ignored") {
            ByteArrayInputStream(("holybeans://bean?d=" + "A".repeat(8192)).toByteArray())
        })
    }
    private class Queue : Executor {
        private val tasks = ArrayDeque<Runnable>()
        override fun execute(task: Runnable) { tasks.add(task) }
        fun drain() { while (tasks.isNotEmpty()) tasks.removeFirst().run() }
    }
    @Test fun launchIsDeliveredOnceWhetherTakePrecedesOrFollowsRead() {
        for (takeEarly in listOf(false, true)) {
            val worker = Queue(); val ui = Queue(); val arrivals = mutableListOf<String>()
            val delivery = IncomingDelivery(worker, ui, arrivals::add)
            var read = false
            delivery.receive { read = true; "card" }
            assertFalse(read)
            if (takeEarly) assertNull(delivery.take())
            worker.drain()
            assertTrue(arrivals.isEmpty())
            ui.drain()
            if (takeEarly) assertEquals(listOf("card"), arrivals)
            else assertEquals("card", delivery.take())
            assertNull(delivery.take())
        }
    }
    @Test fun failuresAndDisposalDoNotDeliverStaleCards() {
        val worker = Queue(); val ui = Queue()
        val delivery = IncomingDelivery(worker, ui) { fail("Disposed delivery") }
        delivery.take()
        delivery.receive { throw IOException() }
        delivery.receive { "late" }
        worker.drain()
        delivery.close()
        ui.drain()
        assertNull(delivery.take())
    }
}
