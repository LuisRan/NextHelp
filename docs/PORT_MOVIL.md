# NextHelp móvil: alcance y plan de adaptación

Este documento conecta la idea y el código original del curso con el producto NextHelp actual. El ZIP `NH-Dev-main` se usa como referencia funcional de macOS; no se copia su código de AppKit ni sus servicios locales de Ollama. La publicación del curso será Android en Google Play; iOS forma parte del alcance de portabilidad y debe conservar el flujo principal donde el sistema lo permita.

## Producto móvil

NextHelp móvil ayuda durante una reunión o entrevista: escucha el micrófono con permiso explícito, transcribe, permite preguntar al asistente sobre la conversación y documentos, y muestra las respuestas en una interfaz discreta. La conversación y los documentos se procesan mediante servicios API configurados para el producto. El cliente móvil no descarga ni ejecuta un LLM local.

La app nunca inicia captura de micrófono o pantalla sin una acción visible del usuario. Debe mostrar un indicador persistente mientras graba, controles para pausar/detener y una explicación clara de qué texto se envía al servicio remoto. No se ofrece invisibilidad frente a la persona usuaria ni frente a los indicadores de privacidad del sistema.

NextHelp también incluye un minijuego original de acción lateral para darle un segundo uso atractivo a la app móvil. No comparte captura, micrófono ni backend con el asistente; se puede jugar sin conexión.

## Estado implementado en este clon

- Proyecto Android Compose en el módulo `app/`, abierto desde la raíz con Gradle Wrapper. La pantalla principal tiene accesos visibles al Asistente y al Minijuego.
- Asistente demo local y envío opcional a `POST /v1/assistant/answer`; permite escribir o dictar una pregunta y muestra respuesta, fuente y errores. El host/token no son obligatorios; el token ingresado permanece solo en memoria.
- Minijuego funcional con protagonista original dibujado en pixel art, tres escenarios/ciclo, cuatro armas (pistola, escopeta, rayo y granada de área), movimiento lateral por toques, salto, disparo, oleadas, jefe, acertijo de opción múltiple, dificultad creciente y mejor puntaje/ciclo guardados localmente.
- iOS, transcripción continua, perfiles/documentos, historial completo, overlay, memoria y el backend real siguen pendientes. La captura por voz disponible en el MVP es dictado bajo demanda mediante el reconocedor del sistema, no escucha continua de la reunión.

## Alcance priorizado

### P0: entrega Android

- Onboarding, idioma español, permisos explicados y consentimiento de procesamiento remoto.
- Sesión de reunión: iniciar/detener captura del micrófono, transcripción en vivo, editar/borrar líneas y manejo de errores.
- Responder a la última intervención, seleccionar texto para preguntar, chat contextual y tarjeta con respuesta/fuentes.
- Perfiles y documentos gestionados por el servicio remoto; selección del perfil activo.
- Historial y exportación/guardado de transcripciones, ajustes de proveedor/conexión y fallos de red visibles.
- Modo compacto con ventana flotante Android opcional, solicitado por el usuario y concedido en Ajustes; botón para ocultar/cerrar. Si el permiso no se concede, el flujo sigue dentro de la app mediante notificación/controles normales.
- Pipeline de build firmado fuera del repositorio y dos versiones en canal de prueba cerrada según `AppMovilesEntrega2Proyecto_2027-1.md`.
- Minijuego táctil de desplazamiento lateral, arte pixelado original, tres niveles en ciclo, dificultad creciente, jefe al final de cada ciclo, varias armas, salto y encuentros de acertijo de opción múltiple. Respuesta correcta deja avanzar; error termina la partida.
- Guardado local de puntuación y progreso, sin cuenta ni API. Violencia estilizada, sin gore ni contenido instructivo de daño real.
- Apertura desde el clon en Android Studio con Gradle Wrapper y ejecución sin credenciales: modo demo para el asistente y datos/partida de ejemplo para el juego.

### P1: iOS

- Mismo flujo de sesión, transcripción del micrófono, API, perfiles, preguntas, historial, teleprompter y ajustes.
- Interfaz compacta en la app, controles accesibles desde notificación/actividad admitida por el sistema cuando aplique.
- Sin ventana global flotante ni ocultamiento de la app de capturas. Audio de otras apps no es requisito del MVP.

### P2: equivalencias opcionales

- Captura de reproducción de otras apps Android mediante MediaProjection/AudioPlaybackCapture solo como modo opt-in, sujeto al permiso del sistema y a las políticas de captura de cada app de origen. Debe probarse por dispositivo y no es condición para el flujo P0.
- No implementar captura de audio de otras apps en iOS como si fuera equivalente al audio del sistema de macOS.

## Mapa macOS → móvil

| Código/función de macOS | Adaptación móvil |
|---|---|
| `MicCaptureService`, `LiveTranscriber` | Implementación nativa por plataforma: Android `AudioRecord` + reconocimiento de voz compatible; iOS `AVAudioEngine` + Speech. Si el reconocimiento local no está disponible para el idioma/dispositivo, explicar la alternativa remota antes de enviar audio. |
| `SystemAudioCaptureService` | No forma parte del MVP. Android tiene captura de reproducción condicionada por consentimiento y política de la app emisora; iOS no ofrece la captura general equivalente. |
| `RAGClient`, `AssistantService`, adaptadores LLM | Cliente de una API autenticada. El proveedor LLM y sus credenciales residen en backend; nunca incluir secretos de proveedor en el APK/IPA. Mantener respuestas rápidas/profundas, streaming, fuentes, errores y cancelación si la API los soporta. |
| `ProfileLibrary`, `IngestService`, stores vectoriales | API de perfiles/documentos e indexación remota. El teléfono carga, lista y elimina documentos; el backend valida tipo/tamaño, indexa, busca y devuelve referencias de fuente. |
| `MeetingController`, memoria y resúmenes | Modelo de sesión común en el producto API: guardar localmente borradores y sincronizar sesiones solo con consentimiento; permitir borrar/exportar. Resumen y memoria se procesan vía API. |
| `Teleprompter` | Parser y avance por voz dentro de cada cliente. Importar guiones desde el selector de archivos del sistema. |
| `WindowSharing` | Android: modo overlay explícito y revocable; no prometer que quede fuera de capturas. iOS: panel compacto dentro de la app; sin overlay universal. |
| Atajos y controles de reunión | Botones grandes, acción rápida y notificación/controles permitidos; no depender de atajos globales de teclado. |
| Ollama, `ModelManager`, descarga de modelos | Se omiten del cliente móvil. La pantalla de proveedor muestra conexión/estado de API, modelo remoto y consentimiento. |
| Ajustes, privacidad, traducción, documentos legales | Se conservan como categorías; adaptar los permisos, textos de datos y opciones a cada plataforma y al backend. |

## Arquitectura propuesta

Mantener los clientes nativos porque audio, permisos, ciclo de vida y overlay son APIs distintas:

- `android/`: Kotlin, Jetpack Compose, capas `domain`, `data`, `audio`, `ui`; servicio de captura de primer plano solo mientras una sesión iniciada por el usuario esté activa.
- `ios/`: SwiftUI, capas equivalentes y adaptadores nativos de audio/voz. Puede añadirse después de estabilizar el contrato de API y el flujo Android.
- `game/` o módulo `arcade`: lógica de niveles, combate, acertijos y progreso separada del asistente. Definiciones de niveles compartidas como datos; controles/renderizado táctil nativos por plataforma. Mantener los assets originales y ligeros para que el arranque del proyecto no requiera descargas manuales.
- Android Studio debe abrir el proyecto desde la raíz del clon; incluir Gradle Wrapper y configuración de desarrollo sin secretos. La app debe tener modo demo local para que la primera ejecución no dependa de un backend desplegado.
- Contratos de negocio compartidos mediante OpenAPI/JSON y ejemplos de respuestas, no mediante dependencias de interfaz comunes.
- El contrato inicial está en [`docs/mobile-api.yaml`](mobile-api.yaml); el dominio `example.invalid` es intencional y debe reemplazarse por el API desplegado al iniciar la integración.
- Backend: autenticación de usuario, cuotas, protección de credenciales de proveedor, consentimiento, API de sesiones, perfiles, documentos y asistente. No exponer Ollama ni una API key privada directamente a Internet o a la app.
- Persistencia local: preferencias, borradores y cache mínima cifrada cuando contenga datos de reunión. La persona puede borrar datos desde la app.

El contrato mínimo versionado incluye `POST /v1/sessions`, `POST /v1/sessions/{id}/transcript`, `POST /v1/assistant/answer`, `POST /v1/assistant/chat`, `GET/POST /v1/profiles` y carga de documentos. Respuestas del asistente incluyen `answer`, `sources[]`, `requestId`; errores incluyen código estable y mensaje seguro. Aún falta implementar y desplegar el backend; streaming puede agregarse como SSE en una iteración posterior.

## Criterios de aceptación del flujo móvil

1. Sin permiso de micrófono, se muestra cómo habilitarlo y no se inicia captura.
2. Al iniciar sesión, aparece indicador claro; detener termina captura y envío pendiente.
3. El texto transcrito se puede corregir y borrar antes de enviarse.
4. Con transcripción vacía, responder presenta un estado explicativo y no llama la API.
5. Una pregunta válida presenta respuesta, fuentes si existen, carga, reintento y error de conexión.
6. El modo compacto no inicia solo; Android pide el permiso de overlay en contexto y funciona sin él; iOS permanece dentro de la app.
7. No hay claves de proveedor, transcripciones ni documentos en logs, analítica o repositorio.
8. El usuario puede retirar consentimiento, detener la sesión y borrar transcripciones/perfiles.

## Entrega del curso y trazabilidad

La versión del curso sigue siendo el mismo proyecto NextHelp y su repo. La actualización sustantiva de Play debe ser una función móvil observable, vinculada a issue, PR y tarjeta Scrum; sugerencia para la segunda publicación: respuesta API con fuentes y estados de error/cancelación, si no existe en la primera versión. `docs/entrega-2.md` debe enlazar ambos releases de prueba cerrada; `docs/pruebas.md` debe registrar dispositivos/API, versiones, resultados observados y evidencia real. No sustituir las publicaciones por APK/AAB locales.

No se deben inventar URLs, testers, resultados, PRs fusionados, credenciales, firmas ni evidencia. Antes de publicar hacen falta cuenta/API disponible, bundle/application ID acordado, configuración de Play Console, clave de firma protegida y dispositivos/cuentas de prueba.

## Fuentes de plataforma

- Android permite capturar reproducción de otras apps desde Android 10 con `MediaProjection` y aprobación visible; depende de que la app emisora permita captura: [Audio playback capture](https://developer.android.com/media/platform/av-capture?authuser=6).
- Android exige autorización especial concedida por el usuario para dibujar encima de otras apps: [Settings.canDrawOverlays](https://developer.android.com/reference/android/provider/Settings?authuser=86).
- Apple describe ReplayKit como grabación/transmisión de pantalla y audio, no como una ventana global flotante o captura arbitraria de otras apps: [ReplayKit](https://developer.apple.com/documentation/ReplayKit).
