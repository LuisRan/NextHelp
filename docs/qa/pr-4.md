# QA — PR #4: granada y pruebas de proyectiles

**Issue:** [#3](https://github.com/LuisRan/NextHelp/issues/3)
**PR:** [#4](https://github.com/LuisRan/NextHelp/pull/4)
**Commit probado:** `762aa92f2ad317e99e5fc14cb12696a41a79f343`
**Commit de merge:** `9f03e5f721531080eda2016bce95e2f92a9ee47a`
**Fecha de repetición de QA:** 2026-11-17
**Dispositivo:** emulador Android API 35 / Android 15 (`emulator-5556`, `sdk_gphone64_arm64`).

## Build y pruebas

Registro íntegro de Gradle: [pr4-build.log](pr4-build.log).

En el checkout exacto del commit probado ejecuté:

```bash
./gradlew clean testDebugUnitTest assembleDebug
```

**Esperado:** compilar el APK y ejecutar las pruebas de resolución de disparos.
**Observado:** `BUILD SUCCESSFUL`; JUnit reportó 2 pruebas, 0 fallas, 0 errores y 0 omisiones. La salida XML se conserva en [pr4-test-results.xml](pr4-test-results.xml). Aparecieron las mismas advertencias de deprecación de colores de barras del sistema; no bloquearon el build.

| Prueba | Dato de entrada | Resultado esperado y observado |
|---|---|---|
| `grenadeDamagesNearbyEnemiesAndBoss` | Granada en x=0.60; enemigos en x=0.62 y 0.70; jefe en x=0.78 con 10 HP; radio 0.20 | Los dos enemigos regulares desaparecen, el jefe recibe 2 de daño y queda con 8 HP, y se suman 20 puntos. Pasó. |
| `directShotDoesNotDamageAnEnemyOutsideItsHitRange` | Disparo directo en x=0.50; enemigo en x=0.90; puntaje inicial 5 | Enemigo y proyectil permanecen, puntaje sigue en 5. Pasó. |

## Pasos en emulador

1. Instalar el APK del commit indicado y abrir **Cacería nocturna**.
2. Tocar **INICIAR**.
3. Cambiar el selector tres veces desde **Pistola** hasta **Granada**.

**Esperado:** se muestra `Granada` en el encabezado y botón de arma, con los controles de juego activos.
**Observado:** el emulador mostró `Ciclo 1 · Centro · Granada` y el botón **GRANADA**.

Capturas: [pantalla de juego](pr4-game-api35.png) y [granada seleccionada](pr4-grenade-api35.png). El daño de área se verificó con la prueba unitaria, no con un impacto manual capturado.
