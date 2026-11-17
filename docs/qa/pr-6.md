# QA — PR #6: conservar el arma de cada proyectil

**Issue:** [#5](https://github.com/LuisRan/NextHelp/issues/5)
**PR:** [#6](https://github.com/LuisRan/NextHelp/pull/6)
**Commit probado:** `e1e2e82873222a2dff12e9b98768bbbcc3dfa003`
**Commit de merge:** `f71e7975c930c9e48785d0c76c3d8a342fd93ad2`
**Dispositivo:** emulador Android API 35 / Android 15 (`emulator-5556`, `sdk_gphone64_arm64`).

## Build y pruebas

```bash
./gradlew testDebugUnitTest assembleDebug
```

**Esperado:** compilar y conservar verdes las pruebas de impacto directo y área.
**Observado:** `BUILD SUCCESSFUL`; pasan las dos pruebas unitarias existentes. El APK se instaló y abrió en el emulador.

## Pasos funcionales

1. Abrir **Cacería nocturna** e iniciar.
2. Seleccionar **Rayo** y disparar.
3. Antes de que el proyectil salga de pantalla, cambiar a **Granada**.

**Esperado:** se muestra Granada como arma seleccionada y el rayo ya disparado conserva su color/tamaño hasta desaparecer. La granada conserva su efecto naranja hasta explotar.
**Observado:** la captura muestra el disparo cian en vuelo mientras el selector muestra Granada. La prueba directa conserva `weapon = 2` en el proyectil no impactado; la prueba de granada conserva el daño de área.

Captura: [qa-pr5-projectile-switch.png](../qa-pr5-projectile-switch.png).
