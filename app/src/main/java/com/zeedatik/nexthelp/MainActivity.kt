package com.zeedatik.nexthelp

import android.app.Activity
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import android.speech.RecognizerIntent
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val Ink = Color(0xFF10141F)
private val Panel = Color(0xFF1A2232)
private val Mint = Color(0xFF70E1C1)
private val Amber = Color(0xFFFFC857)
private val Rose = Color(0xFFFF7188)
private val Muted = Color(0xFF9BA8BC)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(16, 20, 31)
        window.navigationBarColor = android.graphics.Color.rgb(16, 20, 31)
        window.decorView.setBackgroundColor(android.graphics.Color.rgb(16, 20, 31))
        setContent { NextHelpApp() }
    }
}

private enum class Page { Home, Assistant, Game }

@Composable
private fun NextHelpApp() {
    var page by remember { mutableStateOf(Page.Home) }
    var game by remember { mutableStateOf(ArcadeState()) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val activity = context as? Activity
    val prefs = context.getSharedPreferences("nexthelp_arcade", Activity.MODE_PRIVATE)
    DisposableEffect(page, activity) {
        activity?.requestedOrientation = if (page == Page.Game) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        onDispose { activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }
    var bestScore by remember { mutableStateOf(prefs.getInt("best_score", 0)) }
    var bestCycle by remember { mutableStateOf(prefs.getInt("best_cycle", 1)) }
    BackHandler(page != Page.Home) { page = Page.Home }

    MaterialTheme {
        Surface(Modifier.fillMaxSize().systemBarsPadding(), color = Ink) {
            when (page) {
                Page.Home -> HomeScreen(
                    bestScore = bestScore,
                    bestCycle = bestCycle,
                    openAssistant = { page = Page.Assistant },
                    openGame = { game = ArcadeState(); page = Page.Game }
                )
                Page.Assistant -> AssistantScreen(onBack = { page = Page.Home })
                Page.Game -> ArcadeScreen(
                    state = game,
                    onState = { game = it },
                    onBack = { page = Page.Home },
                    onGameOver = { score, cycle ->
                        if (score > bestScore) bestScore = score
                        if (cycle > bestCycle) bestCycle = cycle
                        prefs.edit().putInt("best_score", bestScore).putInt("best_cycle", bestCycle).apply()
                    }
                )
            }
        }
    }
}

@Composable
private fun HomeScreen(bestScore: Int, bestCycle: Int, openAssistant: () -> Unit, openGame: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 28.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("ZEEDATIK  •  NEXTHELP", color = Mint, fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
        Text("Tu compañero\nde misión.", color = Color.White, fontSize = 34.sp, lineHeight = 38.sp, fontWeight = FontWeight.Black)
        Text("Asistencia para tus reuniones y un arcade para el descanso.", color = Muted, fontSize = 16.sp)

        FeatureCard(
            eyebrow = "ASISTENTE · DEMO LISTA",
            title = "Prepárate para responder",
            body = "Dicta o escribe una pregunta. Prueba respuestas de ejemplo o conecta tu API.",
            accent = Mint,
            action = "Abrir asistente",
            onClick = openAssistant
        )
        FeatureCard(
            eyebrow = "MINIJUEGO · ARCADE LATERAL",
            title = "Cacería nocturna",
            body = "Un protagonista, tres escenarios, armas, saltos y acertijos. Récord: $bestScore  ·  Ciclo: $bestCycle",
            accent = Amber,
            action = "Jugar ahora",
            onClick = openGame
        )
        Spacer(Modifier.weight(1f))
        Text("La demo escrita y el juego funcionan sin conexión. El dictado depende del servicio de voz del dispositivo.", color = Muted, fontSize = 12.sp, modifier = Modifier.align(Alignment.CenterHorizontally))
    }
}

@Composable
private fun FeatureCard(eyebrow: String, title: String, body: String, accent: Color, action: String, onClick: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(24.dp)) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Text(eyebrow, color = accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
            Text(title, color = Color.White, fontSize = 21.sp, fontWeight = FontWeight.Bold)
            Text(body, color = Muted, fontSize = 14.sp, lineHeight = 19.sp)
            Button(onClick = onClick, colors = ButtonDefaults.buttonColors(containerColor = accent, contentColor = Ink), shape = RoundedCornerShape(14.dp)) {
                Text(action, fontWeight = FontWeight.Bold)
            }
        }
    }
}

private data class ChatLine(val question: String, val answer: String, val source: String)

@Composable
private fun AssistantScreen(onBack: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val lines = remember { mutableStateListOf<ChatLine>() }
    var question by remember { mutableStateOf("") }
    var apiBase by remember { mutableStateOf("") }
    var bearer by remember { mutableStateOf("") }
    var showSettings by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Demo local. Al dictar, el sistema de voz del dispositivo recibe el audio.") }
    val speechLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            question = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull().orEmpty()
        }
    }

    Column(Modifier.fillMaxSize().padding(18.dp)) {
        TopBar("Asistente", onBack, trailing = { TextButton(onClick = { showSettings = !showSettings }) { Text("API", color = Mint) } })
        if (showSettings) {
            OutlinedTextField(apiBase, { apiBase = it }, label = { Text("URL base de API (opcional)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            Spacer(Modifier.height(7.dp))
            OutlinedTextField(bearer, { bearer = it }, label = { Text("Token de sesión (no se guarda)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            Text("La API debe implementar POST /v1/assistant/answer. El token solo vive en memoria mientras esta pantalla está abierta.", color = Muted, fontSize = 12.sp)
        }
        Spacer(Modifier.height(10.dp))
        Text("Pregunta sobre tu reunión", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Text(status, color = Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 5.dp, bottom = 10.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(lines) { line ->
                Card(colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(16.dp)) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Tú · ${line.question}", color = Mint, fontWeight = FontWeight.SemiBold)
                        Text(line.answer, color = Color.White)
                        Text("Fuente: ${line.source}", color = Amber, fontSize = 12.sp)
                    }
                }
            }
            if (lines.isEmpty()) item {
                Text("Prueba con una pregunta como: “¿Qué sigue en el plan del proyecto?”", color = Muted, modifier = Modifier.padding(top = 18.dp))
            }
        }
        OutlinedTextField(question, { question = it }, label = { Text("Escribe una pregunta…") }, modifier = Modifier.fillMaxWidth())
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = {
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "es-MX")
                    putExtra(RecognizerIntent.EXTRA_PROMPT, "Dicta tu pregunta")
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
                runCatching { speechLauncher.launch(intent) }.onFailure { status = "No hay reconocimiento de voz disponible en este dispositivo." }
            }) { Text("🎙 Dictar", color = Mint) }
            Button(enabled = !busy, onClick = {
                val prompt = question.trim()
                if (prompt.isBlank()) { status = "Escribe o dicta una pregunta para continuar."; return@Button }
                busy = true
                status = "Preparando respuesta…"
                scope.launch {
                    val result = if (apiBase.isBlank()) demoAnswer(prompt) else withContext(Dispatchers.IO) { callAssistantApi(apiBase, bearer, prompt) }
                    lines.add(0, result.first)
                    status = result.second
                    question = ""
                    busy = false
                }
            }, colors = ButtonDefaults.buttonColors(containerColor = Mint, contentColor = Ink), shape = RoundedCornerShape(14.dp)) {
                Text(if (busy) "Pensando…" else "Responder", fontWeight = FontWeight.Bold)
            }
        }
    }
}

private fun demoAnswer(question: String): Pair<ChatLine, String> {
    val answer = when {
        question.contains("plan", ignoreCase = true) -> "Primero confirmemos el alcance, después dividimos el trabajo en tareas pequeñas y cerramos con una revisión del resultado."
        question.contains("riesgo", ignoreCase = true) -> "El riesgo principal es depender de un servicio externo. Conviene verificar la conexión y tener una respuesta de error clara antes de continuar."
        else -> "Buena pregunta. Aclara el objetivo, verifica el dato con tu equipo y propone el siguiente paso concreto. Esta es una respuesta de demostración; conecta una API para obtener respuestas del modelo."
    }
    return ChatLine(question, answer, "Respuesta de muestra") to "Modo demostración: pregunta procesada localmente."
}

private fun callAssistantApi(base: String, token: String, question: String): Pair<ChatLine, String> {
    return try {
        val root = base.trim().trimEnd('/')
        val endpoint = if (root.endsWith("/v1")) "$root/assistant/answer" else "$root/v1/assistant/answer"
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 45_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            if (token.isNotBlank()) setRequestProperty("Authorization", "Bearer $token")
        }
        val payload = JSONObject().apply {
            put("sessionId", UUID.nameUUIDFromBytes("nexthelp-demo-session".toByteArray()).toString())
            put("question", question)
            put("mode", "fast")
        }
        connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        connection.disconnect()
        if (code !in 200..299) error("HTTP $code")
        val response = JSONObject(body)
        val sources = response.optJSONArray("sources") ?: JSONArray()
        val source = if (sources.length() > 0) sources.optJSONObject(0)?.optString("title", "Documento") ?: "Documento" else "Sin fuentes"
        ChatLine(question, response.optString("answer", "La API no devolvió una respuesta."), source) to "Respuesta recibida de la API."
    } catch (failure: Exception) {
        ChatLine(question, "No se pudo conectar a la API: ${failure.message ?: "error de red"}. Puedes seguir usando el modo demo.", "Error de conexión") to "La API no respondió. Revisa la URL y el token."
    }
}

@Composable
private fun TopBar(title: String, onBack: () -> Unit, trailing: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = onBack) { Text("‹", color = Mint, fontSize = 30.sp) }
        Text(title, color = Color.White, fontSize = 21.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        trailing()
    }
}

