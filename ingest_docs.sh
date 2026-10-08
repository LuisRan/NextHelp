#!/bin/bash
# Carga al RAG todos los documentos de docs/<perfil>/ (.txt, .md o .pdf).
# El nombre de la subcarpeta es el perfil. Ej: docs/servicenow/*.txt -> perfil "servicenow".
# Se puede correr las veces que quieras: si un documento ya existía, se reemplaza.
# Requisito: el rag_service corriendo (uvicorn ... --port 8000).
cd "$(dirname "$0")"
for dir in docs/*/; do
  profile=$(basename "$dir")
  for f in "$dir"*; do
    case "$f" in *.txt|*.md|*.pdf) ;; *) continue ;; esac
    echo "→ [$profile] $(basename "$f")"
    curl -s -X POST http://localhost:8000/ingest \
      -F "profile=$profile" \
      -F "source=$(basename "$f")" \
      -F "file=@$f"
    echo
  done
done
