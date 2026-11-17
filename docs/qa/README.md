# Evidencia QA de Pull Requests móviles

Los reportes de abajo documentan la verificación reproducible de los commits exactos integrados. Las capturas se tomaron en emulador Android API 35 (Android 15), identificador `emulator-5556`, con los APK de cada commit, no con una compilación posterior.

| PR / issue | Cambio | Commit de la rama | Integración | Reporte |
|---|---|---|---|---|
| [PR #2](https://github.com/LuisRan/NextHelp/pull/2) / [#1](https://github.com/LuisRan/NextHelp/issues/1) | MVP Android, asistente demo y minijuego | `d543d6f120c07264b839890eac42f253ad810af8` | `543efeac02eb89607519799d9859100af0735903` | [Reporte QA](pr-2.md) |
| [PR #4](https://github.com/LuisRan/NextHelp/pull/4) / [#3](https://github.com/LuisRan/NextHelp/issues/3) | Granada y pruebas de proyectiles | `762aa92f2ad317e99e5fc14cb12696a41a79f343` | `9f03e5f721531080eda2016bce95e2f92a9ee47a` | [Reporte QA](pr-4.md) |
| [PR #6](https://github.com/LuisRan/NextHelp/pull/6) / [#5](https://github.com/LuisRan/NextHelp/issues/5) | Proyectiles conservan su arma | `e1e2e82873222a2dff12e9b98768bbbcc3dfa003` | `f71e7975c930c9e48785d0c76c3d8a342fd93ad2` | [Reporte QA](pr-6.md) |

## Revisiones

Las tres ramas tienen una revisión técnica registrada en la conversación de su PR. Como el autor trabaja sin equipo, las revisiones retrospectivas de #2 y #4 y la revisión de #6 fueron hechas por el autor con asistencia de Codex; no se presentan como revisiones independientes de terceros. GitHub no permite que la cuenta autora apruebe su propio PR, así que los registros tienen estado `COMMENTED`.

## Límites de la evidencia

- El PR #2 no agregó pruebas unitarias: `testDebugUnitTest` terminó como `NO-SOURCE`. La demo del asistente y la navegación se comprobaron manualmente.
- El PR #4 añadió dos pruebas unitarias de lógica de impactos; no se probó un backend real ni iOS.
- El PR #6 comprobó identidad de arma en vuelo con prueba de regresión y captura del emulador.
- El repositorio no tiene un workflow de CI configurado ni checks requeridos. Los resultados listados son de ejecución local.
