"""Encode supplied artwork for web delivery without changing the originals."""
from pathlib import Path
from PIL import Image
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--source', default='../assets-dev')
parser.add_argument('--output', default='dist/assets/art')
args = parser.parse_args()
source, output = Path(args.source), Path(args.output)
output.mkdir(parents=True, exist_ok=True)
total = 0
for original in sorted(source.glob('*.png')):
    name = original.stem.lower().replace('elysl_', 'elys_')
    image = Image.open(original).convert('RGBA')
    if name == 'logo':
        variants = [(output / 'logo.webp', (768, 420))]
    elif name == 'civilization':
        # The supplied civilization icon has substantial transparent padding.
        bounds = image.getchannel('A').getbbox()
        if bounds:
            image = image.crop(bounds)
        variants = [(output / 'civilization.webp', (160, 160))]
    elif name.startswith(('race_', 'resource_', 'pop_')):
        variants = [(output / (name + '.webp'), (160, 160))]
    else:
        variants = [(output / (name + '.webp'), (768, 768)),
                    (output / (name + '-map.webp'), (112, 112))]
    for destination, size in variants:
        optimized = image.copy()
        optimized.thumbnail(size, Image.Resampling.LANCZOS)
        optimized.save(destination, 'WEBP', quality=88, method=6)
        total += destination.stat().st_size
print(f'Prepared artwork: {total:,} bytes. Original PNG files unchanged.')
