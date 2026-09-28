import os
import sys
import json
import shutil

HARBOR_LOCAL = os.path.expandvars(r"%LOCALAPPDATA%\Harbor")
HARBOR_ROAMING_SETTINGS = os.path.expandvars(r"%APPDATA%\app.harbor\settings.json")

def get_paths():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    vs_dir = os.path.join(base_dir, "vs")
    vpy_file = os.path.join(base_dir, "mpv", "portable_config", "vs", "interpolation.vpy")
    return base_dir, vs_dir, vpy_file

def link_harbor():
    print("=" * 78)
    print("      Harbor Streamio <-> MPV Flow RIFE TensorRT Bridge Linker")
    print("=" * 78)
    print()

    base_dir, vs_dir, vpy_file = get_paths()

    # 1. Validation
    # Check if project setup.bat was executed
    nvinfer_dll = os.path.join(vs_dir, "vs-plugins", "vsmlrt-cuda", "nvinfer_10.dll")
    models_dir = os.path.join(vs_dir, "vs-plugins", "models", "rife_v2")
    if not os.path.isfile(nvinfer_dll) or not os.path.isdir(models_dir):
        print("=" * 78)
        print("[ERROR] MPV Flow setup has NOT been completed yet!")
        print("=" * 78)
        print("Before linking with Harbor, you must run 'setup.bat' in the project root")
        print("to download TensorRT libraries and verify your GPU setup.")
        print("=" * 78)
        return False

    if not os.path.isdir(HARBOR_LOCAL):
        print(f"[ERROR] Harbor application folder was not found at:")
        print(f"        {HARBOR_LOCAL}")
        print("Please install Harbor or run it at least once.")
        return False

    vsscript = os.path.join(vs_dir, "VSScript.dll")
    if not os.path.isfile(vsscript):
        print(f"[ERROR] Portable VapourSynth runtime not found at:")
        print(f"        {vs_dir}")
        print("Please run setup.bat first.")
        return False

    if not os.path.isfile(vpy_file):
        print(f"[ERROR] Interpolation script not found at:")
        print(f"        {vpy_file}")
        return False

    print(f"[*] Project Root : {base_dir}")
    print(f"[*] Harbor Path  : {HARBOR_LOCAL}")
    print()

    # 2. Copy bridge DLLs
    print("[1/3] Copying runtime bridge libraries into Harbor...")
    dlls_to_copy = [
        ("VSScript.dll", os.path.join(vs_dir, "VSScript.dll")),
        ("python312.dll", os.path.join(vs_dir, "python312.dll")),
        ("python3.dll", os.path.join(vs_dir, "python3.dll")),
        ("portable.vs", os.path.join(vs_dir, "portable.vs")),
    ]
    # vapoursynth.dll can be in vs/Lib/site-packages or vs/
    vs_dll_primary = os.path.join(vs_dir, "Lib", "site-packages", "vapoursynth.dll")
    vs_dll_sec = os.path.join(vs_dir, "vapoursynth.dll")
    if os.path.isfile(vs_dll_primary):
        dlls_to_copy.append(("vapoursynth.dll", vs_dll_primary))
    elif os.path.isfile(vs_dll_sec):
        dlls_to_copy.append(("vapoursynth.dll", vs_dll_sec))

    for name, src in dlls_to_copy:
        if os.path.isfile(src):
            dst = os.path.join(HARBOR_LOCAL, name)
            try:
                shutil.copy2(src, dst)
                print(f"      + Installed: {name}")
            except Exception as e:
                print(f"      ! Warning copying {name}: {e}")

    # 3. Create python312._pth pointing dynamically to this project's vs folder
    print()
    print("[2/3] Writing dynamic Python environment link (python312._pth)...")
    vs_fwd = vs_dir.replace("\\", "/")
    pth_content = "\n".join([
        f"{vs_fwd}/python312.zip",
        ".",
        "import site",
        f"{vs_fwd}/Lib/site-packages",
        f"{vs_fwd}/vs-plugins",
        f"{vs_fwd}",
        ""
    ])
    pth_file = os.path.join(HARBOR_LOCAL, "python312._pth")
    with open(pth_file, "w", encoding="utf-8") as f:
        f.write(pth_content)
    print("      + Created: python312._pth")

    # 4. Prepare configuration block and copy to clipboard
    print()
    print("[3/3] Generating MPV configuration block for Harbor...")
    vpy_fwd = vpy_file.replace("\\", "/")
    extra_lines = [
        "hwdec=d3d11va-copy",
        "vo=gpu-next",
        "d3d11-flip=no",
        "d3d11-sync-interval=0",
        "priority=high",
        "video-sync=audio",
        "hr-seek=no",
        "hr-seek-framedrop=no",
        f'vf=vapoursynth="{vpy_fwd}":4:4'
    ]
    extra_block = "\n".join(extra_lines)

    # Copy to Windows clipboard
    try:
        import subprocess
        p = subprocess.Popen(["clip"], stdin=subprocess.PIPE, shell=True)
        p.communicate(extra_block.encode("utf-8"))
        clipboard_copied = True
    except Exception:
        clipboard_copied = False

    print()
    print("=" * 78)
    print("  [SUCCESS] Runtime DLLs and Python bridge linked to Harbor successfully!")
    if clipboard_copied:
        print("  [+] The complete MPV configuration has been COPIED to your clipboard!")
    print("=" * 78)
    print()
    print("  IMPORTANT NEXT STEP (Required by Harbor):")
    print("  1. Open Harbor.")
    print("  2. Go to: Settings (Gear icon) -> Video / Player -> Advanced (mpv.conf).")
    print("  3. Paste (Ctrl + V) the configuration lines below into the box:")
    print("  " + "-" * 74)
    for line in extra_lines:
        print("    " + line)
    print("  " + "-" * 74)
    print("  4. Restart playback or restart Harbor to enjoy smooth playback!")
    print("=" * 78)
    return True

def unlink_harbor():
    print("=" * 78)
    print("         Harbor Streamio <-> Unlink MPV Flow Bridge")
    print("=" * 78)
    print()

    if not os.path.isdir(HARBOR_LOCAL):
        print("[*] Harbor is not installed or already removed.")
        return True

    # 1. Remove bridge files
    print("[1/2] Removing bridge files from Harbor directory...")
    bridge_files = [
        "python312._pth",
        "portable.vs",
        "VSScript.dll",
        "vapoursynth.dll",
        "python312.dll",
        "python3.dll"
    ]
    for bfile in bridge_files:
        fpath = os.path.join(HARBOR_LOCAL, bfile)
        if os.path.isfile(fpath):
            try:
                os.remove(fpath)
                print(f"      - Removed: {bfile}")
            except Exception as e:
                print(f"      ! Could not remove {bfile}: {e}")

    # 2. Instructions for Harbor UI
    print()
    print("[2/2] Bridge DLLs and Python connection removed from Harbor folder.")
    print()
    print("=" * 78)
    print("  [SUCCESS] Harbor has been completely unlinked from mpv-vs-trt!")
    print("=" * 78)
    print()
    print("  [CRITICAL STEP TO COMPLETE UNLINK IN HARBOR]:")
    print("  Because Harbor stores Advanced (mpv.conf) options in its internal memory:")
    print("  1. Open Harbor.")
    print("  2. Go to: Settings -> Video / Player -> Advanced (mpv.conf).")
    print("  3. DELETE the 'vf=vapoursynth=...' line from the text box.")
    print("  4. Restart Harbor.")
    print("=" * 78)
    return True

def print_manual_instructions(block):
    print()
    print("      Manual Configuration (In Harbor -> Settings -> Video/Player -> MPV Extra):")
    print("-" * 60)
    print(block)
    print("-" * 60)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1].lower() in ("--unlink", "-u", "unlink"):
        unlink_harbor()
    else:
        link_harbor()
