"""
Servicio RAG local para el asistente de reuniones.

Todo el trabajo de modelos (embeddings y generación) se delega a Ollama,
que debe estar corriendo en localhost:11434. Este servicio solo:
  - chunkea e indexa documentos por perfil
  - busca los chunks más relevantes para una pregunta
  - arma un prompt anti-alucinación y llama al LLM
"""

import re
import sqlite3
from pathlib import Path
from typing import Optional

import requests
import sqlite_vec
import threading

from fastapi import FastAPI, Form, Request, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel

OLLAMA_URL = "http://localhost:11434"
EMBED_MODEL = "nomic-embed-text"
EMBED_DIMS = 768
# "-instruct-2507" es la variante de Qwen3 SIN modo thinking: responde
# directo, sin cadena de razonamiento interna. Es lo que queremos para
# respuestas rápidas en vivo durante una reunión.
LLM_MODEL = "qwen3:4b-instruct-2507-q4_K_M"

# Ambos modelos se quedan cargados en memoria este tiempo. Si solo uno se
# queda, Ollama saca y mete modelos en CADA pregunta (embedding → LLM →
# embedding…) y con 8 GB de RAM esa recarga puede pasar de 30 s (timeout).
KEEP_ALIVE = "30m"
# Contexto fijo del LLM: nuestros prompts son chicos (~1.5k tokens). Fijarlo
# reduce RAM y evita que Ollama recargue el modelo por configuraciones distintas.
NUM_CTX = 4096
# Tiempo máximo por llamada a Ollama (la primera carga en frío puede tardar).
OLLAMA_TIMEOUT = 90


class OllamaError(RuntimeError):
    """Error de Ollama con mensaje claro para mostrar en la app."""

DB_DIR = Path(__file__).parent / "data"
DB_DIR.mkdir(exist_ok=True)
DB_PATH = DB_DIR / "meeting_assistant.db"

app = FastAPI(title="RAG local - asistente de reuniones")


@app.exception_handler(Exception)
async def any_error(request: Request, exc: Exception):
    """Cualquier error se regresa como {"error": ...} (la app lo muestra)."""
    message = str(exc) if isinstance(exc, OllamaError) else f"{type(exc).__name__}: {exc}"
    return JSONResponse(status_code=500, content={"error": message})


def warm_up_models() -> None:
    """Carga ambos modelos en memoria al arrancar, para que la primera
    pregunta no espere la carga en frío."""
    try:
        embed("calentando modelo")
        requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={"model": LLM_MODEL, "keep_alive": KEEP_ALIVE, "options": {"num_ctx": NUM_CTX}},
            timeout=180,
        ).raise_for_status()
        print(f"✅ Modelos precargados en Ollama: {EMBED_MODEL} + {LLM_MODEL}")
    except Exception as exc:  # no tumbar el servidor por esto
        print(f"⚠️ No se pudieron precargar los modelos: {exc}")


@app.on_event("startup")
def start_warm_up() -> None:
    threading.Thread(target=warm_up_models, daemon=True).start()


def get_db() -> sqlite3.Connection:
    db = sqlite3.connect(DB_PATH)
    db.enable_load_extension(True)
    sqlite_vec.load(db)
    db.enable_load_extension(False)
    return db


def safe_profile_name(profile: str) -> str:
    """Solo letras, números y guion bajo, para usar en nombres de tabla."""
    cleaned = re.sub(r"[^a-zA-Z0-9_]", "_", profile.strip().lower())
    if not cleaned:
        raise ValueError("Nombre de perfil inválido")
    return cleaned


def ensure_profile_tables(db: sqlite3.Connection, profile: str) -> None:
    p = safe_profile_name(profile)
    db.execute(
        f"""CREATE TABLE IF NOT EXISTS chunks_{p} (
            id INTEGER PRIMARY KEY,
            source TEXT NOT NULL,
            text TEXT NOT NULL
        )"""
    )
    db.execute(
        f"""CREATE VIRTUAL TABLE IF NOT EXISTS vec_{p}
            USING vec0(embedding float[{EMBED_DIMS}])"""
    )
    db.commit()


def chunk_text(text: str, size: int = 1200, overlap: int = 150) -> list[str]:
    """Chunking por PÁRRAFOS: junta párrafos (separados por línea en blanco)
    hasta ~size caracteres, sin partir secciones a la mitad. Así cada chunk
    conserva su título ("FSO Banca — Card Operations…") y el RAG sabe de qué
    habla. Solo un párrafo más largo que `size` se corta por caracteres."""
    text = text.strip()
    if not text:
        return []
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks: list[str] = []
    current = ""
    for para in paragraphs:
        if len(para) > size:
            if current:
                chunks.append(current)
                current = ""
            start = 0
            while start < len(para):
                chunks.append(para[start:start + size])
                start += size - overlap
            continue
        if current and len(current) + 2 + len(para) > size:
            chunks.append(current)
            current = para
        else:
            current = f"{current}\n\n{para}" if current else para
    if current:
        chunks.append(current)
    return chunks


def ollama_post(path: str, payload: dict) -> dict:
    try:
        resp = requests.post(f"{OLLAMA_URL}{path}", json=payload, timeout=OLLAMA_TIMEOUT)
    except requests.Timeout:
        raise OllamaError(
            f"Ollama tardó más de {OLLAMA_TIMEOUT}s en responder (probablemente cargando "
            "un modelo en memoria; con poca RAM libre tarda más). Intenta de nuevo en unos segundos."
        )
    except requests.ConnectionError:
        raise OllamaError("No me pude conectar a Ollama en localhost:11434. ¿Está corriendo? (ollama serve)")
    if resp.status_code != 200:
        raise OllamaError(f"Ollama respondió {resp.status_code}: {resp.text[:200]}")
    return resp.json()


def embed(text: str) -> list[float]:
    data = ollama_post(
        "/api/embeddings",
        {"model": EMBED_MODEL, "prompt": text, "keep_alive": KEEP_ALIVE},
    )
    return data.get("embedding") or []


@app.post("/ingest")
def ingest(
    profile: str = Form(...),
    source: str = Form(...),
    text: Optional[str] = Form(None),
    file: Optional[UploadFile] = None,
):
    """Agrega un documento (texto directo o archivo .txt/.pdf) al perfil dado."""
    if file is not None:
        raw = file.file.read()
        if file.filename and file.filename.lower().endswith(".pdf"):
            from pypdf import PdfReader
            import io

            reader = PdfReader(io.BytesIO(raw))
            text = "\n".join(page.extract_text() or "" for page in reader.pages)
        else:
            text = raw.decode("utf-8", errors="ignore")

    if not text:
        return {"error": "no se recibió texto ni archivo"}

    db = get_db()
    ensure_profile_tables(db, profile)
    p = safe_profile_name(profile)

    # Si ya existía un documento con el mismo nombre (source) en este perfil,
    # se reemplaza: así puedes volver a cargarlo actualizado sin duplicarlo.
    old_ids = [r[0] for r in db.execute(f"SELECT id FROM chunks_{p} WHERE source = ?", (source,)).fetchall()]
    for old_id in old_ids:
        db.execute(f"DELETE FROM vec_{p} WHERE rowid = ?", (old_id,))
    db.execute(f"DELETE FROM chunks_{p} WHERE source = ?", (source,))

    pieces = chunk_text(text)
    inserted = 0
    for piece in pieces:
        vector = embed(piece)
        cur = db.execute(
            f"INSERT INTO chunks_{p} (source, text) VALUES (?, ?)",
            (source, piece),
        )
        chunk_id = cur.lastrowid
        db.execute(
            f"INSERT INTO vec_{p} (rowid, embedding) VALUES (?, ?)",
            (chunk_id, sqlite_vec.serialize_float32(vector)),
        )
        inserted += 1

    db.commit()
    db.close()
    return {"profile": p, "source": source, "chunks_indexed": inserted, "replaced_chunks": len(old_ids)}


# Perfil especial: siempre aparece en la lista. Si tiene documentos indexados
# los usa como apoyo, pero si no, responde con el conocimiento general del
# modelo (los demás perfiles SOLO responden con sus documentos).
GENERAL_PROFILE = "general"


@app.get("/profiles")
def list_profiles():
    db = get_db()
    rows = db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'chunks_%'"
    ).fetchall()
    db.close()
    names = {r[0].removeprefix("chunks_") for r in rows}
    names.add(GENERAL_PROFILE)
    # "general" primero, luego el resto en orden alfabético.
    return {"profiles": sorted(names, key=lambda n: (n != GENERAL_PROFILE, n))}


class AskRequest(BaseModel):
    profile: str
    question: str
    top_k: int = 4
    recent_context: Optional[str] = None  # últimas frases de la reunión, si aplica
    # Aclaración tuya (ej. "se refiere al módulo Change Management"). Se usa
    # para BUSCAR en los documentos y se le pasa al LLM como contexto.
    hint: Optional[str] = None
    # Guion de la demo en curso (teleprompter): paso actual + guion completo.
    demo_context: Optional[str] = None


def chat(system_prompt: str, user_prompt: str, num_predict: int = 220) -> str:
    data = ollama_post(
        "/api/chat",
        {
            "model": LLM_MODEL,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "stream": False,
            "keep_alive": KEEP_ALIVE,
            # Tope de largo de respuesta: menos tokens = respuesta más rápida.
            "options": {"temperature": 0.2, "num_predict": num_predict, "num_ctx": NUM_CTX},
        },
    )
    return data["message"]["content"].strip()


def search(db: sqlite3.Connection, p: str, question: str, top_k: int):
    """Regresa (chunks, error). chunks = [(texto, fuente, distancia)]."""
    exists = db.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
        (f"chunks_{p}",),
    ).fetchone()
    if not exists:
        return [], None
    q_vector = embed(question)
    # Ollama regresa [] si el modelo de embeddings no está cargado o el texto
    # no produce tokens; sqlite-vec truena con eso ("zero-length vectors").
    if not q_vector:
        return [], f"Ollama devolvió un embedding vacío — revisa que '{EMBED_MODEL}' esté descargado (ollama pull {EMBED_MODEL})"
    rows = db.execute(
        f"""SELECT c.text, c.source, v.distance
            FROM vec_{p} v
            JOIN chunks_{p} c ON c.id = v.rowid
            WHERE v.embedding MATCH ? AND k = ?
            ORDER BY v.distance""",
        (sqlite_vec.serialize_float32(q_vector), top_k),
    ).fetchall()
    return rows, None


@app.post("/ask")
def ask(req: AskRequest):
    p = safe_profile_name(req.profile)
    question = (req.question or "").strip()
    if not question:
        return {"error": "la pregunta llegó vacía (todavía no hay transcripción)"}

    hint = (req.hint or "").strip()
    db = get_db()
    # La aclaración se suma a la búsqueda: así el RAG trae los documentos del
    # tema correcto aunque la transcripción venga incompleta o con errores.
    rows, error = search(db, p, f"{question}\n{hint}" if hint else question, req.top_k)
    db.close()
    if error:
        return {"error": error}

    context_block = "\n\n".join(f"[Fuente: {source}]\n{text}" for text, source, _ in rows)

    if p == GENERAL_PROFILE:
        system_prompt = (
            "Eres un asistente discreto que ayuda al usuario EN VIVO durante una "
            "reunión o entrevista. Te paso lo último que se dijo y el fragmento "
            "al que hay que responder (puede venir de una transcripción automática "
            "con errores). Identifica qué se está preguntando y da la respuesta "
            "que el usuario podría decir, en español, directa y breve (2-4 líneas), "
            "sin introducciones. Si no estás seguro de un dato concreto (cifras, "
            "nombres, fechas), dilo en vez de inventarlo."
        )
        user_prompt = ""
        if context_block:
            user_prompt += f"Documentos de apoyo:\n{context_block}\n\n"
    else:
        if not rows:
            return {"error": f"el perfil '{p}' no tiene documentos indexados todavía"}
        system_prompt = (
            "Eres un asistente que responde preguntas SOLO con base en el contexto "
            "proporcionado. Si el contexto no contiene información suficiente para "
            "responder con confianza, dilo explícitamente en vez de inventar o "
            "suponer. No agregues información que no esté en el contexto. "
            "Responde de forma breve y directa, apta para leerse en vivo durante "
            "una reunión (2-4 líneas como máximo)."
        )
        user_prompt = f"Contexto:\n{context_block}\n\n"

    if req.demo_context:
        user_prompt += (f"El usuario está dando una DEMO en vivo. Responde en el contexto de lo que "
                        f"está mostrando:\n{req.demo_context}\n\n")
    if req.recent_context:
        user_prompt += f"Lo último dicho en la reunión:\n{req.recent_context}\n\n"
    user_prompt += f"Fragmento a responder: {question}"
    if hint:
        user_prompt += f"\n\nAclaración del usuario (tómala en cuenta, es confiable): {hint}"

    answer = chat(system_prompt, user_prompt)
    return {
        "answer": answer,
        "sources": [{"source": source, "distance": dist} for _, source, dist in rows],
    }


# ---------------------------------------------------------------------------
# Preguntas libres sobre la reunión
# ---------------------------------------------------------------------------

# Límite de transcripción que cabe en el contexto del modelo (NUM_CTX=4096
# tokens ≈ 12k caracteres en total, dejando espacio para docs y respuesta).
MAX_TRANSCRIPT_CHARS = 7000


class ChatRequest(BaseModel):
    profile: str
    question: str
    transcript: str
    top_k: int = 3
    demo_context: Optional[str] = None


@app.post("/chat")
def chat_meeting(req: ChatRequest):
    """Responde preguntas libres tuyas sobre lo que se ha dicho en la reunión."""
    question = (req.question or "").strip()
    if not question:
        return {"error": "escribe una pregunta"}
    transcript = (req.transcript or "").strip()
    # El guion de la demo también ocupa contexto: se le resta a la transcripción.
    limit = max(3000, MAX_TRANSCRIPT_CHARS - len(req.demo_context or ""))
    truncated = len(transcript) > limit
    if truncated:
        # Lo más reciente es lo más relevante en una reunión en curso.
        transcript = "…(inicio omitido)…\n" + transcript[-limit:]

    p = safe_profile_name(req.profile)
    db = get_db()
    rows, _ = search(db, p, question, req.top_k)
    db.close()
    context_block = "\n\n".join(f"[Fuente: {source}]\n{text}" for text, source, _ in rows)

    system_prompt = (
        "Eres el asistente personal del usuario durante una reunión. Tienes la "
        "transcripción automática (puede traer errores de reconocimiento; 'Tú' es "
        "el usuario y 'Ellos' son las demás personas). Responde en español, claro "
        "y breve, lo que el usuario te pregunte sobre la reunión: resúmenes, "
        "acuerdos, qué le preguntaron, pendientes, etc. Básate en la transcripción; "
        "si algo no aparece en ella, dilo en vez de inventarlo. Si hay documentos "
        "de apoyo, úsalos para complementar."
    )
    user_prompt = f"Transcripción de la reunión:\n{transcript or '(todavía vacía)'}\n\n"
    if req.demo_context:
        user_prompt += f"El usuario está dando una DEMO en vivo con este guion:\n{req.demo_context}\n\n"
    if context_block:
        user_prompt += f"Documentos de apoyo ({p}):\n{context_block}\n\n"
    user_prompt += f"Pregunta del usuario: {question}"

    answer = chat(system_prompt, user_prompt, num_predict=450)
    if truncated:
        answer += "\n\n(Nota: la reunión es larga; usé solo la parte más reciente de la transcripción.)"
    return {
        "answer": answer,
        "sources": [{"source": source, "distance": dist} for _, source, dist in rows],
    }
