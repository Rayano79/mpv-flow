import os
import sys
import time
from fractions import Fraction
import vapoursynth as vs
from vapoursynth import core


# 1. إعدادات RIFE الافتراضية المعتمدة
DEFAULT_ACTIVE     = True  # حالة التفعيل الافتراضية
DEFAULT_CACHE_SIZE = 8192  # ذاكرة الرام بالميجابايت (8GB System RAM Cache)
DEFAULT_MODEL_NUM  = 4     # النموذج الافتراضي 4 (RIFE v4.17 Lite - الأسرع والأخف)
DEFAULT_MULTI      = 2     # مضاعفة الفريمات (2x)
DEFAULT_STREAMS    = 2     # مسارات المعالجة المتزامنة في الكرت (2 streams)
DEFAULT_UHD_MODE   = 1     # نمط معالجة 4K (1 = Bypass RIFE on 4K by default)
DEFAULT_MAX_FPS    = 70    # الحد الأقصى لبدء المعالجة
DEFAULT_FP16       = True  # تسريع FP16 لأنوية Tensor Cores
DEFAULT_CUDA_GRAPH = False  # تقنية NVIDIA CUDA Graph لتسجيل وتسريع استدعاءات أنوية TensorRT (معطلة افتراضياً لأعلى توافق واستقرار)
DEFAULT_SC_THRESH  = 0.10  # حساسية كشف الانتقال بين المشاهد

# تحديد مسار vs المحمول وضمان أولوية البيئة المحلية وعزل تام عن بايثون النظام
base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "vs"))
if not os.path.isdir(base_dir):
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "vs"))

if os.path.isdir(base_dir):
    # إزالة أي مسارات بايثون خارجية أو مثبتة بالنظام لتفادي أي تداخل
    base_lower = base_dir.lower()
    sys.path = [p for p in sys.path if not (("python" in os.path.normpath(p).lower() or "site-packages" in os.path.normpath(p).lower()) and not os.path.normpath(p).lower().startswith(base_lower))]
    if base_dir not in sys.path:
        sys.path.insert(0, base_dir)
    site_packages = os.path.join(base_dir, "Lib", "site-packages")
    if os.path.isdir(site_packages) and site_packages not in sys.path:
        sys.path.insert(0, site_packages)
    cuda_dir = os.path.join(base_dir, "vs-plugins", "vsmlrt-cuda")
    plugins_dir = os.path.join(base_dir, "vs-plugins")
    os.environ["PATH"] = cuda_dir + os.pathsep + plugins_dir + os.pathsep + base_dir + os.pathsep + os.environ.get("PATH", "")
    if hasattr(os, "add_dll_directory"):
        for d in (cuda_dir, plugins_dir, base_dir):
            if os.path.isdir(d):
                try:
                    os.add_dll_directory(d)
                except Exception:
                    pass

# تحميل فلاتر MiscFilters تلقائياً لكشف المشاهد إن وجدت
if not hasattr(core, 'misc'):
    for dll in [
        os.path.join(base_dir, "vs-plugins", "MiscFilters.dll"),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "vapoursynth64", "plugins", "MiscFilters.dll")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "MiscFilters.dll")),
    ]:
        if os.path.isfile(dll):
            try:
                core.std.LoadPlugin(dll)
                break
            except Exception:
                pass

# تحميل فلاتر vsmlrt TensorRT تلقائياً لضمان التوافق مع R70 و R79 وأحدث الإصدارات
if not hasattr(core, 'trt'):
    trt_dll = os.path.join(base_dir, "vs-plugins", "vstrt.dll")
    if os.path.isfile(trt_dll):
        try:
            core.std.LoadPlugin(trt_dll)
        except Exception:
            pass

import vsmlrt
from vsmlrt import RIFE, RIFEModel, Backend

# فرض مسارات المحركات والمكتبات المحمولة التابعة للمشروع حصراً
vsmlrt.plugins_path = plugins_dir
vsmlrt.trtexec_path = os.path.join(cuda_dir, "trtexec.exe" if sys.platform == "win32" else "trtexec")
vsmlrt.models_path = os.path.join(plugins_dir, "models")
models_path = vsmlrt.models_path
engines_dir = os.path.join(models_path, "rife_v2", "engines")
os.makedirs(engines_dir, exist_ok=True)

# ================= النماذج الأربعة المعتمدة =================
MODELS = {
    1: 425,   # RIFE v4.25 (النموذج الكامل - أعلى دقة وتفاصيل ونقاء بصري)
    2: 4251,  # RIFE v4.25 Lite (نسخة سريعة بدقة عالية جداً)
    3: 4221,  # RIFE v4.22 Lite (متوازن بين السرعة الفائقة والجودة)
    4: 4171   # RIFE v4.17 Lite (الأسرع والأخف وزناً بمعدل استهلاك منخفض)
}

# ================= قراءة ملف الإعدادات الموحد player_settings.conf =================
player_cfg_file = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "player_settings.conf"))
rife_cfg_file   = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "rife_settings.conf"))
target_cfg_file = player_cfg_file if os.path.isfile(player_cfg_file) else rife_cfg_file

ACTIVE           = DEFAULT_ACTIVE
chosen_model_num = DEFAULT_MODEL_NUM
RIFE_MULTI       = DEFAULT_MULTI
TRT_STREAMS      = DEFAULT_STREAMS
UHD_MODE         = DEFAULT_UHD_MODE
MAX_CACHE_SIZE   = DEFAULT_CACHE_SIZE
MAX_SOURCE_FPS   = DEFAULT_MAX_FPS
TRT_FP16         = DEFAULT_FP16
TRT_CUDA_GRAPH   = DEFAULT_CUDA_GRAPH
SC_THRESHOLD     = DEFAULT_SC_THRESH

found_model_in_conf = False

if os.path.isfile(target_cfg_file):
    try:
        with open(target_cfg_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    k = k.strip().lower()
                    v = v.strip()
                    if k == "model":
                        try:
                            m_val = int(v)
                            if m_val in MODELS:
                                chosen_model_num = m_val
                                found_model_in_conf = True
                            elif m_val == 425:  chosen_model_num = 1; found_model_in_conf = True
                            elif m_val == 4251: chosen_model_num = 2; found_model_in_conf = True
                            elif m_val == 4221: chosen_model_num = 3; found_model_in_conf = True
                            elif m_val == 4171: chosen_model_num = 4; found_model_in_conf = True
                        except ValueError:
                            pass
                    elif k == "multi":
                        try:
                            m_val = int(v)
                            if 2 <= m_val <= 6:
                                RIFE_MULTI = m_val
                        except ValueError:
                            pass
                    elif k == "streams":
                        try:
                            s_val = int(v)
                            if 1 <= s_val <= 6:
                                TRT_STREAMS = s_val
                        except ValueError:
                            pass
                    elif k == "uhd_mode":
                        try:
                            u_val = int(v)
                            if u_val in (1, 2, 3):
                                UHD_MODE = u_val
                        except ValueError:
                            pass
                    elif k == "active":
                        ACTIVE = (v.lower() in ("yes", "true", "1", "on"))
                    elif k in ("ram", "max_cache_size", "cache_size"):
                        try:
                            c_val = int(v)
                            if c_val >= 1024:
                                MAX_CACHE_SIZE = c_val
                        except ValueError:
                            pass
                    elif k == "max_source_fps":
                        try:
                            fps_val = float(v)
                            if fps_val > 0:
                                MAX_SOURCE_FPS = fps_val
                        except ValueError:
                            pass
                    elif k == "fp16":
                        TRT_FP16 = (v.lower() in ("true", "1", "yes"))
                    elif k == "cuda_graph":
                        TRT_CUDA_GRAPH = (v.lower() in ("true", "1", "yes"))
                    elif k == "sc_threshold":
                        try:
                            sc_val = float(v)
                            if sc_val >= 0:
                                SC_THRESHOLD = sc_val
                        except ValueError:
                            pass
    except Exception:
        pass

# تطبيق إعدادات الرام ونموذج الذكاء الاصطناعي
core.max_cache_size = MAX_CACHE_SIZE
RIFE_MODEL = MODELS[chosen_model_num]

# خريطة ملفات النماذج الرسمية
MODEL_FILE_MAP = {
    1: "rife_v4.25_v2.onnx",
    2: "rife_v4.25_lite_v2.onnx",
    3: "rife_v4.22_lite_v2.onnx",
    4: "rife_v4.17_lite_v2.onnx"
}

# ================= فحص أمان مبكر: هل ملف النموذج موجود على القرص؟ =================
target_onnx_name = MODEL_FILE_MAP.get(chosen_model_num)
target_onnx_path = os.path.join(models_path, "rife_v2", target_onnx_name) if target_onnx_name else None

if not target_onnx_path or not os.path.isfile(target_onnx_path) or os.path.getsize(target_onnx_path) < 1024 * 1024:
    # أمان فائق: في حال حذف النموذج من القرص، يعمل المشغل فوراً بالوضع الأصلي الخالص (RIFE OFF)
    try:
        sys.stderr.write(f"[MPV-Flow] Model {chosen_model_num} ({target_onnx_name}) not found on disk. RIFE is OFF (safe native playback).\n")
    except Exception:
        pass
    video_in.set_output()
    # نوقف التنفيذ هنا لتفادي أي استهلاك للذاكرة أو محاولات بناء
else:
    # ================= قراءة الفيديو ومعدل الفريمات =================
    clip = video_in

    raw_fps = 23.976024
    if 'container_fps' in globals() and container_fps:
        try:
            raw_fps = float(container_fps)
        except Exception:
            pass
    elif hasattr(clip, 'fps') and float(clip.fps) > 0:
        raw_fps = float(clip.fps)

    # فحص إذا كان الفيديو فائق الدقة (أكبر من 1080p مثل 2K أو 4K)
    is_uhd = clip.width > 1920 or clip.height > 1088

    # 1. فحص خيار التفعيل العام: إذا كان معطلاً نخرج فوراً بالفيديو الخام بدون أي معالجة أو عبء
    if not ACTIVE:
        clip.set_output()
    # 2. إذا اختار المستخدم الخيار 1 للـ UHD (أو كان الخيار 3 المعطل): بث الفيديو الخام الأصلي فوراً بدون أي معالجة (Off in 4K)
    # [ملاحظة: تم تعطيل خيار 3 (4K Native AI) مؤقتاً لعدم استقراره وثقله الشديد على العتاد]
    elif is_uhd and UHD_MODE != 2:
        clip.set_output()
    # 3. إذا كان الفيديو أصلاً بمعدل فريمات فائق جداً (> 70fps مثل 120fps و 144fps) نتخطى المعالجة:
    elif raw_fps > MAX_SOURCE_FPS:
        clip.set_output()
    else:
        # إذا كان الفيديو فائق الدقة واختار المستخدم الخيار 2 (تصغير إلى 1080p):
        # يتم تصغير الفيديو إلى 1080p ليتطابق مع محركات 1080p الجاهزة فوراً بدون أي تقطيع
        if is_uhd and UHD_MODE == 2:
            scale = min(1920.0 / clip.width, 1080.0 / clip.height)
            w1080 = int(clip.width * scale)
            h1080 = int(clip.height * scale)
            w1080 = (w1080 // 2) * 2
            h1080 = (h1080 // 2) * 2
            clip = core.resize.Bilinear(clip, width=w1080, height=h1080)
            active_multi = 2             # قفل المضاعفة عند 2x لـ 4K لتفادي عنق الزجاجة
        else:
            active_multi = RIFE_MULTI

        # معالجة ذكية لتسجيلات الشاشة (فيديوهات 50-60fps الحاوية لحركة 24/30fps مع فريمات مكررة من برنامج التسجيل):
        if raw_fps >= 45:
            clip = core.std.SelectEvery(clip, cycle=2, offsets=0)
            raw_fps = raw_fps / 2.0
            active_multi = 2

        # حساب الفريمات الدقيق المتطابق مع الصوت 100%
        fps = Fraction(raw_fps).limit_denominator(1001)
        fps_num = fps.numerator
        fps_den = fps.denominator

        # استنتاج مصفوفة الألوان بدقة (BT.2020 للـ 4K HDR، و BT.709 للـ HD)
        matrix_str = "709"
        try:
            props = video_in.get_frame(0).props
            _matrix = props.get("_Matrix")
            if _matrix in (9, 10):
                matrix_str = "2020ncl"
            elif _matrix == 1:
                matrix_str = "709"
            elif _matrix in (5, 6):
                matrix_str = "470bg"
            elif is_uhd:
                matrix_str = "2020ncl"
            elif clip.width > 1024 or clip.height >= 600:
                matrix_str = "709"
            else:
                matrix_str = "470bg"
        except Exception:
            if is_uhd:
                matrix_str = "2020ncl"
            elif clip.width > 1024 or clip.height >= 600:
                matrix_str = "709"
            else:
                matrix_str = "470bg"

        # توحيد الأبعاد للـ 1080p أو 720p لمنع تكرار بناء المحركات
        # [ملاحظة: تم تعطيل خيار 4K Native RIFE مؤقتاً لعدم استقراره وثقله الشديد على العتاد]
        # if is_uhd and UHD_MODE == 3:
        #     target_w, target_h = 3840, 2176
        # elif clip.width > 1280 or clip.height > 720:
        if clip.width > 1280 or clip.height > 720:
            target_w, target_h = 1920, 1088
        else:
            target_w, target_h = 1280, 768

        # 1. كشف تغير المشهد على إشارة YUV الأصلية قبل أي تحويل
        sc_clip = None
        if hasattr(core, 'misc') and hasattr(core.misc, 'SCDetect'):
            try:
                if clip.format.color_family in [vs.YUV, vs.GRAY]:
                    sc_base = core.std.ShufflePlanes(clip, planes=0, colorfamily=vs.GRAY)
                else:
                    sc_base = core.resize.Bilinear(clip, format=vs.GRAY8)
                sc_clip = sc_base.misc.SCDetect(SC_THRESHOLD)
            except Exception:
                sc_clip = None

        # 2. توحيد الأبعاد بالـ Padding لحماية الدقة ومنع تكرار بناء المحرك
        pad_w = target_w - clip.width
        pad_h = target_h - clip.height

        if pad_w > 0 or pad_h > 0:
            clip = core.std.AddBorders(clip, right=max(0, pad_w), bottom=max(0, pad_h))

        # 3. تحويل مباشر إلى صيغة RGBH (FP16) لأنوية Tensor Cores لـ RIFE
        clip = core.resize.Bicubic(clip, format=vs.RGBH, matrix_in_s=matrix_str)

        if sc_clip is not None:
            try:
                clip = core.std.CopyFrameProps(clip, prop_src=sc_clip, props=["_SceneChangePrev", "_SceneChangeNext"])
            except Exception:
                pass

        # 4. التحقق والتشغيل المرن لموديل RIFE عبر محرك TensorRT
        try:
            engine_fname = None
            if not os.path.isfile(target_onnx_path) or os.path.getsize(target_onnx_path) < 1024 * 1024:
                raise FileNotFoundError(f"Model file '{target_onnx_name}' not found on disk")

            # فحص جاهزية محرك TensorRT لتفادي أي تجميد أو تشغيل بناء مزدوج أثناء التشغيل
            manifest_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "engines_manifest.json"))
            engine_ready = False
            res_key = "4k" if target_w == 3840 else ("1080p" if target_w == 1920 else "720p")

            if os.path.isfile(manifest_path):
                try:
                    import json
                    with open(manifest_path, "r", encoding="utf-8") as mf:
                        mdata = json.load(mf)
                        mf_file = mdata.get("models", {}).get(str(chosen_model_num), {}).get("resolutions", {}).get(res_key, {}).get("file")
                        if mf_file:
                            epath = os.path.join(engines_dir, mf_file)
                            if os.path.isfile(epath) and os.path.getsize(epath) > 1024 * 1024:
                                engine_ready = True
                                engine_fname = mf_file
                except Exception:
                    engine_ready = False

            if not engine_ready:
                # التحقق المباشر من مسار المحرك المحسوب في حال غياب أو عدم تحديث الـ manifest
                try:
                    trt_ver = vsmlrt.parse_trt_version(int(core.trt.Version()["tensorrt_version"]))
                    dev_name = core.trt.DeviceProperties(0)["name"].decode().replace(' ', '-')
                    ep_calc = vsmlrt.get_engine_path(
                        network_path=target_onnx_path,
                        min_shapes=(target_w, target_h), opt_shapes=(target_w, target_h), max_shapes=(target_w, target_h),
                        workspace=None, fp16=TRT_FP16, use_cublas=False, static_shape=True,
                        tf32=False, use_cudnn=False, input_format=1, output_format=1,
                        builder_optimization_level=3, max_aux_streams=None, short_path=True,
                        bf16=False, engine_folder=engines_dir,
                        trt_version=trt_ver, device_name=dev_name
                    )
                    if os.path.isfile(ep_calc) and os.path.getsize(ep_calc) > 1024 * 1024:
                        engine_ready = True
                        engine_fname = os.path.basename(ep_calc)
                except Exception:
                    pass

            if not engine_ready:
                raise FileNotFoundError(f"TensorRT engine for model {chosen_model_num} ({res_key}) is not built yet")
            interpolated = RIFE(
                clip,
                multi=active_multi,
                model=RIFE_MODEL,
                _implementation=2,
                backend=Backend.TRT(
                    fp16=TRT_FP16,
                    use_cuda_graph=TRT_CUDA_GRAPH,
                    static_shape=True,
                    num_streams=TRT_STREAMS,
                    output_format=1, # 1 = FP16
                    log=False,
                    engine_folder=engines_dir
                )
            )

            # 5. ضبط توقيت الفريمات SMPTE المتطابق مع الصوت بالميكروثانية
            interpolated = core.std.AssumeFPS(interpolated, fpsnum=(fps_num * active_multi), fpsden=fps_den)

            # 6. إزالة الـ Padding والعودة للدقة تماماً
            if pad_w > 0 or pad_h > 0:
                interpolated = core.std.Crop(interpolated, right=max(0, pad_w), bottom=max(0, pad_h))

            # 8. تحويل الإخراج المتوافق مع المشغل والعرض
            interpolated = core.resize.Bicubic(interpolated, format=video_in.format.id, matrix_s=matrix_str)

            # 9. إخراج الفيديو المعالج
            interpolated.set_output()

        except Exception as err:
            # المرونة التامة: في حال غياب الموديل أو حدوث أي خطأ في المحرك، يستمر الفيديو بالعمل خام تلقائياً (RIFE OFF)
            err_str = str(err)
            try:
                sys.stderr.write(f"[MPV-Flow] RIFE Bypassed: {err_str}. Playing native video.\n")
            except Exception:
                pass
            if "deserialization failed" in err_str.lower() or "not compatible" in err_str.lower():
                try:
                    if engine_fname:
                        bad_ep = os.path.join(engines_dir, engine_fname)
                        if os.path.isfile(bad_ep):
                            os.remove(bad_ep)
                        if os.path.isfile(bad_ep + ".cache"):
                            os.remove(bad_ep + ".cache")
                except Exception:
                    pass
            video_in.set_output()



