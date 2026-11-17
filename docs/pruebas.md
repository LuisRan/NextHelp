# Matriz de pruebas Android

Las pruebas se repiten en un emulador Android API 35 / Android 15. Los reportes guardan el commit exacto probado, los comandos, resultados, datos usados y capturas.

| ID | Caso | Esperado | Evidencia / estado |
|---|---|---|---|
| AND-01 | Compilar APK desde el clon | `assembleDebug` exitoso | [PR #2](qa/pr-2.md); log guardado. |
| AND-02 | Pregunta demo `riesgo` sin API | Respuesta muestra texto y fuente de demostración | [PR #2](qa/pr-2.md); captura guardada. |
| AND-03 | Abrir e iniciar minijuego | Pantalla horizontal, controles y mensaje de partida activa | [PR #2](qa/pr-2.md); capturas guardadas. |
| AND-04 | Granada contra enemigos y jefe | Daño dentro del radio y reducción de 2 HP al jefe | [PR #4](qa/pr-4.md); dos pruebas JUnit pasaron. |
| AND-05 | Disparo fuera del alcance | No cambia el enemigo ni el puntaje y el proyectil sigue en vuelo | [PR #4](qa/pr-4.md); prueba JUnit pasó. |
| AND-06 | Cambiar arma mientras el disparo está en vuelo | El proyectil conserva el aspecto de su arma original | [PR #6](qa/pr-6.md); prueba de regresión y captura guardadas. |

## Alcance aún no verificado

No se probó conexión a un backend real, dictado con proveedor de voz, iOS, ni uso con testers externos. El PR #2 aún no tenía pruebas unitarias; en ese commit la tarea `testDebugUnitTest` terminó `NO-SOURCE`. La granularidad de impactos se cubre con dos pruebas unitarias desde el PR #4.
