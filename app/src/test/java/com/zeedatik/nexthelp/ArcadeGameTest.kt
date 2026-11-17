package com.zeedatik.nexthelp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ArcadeGameTest {
    @Test
    fun grenadeDamagesNearbyEnemiesAndBoss() {
        val enemies = listOf(
            PixelEnemy(x = .62f),
            PixelEnemy(x = .70f),
            PixelEnemy(x = .78f, hp = 10, boss = true)
        )
        val grenade = PixelBullet(x = .60f, y = .64f, blastRadius = .2f)

        val result = resolveShots(enemies, listOf(grenade), initialScore = 0)

        assertEquals(20, result.score)
        assertEquals(1, result.enemies.size)
        assertTrue(result.enemies.single().boss)
        assertEquals(8, result.enemies.single().hp)
    }

    @Test
    fun directShotDoesNotDamageAnEnemyOutsideItsHitRange() {
        val enemy = PixelEnemy(x = .9f)
        val bullet = PixelBullet(x = .5f, y = .64f)

        val result = resolveShots(listOf(enemy), listOf(bullet), initialScore = 5)

        assertEquals(5, result.score)
        assertEquals(listOf(enemy), result.enemies)
        assertEquals(listOf(bullet), result.bullets)
    }
}
