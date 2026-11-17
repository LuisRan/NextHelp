# QA — PR #2: MVP Android

**Issue:** [#1](https://github.com/LuisRan/NextHelp/issues/1)
**PR:** [#2](https://github.com/LuisRan/NextHelp/pull/2)
**Commit probado:** `d543d6f120c07264b839890eac42f253ad810af8`
**Commit de merge:** `543efeac02eb89607519799d9859100af0735903`
**Fecha de repetición de QA:** 2026-11-17
**Dispositivo:** emulador Android API 35 / Android 15 (`emulator-5556`, `sdk_gphone64_arm64`).

## Build

Registro íntegro de Gradle: [pr2-build.log](pr2-build.log).

En el checkout exacto del commit probado ejecuté:

```bash
./gradlew clean testDebugUnitTest assembleDebug
```

**Esperado:** compilar el APK debug y completar la tarea de pruebas.
**Observado:** `BUILD SUCCESSFUL`; `assembleDebug` generó `app/build/outputs/apk/debug/app-debug.apk`. `testDebugUnitTest` reportó `NO-SOURCE`, porque este PR todavía no incluía pruebas unitarias. Kotlin mostró advertencias de deprecación para `statusBarColor` y `navigationBarColor`; no impidieron compilar.

## Pasos funcionales

1. Instalar el APK del commit indicado y abrir NextHelp.
2. En inicio, comprobar que aparecen las tarjetas **Asistente** y **Minijuego**.
3. Abrir **Asistente**, escribir `riesgo` y tocar **Responder**.
4. Regresar, abrir **Cacería nocturna**, comprobar la vista horizontal con protagonista y controles, y tocar **INICIAR**.

**Resultado esperado:** la aplicación abre; la pregunta demo recibe una respuesta de ejemplo etiquetada como tal; el minijuego muestra su escena y permite iniciar.
**Resultado observado:** se verificaron esos estados en el emulador, incluida la transición a `¡Avanza! Los enemigos ya vienen.` al iniciar la partida. Para `riesgo`, la demo respondió que el riesgo principal es depender de un servicio externo y marcó la fuente como `Respuesta de muestra`.

## Capturas

- Inicio: [pr2-home-api35.png](pr2-home-api35.png)
- Asistente con respuesta demo: [pr2-assistant-response-api35.png](pr2-assistant-response-api35.png)
- Entrada al minijuego: [pr2-game-api35.png](pr2-game-api35.png)
- Partida iniciada: [pr2-game-start-api35.png](pr2-game-start-api35.png)

## Fuera de esta verificación

No había pruebas unitarias en este PR. No se configuró una API real, no se solicitó dictado de voz y no se validó iOS; por ello estas capturas no demuestran esos flujos.
