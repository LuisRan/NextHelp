#!/usr/bin/env bash
# Bootstrap del entorno nativo. Correr una sola vez por máquina.
set -euo pipefail

echo "== Verificando Homebrew =="
if ! command -v brew &> /dev/null; then
  echo "Homebrew no está instalado. Instálalo desde https://brew.sh y vuelve a correr este script."
  exit 1
fi

echo "== Instalando Ollama =="
brew list ollama &> /dev/null || brew install ollama

echo "== Arrancando el servicio de Ollama =="
brew services start ollama
sleep 2

echo "== Descargando modelo de embeddings (una sola vez, requiere internet) =="
# El LLM (qwen3:4b-instruct-2507-q4_K_M) ya lo tienes descargado.
# Si en otra máquina no lo tienes, corre antes: ollama pull qwen3:4b-instruct-2507-q4_K_M
ollama pull nomic-embed-text

echo "== Creando entorno virtual de Python para el servicio RAG =="
python3 -m venv rag_service/venv
source rag_service/venv/bin/activate
pip install --upgrade pip
pip install -r rag_service/requirements.txt

echo ""
echo "Listo. Para levantar el servicio de RAG:"
echo "  source rag_service/venv/bin/activate"
echo "  uvicorn rag_service.main:app --reload --port 8000"