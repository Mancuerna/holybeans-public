package com.caffeinateddev.holybeans

import org.junit.Assert.*
import org.junit.Test

class DriveSafetyTest {
    @Test fun cancelledRequestCannotCompleteItsReplacement() {
        val operations = DriveOperations<String>()
        val old = operations.begin("old request")
        assertEquals("old request", operations.cancel())
        val current = operations.begin("new connection")
        assertNull(operations.take(old))
        assertTrue(operations.isCurrent(current))
        assertEquals("new connection", operations.take(current))
        assertNull(operations.take(current))
    }
    @Test fun finishedRequestCannotConsumeTheNextResult() {
        val operations = DriveOperations<String>()
        val old = operations.begin("first")
        assertEquals("first", operations.take(old))
        val current = operations.begin("second")
        assertNull(operations.take(old))
        assertEquals("second", operations.take(current))
    }
    @Test fun pendingAuthorizationsKeepDistinctRequestCodes() {
        val operations = DriveOperations<String>()
        val old = operations.begin("first")
        val firstCode = operations.reserveResolution(old)
        operations.cancel()
        val current = operations.begin("second")
        val secondCode = operations.reserveResolution(current)
        assertNotEquals(firstCode, secondCode)
        assertEquals(old, operations.consumeResolution(firstCode))
        assertFalse(operations.isCurrent(old))
        assertEquals(current, operations.consumeResolution(secondCode))
        assertTrue(operations.isCurrent(current))
        assertNull(operations.consumeResolution(secondCode))
        assertNull(operations.consumeResolution(9142))
    }
    @Test fun oldAuthorizationNeverBecomesTheCurrentOperation() {
        val operations = DriveOperations<String>()
        val old = operations.begin("first")
        val code = operations.reserveResolution(old)
        operations.cancel()
        val current = operations.begin("second")
        assertEquals(old, operations.consumeResolution(code))
        assertFalse(operations.isCurrent(old))
        assertTrue(operations.isCurrent(current))
    }
    @Test fun cancelledOperationsCannotChangeCredentials() {
        val operations = DriveOperations<String>()
        val old = operations.begin("first")
        operations.cancel()
        val current = operations.begin("second")
        var credential = "new account"
        operations.runIfCurrent(old) { credential = "stale account" }
        assertEquals("new account", credential)
        operations.cancel()
        operations.runIfCurrent(current) { credential = "cancelled account" }
        assertEquals("new account", credential)
        assertFalse(operations.isCurrent(current))
        assertFalse(operations.busy)
        assertNull(operations.take(current))
    }
    @Test fun recreatedBridgeCannotClaimAnEarlierActivityResult() {
        val previous = DriveOperations<String>()
        val old = previous.begin("old activity")
        val oldCode = previous.reserveResolution(old)
        previous.cancel()
        val replacement = DriveOperations<String>()
        val current = replacement.begin("new activity")
        val currentCode = replacement.reserveResolution(current)
        assertNotEquals(oldCode, currentCode)
        val stale = replacement.consumeResolution(oldCode)
        assertNotNull(stale)
        assertFalse(replacement.isCurrent(stale!!))
        assertEquals(current, replacement.consumeResolution(currentCode))
        assertEquals("new activity", replacement.take(current))
    }
    @Test fun pendingCodeExhaustionCannotOverwriteAnEarlierAuthorization() {
        val operations = DriveOperations<Int>()
        val codes = mutableListOf<Int>()
        repeat(1000) {
            val operation = operations.begin(it)
            codes.add(operations.reserveResolution(operation))
            operations.cancel()
        }
        assertEquals(1000, codes.toSet().size)
        val current = operations.begin(1000)
        try { operations.reserveResolution(current); fail("Reused a pending code") }
        catch (_: IllegalStateException) { }
        assertNotNull(operations.consumeResolution(codes.first()))
        assertEquals(codes.first(), operations.reserveResolution(current))
        codes.forEach(operations::consumeResolution)
    }
    @Test fun driveUrlsRejectTraversalAndForeignAuthorities() {
        for (address in listOf(
            "https://www.googleapis.com/drive/v3/../files",
            "https://www.googleapis.com/upload/drive/v3/./files",
            "https://www.googleapis.com/drive/v3/%2e%2e/files",
            "https://www.googleapis.com/drive/v3/files%2f..%2fother",
            "https://www.googleapis.com/drive/v3/%252e%252e/files",
            "https://www.googleapis.com/drive/v3/files%5c..%5cother",
            "https://www.googleapis.com/drive/v3/files\\..\\other",
            "http://www.googleapis.com/drive/v3/files",
            "https://www.googleapis.com.evil.example/drive/v3/files",
            "https://user@www.googleapis.com/drive/v3/files",
            "https://www.googleapis.com:443/drive/v3/files",
            "https://www.googleapis.com/drive/v3/files#fragment",
            "https://www.googleapis.com/other/files"
        )) {
            try { DriveRequestPolicy.url(address); fail("Accepted $address") }
            catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun normalAndResumableDriveUrlsKeepTheirQueries() {
        for (address in listOf(
            "https://www.googleapis.com/drive/v3/about?fields=user(permissionId)",
            "https://www.googleapis.com/drive/v3/files/abc-123_xyz?alt=media",
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable",
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=abc%2Fdef"
        )) assertEquals(address, DriveRequestPolicy.url(address).toString())
    }
}
