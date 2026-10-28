"""Draw the app icon and pack it into resources/icon.icns.

Run with the project's Python:  python tools/make_icon.py
A macOS-style rounded square with a blue gradient and a white bus (our own drawing).
"""
import os, shutil, subprocess, tempfile
from AppKit import (
    NSBezierPath, NSBitmapImageRep, NSColor, NSGradient, NSGraphicsContext, NSImage,
    NSMakeRect, NSPNGFileType, NSCompositingOperationSourceOver, NSCompositingOperationClear,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'resources', 'icon.icns')


def draw(size):
    rep = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, size, size, 8, 4, True, False, 'NSDeviceRGBColorSpace', 0, 0)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.setCurrentContext_(NSGraphicsContext.graphicsContextWithBitmapImageRep_(rep))

    # Apple's icon grid: the shape fills ~80% of the canvas, corner radius ~22.5% of the shape.
    inset = size * 0.1
    box = NSMakeRect(inset, inset, size - 2 * inset, size - 2 * inset)
    radius = box.size.width * 0.225
    # soft drop shadow
    shadow = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        NSMakeRect(box.origin.x, box.origin.y - size * 0.012, box.size.width, box.size.height), radius, radius)
    NSColor.colorWithCalibratedWhite_alpha_(0, 0.22).setFill()
    shadow.fill()
    shape = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(box, radius, radius)
    NSGradient.alloc().initWithStartingColor_endingColor_(
        NSColor.colorWithSRGBRed_green_blue_alpha_(0.30, 0.62, 1.00, 1),    # top
        NSColor.colorWithSRGBRed_green_blue_alpha_(0.05, 0.33, 0.86, 1),    # bottom
    ).drawInBezierPath_angle_(shape, -90)

    # Bus (front view), drawn as our own shapes: SF Symbols may not be used in app icons.
    bus = NSImage.alloc().initWithSize_((size, size))
    bus.lockFocus()
    u = size  # shapes are laid out on a 0..1 grid

    def rr(x0, y0, x1, y1, r):
        return NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            NSMakeRect(x0 * u, y0 * u, (x1 - x0) * u, (y1 - y0) * u), r * u, r * u)

    NSColor.whiteColor().setFill()
    rr(0.30, 0.25, 0.70, 0.78, 0.075).fill()   # body
    rr(0.255, 0.56, 0.29, 0.68, 0.015).fill()  # mirrors
    rr(0.71, 0.56, 0.745, 0.68, 0.015).fill()
    rr(0.33, 0.18, 0.42, 0.27, 0.025).fill()   # wheels
    rr(0.58, 0.18, 0.67, 0.27, 0.025).fill()
    # cut-outs (transparent, so the gradient shows through)
    NSGraphicsContext.currentContext().setCompositingOperation_(NSCompositingOperationClear)
    rr(0.345, 0.475, 0.655, 0.725, 0.04).fill()                       # windscreen
    for cx in (0.375, 0.625):                                         # headlights
        NSBezierPath.bezierPathWithOvalInRect_(NSMakeRect((cx - 0.032) * u, 0.335 * u, 0.064 * u, 0.064 * u)).fill()
    rr(0.445, 0.35, 0.555, 0.385, 0.017).fill()                       # grille
    rr(0.30, 0.425, 0.70, 0.44, 0.0).fill()                           # bumper line
    bus.unlockFocus()
    bus.drawInRect_fromRect_operation_fraction_(
        NSMakeRect(0, 0, size, size), NSMakeRect(0, 0, 0, 0), NSCompositingOperationSourceOver, 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representationUsingType_properties_(NSPNGFileType, {})


def main():
    work = tempfile.mkdtemp()
    iconset = os.path.join(work, 'icon.iconset')
    os.makedirs(iconset)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            suffix = '' if scale == 1 else '@2x'
            draw(px).writeToFile_atomically_(os.path.join(iconset, f'icon_{pt}x{pt}{suffix}.png'), True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', OUT], check=True)
    draw(512).writeToFile_atomically_(os.path.join(os.path.dirname(OUT), 'icon.png'), True)  # preview for the README
    shutil.rmtree(work)
    print('wrote', OUT)


if __name__ == '__main__':
    main()
