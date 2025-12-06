package com.example.fcmplayground

import android.content.Context
import android.content.SharedPreferences
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
import java.util.UUID

/**
 * Instrumented test for UserIdManager.
 * Tests verify:
 * 1. A new UUID is generated and persisted when no user ID exists
 * 2. The same ID is returned on subsequent calls
 * 3. The generated ID is a valid UUID format
 * 4. Thread safety (multiple threads get the same ID)
 */
@RunWith(AndroidJUnit4::class)
class UserIdManagerTest {

    private lateinit var context: Context
    private lateinit var prefs: SharedPreferences

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        prefs = context.getSharedPreferences("fcm_playground_prefs", Context.MODE_PRIVATE)
        
        // Clear any existing user_id before each test
        prefs.edit().remove("user_id").commit()
    }

    @After
    fun tearDown() {
        // Clean up after each test
        prefs.edit().remove("user_id").commit()
    }

    @Test
    fun testNewUserIdIsGeneratedWhenNotExists() {
        // Ensure no user_id exists
        assertNull(prefs.getString("user_id", null))
        
        // Call getOrCreateUserId
        val userId = UserIdManager.getOrCreateUserId(context)
        
        // Verify a UUID was generated
        assertNotNull(userId)
        assertFalse(userId.isEmpty())
        
        // Verify it's a valid UUID format
        assertTrue("Generated ID should be a valid UUID format", isValidUUID(userId))
    }

    @Test
    fun testUserIdIsPersisted() {
        // Generate a user ID
        val userId = UserIdManager.getOrCreateUserId(context)
        
        // Verify it was saved to SharedPreferences
        val savedUserId = prefs.getString("user_id", null)
        assertNotNull("User ID should be persisted", savedUserId)
        assertEquals("Persisted ID should match generated ID", userId, savedUserId)
    }

    @Test
    fun testSameIdReturnedOnSubsequentCalls() {
        // First call
        val firstUserId = UserIdManager.getOrCreateUserId(context)
        
        // Second call
        val secondUserId = UserIdManager.getOrCreateUserId(context)
        
        // Third call
        val thirdUserId = UserIdManager.getOrCreateUserId(context)
        
        // All calls should return the same ID
        assertEquals("First and second call should return same ID", firstUserId, secondUserId)
        assertEquals("Second and third call should return same ID", secondUserId, thirdUserId)
        assertEquals("First and third call should return same ID", firstUserId, thirdUserId)
    }

    @Test
    fun testGeneratedIdIsValidUUIDFormat() {
        // Generate a user ID
        val userId = UserIdManager.getOrCreateUserId(context)
        
        // Verify it matches UUID format (e.g., "550e8400-e29b-41d4-a716-446655440000")
        assertTrue(
            "Generated ID '$userId' should be a valid UUID format",
            isValidUUID(userId)
        )
        
        // Additional validation: UUID should have specific structure
        val parts = userId.split("-")
        assertEquals("UUID should have 5 parts separated by hyphens", 5, parts.size)
        assertEquals("First part should be 8 characters", 8, parts[0].length)
        assertEquals("Second part should be 4 characters", 4, parts[1].length)
        assertEquals("Third part should be 4 characters", 4, parts[2].length)
        assertEquals("Fourth part should be 4 characters", 4, parts[3].length)
        assertEquals("Fifth part should be 12 characters", 12, parts[4].length)
    }

    @Test
    fun testUserIdPersistenceAcrossMultipleInstances() {
        // Generate user ID
        val firstUserId = UserIdManager.getOrCreateUserId(context)
        
        // Manually clear from memory (simulate app restart)
        // Since UserIdManager is an object (singleton), we can't clear it,
        // but we can verify persistence by checking SharedPreferences directly
        
        // Verify it's saved
        val savedUserId = prefs.getString("user_id", null)
        assertEquals("User ID should be persisted in SharedPreferences", firstUserId, savedUserId)
        
        // Simulate getting it again (as if app was restarted)
        val secondUserId = UserIdManager.getOrCreateUserId(context)
        
        // Should get the same ID from SharedPreferences
        assertEquals("Should retrieve same ID from SharedPreferences", firstUserId, secondUserId)
    }

    @Test
    fun testThreadSafety() {
        // Test that multiple threads get the same ID
        val threadCount = 10
        val results = mutableListOf<String>()
        val threads = mutableListOf<Thread>()
        
        // Create multiple threads that call getOrCreateUserId simultaneously
        repeat(threadCount) {
            val thread = Thread {
                val userId = UserIdManager.getOrCreateUserId(context)
                synchronized(results) {
                    results.add(userId)
                }
            }
            threads.add(thread)
        }
        
        // Start all threads simultaneously
        threads.forEach { it.start() }
        
        // Wait for all threads to complete
        threads.forEach { it.join() }
        
        // Verify all threads got the same ID
        assertEquals("All threads should complete", threadCount, results.size)
        val firstId = results[0]
        results.forEach { id ->
            assertEquals(
                "All threads should get the same user ID (thread safety)",
                firstId,
                id
            )
        }
        
        // Verify only one ID was persisted
        val savedIds = prefs.getString("user_id", null)
        assertEquals("Only one ID should be saved", firstId, savedIds)
    }

    /**
     * Helper function to validate UUID format.
     * UUID format: "550e8400-e29b-41d4-a716-446655440000"
     */
    private fun isValidUUID(uuidString: String): Boolean {
        return try {
            UUID.fromString(uuidString)
            true
        } catch (e: IllegalArgumentException) {
            false
        }
    }
}

