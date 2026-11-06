# DMG background

Approved option 4: Sigma Serif Headline at 28 pt with 4.5 pt additional tracking, centered in a 660 × 440 pt window. `background.tiff` contains 1× and 2× renditions and is used directly by `Tools/package.sh`.

The font binary is not included in the repository or installer. Regenerating requires a locally supplied, appropriately licensed Sigma Serif Headline font:

```sh
DMG_TITLE_FONT_PATH=/path/to/font.woff swift Tools/dmg/render-background.swift Tools/dmg
tiffutil -cathidpicheck Tools/dmg/background{,@2x}.png -out Tools/dmg/background.tiff
```
