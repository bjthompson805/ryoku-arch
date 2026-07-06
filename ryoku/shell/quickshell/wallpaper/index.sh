#!/bin/sh
# Wallpaper index for the switcher overlay. One thumbnail and one dominant-colour
# reading per wallpaper, for images (~/Pictures/Wallpapers) and videos
# (~/Pictures/livewalls) alike, printed as TSV for the Walls singleton:
#
#   type<TAB>mtime<TAB>path<TAB>thumb<TAB>hue<TAB>sat
#
# Thumb and hue are cached beside each other and only rebuilt when the source is
# newer, so a warm run returns at once. Only the untrusted original -> thumbnail
# decode runs through the shared magick cage; the hue reading is taken from the
# thumbnail we just made, and video posters come from ffmpeg's first frame.
wpdir="$HOME/Pictures/Wallpapers"
livedir="$HOME/Pictures/livewalls"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/ryoku-wp-thumbs"
policy="$HOME/.config/hypr/scripts/magick-policy"
mkdir -p "$cache"

# decode an untrusted image through the cage when the policy is present.
caged() {
    if [ -d "$policy" ]; then MAGICK_CONFIGURE_PATH="$policy" magick "$@"; else magick "$@"; fi
}

# drop cached thumbs + hues whose source is gone.
for f in "$cache"/*.png; do
    [ -e "$f" ] || continue
    b=$(basename "$f" .png)
    [ -e "$wpdir/$b" ] || [ -e "$livedir/$b" ] || rm -f "$f" "$cache/$b.hue"
done

emit() {
    kind=$1 src=$2
    [ -e "$src" ] || return
    name=$(basename "$src")
    thumb="$cache/$name.png"
    huef="$cache/$name.hue"
    if [ ! -s "$thumb" ] || [ "$src" -nt "$thumb" ]; then
        if [ "$kind" = live ]; then
            ffmpeg -y -loglevel error -ss 1 -i "$src" -frames:v 1 -vf "scale=512:-2" "$thumb.tmp.png" 2>/dev/null
            [ -s "$thumb.tmp.png" ] || ffmpeg -y -loglevel error -i "$src" -frames:v 1 -vf "scale=512:-2" "$thumb.tmp.png" 2>/dev/null
        else
            caged "${src}[0]" -strip -resize 512x "$thumb.tmp.png" 2>/dev/null
        fi
        if [ -s "$thumb.tmp.png" ]; then mv "$thumb.tmp.png" "$thumb"; rm -f "$huef"; else rm -f "$thumb.tmp.png"; fi
    fi
    [ -s "$thumb" ] || return
    if [ ! -s "$huef" ]; then
        magick "$thumb" -resize 1x1! -colorspace HSL -format '%[fx:u.r*360] %[fx:u.g*100]' info: >"$huef" 2>/dev/null || echo "0 0" >"$huef"
    fi
    read -r hue sat <"$huef"
    mtime=$(stat -c %Y "$src" 2>/dev/null || echo 0)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$mtime" "$src" "$thumb" "${hue:-0}" "${sat:-0}"
}

for src in "$wpdir"/*; do
    case "$src" in
        *.jpg|*.jpeg|*.png|*.webp|*.JPG|*.JPEG|*.PNG|*.WEBP) emit image "$src" ;;
    esac
done
for src in "$livedir"/*; do
    case "$src" in
        *.mp4|*.webm|*.mkv|*.MP4|*.WEBM|*.MKV) emit live "$src" ;;
    esac
done
