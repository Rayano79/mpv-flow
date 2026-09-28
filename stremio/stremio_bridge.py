import os
import sys
import shutil

# Detect possible Stremio installations
POSSIBLE_STREMIO_DIRS = [
    os.path.expandvars(r"%LOCALAPPDATA%\Programs\LNV\Stremio-4"),
    os.path.expandvars(r"%LOCALAPPDATA%\Programs\Stremio-4"),
    os.path.expandvars(r"%LOCALAPPDATA%\Smart Code ltd\Stremio-4"),
]

def find_stremio_dir():
    for path in POSSIBLE_STREMIO_DIRS:
        if os.path.isfile(os.path.join(path, "stremio.exe")):
            return path
    return None

def get_paths():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    mpv_exe = os.path.join(base_dir, "mpv", "mpv.exe")
    return base_dir, mpv_exe

def link_stremio():
    print("=" * 78)
    print("      Stremio <-> MPV Flow External Player Linker")
    print("=" * 78)
    print()

    base_dir, mpv_exe = get_paths()
    stremio_dir = find_stremio_dir()

    # 1. Validation
    # Check if project setup.bat was executed
    vs_dir = os.path.join(base_dir, "vs")
    nvinfer_dll = os.path.join(vs_dir, "vs-plugins", "vsmlrt-cuda", "nvinfer_10.dll")
    models_dir = os.path.join(vs_dir, "vs-plugins", "models", "rife_v2")
    if not os.path.isfile(mpv_exe) or not os.path.isfile(nvinfer_dll) or not os.path.isdir(models_dir):
        print("=" * 78)
        print("[ERROR] MPV Flow setup has NOT been completed yet!")
        print("=" * 78)
        print("Before linking with Stremio, you must run 'setup.bat' in the project root")
        print("to install MPV, download TensorRT libraries and verify your GPU setup.")
        print("=" * 78)
        return False

    if not stremio_dir or not os.path.isdir(stremio_dir):
        print("[ERROR] Stremio application folder was not found.")
        print("Checked locations:")
        for loc in POSSIBLE_STREMIO_DIRS:
            print(f"  - {loc}")
        print("\nPlease ensure Stremio-4 is installed.")
        return False

    server_js = os.path.join(stremio_dir, "server.js")
    if not os.path.isfile(server_js):
        print(f"[ERROR] server.js was not found in:\n        {stremio_dir}")
        return False

    print(f"[*] Project Root : {base_dir}")
    print(f"[*] Stremio Path : {stremio_dir}")
    print(f"[*] MPV Binary   : {mpv_exe}")
    print()

    # 2. Backup server.js before modifying
    server_bak = os.path.join(stremio_dir, "server.js.bak")
    if not os.path.isfile(server_bak):
        try:
            shutil.copy2(server_js, server_bak)
            print(f"[1/2] Created backup of Stremio server.js -> server.js.bak")
        except Exception as e:
            print(f"[ERROR] Failed creating backup of server.js: {e}")
            return False
    else:
        print(f"[1/2] Original backup (server.js.bak) already preserved.")

    # 3. Inject our mpv.exe path into server.js for both VLC and MPV slots
    print("[2/2] Injecting mpv-vs-trt path into Stremio server.js...")
    try:
        with open(server_js, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        mpv_js_path = mpv_exe.replace('\\', '\\\\')
        new_mpv_win32 = f'win32: {{\n                    path: [ \'"{mpv_js_path}"\' ]\n                }}'
        new_vlc_win32 = f'win32: {{\n                    path: [ \'"{mpv_js_path}"\' ]\n                }}'

        import re

        # Patch VLC slot (args with --fs, timeArg, path) so selecting VLC launches mpv-vs-trt in fullscreen
        vlc_pattern = re.compile(
            r'(vlc:\s*\{\s*title:\s*"VLC",\s*)args:\s*\[[^\]]*\],\s*subArg:\s*"[^"]*",\s*timeArg:\s*"[^"]*",\s*playArg:\s*"[^"]*",\s*(darwin:.*?linux:.*?win32:\s*\{\s*path:\s*\[)[^\]]*(\]\s*\})',
            re.DOTALL
        )
        if vlc_pattern.search(content):
            content = vlc_pattern.sub(
                lambda m: m.group(1) + 'args: [ "--no-terminal", "--fs" ],\n                subArg: "--sub-file=",\n                timeArg: "--start=",\n                playArg: "",\n                ' + m.group(2) + f' \'"{mpv_js_path}"\' ' + m.group(3),
                content
            )
            print("      [+] Mapped VLC external slot (with fullscreen --fs) -> mpv-vs-trt")
        else:
            vlc_path_pattern = re.compile(
                r'(vlc:\s*\{.*?win32:\s*\{\s*path:\s*\[)[^\]]*(\]\s*\})',
                re.DOTALL
            )
            if vlc_path_pattern.search(content):
                content = vlc_path_pattern.sub(rf'\g<1> \'"{mpv_js_path}"\' \g<2>', content)
                print("      [+] Mapped VLC external path -> mpv-vs-trt")

        # Patch MPV win32 path and add --fs
        mpv_pattern = re.compile(
            r'(mpv:\s*\{\s*title:\s*"MPV",\s*)args:\s*\[[^\]]*\],\s*(subArg:.*?timeArg:.*?playArg:.*?darwin:.*?linux:.*?win32:\s*\{\s*path:\s*\[)[^\]]*(\]\s*\})',
            re.DOTALL
        )
        if mpv_pattern.search(content):
            content = mpv_pattern.sub(
                lambda m: m.group(1) + 'args: [ "--no-terminal", "--fs" ],\n                ' + m.group(2) + f' \'"{mpv_js_path}"\' ' + m.group(3),
                content
            )
            print("      [+] Mapped MPV external slot (with fullscreen --fs) -> mpv-vs-trt")
        else:
            mpv_simple = re.compile(
                r'(mpv:\s*\{.*?linux:\s*\{\s*path:\s*\[[^\]]*\]\s*\},?\s*)win32:\s*\{\s*path:\s*\[[^\]]*\]\s*\}',
                re.DOTALL
            )
            if mpv_simple.search(content):
                content = mpv_simple.sub(lambda m: m.group(1) + new_mpv_win32, content)
                print("      [+] Mapped MPV external slot -> mpv-vs-trt")

        # Atomic write
        temp_file = server_js + ".tmp"
        with open(temp_file, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(temp_file, server_js)
        print("      [+] Successfully patched Stremio server.js with mpv-vs-trt!")

    except Exception as e:
        print(f"[ERROR] Failed patching server.js: {e}")
        return False

    print()
    print("=" * 78)
    print("  [SUCCESS] Stremio is now fully linked to mpv-vs-trt!")
    print("=" * 78)
    print()
    print("  HOW TO USE IN STREMIO:")
    print("  1. Restart Stremio completely.")
    print("  2. Play any movie or episode inside Stremio.")
    print("  3. At the bottom-right of the player screen, click the Cast icon or (⋮) 3-dots.")
    print("  4. Choose 'Watch on MPV' (or 'Watch on VLC').")
    print("  -> MPV Flow will launch immediately in Fullscreen with smooth RIFE AI playback!")
    print("=" * 78)
    return True

def unlink_stremio():
    print("=" * 78)
    print("         Stremio Media Player <-> Unlink MPV Flow")
    print("=" * 78)
    print()

    stremio_dir = find_stremio_dir()
    if not stremio_dir or not os.path.isdir(stremio_dir):
        print("[*] Stremio installation was not found or already removed.")
        return True

    server_js = os.path.join(stremio_dir, "server.js")
    server_bak = os.path.join(stremio_dir, "server.js.bak")

    # 1. Restore server.js from backup
    print("[1/2] Restoring original server.js from backup...")
    if os.path.isfile(server_bak):
        try:
            shutil.copy2(server_bak, server_js)
            os.remove(server_bak)
            print("      [+] Original server.js successfully restored (backup removed).")
        except Exception as e:
            print(f"      ! Error restoring server.js: {e}")
    else:
        print("      * No server.js.bak found. Checking if manual reset is needed...")
        try:
            with open(server_js, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            import re
            # Reset VLC win32 path to default
            default_vlc = 'win32: {\n                    path: [ \'"C:\\\\Program Files (x86)\\\\VideoLAN\\\\VLC\\\\vlc.exe"\', \'"C:\\\\Program Files\\\\VideoLAN\\\\VLC\\\\vlc.exe"\' ]\n                }'
            vlc_pattern = re.compile(
                r'(vlc:\s*\{.*?linux:\s*\{\s*path:\s*\[[^\]]*\]\s*\},?\s*)win32:\s*\{\s*path:\s*\[[^\]]*\]\s*\}',
                re.DOTALL
            )
            if vlc_pattern.search(content):
                content = vlc_pattern.sub(rf'\g<1>{default_vlc}', content)

            # Reset MPV win32 path to []
            clean_win32 = 'win32: {\n                    path: []\n                }'
            mpv_pattern = re.compile(
                r'(mpv:\s*\{.*?linux:\s*\{\s*path:\s*\[[^\]]*\]\s*\},?\s*)win32:\s*\{\s*path:\s*\[[^\]]*\]\s*\}',
                re.DOTALL
            )
            if mpv_pattern.search(content):
                content = mpv_pattern.sub(rf'\g<1>{clean_win32}', content)

            with open(server_js, "w", encoding="utf-8") as f:
                f.write(content)
            print("      [+] Reset VLC & MPV win32 paths to default in server.js.")
        except Exception as e:
            print(f"      ! Error resetting server.js: {e}")

    # 2. Clean up any leftover DLLs/portable_config from previous experiments
    print()
    print("[2/2] Cleaning any leftover bridge files from Stremio directory...")
    leftovers = [
        "python312._pth",
        "portable.vs",
        "VSScript.dll",
        "vapoursynth.dll",
        "python312.dll",
        "python3.dll"
    ]
    for bfile in leftovers:
        fpath = os.path.join(stremio_dir, bfile)
        if os.path.isfile(fpath):
            try:
                os.remove(fpath)
                print(f"      - Removed leftover: {bfile}")
            except Exception:
                pass

    stremio_cfg_dir = os.path.join(stremio_dir, "portable_config")
    if os.path.isdir(stremio_cfg_dir):
        try:
            shutil.rmtree(stremio_cfg_dir)
            print("      - Removed leftover: portable_config folder")
        except Exception:
            pass

    print()
    print("=" * 78)
    print("  [SUCCESS] Stremio has been completely unlinked from mpv-vs-trt.")
    print("  [IMPORTANT] Please RESTART Stremio to apply default settings.")
    print("=" * 78)
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1].lower() in ("--unlink", "-u", "unlink"):
        unlink_stremio()
    else:
        link_stremio()
