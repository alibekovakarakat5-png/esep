"""Generate Esep logo: capital E with rounded ends on teal background."""
from PIL import Image, ImageDraw

def rounded_rect(draw, xy, radius, fill):
    """Draw a rectangle with rounded corners (pill shape if radius is large)."""
    x0, y0, x1, y1 = xy
    r = min(radius, (x1 - x0) // 2, (y1 - y0) // 2)
    # Four corners
    draw.ellipse([x0, y0, x0 + 2*r, y0 + 2*r], fill=fill)
    draw.ellipse([x1 - 2*r, y0, x1, y0 + 2*r], fill=fill)
    draw.ellipse([x0, y1 - 2*r, x0 + 2*r, y1], fill=fill)
    draw.ellipse([x1 - 2*r, y1 - 2*r, x1, y1], fill=fill)
    # Fill center
    draw.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
    draw.rectangle([x0, y0 + r, x1, y1 - r], fill=fill)

def create_logo(size, output_path, padding_ratio=0.22):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Teal background with rounded corners
    bg_radius = int(size * 0.22)
    # Teal gradient-like color (matching current: ~#1a9ca0 to #2bb5b5 ish)
    bg_color = (26, 163, 168)  # teal
    rounded_rect(draw, (0, 0, size - 1, size - 1), bg_radius, bg_color)

    # Letter E dimensions
    pad = int(size * padding_ratio)
    letter_left = pad + int(size * 0.05)
    letter_right = size - pad - int(size * 0.02)
    letter_top = pad
    letter_bottom = size - pad

    letter_w = letter_right - letter_left
    letter_h = letter_bottom - letter_top

    # Bar thickness
    bar_h = int(letter_h * 0.16)
    bar_radius = bar_h // 2  # fully rounded ends

    # Vertical bar (left side)
    vert_w = int(letter_w * 0.25)
    rounded_rect(draw, (letter_left, letter_top, letter_left + vert_w, letter_bottom),
                 bar_radius, 'white')

    # Top horizontal bar
    rounded_rect(draw, (letter_left, letter_top, letter_right, letter_top + bar_h),
                 bar_radius, 'white')

    # Middle horizontal bar (slightly shorter)
    mid_y = letter_top + (letter_h - bar_h) // 2
    mid_right = letter_right - int(letter_w * 0.08)
    rounded_rect(draw, (letter_left, mid_y, mid_right, mid_y + bar_h),
                 bar_radius, 'white')

    # Bottom horizontal bar
    rounded_rect(draw, (letter_left, letter_bottom - bar_h, letter_right, letter_bottom),
                 bar_radius, 'white')

    img.save(output_path, 'PNG')
    print(f"Saved {output_path} ({size}x{size})")

# Main icon
create_logo(1024, r'c:\Users\USER\Desktop\esep\assets\icon\esep_icon.png')
# Adaptive icon (slightly more padding)
create_logo(1024, r'c:\Users\USER\Desktop\esep\assets\icon\esep_icon_adaptive.png', padding_ratio=0.28)
# Favicon
create_logo(192, r'c:\Users\USER\Desktop\esep\web\favicon.png')
