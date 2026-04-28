#!/usr/bin/env bash
# ==============================================================================
# setup_llama_turboQ.sh
#
# One-shot installer + launcher for Qwen3.5-9B-Q4_K_M on a Jetson Orin Nano
# (8 GB) using the TurboQuant llama.cpp fork for compressed KV cache.
#
# Reproduces vtong's setup from the Jetson AI Lab forum thread.
#
# Usage:
#   chmod +x setup_llama_turboQ.sh
#   ./setup_llama_turboQ.sh              # full install + start server
#   ./setup_llama_turboQ.sh build        # build the fork only (skip run)
#   ./setup_llama_turboQ.sh run          # start server (assumes already built)
#   ./setup_llama_turboQ.sh stop         # stop a running llama-server
#
# Tweak the variables in the CONFIG block below if you want a different
# model path, port, context size, or turbo level.
# ==============================================================================

set -euo pipefail

# ----------------------------- CONFIG -----------------------------------------
INSTALL_DIR="${INSTALL_DIR:-$HOME/llama-cpp-turboquant}"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
MODEL_REPO="${MODEL_REPO:-unsloth/Qwen3.5-9B-GGUF}"
MODEL_FILE="${MODEL_FILE:-Qwen3.5-9B-Q4_K_M.gguf}"
MODEL_PATH="$MODELS_DIR/$MODEL_FILE"

PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-100000}"   # 100K with turbo4; use 131072 with turbo3
GPU_LAYERS="${GPU_LAYERS:-99}"   # 99 = offload everything
THREADS="${THREADS:-4}"          # Orin Nano = 6 cores, leave 2 for the OS
TURBO_LEVEL="${TURBO_LEVEL:-turbo4}"  # turbo2 / turbo3 / turbo4
CUDA_ARCH="${CUDA_ARCH:-87}"     # Orin = sm_87

LOG_FILE="${LOG_FILE:-$HOME/llama-server.log}"
PID_FILE="${PID_FILE:-$HOME/llama-server.pid}"
# ------------------------------------------------------------------------------

LLAMA_SERVER="$INSTALL_DIR/build/bin/llama-server"

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }

install_deps() {
    log "Installing build dependencies (sudo required)..."
    sudo apt update
    sudo apt install -y build-essential cmake git ccache libcurl4-openssl-dev python3-pip

    if ! command -v nvcc >/dev/null 2>&1; then
        warn "nvcc not found on PATH. Make sure JetPack 6 is installed and CUDA is in PATH."
        warn "Try: export PATH=/usr/local/cuda/bin:\$PATH"
    else
        log "Found CUDA: $(nvcc --version | grep release)"
    fi
}

clone_and_build() {
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        log "Cloning TurboQuant fork to $INSTALL_DIR ..."
        git clone https://github.com/TheTom/llama-cpp-turboquant.git "$INSTALL_DIR"
    else
        log "Repo already exists at $INSTALL_DIR, pulling latest..."
        git -C "$INSTALL_DIR" fetch --all
    fi

    cd "$INSTALL_DIR"
    git checkout feature/turboquant-kv-cache

    log "Configuring CMake (CUDA arch $CUDA_ARCH)..."
    cmake -B build \
        -DGGML_CUDA=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH"

    log "Building (this can take 20-40 min on Orin Nano)..."
    cmake --build build --config Release -j"$(nproc)"

    if [ ! -x "$LLAMA_SERVER" ]; then
        err "Build finished but $LLAMA_SERVER is missing. Check build/bin/."
        exit 1
    fi
    log "Build OK: $LLAMA_SERVER"
}

download_model() {
    mkdir -p "$MODELS_DIR"
    if [ -f "$MODEL_PATH" ]; then
        log "Model already present: $MODEL_PATH"
        return
    fi

    log "Installing huggingface-cli..."
    pip install -U --quiet "huggingface_hub[cli]"

    log "Downloading $MODEL_REPO/$MODEL_FILE (~5.7 GB) ..."
    huggingface-cli download "$MODEL_REPO" "$MODEL_FILE" --local-dir "$MODELS_DIR"

    if [ ! -f "$MODEL_PATH" ]; then
        err "Model download failed. Expected: $MODEL_PATH"
        exit 1
    fi
}

start_server() {
    if [ ! -x "$LLAMA_SERVER" ]; then
        err "llama-server not built yet. Run: $0 build"
        exit 1
    fi
    if [ ! -f "$MODEL_PATH" ]; then
        err "Model not found at $MODEL_PATH. Run the full install first."
        exit 1
    fi

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "Server already running (PID $(cat "$PID_FILE")). Use '$0 stop' first."
        exit 1
    fi

    log "Starting llama-server on port $PORT (ctx=$CTX_SIZE, kv=$TURBO_LEVEL)..."
    nohup "$LLAMA_SERVER" \
        --model "$MODEL_PATH" \
        --port "$PORT" \
        --ctx-size "$CTX_SIZE" \
        --n-gpu-layers "$GPU_LAYERS" \
        --threads "$THREADS" \
        --cache-type-k "$TURBO_LEVEL" \
        --cache-type-v "$TURBO_LEVEL" \
        --flash-attn on \
        --host 0.0.0.0 \
        --metrics > "$LOG_FILE" 2>&1 &

    echo $! > "$PID_FILE"
    log "Started PID $(cat "$PID_FILE"). Logs: $LOG_FILE"
    log "Test with:"
    echo "  curl http://localhost:$PORT/v1/chat/completions \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\":\"qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":32}'"
    log "Tailing log (Ctrl+C to detach; server keeps running)..."
    tail -f "$LOG_FILE"
}

stop_server() {
    if [ ! -f "$PID_FILE" ]; then
        warn "No PID file at $PID_FILE."
        pkill -f "llama-server.*$MODEL_FILE" || true
        return
    fi
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        log "Stopping PID $PID..."
        kill "$PID"
        sleep 2
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" || true
    fi
    rm -f "$PID_FILE"
    log "Stopped."
}

# ----------------------------- DISPATCH ---------------------------------------
CMD="${1:-all}"
case "$CMD" in
    all)
        install_deps
        clone_and_build
        download_model
        start_server
        ;;
    deps)   install_deps ;;
    build)  clone_and_build ;;
    model)  download_model ;;
    run)    start_server ;;
    stop)   stop_server ;;
    *)
        echo "Usage: $0 [all|deps|build|model|run|stop]"
        exit 1
        ;;
esac