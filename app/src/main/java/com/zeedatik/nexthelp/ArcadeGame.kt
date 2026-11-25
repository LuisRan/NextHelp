package com.zeedatik.nexthelp

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.random.Random

private val Night = Color(0xFF11182A)
private val Sky = Color(0xFF202D4B)
private val Building = Color(0xFF313F5A)
private val Ground = Color(0xFF413C48)
private val HeroBlue = Color(0xFF46B5E8)
private val HeroRed = Color(0xFFE95E62)
private val Monster = Color(0xFFB84F64)
private val Gold = Color(0xFFFFC857)
private val PixelCream = Color(0xFFFFE5B0)

internal data class PixelEnemy(val x: Float, val hp: Int = 1, val boss: Boolean = false)
internal data class PixelBullet(
    val x: Float,
    val y: Float,
    val speed: Float = .055f,
    val blastRadius: Float = 0f,
    val weapon: Int = 0
)
internal data class ArcadeState(
    val running: Boolean = false,
    val finished: Boolean = false,
    val playerX: Float = .16f,
    val jump: Float = 0f,
    val enemies: List<PixelEnemy> = emptyList(),
    val bullets: List<PixelBullet> = emptyList(),
    val elapsed: Float = 0f,
    val spawnClock: Float = 0f,
    val level: Int = 1,
    val cycle: Int = 1,
    val score: Int = 0,
    val lives: Int = 3,
    val weapon: Int = 0,
    val bossSpawned: Boolean = false,
    val riddle: Boolean = false,
    val message: String = "Pulsa INICIAR para entrar a la ciudad."
)

@Composable
internal fun ArcadeScreen(state: ArcadeState, onState: (ArcadeState) -> Unit, onBack: () -> Unit, onGameOver: (Int, Int) -> Unit) {
    val latestState by rememberUpdatedState(state)
    LaunchedEffect(state.score, state.cycle) { onGameOver(state.score, state.cycle) }
    LaunchedEffect(state.running, state.finished, state.riddle) {
        while (state.running && !state.finished && !state.riddle) {
            delay(50)
            onState(stepArcade(latestState))
        }
    }

    Column(Modifier.fillMaxSize().background(Night).padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹", color = Color(0xFF70E1C1), fontSize = 29.sp) }
            Column(Modifier.weight(1f)) {
                Text("CACERÍA NOCTURNA", color = Gold, fontWeight = FontWeight.Black, fontSize = 16.sp, letterSpacing = 1.sp)
                Text("Ciclo ${state.cycle} · ${stageName(state.level)} · ${weaponName(state.weapon)}", color = Color(0xFFB0BBD0), fontSize = 12.sp)
            }
            Text("★ ${state.score}   ♥ ${"■".repeat(state.lives.coerceAtLeast(0))}", color = PixelCream, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        }

        Box(Modifier.fillMaxWidth().weight(1f).border(2.dp, Color(0xFF53627E), RoundedCornerShape(12.dp))) {
            Canvas(Modifier.fillMaxSize()) {
                val w = size.width
                val h = size.height
                val skyColor = when (state.level) {
                    2 -> Color(0xFF302B45)
                    3 -> Color(0xFF16313D)
                    else -> Sky
                }
                val buildingColor = when (state.level) {
                    2 -> Color(0xFF55414A)
                    3 -> Color(0xFF28505A)
                    else -> Building
                }
                drawRect(skyColor)
                drawRect(Night.copy(alpha = .45f), topLeft = Offset.Zero, size = Size(w, h * .48f))
                for (i in 0..17) {
                    val sx = ((i * 83f + 27f) % w)
                    val sy = ((i * 37f + 11f) % (h * .42f))
                    drawRect(PixelCream.copy(alpha = .45f), Offset(sx, sy), Size(3f, 3f))
                }
                val parallax = (state.elapsed * 10f) % (w * .26f)
                for (i in -1..5) {
                    val x = i * (w * .26f) - parallax
                    val height = h * (.2f + ((i + 7) % 3) * .055f)
                    drawRect(buildingColor, Offset(x, h * .53f - height), Size(w * .2f, height))
                    for (window in 0..3) drawRect(Gold.copy(alpha = .55f), Offset(x + 10 + window * 15, h * .53f - height + 14), Size(5f, 8f))
                    if (state.level == 2) drawRect(Color(0xFF78545A), Offset(x + w * .15f, h * .53f - height - h * .08f), Size(w * .035f, h * .08f))
                }
                if (state.level == 3) {
                    drawRect(Color(0xFF315C66), Offset(0f, h * .56f), Size(w, h * .08f))
                    drawRect(Color(0xFFB7A17C), Offset(0f, h * .64f), Size(w, 3f))
                    drawRect(Color(0xFFB7A17C), Offset(0f, h * .67f), Size(w, 2f))
                }
                drawRect(Ground, Offset(0f, h * .79f), Size(w, h * .21f))
                drawRect(Color(0xFF80654B), Offset(0f, h * .79f), Size(w, 5f))
                for (i in 0..14) drawRect(Color(0xFF5A5260), Offset(i * w / 14f, h * .94f), Size(24f, 5f))

                val heroX = w * state.playerX
                val heroBottom = h * (.79f - state.jump)
                // Protagonista pixel-art original: chaqueta, rostro, cabello y rifle.
                drawRect(HeroBlue, Offset(heroX, heroBottom - h * .19f), Size(w * .055f, h * .12f))
                drawRect(HeroRed, Offset(heroX + w * .008f, heroBottom - h * .235f), Size(w * .04f, h * .045f))
                drawRect(Color(0xFF342B38), Offset(heroX + w * .007f, heroBottom - h * .27f), Size(w * .042f, h * .04f))
                drawRect(PixelCream, Offset(heroX + w * .017f, heroBottom - h * .225f), Size(w * .025f, h * .025f))
                drawRect(Color(0xFF273042), Offset(heroX + w * .005f, heroBottom - h * .075f), Size(w * .02f, h * .075f))
                drawRect(Color(0xFF273042), Offset(heroX + w * .034f, heroBottom - h * .075f), Size(w * .02f, h * .075f))
                drawRect(Gold, Offset(heroX + w * .045f, heroBottom - h * .17f), Size(w * .075f, h * .025f))

                state.enemies.forEach { enemy ->
                    val ex = w * enemy.x
                    val eh = if (enemy.boss) h * .39f else h * .18f
                    val ew = if (enemy.boss) w * .12f else w * .06f
                    val ey = h * .79f - eh
                    drawRect(if (enemy.boss) Color(0xFF793A61) else Monster, Offset(ex, ey), Size(ew, eh))
                    drawRect(Color(0xFF201D2A), Offset(ex + ew * .17f, ey - eh * .18f), Size(ew * .67f, eh * .2f))
                    drawRect(Gold, Offset(ex + ew * .2f, ey + eh * .2f), Size(ew * .15f, eh * .08f))
                    drawRect(Gold, Offset(ex + ew * .62f, ey + eh * .2f), Size(ew * .15f, eh * .08f))
                    drawRect(Color(0xFF313040), Offset(ex + ew * .1f, h * .75f), Size(ew * .22f, h * .04f))
                    drawRect(Color(0xFF313040), Offset(ex + ew * .67f, h * .75f), Size(ew * .22f, h * .04f))
                    if (enemy.boss) {
                        drawRect(Color(0xFF402840), Offset(w * .66f, h * .08f), Size(w * .27f, h * .035f))
                        drawRect(Color(0xFFE94F73), Offset(w * .66f, h * .08f), Size(w * .27f * (enemy.hp / (8f + (state.cycle - 1) * 2f)).coerceIn(0f, 1f), h * .035f))
                    }
                }
                state.bullets.forEach { bullet ->
                    if (bullet.weapon == 3) drawRect(Color(0xFFFF784F).copy(alpha = .28f), Offset(w * (bullet.x - .025f), h * (bullet.y - .03f)), Size(w * .07f, h * .078f))
                    drawRect(when (bullet.weapon) { 2 -> Color(0xFF77F1F4); 3 -> Color(0xFFFF784F); else -> Gold }, Offset(w * bullet.x, h * bullet.y), Size(w * if (bullet.weapon == 2) .065f else .035f, h * .018f))
                }
                drawRect(Color.White.copy(alpha = .12f), Offset(0f, h * .79f - 2), Size(w, 2f))
            }

            Column(Modifier.align(Alignment.TopCenter).padding(9.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(state.message, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                if (!state.running && !state.finished) {
                    Button(onClick = { onState(state.copy(running = true, message = "¡Avanza! Los enemigos ya vienen.")) }, colors = ButtonDefaults.buttonColors(containerColor = Gold, contentColor = Night)) { Text("INICIAR") }
                }
                if (state.finished) {
                    Button(onClick = {
                        onGameOver(state.score, state.cycle)
                        onState(ArcadeState(running = true, message = "Nueva partida. ¡Buena suerte!"))
                    }, colors = ButtonDefaults.buttonColors(containerColor = Gold, contentColor = Night)) { Text("REINTENTAR") }
                }
            }
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("Nivel ${state.level}/3", color = Color.White, fontWeight = FontWeight.Bold)
            Text("Más enemigos cada ciclo", color = Color(0xFFB0BBD0), fontSize = 11.sp)
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            GameButton("◀", Modifier.weight(1f), enabled = state.running) { onState(state.copy(playerX = (state.playerX - .055f).coerceAtLeast(.04f))) }
            GameButton("▶", Modifier.weight(1f), enabled = state.running) { onState(state.copy(playerX = (state.playerX + .055f).coerceAtMost(.52f))) }
            GameButton("SALTO", Modifier.weight(1.2f), enabled = state.running) { onState(state.copy(jump = .24f)) }
            GameButton("${weaponShort(state.weapon)}", Modifier.weight(1.15f), enabled = state.running) { onState(state.copy(weapon = (state.weapon + 1) % 4, message = "Arma: ${weaponName((state.weapon + 1) % 4)}")) }
            GameButton("DISPARO", Modifier.weight(1.35f), enabled = state.running) {
                val bullets = when (state.weapon) {
                    1 -> listOf(PixelBullet(state.playerX + .12f, .64f, .06f, weapon = 1), PixelBullet(state.playerX + .12f, .68f, .06f, weapon = 1), PixelBullet(state.playerX + .12f, .60f, .06f, weapon = 1))
                    2 -> listOf(PixelBullet(state.playerX + .12f, .64f, .13f, weapon = 2))
                    3 -> listOf(PixelBullet(state.playerX + .12f, .64f, .045f, blastRadius = .2f, weapon = 3))
                    else -> listOf(PixelBullet(state.playerX + .12f, .64f, .075f, weapon = 0))
                }
                onState(state.copy(bullets = state.bullets + bullets))
            }
        }
        Text("Toque varias veces para avanzar. Cambia de arma con el botón central.", color = Color(0xFF8794AA), fontSize = 10.sp, modifier = Modifier.align(Alignment.CenterHorizontally))
    }

    if (state.riddle) {
        AlertDialog(
            onDismissRequest = { },
            title = { Text("El guardián de la salida") },
            text = { Text("Tengo calles pero no autos, ríos pero no agua y fronteras pero no guardias. ¿Qué soy?") },
            confirmButton = {
                TextButton(onClick = {
                    onState(ArcadeState(running = true, score = state.score + 100, cycle = state.cycle + 1, message = "¡Correcto! Comienza un nuevo ciclo."))
                }) { Text("UN MAPA") }
            },
            dismissButton = {
                Column {
                    TextButton(onClick = { onState(state.copy(riddle = false, running = false, finished = true, message = "Respuesta incorrecta. Fin de la partida.")) }) { Text("UN RELOJ") }
                    TextButton(onClick = { onState(state.copy(riddle = false, running = false, finished = true, message = "Respuesta incorrecta. Fin de la partida.")) }) { Text("UNA LLAVE") }
                }
            }
        )
    }
}

@Composable
private fun GameButton(label: String, modifier: Modifier, enabled: Boolean, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled, modifier = modifier.height(54.dp), shape = RoundedCornerShape(12.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF293750), contentColor = Color.White, disabledContainerColor = Color(0xFF1B2639), disabledContentColor = Color(0xFF67748B)), contentPadding = androidx.compose.foundation.layout.PaddingValues(2.dp)) {
        Text(label, fontSize = 11.sp, fontWeight = FontWeight.Black)
    }
}

private fun stepArcade(old: ArcadeState): ArcadeState {
    val dt = .05f
    var elapsed = old.elapsed + dt
    var level = old.level
    var message = old.message
    val stageLength = 13f
    if (elapsed >= stageLength && level < 3) {
        elapsed -= stageLength
        level += 1
        message = when (level) { 2 -> "Distrito industrial · más rápido"; else -> "Estación abandonada · aguanta" }
    }

    val hadBoss = old.enemies.any { it.boss }
    val enemies = old.enemies.map { enemy ->
        if (enemy.boss) enemy.copy(x = (enemy.x - .0022f).coerceAtLeast(.69f))
        else enemy.copy(x = enemy.x - (.012f + old.cycle * .0014f))
    }
    val bullets = old.bullets.map { it.copy(x = it.x + it.speed) }.filter { it.x < 1.1f }
    val shots = resolveShots(enemies, bullets, old.score)
    val score = shots.score
    val remainingBullets = shots.bullets
    var lives = old.lives
    val remainingEnemies = mutableListOf<PixelEnemy>()
    shots.enemies.forEach { enemy ->
        if (!enemy.boss && enemy.x < old.playerX + .065f && enemy.x > old.playerX - .02f && old.jump < .07f) lives -= 1
        else if (enemy.x > -.1f || enemy.boss) remainingEnemies.add(enemy)
    }
    if (lives <= 0) return old.copy(running = false, finished = true, lives = 0, score = score, message = "Te alcanzaron. Puntaje: $score")

    var spawnClock = old.spawnClock + dt
    val bossExists = remainingEnemies.any { it.boss }
    var bossSpawned = old.bossSpawned
    if (level == 3 && elapsed >= stageLength && !bossSpawned) {
        remainingEnemies.add(PixelEnemy(1.03f, hp = 8 + (old.cycle - 1) * 2, boss = true))
        message = "¡JEFE! Apunta y cambia de arma."
        elapsed = stageLength
        spawnClock = 0f
        bossSpawned = true
    } else if (!(level == 3 && elapsed >= stageLength) && spawnClock > (1.55f / (1f + (old.cycle - 1) * .18f)).coerceAtLeast(.48f)) {
        remainingEnemies.add(PixelEnemy(1.04f, hp = 1 + if (old.cycle > 4 && Random.nextFloat() < .3f) 1 else 0))
        spawnClock = 0f
    }

    if (level == 3 && elapsed >= stageLength && hadBoss && !bossExists) {
        return old.copy(running = false, riddle = true, score = score, level = level, message = "El jefe cayó. Resuelve el acertijo para salir.")
    }

    val jump = (old.jump - .018f).coerceAtLeast(0f)
    return old.copy(enemies = remainingEnemies, bullets = remainingBullets, elapsed = elapsed, spawnClock = spawnClock, level = level, score = score, lives = lives, jump = jump, bossSpawned = bossSpawned, message = message)
}

internal data class ShotResolution(val enemies: List<PixelEnemy>, val bullets: List<PixelBullet>, val score: Int)

internal fun resolveShots(inputEnemies: List<PixelEnemy>, inputBullets: List<PixelBullet>, initialScore: Int): ShotResolution {
    val enemies = inputEnemies.toMutableList()
    val remainingBullets = mutableListOf<PixelBullet>()
    var score = initialScore
    inputBullets.forEach { bullet ->
        val target = enemies.indexOfFirst { abs(it.x - bullet.x) < if (it.boss) .12f else .07f }
        if (target < 0) {
            remainingBullets.add(bullet)
        } else if (bullet.blastRadius > 0f) {
            val impactX = enemies[target].x
            val affected = enemies.filter { abs(it.x - impactX) <= bullet.blastRadius }
            affected.forEach { enemy ->
                val index = enemies.indexOf(enemy)
                if (index >= 0 && enemy.boss && enemy.hp > 2) enemies[index] = enemy.copy(hp = enemy.hp - 2)
                else if (index >= 0) { enemies.removeAt(index); score += if (enemy.boss) 100 else 10 }
            }
        } else {
            val enemy = enemies[target]
            if (enemy.boss && enemy.hp > 1) enemies[target] = enemy.copy(hp = enemy.hp - 1)
            else { enemies.removeAt(target); score += if (enemy.boss) 100 else 10 }
        }
    }
    return ShotResolution(enemies, remainingBullets, score)
}

private fun stageName(level: Int) = when (level) { 1 -> "Centro"; 2 -> "Fábrica"; else -> "Estación / Jefe" }
private fun weaponName(weapon: Int) = when (weapon) { 1 -> "Escopeta"; 2 -> "Rayo"; 3 -> "Granada"; else -> "Pistola" }
private fun weaponShort(weapon: Int) = when (weapon) { 1 -> "ESCOPETA"; 2 -> "RAYO"; 3 -> "GRANADA"; else -> "PISTOLA" }
