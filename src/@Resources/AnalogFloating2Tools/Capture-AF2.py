"""Move only the Analog_Floating2 Rainmeter window, capture it, then restore it."""

import ctypes
import json
import sys
from ctypes import wintypes
from pathlib import Path

from PIL import Image, ImageChops, ImageGrab


user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
user32.GetWindowDC.restype = wintypes.HDC
user32.PrintWindow.argtypes = [wintypes.HWND, wintypes.HDC, wintypes.UINT]
gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
gdi32.CreateCompatibleDC.restype = wintypes.HDC
gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
gdi32.SelectObject.restype = wintypes.HGDIOBJ
gdi32.GetDIBits.argtypes = [
    wintypes.HDC,
    wintypes.HBITMAP,
    wintypes.UINT,
    wintypes.UINT,
    wintypes.LPVOID,
    wintypes.LPVOID,
    wintypes.UINT,
]
gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
gdi32.DeleteDC.argtypes = [wintypes.HDC]
user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]


class Rect(ctypes.Structure):
    _fields_ = [
        ("left", ctypes.c_long),
        ("top", ctypes.c_long),
        ("right", ctypes.c_long),
        ("bottom", ctypes.c_long),
    ]


class BitmapInfoHeader(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", ctypes.c_long),
        ("biHeight", ctypes.c_long),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", ctypes.c_long),
        ("biYPelsPerMeter", ctypes.c_long),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class BitmapInfo(ctypes.Structure):
    _fields_ = [
        ("bmiHeader", BitmapInfoHeader),
        ("bmiColors", wintypes.DWORD * 3),
    ]


def find_af2_window():
    result = []
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd, _):
        title_length = user32.GetWindowTextLengthW(hwnd)
        title = ctypes.create_unicode_buffer(title_length + 1)
        class_name = ctypes.create_unicode_buffer(256)
        user32.GetWindowTextW(hwnd, title, len(title))
        user32.GetClassNameW(hwnd, class_name, len(class_name))
        if class_name.value == "RainmeterMeterWindow" and "Analog_Floating2" in title.value:
            result.append(hwnd)
            return False
        return True

    user32.EnumWindows(callback_type(callback), 0)
    if not result:
        raise RuntimeError("Analog_Floating2 Rainmeter window was not found")
    return result[0]


def get_rect(hwnd):
    rect = Rect()
    if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        raise ctypes.WinError()
    return {
        "X": rect.left,
        "Y": rect.top,
        "Width": rect.right - rect.left,
        "Height": rect.bottom - rect.top,
    }


def move(hwnd, x, y):
    swp_no_size = 0x0001
    swp_no_zorder = 0x0004
    swp_no_activate = 0x0010
    if not user32.SetWindowPos(
        hwnd, None, x, y, 0, 0, swp_no_size | swp_no_zorder | swp_no_activate
    ):
        raise ctypes.WinError()


def capture_window(hwnd, width, height):
    window_dc = user32.GetWindowDC(hwnd)
    memory_dc = gdi32.CreateCompatibleDC(window_dc)
    bitmap = gdi32.CreateCompatibleBitmap(window_dc, width, height)
    old_bitmap = gdi32.SelectObject(memory_dc, bitmap)
    try:
        if not user32.PrintWindow(hwnd, memory_dc, 0x00000002):
            raise RuntimeError("PrintWindow failed for Analog_Floating2")
        info = BitmapInfo()
        info.bmiHeader.biSize = ctypes.sizeof(BitmapInfoHeader)
        info.bmiHeader.biWidth = width
        info.bmiHeader.biHeight = -height
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = 0
        buffer = ctypes.create_string_buffer(width * height * 4)
        scanlines = gdi32.GetDIBits(
            memory_dc,
            bitmap,
            0,
            height,
            buffer,
            ctypes.byref(info),
            0,
        )
        if scanlines != height:
            raise RuntimeError(f"GetDIBits returned {scanlines} of {height} scanlines")
        image = Image.frombuffer(
            "RGB", (width, height), buffer, "raw", "BGRX", 0, 1
        ).copy()
        if image.getbbox() is None:
            raise RuntimeError("PrintWindow returned an all-black Analog_Floating2 image")
        return image
    finally:
        gdi32.SelectObject(memory_dc, old_bitmap)
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(memory_dc)
        user32.ReleaseDC(hwnd, window_dc)


def main():
    output_dir = Path(sys.argv[1])
    blueprint_path = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)
    desktop_path = output_dir / "Analog_Floating2_validation_desktop.png"
    crop_path = output_dir / "Analog_Floating2_validation_crop.png"
    overlay_path = output_dir / "Analog_Floating2_overlay.png"
    difference_path = output_dir / "Analog_Floating2_difference.png"
    result_path = output_dir / "Analog_Floating2_capture_result.json"

    hwnd = find_af2_window()
    original = get_rect(hwnd)
    validation = None
    restored = None
    try:
        move(hwnd, 2560, 384)
        validation = get_rect(hwnd)

        desktop = ImageGrab.grab(all_screens=True)
        desktop.save(desktop_path)

        # Capture the layered Rainmeter window itself. Desktop pixels and window
        # rectangles can use different coordinate spaces on mixed-DPI monitors.
        crop = capture_window(hwnd, validation["Width"], validation["Height"])
        crop.save(crop_path)

        blueprint_crop = (
            Image.open(blueprint_path).convert("RGB").crop((209, 47, 1459, 780))
        )
        # AF2 preserves the blueprint display aspect ratio: 1707x1000 centered
        # vertically in its 1707x1067 canvas.
        blueprint = Image.new("RGB", crop.size, (0, 0, 0))
        mapped = blueprint_crop.resize(
            (crop.width, round(crop.width * blueprint_crop.height / blueprint_crop.width)),
            Image.Resampling.LANCZOS,
        )
        blueprint.paste(mapped, (0, (crop.height - mapped.height) // 2))
        live = crop.convert("RGB")
        Image.blend(blueprint, live, 0.5).save(overlay_path)
        ImageChops.difference(blueprint, live).save(difference_path)
    finally:
        move(hwnd, original["X"], original["Y"])
        restored = get_rect(hwnd)
        result_path.write_text(
            json.dumps(
                {
                    "Original": original,
                    "RequestedValidation": {"X": 2560, "Y": 384},
                    "Validation": validation,
                    "PlacementAccepted": (
                        validation is not None
                        and validation["X"] == 2560
                        and validation["Y"] == 384
                    ),
                    "Restored": restored,
                    "Desktop": str(desktop_path),
                    "Crop": str(crop_path),
                    "Overlay": str(overlay_path),
                    "Difference": str(difference_path),
                },
                indent=2,
            ),
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
