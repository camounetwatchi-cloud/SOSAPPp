#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import os

# Créer le répertoire s'il n'existe pas
os.makedirs('assets/icon', exist_ok=True)

# Créer une nouvelle image 512x512 avec fond rouge
img = Image.new('RGB', (512, 512), color='red')
draw = ImageDraw.Draw(img)

# Dessiner un cercle blanc au centre
circle_box = [100, 100, 412, 412]
draw.ellipse(circle_box, fill='white')

# Ajouter le texte "SOS" en noir au centre
try:
    # Essayer avec une police système
    font = ImageFont.truetype("arial.ttf", 120)
except:
    # Utiliser la police par défaut si Arial n'existe pas
    font = ImageFont.load_default()

text = "SOS"
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
text_height = bbox[3] - bbox[1]

x = (512 - text_width) // 2
y = (512 - text_height) // 2 + 20

draw.text((x, y), text, fill='red', font=font)

# Sauvegarder l'image
img.save('assets/icon/icon.png')
print("Icône créée avec succès: assets/icon/icon.png")
