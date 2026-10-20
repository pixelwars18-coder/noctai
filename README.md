# Noctai

A Noctalia-styled Quickshell front end for running AI models locally: chat with LLMs (through Ollama), and
generate images, video, speech and audio (diffusers, Kokoro, transformers). Browse and download models from
Hugging Face and Ollama inside the app. One model sits on the GPU at a time.

- `shell.qml` and the other `*.qml` files: the UI (Quickshell). `Theme.qml` follows the Noctalia palette.
- `server.py`: the backend (plain Python HTTP server) that manages downloads and runs the models.
- `noctai`: launcher (`noctai [chat|image|video|speech|audio|models|downloads]`).

Setup: create a venv and `pip install -r requirements.txt` (an NVIDIA GPU with CUDA 12.8 wheels is assumed),
install Ollama for chat, then run `./noctai`. Generated files go to `outputs/` (ignored by git).
