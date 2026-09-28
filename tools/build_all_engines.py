# -*- coding: utf-8 -*-
"""
==============================================================================
   TensorRT Engine Pre-Compiler for RIFE v2 Models
   Pre-builds optimized static engines for 1080p, 720p, or 4K resolutions
   across selected or all 4 modern RIFE models.
==============================================================================
"""

import os
import sys
import time
import json

# Ensure UTF-8 console output
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Determine root directory (handles being placed in tools/ or in root)
current_dir = os.path.dirname(os.path.abspath(__file__))
if os.path.isdir(os.path.join(current_dir, "vs")):
    root_dir = current_dir
else:
    root_dir = os.path.abspath(os.path.join(current_dir, ".."))

vs_dir = os.path.join(root_dir, "vs")
# Purge external system python paths from sys.path
vs_lower = vs_dir.lower()
sys.path = [p for p in sys.path if not (("python" in os.path.normpath(p).lower() or "site-packages" in os.path.normpath(p).lower()) and not os.path.normpath(p).lower().startswith(vs_lower))]
if vs_dir not in sys.path:
    sys.path.insert(0, vs_dir)

site_packages = os.path.join(vs_dir, "Lib", "site-packages")
if os.path.isdir(site_packages) and site_packages not in sys.path:
    sys.path.insert(0, site_packages)

cuda_dir = os.path.join(vs_dir, "vs-plugins", "vsmlrt-cuda")
plugins_dir = os.path.join(vs_dir, "vs-plugins")
models_path = os.path.join(vs_dir, "vs-plugins", "models")

if sys.platform == "win32":
    os.environ["PATH"] = cuda_dir + os.pathsep + plugins_dir + os.pathsep + vs_dir + os.pathsep + os.environ.get("PATH", "")
    if hasattr(os, "add_dll_directory"):
        for d in (cuda_dir, plugins_dir, vs_dir):
            if os.path.isdir(d):
                try:
                    os.add_dll_directory(d)
                except Exception:
                    pass

print("\n" + "=" * 75)
print("  NVIDIA TensorRT Engine Pre-Compiler for RIFE (v2 Architecture)")
print("=" * 75)

try:
    import vapoursynth as vs  # type: ignore
    from vapoursynth import core  # type: ignore
    import vsmlrt  # type: ignore
except Exception as e:
    print(f"\n[ERROR] Failed to load VapourSynth or vsmlrt: {e}")
    sys.exit(1)

# Enforce strictly portable paths on vsmlrt runtime
vsmlrt.plugins_path = plugins_dir
vsmlrt.trtexec_path = os.path.join(cuda_dir, "trtexec.exe" if sys.platform == "win32" else "trtexec")
vsmlrt.models_path = models_path
engines_dir = os.path.join(models_path, "rife_v2", "engines")
os.makedirs(engines_dir, exist_ok=True)

# 4 Newest RIFE Models
ALL_MODELS = [
    {"num": 1, "id": 425,  "name": "RIFE v4.25 (Highest Quality / Detail)", "file": "rife_v4.25_v2.onnx"},
    {"num": 2, "id": 4251, "name": "RIFE v4.25 Lite (Fast & Detailed)",      "file": "rife_v4.25_lite_v2.onnx"},
    {"num": 3, "id": 4221, "name": "RIFE v4.22 Lite (Balanced)",             "file": "rife_v4.22_lite_v2.onnx"},
    {"num": 4, "id": 4171, "name": "RIFE v4.17 Lite (Ultra Fast / Lightweight)", "file": "rife_v4.17_lite_v2.onnx"},
]

def is_model_on_disk(model_dict):
    p = os.path.join(models_path, "rife_v2", model_dict["file"])
    return os.path.isfile(p) and os.path.getsize(p) > 1024 * 1024

# Check if a single model is requested via --model <num>
selected_model_num = None
for i, arg in enumerate(sys.argv):
    if arg == "--model" and i + 1 < len(sys.argv):
        try:
            val = int(sys.argv[i + 1])
            if val in (1, 2, 3, 4):
                selected_model_num = val
            elif val == 425:  selected_model_num = 1
            elif val == 4251: selected_model_num = 2
            elif val == 4221: selected_model_num = 3
            elif val == 4171: selected_model_num = 4
        except ValueError:
            pass

if selected_model_num is not None:
    candidate_models = [m for m in ALL_MODELS if m["num"] == selected_model_num]
else:
    candidate_models = ALL_MODELS

TARGET_MODELS = [m for m in candidate_models if is_model_on_disk(m)]
skipped_models = [m for m in candidate_models if not is_model_on_disk(m)]

if skipped_models:
    print("\n[INFO] Skipped models (not present in models/rife_v2):")
    for sm in skipped_models:
        print(f"  - Model {sm['num']}: {sm['name']} ({sm['file']})")

if len(TARGET_MODELS) == 0:
    print("\n[WARNING] None of the requested RIFE model files exist on disk.")
    print("Exiting cleanly without build errors.\n")
    sys.exit(0)

# Resolution targets based on flags
# [ملاحظة: تم تعطيل خيار بناء محركات 4K مؤقتاً لثقل المعالجة الفائق وعدم استقراره على كروت الشاشة حتى RTX 5080]
if "--4k" in sys.argv:
    print("\n" + "=" * 78)
    print("  [NOTICE] 4K Engine Build is temporarily disabled.")
    print("  Real-time 4K RIFE interpolation exceeds real-time budget on modern GPUs.")
    print("  Please use 1080p Downscale (UHD Mode 2) for smooth real-time AI playback.")
    print("=" * 78 + "\n")
    sys.exit(0)
elif "--all" in sys.argv:
    RESOLUTIONS = [
        {"name": "1080p (Full HD & UHD Mode 2)", "width": 1920, "height": 1088},
        {"name": "720p (HD & SD Formats)",        "width": 1280, "height": 768},
        # [ملاحظة: تم تعطيل 4K مؤقتاً]
        # {"name": "4K Ultra HD (Native 4K RIFE)", "width": 3840, "height": 2176},
    ]
    mode_desc = f"Full Comprehensive Build (1080p + 720p across {len(TARGET_MODELS)} model(s))"
else:
    RESOLUTIONS = [
        {"name": "1080p (Full HD & UHD Mode 1)", "width": 1920, "height": 1088},
        {"name": "720p (HD & SD Formats)",        "width": 1280, "height": 768},
    ]
    if len(TARGET_MODELS) == 1:
        mode_desc = f"Single Model Build (1080p + 720p for {TARGET_MODELS[0]['name']})"
    else:
        mode_desc = "Standard Fast Build (1080p + 720p across all 4 RIFE models)"

total_targets = len(TARGET_MODELS) * len(RESOLUTIONS)
MAX_TIME_PER_ENGINE = 120.0 if "--4k" in sys.argv else 90.0
EST_TOTAL_MINUTES = max(1, int((total_targets * MAX_TIME_PER_ENGINE) / 60.0))

print(f"\n[Target Mode]             : {mode_desc}")
print(f"[Target Engines Directory]: {engines_dir}")
print(f"[Total Target Builds]     : {total_targets} engine(s) ({len(TARGET_MODELS)} Model(s) x {len(RESOLUTIONS)} Resolution(s))")
print("---------------------------------------------------------------------------")
print(" [ESTIMATED TIME]:")
print(f"  * First-Time Build (No local cache) : ~{EST_TOTAL_MINUTES} Minute(s) (~{int(MAX_TIME_PER_ENGINE)}s per engine)")
print("  * Already Cached (Verified in cache): ~1 - 2 Seconds (Instant check)")
print("---------------------------------------------------------------------------\n")

# Automatically purge any incompatible engines built with different TensorRT versions
try:
    curr_trt = int(core.trt.Version()["tensorrt_version"])
    curr_maj, curr_mnr, curr_pch = curr_trt // 10000, (curr_trt % 10000) // 100, curr_trt % 100
    if os.path.isdir(engines_dir):
        for ef in os.listdir(engines_dir):
            if ef.endswith(".engine"):
                ep = os.path.join(engines_dir, ef)
                try:
                    with open(ep, "rb") as ef_obj:
                        header = ef_obj.read(32)
                        if len(header) >= 28 and header[:4] == b"ftrt":
                            if (header[24], header[25], header[26]) != (curr_maj, curr_mnr, curr_pch):
                                print(f"[AUTO-FIX] Removing incompatible engine: {ef} (TRT {header[24]}.{header[25]}.{header[26]} != current {curr_maj}.{curr_mnr}.{curr_pch})")
                                os.remove(ep)
                                if os.path.exists(ep + ".cache"):
                                    os.remove(ep + ".cache")
                except Exception:
                    pass
except Exception:
    pass

overall_start = time.time()
current_idx = 0
compiled_count = 0
cached_count = 0

for model in TARGET_MODELS:
    print("-" * 75)
    print(f" Model [{model['num']}/4]: {model['name']} (ID: {model['id']})")
    print("-" * 75)

    for res in RESOLUTIONS:
        current_idx += 1
        remaining_targets = total_targets - current_idx
        est_remaining_seconds = remaining_targets * MAX_TIME_PER_ENGINE

        print(f"  [{current_idx}/{total_targets}] {res['name']} ({res['width']}x{res['height']})...", end="", flush=True)

        start_time = time.time()
        try:
            clip = core.std.BlankClip(format=vs.RGBH, width=res['width'], height=res['height'], length=2)

            out = vsmlrt.RIFE(
                clip,
                multi=2,
                model=model['id'],
                _implementation=2,
                backend=vsmlrt.Backend.TRT(
                    fp16=True,
                    use_cuda_graph=False,
                    static_shape=True,
                    num_streams=2,
                    output_format=1, # FP16
                    log=False,
                    engine_folder=engines_dir
                )
            )

            # Trigger compilation or instant cache load on interpolated frame (frame 1)
            _ = out.get_frame(1)
            elapsed = time.time() - start_time

            if elapsed < 2.5:
                cached_count += 1
                print(f" [ALREADY CACHED] (Verified in {elapsed:.2f}s)")
            else:
                compiled_count += 1
                rem_min = int(est_remaining_seconds // 60)
                rem_sec = int(est_remaining_seconds % 60)
                eta_str = f"~{rem_min}m {rem_sec:02d}s" if remaining_targets > 0 else "0s"
                print(f" [SUCCESS] (Built in {elapsed:.1f}s | Max ETA Remaining: {eta_str})")

        except Exception as err:
            err_str = str(err)
            if "deserialization failed" in err_str.lower() or "not compatible" in err_str.lower():
                print(f" [REBUILDING]: Incompatible/corrupted engine detected in cache...", flush=True)
                # Purge incompatible engine and rebuild immediately
                try:
                    curr_trt = int(core.trt.Version()["tensorrt_version"])
                    curr_maj, curr_mnr, curr_pch = curr_trt // 10000, (curr_trt % 10000) // 100, curr_trt % 100
                    for ef in os.listdir(engines_dir):
                        if ef.endswith(".engine"):
                            ep = os.path.join(engines_dir, ef)
                            try:
                                with open(ep, "rb") as ef_obj:
                                    header = ef_obj.read(32)
                                    if len(header) >= 28 and header[:4] == b"ftrt":
                                        if (header[24], header[25], header[26]) != (curr_maj, curr_mnr, curr_pch):
                                            os.remove(ep)
                                            if os.path.exists(ep + ".cache"):
                                                os.remove(ep + ".cache")
                            except Exception:
                                pass
                    out = vsmlrt.RIFE(
                        clip,
                        multi=2,
                        model=model['id'],
                        _implementation=2,
                        backend=vsmlrt.Backend.TRT(
                            fp16=True,
                            use_cuda_graph=False,
                            static_shape=True,
                            num_streams=2,
                            output_format=1,
                            log=False,
                            engine_folder=engines_dir
                        )
                    )
                    _ = out.get_frame(1)
                    elapsed = time.time() - start_time
                    compiled_count += 1
                    print(f" [SUCCESS - REBUILT] (Cleanly built in {elapsed:.1f}s)")
                except Exception as retry_err:
                    print(f" [FAILED]: {retry_err}")
            else:
                print(f" [FAILED]: {err}")

total_elapsed = time.time() - overall_start
total_min = int(total_elapsed // 60)
total_sec = int(total_elapsed % 60)

print("\n" + "=" * 75)
print(f"  Target TensorRT Engines are Ready! (Total Time: {total_min}m {total_sec:02d}s)")
print("=" * 75)

# Clean up empty files from aborted builds and list generated engines
engine_files = []
for f in os.listdir(engines_dir):
    if f.endswith(".engine"):
        p = os.path.join(engines_dir, f)
        if os.path.getsize(p) == 0:
            try:
                os.remove(p)
            except Exception:
                pass
        else:
            engine_files.append(f)

print(f"\n[Engines in Cache]: {len(engine_files)} files in {engines_dir}")
for ef in engine_files:
    size_mb = os.path.getsize(os.path.join(engines_dir, ef)) / (1024 * 1024)
    print(f"  - {ef} ({size_mb:.2f} MB)")

print(f"\nStatus: {cached_count} verified from cache, {compiled_count} newly compiled.")
print("You can now launch MPV with instant RIFE AI playback!\n")

# Automatically generate or update engines_manifest.json for all models
def update_engines_manifest():
    manifest_file = os.path.join(root_dir, "mpv", "portable_config", "engines_manifest.json")
    try:
        trt_ver = vsmlrt.parse_trt_version(int(core.trt.Version()["tensorrt_version"]))
        dev_name = core.trt.DeviceProperties(0)["name"].decode().replace(' ', '-')
        manifest = {"models": {}, "device": dev_name}
        
        check_resolutions = [
            ("1080p", 1920, 1088),
            ("720p", 1280, 768),
            ("4k", 3840, 2176)
        ]
        
        for m in ALL_MODELS:
            mid = m["id"]
            num = m["num"]
            name = m["name"]
            model_major = int(str(mid)[0])
            model_minor = int(str(mid)[1:3])
            rife_type = "_lite" if len(str(mid)) >= 4 and str(mid)[-1] == '1' else ''
            version = f"v{model_major}.{model_minor}{rife_type}"
            network_path = os.path.join(vsmlrt.models_path, "rife_v2", f"rife_{version}_v2.onnx")
            
            m_dict = {"id": mid, "name": name, "resolutions": {}}
            for rname, w, h in check_resolutions:
                ep = vsmlrt.get_engine_path(
                    network_path=network_path,
                    min_shapes=(w, h), opt_shapes=(w, h), max_shapes=(w, h),
                    workspace=None, fp16=True, use_cublas=False, static_shape=True,
                    tf32=False, use_cudnn=False, input_format=1, output_format=1,
                    builder_optimization_level=3, max_aux_streams=None, short_path=True,
                    bf16=False, engine_folder=engines_dir,
                    trt_version=trt_ver, device_name=dev_name
                )
                cached = os.path.isfile(ep) and os.path.getsize(ep) > 1024 * 1024
                m_dict["resolutions"][rname] = {
                    "file": os.path.basename(ep),
                    "cached": cached
                }
            m_dict["base_ready"] = m_dict["resolutions"]["1080p"]["cached"] and m_dict["resolutions"]["720p"]["cached"]
            m_dict["4k_ready"] = m_dict["resolutions"]["4k"]["cached"]
            manifest["models"][str(num)] = m_dict
            
        with open(manifest_file, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
        print(f"[Manifest Updated]: Successfully synchronized status in {manifest_file}\n")
    except Exception as e:
        print(f"! Warning: Failed to update engines_manifest.json: {e}\n")

update_engines_manifest()


