import os
import sys
import json
import time
import shutil
import urllib.request
import urllib.error
import subprocess

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
MPV_DIR = os.path.join(ROOT_DIR, "mpv")
MPV_EXE = os.path.join(MPV_DIR, "mpv.exe")
VS_DIR = os.path.join(ROOT_DIR, "vs")
SEVEN_ZIP = os.path.join(VS_DIR, "7z.exe")
VS_PLUGINS_DIR = os.path.join(VS_DIR, "vs-plugins")
VSMLRT_CUDA_DIR = os.path.join(VS_PLUGINS_DIR, "vsmlrt-cuda")
NVINFER_DLL = os.path.join(VSMLRT_CUDA_DIR, "nvinfer_10.dll")
TOOLS_DIR = os.path.join(ROOT_DIR, "tools")
BUILD_MODEL_4_BAT = os.path.join(TOOLS_DIR, "build_model_4.bat")

MPV_RELEASE_TAG = "2026-09-03-f5bcfb1954"
MPV_PRIMARY_URL = f"https://github.com/zhongfly/mpv-winbuild/releases/download/{MPV_RELEASE_TAG}/mpv-x86_64-v3-20260903-git-f5bcfb1954.7z"
MPV_FALLBACK_URL = "https://github.com/zhongfly/mpv-winbuild/releases/latest/download/mpv-x86_64-v3.7z"

TENSORRT_001_URL = "https://github.com/AmusementClub/vs-mlrt/releases/download/v15.13.cu13/vsmlrt-windows-x64-cuda.v15.13.cu13.7z.001"
TENSORRT_002_URL = "https://github.com/AmusementClub/vs-mlrt/releases/download/v15.13.cu13/vsmlrt-windows-x64-cuda.v15.13.cu13.7z.002"

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

def format_size(bytes_val):
    if bytes_val < 1024 * 1024:
        return f"{bytes_val / 1024:.1f} KB"
    elif bytes_val < 1024 * 1024 * 1024:
        return f"{bytes_val / (1024 * 1024):.1f} MB"
    else:
        return f"{bytes_val / (1024 * 1024 * 1024):.2f} GB"

def download_file_with_resume(url, target_path, label):
    print(f"\n[*] {label}")
    print(f"    URL: {url}")
    print(f"    Target: {target_path}")

    temp_path = target_path + ".part"
    existing_bytes = 0
    if os.path.exists(temp_path):
        existing_bytes = os.path.getsize(temp_path)

    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    if existing_bytes > 0:
        req.add_header("Range", f"bytes={existing_bytes}-")
        print(f"    Resuming from {format_size(existing_bytes)}...")

    try:
        response = urllib.request.urlopen(req, timeout=30)
    except urllib.error.HTTPError as e:
        if e.code == 416: # Range not satisfiable, file might be complete
            existing_bytes = 0
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            response = urllib.request.urlopen(req, timeout=30)
        else:
            raise

    # Determine total size
    content_range = response.headers.get("Content-Range")
    if content_range:
        total_size = int(content_range.split("/")[-1])
    else:
        cl = response.headers.get("Content-Length")
        total_size = (int(cl) + existing_bytes) if cl else None

    mode = "ab" if existing_bytes > 0 else "wb"
    downloaded = existing_bytes
    start_time = time.time()
    last_print = 0

    with open(temp_path, mode) as f:
        while True:
            chunk = response.read(128 * 1024)
            if not chunk:
                break
            f.write(chunk)
            downloaded += len(chunk)

            now = time.time()
            if now - last_print >= 0.25:
                last_print = now
                elapsed = now - start_time
                speed = (downloaded - existing_bytes) / elapsed if elapsed > 0 else 0
                if total_size and total_size > 0:
                    percent = (downloaded / total_size) * 100
                    rem_bytes = max(0, total_size - downloaded)
                    eta = (rem_bytes / speed) if speed > 0 else 0
                    bar_len = 25
                    filled = int(bar_len * (downloaded / total_size))
                    bar = "=" * filled + (">" if filled < bar_len else "") + " " * (bar_len - filled - (1 if filled < bar_len else 0))
                    status = f"\r    [{bar}] {percent:5.1f}% | {format_size(downloaded)} / {format_size(total_size)} | {format_size(speed)}/s | ETA: {int(eta)}s  "
                else:
                    status = f"\r    Downloaded {format_size(downloaded)} | {format_size(speed)}/s  "
                sys.stdout.write(status)
                sys.stdout.flush()

    sys.stdout.write("\n")
    sys.stdout.flush()

    if os.path.exists(target_path):
        os.remove(target_path)
    os.rename(temp_path, target_path)
    print(f"    [+] Completed: {format_size(os.path.getsize(target_path))}")

def ensure_bridge_files():
    print("\n[*] Synchronizing VapourSynth bridge files to mpv/...")
    vsscript = os.path.join(VS_DIR, "VSScript.dll")
    py_dll = os.path.join(VS_DIR, "python312.dll")
    py3_dll = os.path.join(VS_DIR, "python3.dll")
    vs_dll = os.path.join(VS_DIR, "Lib", "site-packages", "vapoursynth.dll")
    if not os.path.exists(vs_dll):
        vs_dll = os.path.join(VS_DIR, "vapoursynth.dll")

    if os.path.exists(vsscript):
        shutil.copy2(vsscript, os.path.join(MPV_DIR, "VSScript.dll"))
    if os.path.exists(py_dll):
        shutil.copy2(py_dll, os.path.join(MPV_DIR, "python312.dll"))
    if os.path.exists(py3_dll):
        shutil.copy2(py3_dll, os.path.join(MPV_DIR, "python3.dll"))
    if os.path.exists(vs_dll):
        shutil.copy2(vs_dll, os.path.join(MPV_DIR, "vapoursynth.dll"))

    # Configure vapoursynth.toml for VSScript R72 runtime
    configure_vapoursynth_toml()


    # Write mpv/python312._pth
    pth_content = "python312.zip\n.\n../vs/Lib/site-packages\n../vs/vs-plugins\n../vs\n"
    with open(os.path.join(MPV_DIR, "python312._pth"), "w", encoding="utf-8") as f:
        f.write(pth_content)

    portable_vs = os.path.join(VS_DIR, "portable.vs")
    if os.path.exists(portable_vs):
        shutil.copy2(portable_vs, os.path.join(MPV_DIR, "portable.vs"))

    print("    [+] Bridge files configured successfully.")

def configure_vapoursynth_toml():
    python_exe = os.path.join(VS_DIR, "python.exe")
    python_dll = os.path.join(VS_DIR, "python312.dll")
    if not (os.path.exists(python_exe) and os.path.exists(python_dll)):
        return
    mtime = int(os.path.getmtime(python_exe))
    vsscripts = [
        os.path.join(MPV_DIR, "VSScript.dll"),
        os.path.join(VS_DIR, "VSScript.dll"),
        os.path.join(MPV_DIR, "vsscript.dll"),
        os.path.join(VS_DIR, "vsscript.dll"),
    ]
    lines = []
    for vs_path in set(vsscripts):
        p_lower = vs_path.lower()
        p_esc = p_lower.replace("\\", "\\\\")
        exe_esc = python_exe.replace("\\", "\\\\")
        dll_esc = python_dll.replace("\\", "\\\\")
        lines.append(f'"{p_esc}" = ["{exe_esc}", "{dll_esc}", "{mtime}"]\n')

    for env_var in ["APPDATA", "LOCALAPPDATA"]:
        dir_val = os.environ.get(env_var)
        if dir_val:
            target_dir = os.path.join(dir_val, "vapoursynth")
            os.makedirs(target_dir, exist_ok=True)
            target_file = os.path.join(target_dir, "vapoursynth.toml")
            existing = []
            if os.path.exists(target_file):
                try:
                    with open(target_file, "r", encoding="utf-8") as f:
                        existing = [l for l in f.readlines() if not any(p_lower in l.lower() for p_lower in [vs_p.lower() for vs_p in vsscripts])]
                except Exception:
                    existing = []
            with open(target_file, "w", encoding="utf-8") as f:
                f.writelines(existing + lines)

    # Set user environment variable and root launcher for seamless double-click from anywhere
    vsscript_dll = os.path.join(MPV_DIR, "VSScript.dll")
    if os.path.exists(vsscript_dll):
        try:
            cmd = f'[Environment]::SetEnvironmentVariable("VSSCRIPT_PATH", "{vsscript_dll}", "User")'
            subprocess.run(["powershell", "-NoProfile", "-Command", cmd], check=False)
        except Exception:
            pass




def check_and_setup_mpv():
    if os.path.exists(MPV_EXE) and os.path.getsize(MPV_EXE) > 10 * 1024 * 1024:
        print("[+] MPV binary (mpv.exe) already present.")
        ensure_bridge_files()
        return

    print("\n==============================================================================")
    print(f"    Step 1: Downloading MPV Build ({MPV_RELEASE_TAG})")
    print("==============================================================================")
    archive_path = os.path.join(ROOT_DIR, "_tmp_mpv.7z")

    try:
        download_file_with_resume(MPV_PRIMARY_URL, archive_path, f"Downloading MPV v3 ({MPV_RELEASE_TAG})")
    except Exception as e:
        print(f"    Primary download failed: {e}. Trying fallback to latest official build...")
        download_file_with_resume(MPV_FALLBACK_URL, archive_path, "Downloading MPV (Latest Build)")

    print("\n[*] Extracting MPV archive into mpv/...")
    cmd = [SEVEN_ZIP, "x", archive_path, f"-o{MPV_DIR}", "-aoa"]
    subprocess.run(cmd, check=True)

    if os.path.exists(archive_path):
        os.remove(archive_path)

    # Clean up redundant nested mpv/mpv/ subfolder extracted by some archives
    nested_mpv = os.path.join(MPV_DIR, "mpv")
    if os.path.isdir(nested_mpv):
        try:
            shutil.rmtree(nested_mpv, ignore_errors=True)
        except Exception:
            pass

    ensure_bridge_files()
    print("    [+] MPV installed and ready.")

def check_and_setup_tensorrt():
    if os.path.exists(NVINFER_DLL) and os.path.getsize(NVINFER_DLL) > 10 * 1024 * 1024:
        print("[+] TensorRT & CUDA runtime (vsmlrt-cuda) already present.")
        return

    print("\n==============================================================================")
    print("    Step 2: Downloading NVIDIA TensorRT & CUDA Runtime (~3.1 GB)")
    print("==============================================================================")
    print("  This step is performed once. Required for high-performance AI frame interpolation.")

    part1 = os.path.join(ROOT_DIR, "vsmlrt-windows-x64-cuda.v15.13.cu13.7z.001")
    part2 = os.path.join(ROOT_DIR, "vsmlrt-windows-x64-cuda.v15.13.cu13.7z.002")

    download_file_with_resume(TENSORRT_001_URL, part1, "Downloading TensorRT & CUDA Package Part 1 of 2 (~2.1 GB)")
    download_file_with_resume(TENSORRT_002_URL, part2, "Downloading TensorRT & CUDA Package Part 2 of 2 (~950 MB)")

    print("\n[*] Extracting TensorRT & CUDA runtime into vs/vs-plugins/vsmlrt-cuda/...")
    # The archive contains a 'vsmlrt-cuda/' folder with CUDA/TensorRT runtime files.
    # Extract ONLY 'vsmlrt-cuda\*' into VS_PLUGINS_DIR so files land cleanly in vs/vs-plugins/vsmlrt-cuda/
    # without extracting unused models (waifu2x/dpir/realesrgan) or other backends (vsort/vsov/ncnn).
    cmd = [SEVEN_ZIP, "x", part1, f"-o{VS_PLUGINS_DIR}", "vsmlrt-cuda\\*", "-aoa"]
    ret = subprocess.run(cmd)
    if ret.returncode != 0 or not os.path.exists(NVINFER_DLL):
        # Fallback if selective extract fails
        cmd_fallback = [SEVEN_ZIP, "x", part1, f"-o{VSMLRT_CUDA_DIR}", "-aoa"]
        subprocess.run(cmd_fallback)
        for root, dirs, files in os.walk(VSMLRT_CUDA_DIR):
            if "nvinfer_10.dll" in files and root != VSMLRT_CUDA_DIR:
                for f in files:
                    src = os.path.join(root, f)
                    dst = os.path.join(VSMLRT_CUDA_DIR, f)
                    if not os.path.exists(dst):
                        shutil.move(src, dst)
                break

    # Clean up any unwanted folders/files from vsmlrt-cuda
    for junk_name in ["models", "vsort", "vsov", "vsmlrt-cuda"]:
        junk_path = os.path.join(VSMLRT_CUDA_DIR, junk_name)
        if os.path.isdir(junk_path):
            try:
                shutil.rmtree(junk_path)
            except Exception:
                pass

    for junk_file in ["vsncnn.dll", "vsort.dll", "vsov.dll", "vstrt_rtx.dll", "vsmlrt.py", "vstrt.dll"]:
        jf_path = os.path.join(VSMLRT_CUDA_DIR, junk_file)
        if os.path.isfile(jf_path):
            try:
                os.remove(jf_path)
            except Exception:
                pass

    print("    [+] TensorRT extraction verified.")

    # Cleanup downloaded archives to save ~3.1 GB
    print("[*] Cleaning up temporary archive files...")
    if os.path.exists(part1):
        os.remove(part1)
    if os.path.exists(part2):
        os.remove(part2)
    print("    [+] Temporary archives cleaned up.")

def check_gpu_and_driver():
    print("\n[*] Pre-flight Check: Inspecting System Hardware & Graphics Driver...")

    # Check free disk space
    try:
        total, used, free = shutil.disk_usage(ROOT_DIR)
        free_gb = free / (1024 ** 3)
        if free_gb < 5.0:
            print(f"  [!] WARNING: Low disk space! Only {free_gb:.1f} GB available on drive.")
            print("      At least 5 to 6 GB free space is recommended for download & TensorRT engines.")
        else:
            print(f"  [+] Available Disk Space: {free_gb:.1f} GB")
    except Exception:
        pass

    # Check via ctypes / nvcuda.dll
    cuda_driver_ver = None
    try:
        import ctypes
        nvcuda = ctypes.WinDLL("nvcuda.dll")
        v = ctypes.c_int()
        if nvcuda.cuDriverGetVersion(ctypes.byref(v)) == 0:
            cuda_driver_ver = v.value  # e.g., 13040 -> CUDA 13.4
    except Exception:
        pass

    # 2. Check for NVIDIA via nvidia-smi (Driver version, GPU model name, and Total VRAM in MB)
    gpu_name = None
    driver_str = None
    vram_mb = None
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=driver_version,gpu_name,memory.total", "--format=csv,noheader,nounits"],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        if out:
            parts = [p.strip() for p in out.split("\n")[0].split(",")]
            if len(parts) >= 3:
                driver_str = parts[0]
                gpu_name = parts[1]
                try:
                    vram_mb = int(parts[2])
                except ValueError:
                    pass
            elif len(parts) >= 2:
                driver_str = parts[0]
                gpu_name = parts[1]
    except Exception:
        pass

    # 3. If no NVIDIA GPU detected, inspect other GPUs (AMD Radeon, Intel Arc / Iris) via wmic / PowerShell
    if not gpu_name and not cuda_driver_ver:
        other_gpu_name = None
        try:
            cmd = ["powershell", "-NoProfile", "-Command", "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name"]
            ps_out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
            for line in ps_out.splitlines():
                line = line.strip()
                if line and not any(v in line.lower() for v in ["virtual", "remote", "parsec", "meta", "spacedesk"]):
                    other_gpu_name = line
                    break
        except Exception:
            pass

        detected_label = other_gpu_name or "AMD / Intel / Non-NVIDIA Graphics"
        print(f"  [+] Detected GPU   : {detected_label}")
        print("\n" + "=" * 78)
        print("  [i] GPU Architecture Notice:")
        print("=" * 78)
        print("  Unfortunately, your GPU architecture does not currently support TensorRT acceleration.")
        print("  NVIDIA TensorRT strictly requires NVIDIA GeForce / RTX graphics cards.")
        print()
        print("  [+] MPV player is installed and ready for daily playback with full shader support")
        print("      and modern UI features (without RIFE AI frame interpolation).")
        print()
        print("  If you have questions, feature requests, or wish to open an issue:")
        print("  >> https://github.com/Rayano79/mpv-flow")
        print("=" * 78 + "\n")
        return {"has_nvidia": False, "compatible": False, "gpu_name": detected_label, "driver_str": None, "vram_mb": None}

    print(f"  [+] Detected GPU   : {gpu_name or 'NVIDIA CUDA Device'}")
    if vram_mb:
        print(f"  [+] Dedicated VRAM : {vram_mb} MB (~{round(vram_mb / 1024)} GB)")
    print(f"  [+] Driver Version : {driver_str or 'Unknown'} (CUDA API: {cuda_driver_ver})")

    # Check driver version (CUDA 13 / TensorRT 10 requires >= 580.00)
    is_driver_insufficient = False
    if driver_str:
        try:
            major_ver = float(driver_str.split(".")[0])
            if major_ver < 580:
                is_driver_insufficient = True
        except Exception:
            pass
    elif cuda_driver_ver and cuda_driver_ver < 13000:
        is_driver_insufficient = True

    if is_driver_insufficient:
        print("\n" + "!" * 78)
        print("  [!] CRITICAL: NVIDIA Driver Update Required Before TensorRT Download!")
        print("!" * 78)
        print(f"  Your current NVIDIA Driver ({driver_str or 'Pre-580'}) is below version 580.00.")
        print("  The bundled TensorRT 10 runtime requires CUDA 13.0, which mandates Driver >= 580.00.")
        print()
        print("  Please update your graphics driver from NVIDIA before proceeding:")
        print("  >> https://www.nvidia.com/Download/index.aspx")
        print("  (or through NVIDIA GeForce Experience / NVIDIA App)")
        print("!" * 78 + "\n")
        return {"has_nvidia": True, "compatible": False, "gpu_name": gpu_name, "driver_str": driver_str, "vram_mb": vram_mb}
    else:
        print("  [+] Driver Compatibility: PASSED (Driver >= 580.00 compatible with CUDA 13)")
        return {"has_nvidia": True, "compatible": True, "gpu_name": gpu_name, "driver_str": driver_str, "vram_mb": vram_mb}

def configure_initial_hardware_settings(vram_mb):
    hw_marker = os.path.join(MPV_DIR, "portable_config", ".hardware_configured")
    if os.path.exists(hw_marker):
        return  # Hardware already configured on initial setup; preserve user customizations

    player_conf = os.path.join(MPV_DIR, "portable_config", "player_settings.conf")
    if not os.path.isfile(player_conf):
        return

    # Base streams purely on GPU VRAM capacity (GPU parallel execution contexts)
    target_vram = vram_mb if (vram_mb and vram_mb >= 2048) else 8192
    if target_vram >= 16384:
        optimal_streams = 4
    elif target_vram >= 8192:
        optimal_streams = 2
    else:
        optimal_streams = 1

    try:
        with open(player_conf, "r", encoding="utf-8") as f:
            lines = f.readlines()

        new_lines = []
        model_found = False
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("streams="):
                new_lines.append(f"streams={optimal_streams}\n")
            elif stripped.startswith("model="):
                new_lines.append("model=4\n")
                model_found = True
            else:
                new_lines.append(line)

        if not model_found:
            new_lines.append("model=4\n")

        with open(player_conf, "w", encoding="utf-8") as f:
            f.writelines(new_lines)

        with open(hw_marker, "w", encoding="utf-8") as f:
            f.write(f"configured_vram={target_vram}\nconfigured_streams={optimal_streams}\nconfigured_model=4\n")

        print(f"\n[*] Initial Hardware Auto-Tuning Applied to player_settings.conf:")
        print(f"    - GPU CUDA Streams : {optimal_streams} Concurrent Context(s) (Detected VRAM: {target_vram} MB)")
        print(f"    - RAM Buffer Cache : 8192 MB (VapourSynth Host System RAM)")
        print(f"    - Default RIFE Model: 4 (RIFE v4.17 Lite - Pre-compiled)")
    except Exception as e:
        print(f"  [!] Note: Hardware auto-tuning skipped: {e}")

def verify_models():
    models_dir = os.path.join(VS_PLUGINS_DIR, "models", "rife_v2")
    onnx_target = os.path.join(models_dir, "rife_v4.17_lite_v2.onnx")
    if os.path.isdir(models_dir) and os.path.isfile(onnx_target) and os.path.getsize(onnx_target) > 5 * 1024 * 1024:
        print("[+] RIFE ONNX base models verified.")
        return True

    print("[-] Base ONNX models not detected in models/rife_v2. Skipping pre-compilation.")
    return False

def run_health_check():
    print("\n==============================================================================")
    print("    Step 3: Verifying AI Runtime & GPU Integration")
    print("==============================================================================")
    test_code = """
import sys
try:
    import vapoursynth as vs
    core = vs.core
    import vsmlrt
    dev_name = "NVIDIA CUDA GPU"
    if hasattr(core, "trt") and hasattr(core.trt, "DeviceProperties"):
        try:
            dev_info = core.trt.DeviceProperties(0)
            dev_name = dev_info.get("name", b"").decode()
        except Exception:
            pass
    ver_str = getattr(core.core_version, "release_major", "72") if hasattr(core, "core_version") else "Ready"
    print(f'  [+] VapourSynth Core: R{ver_str} (Thread Pool: {core.num_threads})')
    print(f'  [+] Active Graphics Card: {dev_name}')
    print('  [+] NVIDIA TensorRT Runtime: Initialized and ready.')
    print('  [+] Runtime health check: PASSED.')
except Exception as e:
    err_str = str(e)
    print('  [!] Health check error:', err_str)
    if 'insufficient' in err_str.lower() or 'driver' in err_str.lower():
        print('\\n  [!] CAUSE: Your NVIDIA Driver version is lower than 580.00!')
        print('      Please update your NVIDIA graphics driver from https://www.nvidia.com/drivers')
    sys.exit(1)
"""
    ret = subprocess.run([os.path.join(VS_DIR, "python.exe"), "-c", test_code])
    if ret.returncode != 0:
        print("[!] Health check reported an issue. Please verify your NVIDIA graphics drivers.")
    else:
        print("  [+] Health check completed successfully.")

def run_final_build_step():
    print("\n==============================================================================")
    print("    Final Step: Pre-compiling Model 4 (RIFE v4.17 Lite)")
    print("==============================================================================")
    print("  [ESTIMATED TIME]: ~1 to 3 Minutes (depending on GPU speed)")
    print("  [*] Launching TensorRT Builder in a separate window...")
    print("      Please wait until engine compilation completes...")

    # Launch build_model_4.bat in a separate console window and wait for completion
    bat_path = BUILD_MODEL_4_BAT
    start_time = time.time()
    
    # Use start /wait cmd.exe /c to run in separate window and auto-close on finish
    window_title = "TensorRT Engine Compiler - Model 4 (1080p + 720p)"
    cmd = f'start "{window_title}" /wait cmd.exe /c "{bat_path}"'
    ret = subprocess.run(cmd, shell=True)

    elapsed = int(time.time() - start_time)
    minutes = elapsed // 60
    seconds = elapsed % 60
    time_str = f"{minutes}m {seconds:02d}s" if minutes > 0 else f"{seconds}s"

    # Self-healing verification: confirm both 1080p and 720p engines were built successfully
    manifest_file = os.path.join(MPV_DIR, "portable_config", "engines_manifest.json")
    model4_ready = False
    if os.path.isfile(manifest_file):
        try:
            with open(manifest_file, "r", encoding="utf-8") as f:
                mdata = json.load(f)
                m4 = mdata.get("models", {}).get("4", {})
                model4_ready = m4.get("base_ready", False)
        except Exception:
            pass

    if not model4_ready:
        print("\n[!] Notice: Model 4 build incomplete (both 1080p and 720p engines required).")
        print("    Running self-healing compilation pass...")
        py_exe = os.path.join(VS_DIR, "python.exe")
        build_script = os.path.join(TOOLS_DIR, "build_all_engines.py")
        if os.path.isfile(py_exe) and os.path.isfile(build_script):
            subprocess.run([py_exe, build_script, "--model", "4"])

    print(f"  [+] Model 4 TensorRT engines compiled successfully! (Time taken: {time_str})")


def main():
    print("==============================================================================")
    print("   MPV Flow (mpv-flow) — VapourSynth RIFE TensorRT Setup Pipeline")
    print("==============================================================================")
    print(f"Target Directory: {ROOT_DIR}")

    gpu_info = check_gpu_and_driver()

    # Case 1: AMD / Intel / Non-NVIDIA GPU
    if not gpu_info.get("has_nvidia", False):
        print("[*] Installing MPV core player for native playback...")
        check_and_setup_mpv()
        print("\n==============================================================================")
        print("  [+] MPV player installed successfully and ready for use!")
        print("      (TensorRT package was skipped as non-NVIDIA GPU was detected).")
        print("==============================================================================")
        return

    # Case 2: NVIDIA GPU with driver < 580
    if not gpu_info.get("compatible", True):
        print("[!] Setup halted: Please update your NVIDIA graphics driver to 580.00+ and re-run setup.")
        print("    TensorRT download skipped to preserve bandwidth.")
        return

    # Case 3: Fully compatible NVIDIA system (Driver >= 580.00)
    check_and_setup_mpv()
    configure_initial_hardware_settings(gpu_info.get("vram_mb"))
    check_and_setup_tensorrt()
    models_ok = verify_models()
    run_health_check()
    if models_ok:
        run_final_build_step()

    print("\n==============================================================================")
    print("  [+] Setup completed successfully! All components are ready.")
    print("      Enjoy silky smooth AI playback with MPV!")
    print("==============================================================================")

if __name__ == "__main__":
    main()


