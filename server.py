#!/usr/bin/env python3
"""Noctai backend: browses and downloads models (Hugging Face + Ollama) and runs them locally.

LLMs go through Ollama; image/video use diffusers; speech uses Kokoro or transformers;
audio uses transformers (MusicGen) or diffusers (AudioLDM, Stable Audio).
One model is kept on the GPU at a time; Ollama is asked to unload before diffusion runs.
"""
import fnmatch
import inspect
import json
import os
import queue
import random
import re
import subprocess
import sys
import threading
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("NOCTAI_PORT", "47821"))
DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "noctai")
OUT = os.path.join(DATA, "outputs")
REG_PATH = os.path.join(DATA, "models.json")
OLLAMA = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")
if not OLLAMA.startswith("http"):
    OLLAMA = "http://" + OLLAMA
HF = "https://huggingface.co"
KINDS = {"llm": "text-generation", "tti": "text-to-image", "ttv": "text-to-video",
         "tts": "text-to-speech", "tta": "text-to-audio"}
SUGGESTED = {
    "llm": ["unsloth/Qwen3-8B-GGUF", "unsloth/gemma-3-12b-it-GGUF", "bartowski/Llama-3.2-3B-Instruct-GGUF"],
    "tti": ["Lykon/dreamshaper-xl-v2-turbo", "stabilityai/sdxl-turbo", "black-forest-labs/FLUX.1-schnell"],
    "ttv": ["Wan-AI/Wan2.1-T2V-1.3B-Diffusers", "ali-vilab/text-to-video-ms-1.7b", "Lightricks/LTX-Video"],
    "tts": ["hexgrad/Kokoro-82M", "facebook/mms-tts-eng", "suno/bark-small"],
    "tta": ["facebook/musicgen-small", "cvssp/audioldm2-music", "stabilityai/stable-audio-open-1.0"],
}
os.makedirs(OUT, exist_ok=True)
lock = threading.Lock()


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- registry

def reg_load():
    try:
        with open(REG_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def reg_save(reg):
    tmp = REG_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(reg, f, indent=1)
    os.replace(tmp, REG_PATH)


# ---------------------------------------------------------------- http helpers

def hf_token():
    tok = os.environ.get("HF_TOKEN")
    if tok:
        return tok
    try:
        from huggingface_hub import get_token
        return get_token()
    except Exception:
        return None


def fetch(url, data=None, timeout=25, headers=None, stream=False):
    h = {"User-Agent": "noctai/1.0"}
    if url.startswith(HF) and hf_token():
        h["Authorization"] = "Bearer " + hf_token()
    h.update(headers or {})
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        h["Content-Type"] = "application/json"
    r = urllib.request.urlopen(urllib.request.Request(url, body, h), timeout=timeout)
    if stream:
        return r
    with r:
        return json.load(r)


def hf_api(path, params=None):
    q = ("?" + urllib.parse.urlencode(params, doseq=True)) if params else ""
    return fetch(f"{HF}/api{path}{q}")


def ollama(path, data=None, timeout=10):
    return fetch(OLLAMA + path, data, timeout=timeout)


# ---------------------------------------------------------------- hugging face cache

def hub_cache():
    from huggingface_hub.constants import HF_HUB_CACHE
    return HF_HUB_CACHE


def repo_dir(repo):
    return os.path.join(hub_cache(), "models--" + repo.replace("/", "--"))


def snapshot_dir(repo):
    d = repo_dir(repo)
    try:
        with open(os.path.join(d, "refs", "main")) as f:
            p = os.path.join(d, "snapshots", f.read().strip())
            if os.path.isdir(p):
                return p
    except OSError:
        pass
    snaps = os.path.join(d, "snapshots")
    if os.path.isdir(snaps):
        dirs = sorted((os.path.join(snaps, s) for s in os.listdir(snaps)), key=os.path.getmtime)
        if dirs:
            return dirs[-1]
    return None


WEIGHT_EXT = (".safetensors", ".bin", ".pth", ".pt", ".ckpt", ".gguf")


def snapshot_files(path):
    out = []
    for root, _, files in os.walk(path):
        for f in files:
            full = os.path.join(root, f)
            out.append((os.path.relpath(full, path), full))
    return out


def snapshot_info(path):
    """(complete, size) — complete when at least one weight file resolves to a real blob."""
    size, has_weight = 0, False
    for rel, full in snapshot_files(path):
        if not os.path.exists(full):
            continue
        size += os.path.getsize(full)
        if rel.endswith(WEIGHT_EXT):
            has_weight = True
    return has_weight, size


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def infer_kind(repo, path):
    if "kokoro" in repo.lower():
        return "tts"
    mi = read_json(os.path.join(path, "model_index.json"))
    if mi:
        cls = mi.get("_class_name", "")
        if re.search(r"Video|Wan|LTX|Hunyuan|CogVideo|Mochi|I2V|T2V", cls):
            return "ttv"
        if re.search(r"Audio|Music", cls):
            return "tta"
        if re.search(r"Img2Img|Inpaint|ControlNet|Upscale", cls):
            return None
        return "tti"
    cfg = read_json(os.path.join(path, "config.json")) or {}
    arch = " ".join(cfg.get("architectures") or []) + " " + str(cfg.get("model_type", ""))
    if re.search(r"Musicgen|musicgen", arch):
        return "tta"
    if re.search(r"Vits|vits|Bark|bark|SpeechT5ForTextToSpeech|FastSpeech|seamless", arch):
        return "tts"
    return None


def model_defaults(kind, repo, path):
    name = repo.lower()
    mi = read_json(os.path.join(path, "model_index.json")) or {} if path else {}
    cls = mi.get("_class_name", "")
    if kind == "tti":
        d = {"width": 1024, "height": 1024, "steps": 25, "guidance": 5.0}
        if cls == "StableDiffusionPipeline":
            d.update(width=512, height=512, guidance=7.0)
        elif "Flux" in cls:
            d.update(steps=28, guidance=3.5)
        elif "XL" in cls:
            d.update(guidance=6.0)
        if "schnell" in name:
            d.update(steps=4, guidance=0.0)
        elif re.search(r"(^|/)(sdxl|sd)-turbo", name):
            d.update(steps=1, guidance=0.0, width=512, height=512)
        elif re.search(r"turbo|lightning|lcm|hyper", name):
            d.update(steps=6, guidance=2.0)
        return d
    if kind == "ttv":
        if "Wan" in cls:
            return {"width": 832, "height": 480, "frames": 33, "steps": 30, "guidance": 5.0, "fps": 16}
        if "LTX" in cls:
            return {"width": 704, "height": 480, "frames": 65, "steps": 40, "guidance": 3.0, "fps": 24}
        if "CogVideo" in cls:
            return {"width": 720, "height": 480, "frames": 49, "steps": 50, "guidance": 6.0, "fps": 8}
        if "Hunyuan" in cls:
            return {"width": 848, "height": 480, "frames": 61, "steps": 30, "guidance": 6.0, "fps": 15}
        if "TextToVideoSD" in cls:
            return {"width": 256, "height": 256, "frames": 17, "steps": 25, "guidance": 9.0, "fps": 8}
        return {"width": 512, "height": 320, "frames": 33, "steps": 30, "guidance": 5.0, "fps": 16}
    if kind == "tta":
        if "StableAudio" in cls:
            return {"duration": 10, "steps": 100, "guidance": 7.0}
        if cls:
            return {"duration": 10, "steps": 50, "guidance": 3.5}
        return {"duration": 10, "guidance": 3.0}
    if kind == "tts":
        if "kokoro" in name:
            return {"voice": "af_heart", "speed": 1.0}
        return {}
    return {}


def kokoro_voices(path):
    vd = os.path.join(path, "voices")
    if not os.path.isdir(vd):
        return []
    return sorted(f[:-3] for f in os.listdir(vd) if f.endswith(".pt") and os.path.exists(os.path.join(vd, f)))


def local_models(kind):
    if kind == "llm":
        try:
            tags = ollama("/api/tags").get("models", [])
        except Exception:
            return []
        return [{"id": m["name"], "name": m["name"], "size": m.get("size", 0), "kind": "llm",
                 "detail": " · ".join(x for x in [m.get("details", {}).get("parameter_size", ""),
                                                  m.get("details", {}).get("quantization_level", "")] if x),
                 "capabilities": m.get("capabilities", [])} for m in tags]
    reg = reg_load()
    out, seen = [], set()
    root = hub_cache()
    if not os.path.isdir(root):
        return []
    for d in os.listdir(root):
        if not d.startswith("models--"):
            continue
        repo = d[len("models--"):].replace("--", "/", 1)
        path = snapshot_dir(repo)
        if not path or repo in seen:
            continue
        k = reg.get(repo, {}).get("kind") or infer_kind(repo, path)
        if k != kind:
            continue
        complete, size = snapshot_info(path)
        if not complete:
            continue
        seen.add(repo)
        m = {"id": repo, "name": repo.split("/")[-1], "size": size, "kind": kind, "detail": repo.split("/")[0],
             "defaults": model_defaults(kind, repo, path)}
        if "kokoro" in repo.lower():
            m["voices"] = kokoro_voices(path)
        out.append(m)
    out.sort(key=lambda m: m["name"].lower())
    return out


# ---------------------------------------------------------------- browse

def search(kind, q, sort):
    tag = KINDS[kind]
    params = {"pipeline_tag": tag, "sort": sort or "trendingScore", "direction": -1, "limit": 50}
    if q:
        params["search"] = q
    if kind == "llm":
        params["filter"] = "gguf"
    elif kind in ("tti", "ttv"):
        params["filter"] = "diffusers"
    try:
        res = hf_api("/models", params)
    except urllib.error.HTTPError as e:
        if e.code == 400 and params["sort"] == "trendingScore":
            params["sort"] = "downloads"
            res = hf_api("/models", params)
        else:
            raise
    out = []
    for m in res:
        tags = m.get("tags", [])
        rid = m.get("id") or m.get("modelId")
        if kind in ("tts", "tta") and not ("transformers" in tags or "diffusers" in tags or "kokoro" in rid.lower()):
            continue
        out.append({"id": rid, "downloads": m.get("downloads", 0), "likes": m.get("likes", 0),
                    "updated": m.get("lastModified") or m.get("createdAt") or "",
                    "library": m.get("library_name", ""), "gated": bool(m.get("gated"))})
    if not q:
        have = {m["id"] for m in out}
        out = [{"id": s, "suggested": True, "downloads": 0, "likes": 0, "updated": "", "library": "", "gated": False}
               for s in SUGGESTED.get(kind, []) if s not in have] + out
    return out


QUANT_RE = re.compile(r"(?i)[-_.]((?:I?Q\d(?:_[A-Z0-9]+)*)|BF16|F16|F32|FP16)(?=[-_.]|$)")


def gguf_choices(siblings):
    out = []
    for name, size in siblings:
        base = name.rsplit("/", 1)[-1]
        if not base.endswith(".gguf") or "mmproj" in base.lower() or re.search(r"-\d{5}-of-\d{5}", base):
            continue
        m = QUANT_RE.search(base[:-5])
        if not m:
            continue
        out.append({"file": name, "quant": m.group(1).upper(), "size": size})
    out.sort(key=lambda x: x["size"])
    return out


NON_WEIGHT = (".json", ".txt", ".model", ".tiktoken", ".npy", ".npz", ".py.disabled")


def pick_weights(names):
    """From one folder's weight files pick the set diffusers/transformers will load, preferring fp16 safetensors."""
    st = [n for n in names if n.endswith(".safetensors")]
    fp16 = [n for n in st if ".fp16." in n]
    plain = [n for n in st if not re.search(r"\.(fp16|bf16|fp32|non_ema|ema)\.safetensors$", n)]
    if fp16:
        return fp16, "fp16"
    if plain:
        return plain, None
    if st:
        return st, None
    bins = [n for n in names if n.endswith(".bin") and not n.endswith(("flax_model.bin", "tf_model.bin"))]
    bfp16 = [n for n in bins if ".fp16." in n]
    return (bfp16, "fp16") if bfp16 else (bins, None)


def select_files(repo, siblings):
    names = [n for n, _ in siblings]
    if "kokoro" in repo.lower():
        return [n for n in names if n.endswith((".pth", ".json")) or n.startswith("voices/")], None
    if "model_index.json" in names:
        try:
            mi = fetch(f"{HF}/{repo}/resolve/main/model_index.json")
            comps = {k for k, v in mi.items() if not k.startswith("_") and isinstance(v, list) and v[0]}
        except Exception:
            comps = {n.split("/")[0] for n in names if "/" in n}
        keep, variants = ["model_index.json"], set()
        for c in sorted(comps):
            inside = [n for n in names if n.startswith(c + "/") and n.count("/") == 1]
            keep += [n for n in inside if n.endswith(NON_WEIGHT) or not n.endswith((".safetensors", ".bin", ".onnx", ".msgpack", ".h5", ".ckpt", ".pb"))]
            w, v = pick_weights([n for n in inside if n.endswith((".safetensors", ".bin"))])
            keep += w
            if v:
                variants.add(v)
        return sorted(set(keep)), ("fp16" if variants else None)
    root = [n for n in names if "/" not in n or n.startswith("speaker_embeddings/")]
    keep = [n for n in root if n.endswith(NON_WEIGHT) or n.split("/")[-1].startswith(("tokenizer", "vocab", "merges", "spiece", "preprocessor", "special_tokens"))]
    w, _ = pick_weights([n for n in root if n.endswith((".safetensors", ".bin")) and "/" not in n])
    return sorted(set(keep + w)), None


def repo_info(kind, repo):
    info = hf_api(f"/models/{repo}", {"blobs": "true"})
    sib = [(s["rfilename"], s.get("size") or 0) for s in info.get("siblings", [])]
    card = info.get("cardData") or {}
    res = {"id": repo, "gated": info.get("gated") or False, "license": card.get("license", ""),
           "downloads": info.get("downloads", 0), "likes": info.get("likes", 0),
           "pipeline": info.get("pipeline_tag", ""), "library": info.get("library_name", "")}
    if kind == "llm":
        res["files"] = gguf_choices(sib)
    else:
        files, variant = select_files(repo, sib)
        sizes = dict(sib)
        res["files"] = files
        res["variant"] = variant
        res["size"] = sum(sizes.get(f, 0) for f in files)
    return res


# ---------------------------------------------------------------- downloads

downloads = {}


def new_download(kind, repo, label, total=0):
    d = {"id": uuid.uuid4().hex[:10], "kind": kind, "repo": repo, "label": label, "status": "starting",
         "progress": 0.0, "done": 0, "total": total, "error": "", "started": time.time(), "cancel": False}
    downloads[d["id"]] = d
    return d


def ollama_pull(d, name):
    parts = {}
    try:
        r = fetch(OLLAMA + "/api/pull", {"model": name, "stream": True}, timeout=60, stream=True)
        d["_resp"] = r
        with r:
            for line in r:
                if d["cancel"]:
                    break
                ev = json.loads(line)
                if ev.get("error"):
                    raise RuntimeError(ev["error"])
                d["status"] = ev.get("status", "")
                if ev.get("digest") and ev.get("total"):
                    parts[ev["digest"]] = (ev.get("completed", 0), ev["total"])
                    d["done"] = sum(c for c, _ in parts.values())
                    d["total"] = sum(t for _, t in parts.values())
                    d["progress"] = d["done"] / max(1, d["total"])
                if ev.get("status") == "success":
                    d["progress"] = 1.0
        d["status"] = "cancelled" if d["cancel"] else ("done" if d["progress"] >= 1 or d["status"] == "success" else d["status"])
        if d["status"] not in ("done", "cancelled"):
            d["status"] = "done"
    except Exception as e:
        d["status"], d["error"] = ("cancelled", "") if d["cancel"] else ("error", str(e))


HF_DL = """import sys, json
from huggingface_hub import snapshot_download
print(snapshot_download(sys.argv[1], allow_patterns=json.loads(sys.argv[2])))
"""


def hf_download(d, kind, repo, files, variant, sizes):
    from huggingface_hub import try_to_load_from_cache
    try:
        p = subprocess.Popen([sys.executable, "-c", HF_DL, repo, json.dumps(files)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        d["_proc"] = p
        d["status"] = "downloading"
        blobs = os.path.join(repo_dir(repo), "blobs")
        while p.poll() is None:
            if d["cancel"]:
                p.terminate()
                break
            done = 0
            for f in files:
                r = try_to_load_from_cache(repo, f)
                if isinstance(r, str) and os.path.exists(r):
                    done += sizes.get(f, 0)
            if os.path.isdir(blobs):
                for b in os.listdir(blobs):
                    if b.endswith(".incomplete"):
                        try:
                            done += os.path.getsize(os.path.join(blobs, b))
                        except OSError:
                            pass
            d["done"] = min(done, d["total"])
            d["progress"] = d["done"] / max(1, d["total"])
            time.sleep(0.7)
        err = p.stderr.read()
        if d["cancel"]:
            d["status"] = "cancelled"
        elif p.returncode != 0:
            msg = err.strip().splitlines()
            line = next((l for l in reversed(msg) if "Error" in l or "error" in l), msg[-1] if msg else "download failed")
            if "gated" in err.lower() or "401" in err or "403" in err:
                line = "This repo is gated: accept its license on huggingface.co, then run `hf auth login`."
            d["status"], d["error"] = "error", line[-400:]
        else:
            with lock:
                reg = reg_load()
                reg[repo] = {"kind": kind, "variant": variant, "files": files, "added": time.time()}
                reg_save(reg)
            d["status"], d["progress"], d["done"] = "done", 1.0, d["total"]
    except Exception as e:
        d["status"], d["error"] = "error", str(e)


def start_download(body):
    kind, repo = body["kind"], body["repo"].strip()
    if kind == "llm":
        name = body.get("ollama") or repo
        if body.get("quant"):
            name = f"hf.co/{repo}:{body['quant']}"
        d = new_download(kind, name, body.get("label") or name, body.get("size", 0))
        threading.Thread(target=ollama_pull, args=(d, name), daemon=True).start()
        return d
    info = hf_api(f"/models/{repo}", {"blobs": "true"})
    sib = [(s["rfilename"], s.get("size") or 0) for s in info.get("siblings", [])]
    files, variant = select_files(repo, sib)
    sizes = dict(sib)
    d = new_download(kind, repo, repo, sum(sizes.get(f, 0) for f in files))
    threading.Thread(target=hf_download, args=(d, kind, repo, files, variant, sizes), daemon=True).start()
    return d


def delete_model(kind, mid):
    if kind == "llm":
        req = urllib.request.Request(OLLAMA + "/api/delete", json.dumps({"model": mid}).encode(),
                                     {"Content-Type": "application/json"}, method="DELETE")
        urllib.request.urlopen(req, timeout=20).close()
        return
    if gpu.key and gpu.key[1] == mid:
        gpu.unload()
    from huggingface_hub import scan_cache_dir
    info = scan_cache_dir()
    revs = [r.commit_hash for repo in info.repos if repo.repo_id == mid and repo.repo_type == "model" for r in repo.revisions]
    if revs:
        info.delete_revisions(*revs).execute()
    with lock:
        reg = reg_load()
        reg.pop(mid, None)
        reg_save(reg)


# ---------------------------------------------------------------- gpu / inference

class Cancelled(Exception):
    pass


class Gpu:
    def __init__(self):
        self.key, self.pipe, self.busy = None, None, False

    def unload(self):
        if self.pipe is None:
            return
        log("unloading", self.key)
        self.pipe, self.key = None, None
        import gc
        gc.collect()
        try:
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except Exception:
            pass


gpu = Gpu()
jobs = {}
job_queue = queue.Queue()


def ollama_unload_all():
    try:
        for m in ollama("/api/ps").get("models", []):
            ollama("/api/generate", {"model": m["name"], "keep_alive": 0}, timeout=30)
    except Exception:
        pass


def torch_env():
    import torch
    cuda = torch.cuda.is_available()
    return torch, ("cuda" if cuda else "cpu"), cuda


def place(pipe, path, video=False):
    torch, dev, cuda = torch_env()
    if not cuda:
        return pipe
    _, size = snapshot_info(path)
    total = torch.cuda.get_device_properties(0).total_memory
    if size > total * (0.55 if video else 0.8):
        log("model", size >> 20, "MiB > budget, using cpu offload")
        pipe.enable_model_cpu_offload()
    else:
        pipe.to("cuda")
    for fn in ("enable_vae_tiling",) if video else ():
        try:
            getattr(pipe, fn)()
        except Exception:
            pass
    return pipe


def load_diffusers(kind, repo, path):
    torch, dev, cuda = torch_env()
    import diffusers
    mi = read_json(os.path.join(path, "model_index.json")) or {}
    dtype = (torch.bfloat16 if "transformer" in mi else torch.float16) if cuda else torch.float32
    kw = {"torch_dtype": dtype}
    variant = reg_load().get(repo, {}).get("variant")
    if variant is None and any(".fp16." in r for r, _ in snapshot_files(path)):
        variant = "fp16"
    if variant:
        kw["variant"] = variant
    loaders = [diffusers.DiffusionPipeline]
    if kind == "tti":
        loaders.insert(0, diffusers.AutoPipelineForText2Image)
    err = None
    for L in loaders:
        try:
            pipe = L.from_pretrained(path, **kw)
            break
        except Exception as e:
            err = e
            if variant and "variant" in str(e):
                kw.pop("variant", None)
                try:
                    pipe = L.from_pretrained(path, **kw)
                    break
                except Exception as e2:
                    err = e2
    else:
        raise err
    try:
        pipe.set_progress_bar_config(disable=True)
    except Exception:
        pass
    return place(pipe, path, video=(kind == "ttv"))


def load(kind, repo, extra=""):
    key = (kind, repo, extra)
    if gpu.key == key:
        return gpu.pipe
    gpu.unload()
    ollama_unload_all()
    path = snapshot_dir(repo)
    if not path:
        raise RuntimeError(f"{repo} is not downloaded")
    torch, dev, cuda = torch_env()
    if kind == "tts" and "kokoro" in repo.lower():
        from kokoro import KPipeline
        pipe = KPipeline(lang_code=extra or "a", repo_id=repo, device=dev)
    elif os.path.exists(os.path.join(path, "model_index.json")):
        pipe = load_diffusers(kind, repo, path)
    else:
        from transformers import pipeline
        task = "text-to-speech" if kind == "tts" else "text-to-audio"
        pipe = pipeline(task, model=path, device=0 if cuda else -1,
                        dtype=torch.float16 if cuda and kind == "tta" else None)
    gpu.pipe, gpu.key = pipe, key
    return pipe


def call_diffusers(pipe, job, kw):
    sig = inspect.signature(pipe.__call__).parameters
    total = kw.get("num_inference_steps") or 1
    job["steps"] = total

    def on_step(p, i, t, cb_kw):
        job["step"] = i + 1
        job["progress"] = (i + 1) / total
        if job["cancel"]:
            raise Cancelled()
        return cb_kw

    def on_step_legacy(i, t, latents):
        on_step(None, i, t, None)

    if "callback_on_step_end" in sig:
        kw["callback_on_step_end"] = on_step
    elif "callback" in sig:
        kw["callback"] = on_step_legacy
        kw["callback_steps"] = 1
    kw = {k: v for k, v in kw.items() if k in sig or "kwargs" in sig}
    return pipe(**kw)


def out_path(kind, ext, n=0):
    d = os.path.join(OUT, kind)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, time.strftime("%Y%m%d-%H%M%S") + f"-{uuid.uuid4().hex[:4]}{n or ''}.{ext}")


def write_meta(path, job):
    with open(path + ".json", "w") as f:
        json.dump({"prompt": job["prompt"], "model": job["model"], "kind": job["kind"],
                   "params": job["params"], "time": time.time(), "seconds": round(time.time() - job["t0"], 1)}, f)


def write_audio(path, audio, sr):
    import numpy as np
    import soundfile as sf
    a = np.asarray(audio, dtype=np.float32).squeeze()
    if a.ndim == 2 and a.shape[0] < a.shape[1]:
        a = a.T
    sf.write(path, a, int(sr))


def run_job(job):
    import numpy as np
    torch, dev, cuda = torch_env()
    kind, repo, p = job["kind"], job["model"], job["params"]
    seed = int(p.get("seed", -1))
    if seed < 0:
        seed = random.randint(0, 2**31 - 1)
    job["seed"] = seed
    gen = torch.Generator("cpu").manual_seed(seed)
    prompt, neg = job["prompt"], p.get("negative", "")
    job["status"] = "loading"
    extra = (p.get("voice") or "af_heart")[0] if kind == "tts" and "kokoro" in repo.lower() else ""
    pipe = load(kind, repo, extra)
    job["status"] = "running"
    outs = []
    if kind == "tti":
        r = call_diffusers(pipe, job, dict(prompt=prompt, negative_prompt=neg or None, width=int(p.get("width", 1024)),
                                           height=int(p.get("height", 1024)), num_inference_steps=int(p.get("steps", 25)),
                                           guidance_scale=float(p.get("guidance", 5)), generator=gen,
                                           num_images_per_prompt=int(p.get("count", 1))))
        for i, img in enumerate(r.images):
            path = out_path("tti", "png", i)
            img.save(path)
            outs.append(path)
    elif kind == "ttv":
        from diffusers.utils import export_to_video
        from PIL import Image
        r = call_diffusers(pipe, job, dict(prompt=prompt, negative_prompt=neg or None, width=int(p.get("width", 832)),
                                           height=int(p.get("height", 480)), num_frames=int(p.get("frames", 33)),
                                           num_inference_steps=int(p.get("steps", 30)),
                                           guidance_scale=float(p.get("guidance", 5)), generator=gen))
        frames = r.frames[0]
        path = out_path("ttv", "mp4")
        export_to_video(frames, path, fps=int(p.get("fps", 16)))
        f0 = frames[0]
        if not isinstance(f0, Image.Image):
            a = np.asarray(f0)
            f0 = Image.fromarray((a * 255).clip(0, 255).astype("uint8") if a.dtype != np.uint8 else a)
        f0.save(path + ".jpg", quality=88)
        outs.append(path)
    elif kind == "tts":
        path = out_path("tts", "wav")
        if "kokoro" in repo.lower():
            parts = []
            for _, _, audio in pipe(prompt, voice=p.get("voice") or "af_heart", speed=float(p.get("speed", 1))):
                if job["cancel"]:
                    raise Cancelled()
                parts.append(np.asarray(audio))
            if not parts:
                raise RuntimeError("Kokoro produced no audio for this text")
            write_audio(path, np.concatenate(parts), 24000)
        else:
            r = pipe(prompt)
            write_audio(path, r["audio"], r["sampling_rate"])
        outs.append(path)
    elif kind == "tta":
        path = out_path("tta", "wav")
        dur = float(p.get("duration", 10))
        if hasattr(pipe, "components"):
            kw = dict(prompt=prompt, negative_prompt=neg or None, num_inference_steps=int(p.get("steps", 50)),
                      guidance_scale=float(p.get("guidance", 3.5)), generator=gen,
                      audio_length_in_s=dur, audio_end_in_s=dur)
            r = call_diffusers(pipe, job, kw)
            sr = getattr(getattr(pipe, "vae", None), "sampling_rate", None) or 16000
            write_audio(path, r.audios[0], sr)
        else:
            torch.manual_seed(seed)
            r = pipe(prompt, forward_params={"do_sample": True, "max_new_tokens": int(dur * 50),
                                             "guidance_scale": float(p.get("guidance", 3))})
            write_audio(path, r["audio"], r["sampling_rate"])
        outs.append(path)
    for o in outs:
        write_meta(o, job)
    job["outputs"] = outs


def worker():
    while True:
        job = job_queue.get()
        if job["cancel"]:
            job["status"] = "cancelled"
            continue
        gpu.busy = True
        job["t0"] = time.time()
        try:
            run_job(job)
            job["status"], job["progress"] = "done", 1.0
        except Cancelled:
            job["status"] = "cancelled"
        except Exception as e:
            traceback.print_exc()
            msg = str(e).strip().splitlines()[0] if str(e).strip() else type(e).__name__
            if "out of memory" in str(e).lower():
                msg = "Out of GPU memory: try a smaller size, fewer frames or a smaller model."
                gpu.unload()
            job["status"], job["error"] = "error", msg[:500]
        finally:
            job["seconds"] = round(time.time() - job["t0"], 1)
            gpu.busy = False


def submit(body):
    job = {"id": uuid.uuid4().hex[:10], "kind": body["kind"], "model": body["model"], "prompt": body.get("prompt", ""),
           "params": body.get("params", {}), "status": "queued", "progress": 0.0, "step": 0, "steps": 0,
           "outputs": [], "error": "", "cancel": False, "created": time.time(), "t0": time.time()}
    jobs[job["id"]] = job
    job_queue.put(job)
    return job


def list_outputs(kind, limit=200):
    d = os.path.join(OUT, kind)
    if not os.path.isdir(d):
        return []
    exts = {"tti": (".png", ".jpg", ".webp"), "ttv": (".mp4",), "tts": (".wav",), "tta": (".wav",)}[kind]
    files = sorted((f for f in os.listdir(d) if f.endswith(exts)), reverse=True)[:limit]
    out = []
    for f in files:
        path = os.path.join(d, f)
        meta = read_json(path + ".json") or {}
        out.append({"path": path, "name": f, "prompt": meta.get("prompt", ""), "model": meta.get("model", ""),
                    "seconds": meta.get("seconds"), "thumb": path + ".jpg" if kind == "ttv" else path,
                    "seed": (meta.get("params") or {}).get("seed")})
    return out


# ---------------------------------------------------------------- chat

def chat_stream(handler, body):
    if gpu.pipe is not None and not gpu.busy:
        gpu.unload()
    req = {"model": body["model"], "messages": body["messages"], "stream": True, "options": body.get("options") or {}}
    if body.get("think") is not None:
        req["think"] = bool(body["think"])
    handler.send_response(200)
    handler.send_header("Content-Type", "application/x-ndjson")
    handler.send_header("Cache-Control", "no-cache")
    handler.end_headers()

    def emit(obj):
        handler.wfile.write((json.dumps(obj) + "\n").encode())
        handler.wfile.flush()
    try:
        r = fetch(OLLAMA + "/api/chat", req, timeout=600, stream=True)
    except urllib.error.HTTPError as e:
        emit({"error": json.loads(e.read() or b"{}").get("error", str(e))})
        return
    except Exception as e:
        emit({"error": f"Ollama unreachable: {e}"})
        return
    with r:
        try:
            for line in r:
                ev = json.loads(line)
                if ev.get("error"):
                    emit({"error": ev["error"]})
                    break
                m = ev.get("message") or {}
                out = {"c": m.get("content", ""), "t": m.get("thinking", "")}
                if ev.get("done"):
                    out["done"] = True
                    out["tps"] = round(ev.get("eval_count", 0) / max(1e-9, ev.get("eval_duration", 1) / 1e9), 1)
                emit(out)
        except (BrokenPipeError, ConnectionResetError):
            pass


# ---------------------------------------------------------------- status

_gpu_cache = {"t": 0, "v": None}


def gpu_status():
    if time.time() - _gpu_cache["t"] < 2.5:
        return _gpu_cache["v"]
    v = None
    try:
        s = subprocess.run(["nvidia-smi", "--query-gpu=name,memory.used,memory.total,utilization.gpu",
                            "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=3).stdout
        name, used, total, util = [x.strip() for x in s.splitlines()[0].split(",")]
        v = {"name": name.replace("NVIDIA GeForce ", ""), "used": int(used), "total": int(total), "util": int(util)}
    except Exception:
        pass
    _gpu_cache.update(t=time.time(), v=v)
    return v


def public(d):
    return {k: v for k, v in d.items() if not k.startswith("_") and k != "cancel"}


def status():
    try:
        ver = ollama("/api/version", timeout=2).get("version")
    except Exception:
        ver = None
    recent = sorted(jobs.values(), key=lambda j: j["created"], reverse=True)[:30]
    return {"ok": True, "gpu": gpu_status(), "loaded": gpu.key[1] if gpu.key else None, "busy": gpu.busy,
            "ollama": ver, "hfToken": bool(hf_token()), "outputs": OUT,
            "downloads": [public(d) for d in sorted(downloads.values(), key=lambda d: d["started"], reverse=True)],
            "jobs": [public(j) for j in recent]}


# ---------------------------------------------------------------- server

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        pass

    def reply(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    def handle_err(self, fn):
        try:
            fn()
        except urllib.error.HTTPError as e:
            msg = f"HTTP {e.code}"
            if e.code in (401, 403):
                msg += ": gated or private repo, accept its license on huggingface.co and run `hf auth login`"
            elif e.code == 404:
                msg += ": not found"
            self.reply({"error": msg}, 502)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            traceback.print_exc()
            try:
                self.reply({"error": str(e) or type(e).__name__}, 500)
            except Exception:
                pass

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        routes = {
            "/status": lambda: status(),
            "/search": lambda: search(q["kind"], q.get("q", ""), q.get("sort")),
            "/info": lambda: repo_info(q["kind"], q["repo"]),
            "/local": lambda: local_models(q["kind"]),
            "/outputs": lambda: list_outputs(q["kind"]),
            "/job": lambda: public(jobs[q["id"]]),
        }
        if u.path not in routes:
            return self.reply({"error": "not found"}, 404)
        self.handle_err(lambda: self.reply(routes[u.path]()))

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path

        def run():
            b = self.body()
            if path == "/chat":
                return chat_stream(self, b)
            if path == "/download":
                return self.reply(public(start_download(b)))
            if path == "/download/cancel":
                d = downloads.get(b["id"])
                if d:
                    d["cancel"] = True
                    if d.get("_resp"):
                        try:
                            d["_resp"].close()
                        except Exception:
                            pass
                return self.reply({"ok": True})
            if path == "/download/clear":
                for k in [k for k, d in downloads.items() if d["status"] in ("done", "error", "cancelled")]:
                    downloads.pop(k)
                return self.reply({"ok": True})
            if path == "/delete":
                delete_model(b["kind"], b["id"])
                return self.reply({"ok": True})
            if path == "/generate":
                return self.reply(public(submit(b)))
            if path == "/cancel":
                if b.get("id") in jobs:
                    jobs[b["id"]]["cancel"] = True
                return self.reply({"ok": True})
            if path == "/unload":
                if not gpu.busy:
                    gpu.unload()
                ollama_unload_all()
                return self.reply({"ok": True})
            if path == "/outputs/delete":
                p = os.path.realpath(b["path"])
                if not p.startswith(os.path.realpath(OUT) + os.sep):
                    return self.reply({"error": "outside outputs"}, 400)
                for f in (p, p + ".json", p + ".jpg"):
                    if os.path.exists(f):
                        os.remove(f)
                return self.reply({"ok": True})
            self.reply({"error": "not found"}, 404)
        self.handle_err(run)


def main():
    threading.Thread(target=worker, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    srv.daemon_threads = True
    log(f"noctai backend on http://127.0.0.1:{PORT}  outputs: {OUT}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
