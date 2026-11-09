# Resolves a theme's colors.toml into a complete palette, one "key<TAB>value"
# line per key. Run as: awk -f palette.awk colors.toml
#
# - Every color comes out as lowercase #rrggbb. A value that is not a color
#   (or, for mode, not dark or light) is dropped with a warning, so nothing
#   but hex digits ever reaches a generated config or script.
# - Missing keys fall back to their neighbours or a blend of them, so a
#   minimal theme still renders.
# - Aliases (bg, fg, purple, cursor, ...) and the 16 ANSI slots (color0 to
#   color15) are filled in. A theme may set any alias or slot itself.
# - Gradient keys (hyprland_active_border) keep their "colors... angle" text
#   when it is well formed.

# A message can quote a value from the file: no terminal escape sequences.
function warn(msg) { gsub(/[[:cntrl:]]/, "?", msg); printf "theme: %s: %s\n", FILENAME, msg > "/dev/stderr" }

function hexval(h,   i, n, c) {
    n = 0
    h = tolower(h)
    for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
    return n
}

# "#abc", "#aabbcc", "#aabbccdd", "aabbcc", "0xaabbcc" -> "#aabbcc", else "".
function norm(v,   h, n) {
    h = tolower(v)
    sub(/^0x/, "", h); sub(/^#/, "", h)
    if (h !~ /^[0-9a-f]+$/) return ""
    n = length(h)
    if (n == 3) return "#" substr(h,1,1) substr(h,1,1) substr(h,2,1) substr(h,2,1) substr(h,3,1) substr(h,3,1)
    if (n == 6) return "#" h
    if (n == 8) return "#" substr(h, 1, 6)
    return ""
}

function hex2(n) { n = int(n + 0.5); if (n < 0) n = 0; if (n > 255) n = 255; return sprintf("%02x", n) }

# Linear RGB blend: t = 0 gives a, t = 1 gives b.
function mix(a, b, t,   ar, ag, ab, br, bg, bb) {
    ar = hexval(substr(a, 2, 2)); ag = hexval(substr(a, 4, 2)); ab = hexval(substr(a, 6, 2))
    br = hexval(substr(b, 2, 2)); bg = hexval(substr(b, 4, 2)); bb = hexval(substr(b, 6, 2))
    return "#" hex2(ar + (br - ar) * t) hex2(ag + (bg - ag) * t) hex2(ab + (bb - ab) * t)
}

function luminance(c) {
    return (0.2126 * hexval(substr(c, 2, 2)) + 0.7152 * hexval(substr(c, 4, 2)) + 0.0722 * hexval(substr(c, 6, 2))) / 255
}

# One gradient token: rgba(rrggbbaa), rgb(rrggbb), #rrggbb[aa], 0xaarrggbb, or Ndeg.
function gradient_ok(v,   n, i, parts, t) {
    n = split(v, parts, /[ \t]+/)
    if (n == 0) return 0
    for (i = 1; i <= n; i++) {
        t = tolower(parts[i])
        if (t == "") continue
        if (t ~ /^[0-9]+deg$/ && i == n && i > 1) continue
        if (t ~ /^rgba?\([0-9a-f]+\)$/) { t = substr(t, index(t, "(") + 1); t = substr(t, 1, length(t) - 1); if (length(t) == 6 || length(t) == 8) continue }
        if (t ~ /^#[0-9a-f]+$/ && (length(t) == 7 || length(t) == 9)) continue
        if (t ~ /^0x[0-9a-f]+$/ && length(t) == 10) continue
        return 0
    }
    return 1
}

function set(k, v) { if (!(k in P)) { P[k] = v; order[++count] = k } else P[k] = v }
function has(k) { return (k in P) && P[k] != "" }
function fill(k, v) { if (!has(k)) set(k, v) }

BEGIN { count = 0 }

# key = "value" or key = 'value', at the top level. Tables are not part of
# the schema; their keys are ignored.
/^[ \t]*\[/ { intable = 1; next }
{
    line = $0
    sub(/^[ \t]+/, "", line)
    if (line == "" || substr(line, 1, 1) == "#" || intable) next
    eq = index(line, "=")
    if (eq == 0) next
    key = substr(line, 1, eq - 1); sub(/[ \t]+$/, "", key)
    val = substr(line, eq + 1); sub(/^[ \t]+/, "", val)
    q = substr(val, 1, 1)
    if (q == "\"" || q == "'") {
        val = substr(val, 2)
        end = index(val, q)
        if (end == 0) { warn("unterminated string for " key); next }
        val = substr(val, 1, end - 1)
    } else {
        sub(/[ \t]*#.*$/, "", val)
    }
    if (key !~ /^[a-z][a-z0-9_]*$/) { warn("ignored key " key); next }
    if (key == "mode" || key == "theme_type") {
        v = tolower(val)
        if (v == "dark" || v == "light") raw["mode"] = v
        else warn("mode must be dark or light, not " val)
        next
    }
    if (key ~ /_border$/ && norm(val) == "") {
        if (gradient_ok(val)) raw[key] = val
        else warn("ignored " key ": not a color or gradient")
        next
    }
    c = norm(val)
    if (c == "") { warn("ignored " key ": not a color (" val ")"); next }
    raw[key] = c
}

END {
    # Aliases a theme may use instead of the canonical name.
    split("bg:background fg:foreground dark_bg:dark_background darker_bg:darker_background lighter_bg:lighter_background dark_fg:dark_foreground light_fg:light_foreground bright_fg:bright_foreground purple:magenta bright_purple:bright_magenta", A, " ")
    for (i in A) { split(A[i], kv, ":"); if ((kv[1] in raw) && !(kv[2] in raw)) raw[kv[2]] = raw[kv[1]] }

    mode = raw["mode"]
    bg = raw["background"]; fg = raw["foreground"]
    if (mode == "") mode = (bg != "" && luminance(bg) > 0.5) ? "light" : "dark"
    if (bg == "") bg = (mode == "light") ? "#f5f5f5" : "#1a1a1a"
    if (fg == "") fg = (mode == "light") ? "#303030" : "#d0d0d0"
    toward = (mode == "light") ? "#000000" : "#ffffff"

    set("mode", mode)
    set("background", bg)
    set("foreground", fg)
    for (k in raw) if (k != "mode") set(k, raw[k])

    fill("dark_background", mix(bg, "#000000", 0.2))
    fill("darker_background", mix(bg, "#000000", 0.4))
    fill("lighter_background", mix(bg, fg, 0.08))
    fill("dark_foreground", mix(fg, bg, 0.4))
    fill("light_foreground", mix(fg, toward, 0.15))
    fill("bright_foreground", mix(fg, toward, 0.3))

    # Base colors from One Dark when a theme has none; brights lean toward the foreground side.
    fill("red", "#e06c75"); fill("green", "#98c379"); fill("yellow", "#e5c07b")
    fill("blue", "#61afef"); fill("magenta", "#c678dd"); fill("cyan", "#56b6c2")
    fill("orange", mix(P["red"], P["yellow"], 0.5))
    fill("brown", mix(P["orange"], "#000000", 0.45))
    split("red green yellow blue magenta cyan", base, " ")
    for (i = 1; i <= 6; i++) fill("bright_" base[i], mix(P[base[i]], toward, 0.15))
    fill("bright_orange", mix(P["orange"], toward, 0.15))

    fill("accent", P["blue"])
    # Semantic colors (the Starship prompt): success, failure, and changes.
    fill("success", P["green"]); fill("error", P["red"]); fill("warning", P["yellow"])
    fill("selection", mix(bg, fg, 0.2))
    fill("muted", mix(bg, fg, 0.35))
    fill("inactive_border", P["lighter_background"])
    # Editor shades (Vim and Neovim): comments, the cursor line, inactive
    # windows, and diff backgrounds.
    fill("comment", mix(bg, fg, 0.4))
    fill("shade", mix(bg, fg, 0.06))
    fill("dim_background", mix(bg, fg, 0.04))
    fill("diff_background", mix(bg, P["blue"], 0.1))

    # Canonical names under their short aliases too.
    fill("bg", P["background"]); fill("fg", P["foreground"])
    fill("dark_bg", P["dark_background"]); fill("darker_bg", P["darker_background"])
    fill("lighter_bg", P["lighter_background"]); fill("dark_fg", P["dark_foreground"])
    fill("light_fg", P["light_foreground"]); fill("bright_fg", P["bright_foreground"])
    fill("purple", P["magenta"]); fill("bright_purple", P["bright_magenta"])
    fill("cursor", P["bright_foreground"])
    fill("theme_type", mode)
    fill("selection_background", P["selection"])
    fill("selection_foreground", P["foreground"])

    split("background red green yellow blue magenta cyan foreground muted bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_foreground", ansi, " ")
    for (i = 1; i <= 16; i++) fill("color" (i - 1), P[ansi[i]])

    for (i = 1; i <= count; i++) printf "%s\t%s\n", order[i], P[order[i]]
}
