# Fills in a template's {{ ... }} placeholders from a resolved palette.
# Run as: awk -f render.awk palette.tsv template.tpl > output
#
#   {{ key }}            #7aa2f7
#   {{ key_strip }}      7aa2f7
#   {{ key_rgb }}        122,162,247
#   {{ key_argb }}       0xff7aa2f7 (SketchyBar and the like)
#   {{ mix a b 30% }}    a blended 30% toward b; also mix_strip, mix_rgb,
#                        mix_argb. a and b are keys or literal colors, the
#                        amount 0.3 or 30%.
#   {{ readable c bg 4.5 }} c, or c moved toward black or white (away from bg)
#                        just far enough for a WCAG contrast of 4.5 against bg
#   {{ hypr_gradient key fallback }}    rgba(rrggbbaa) ... 45deg
#   {{ gradient_start key fallback }}   the first color, #rrggbb
#   {{ shell_gradient key fallback }}   "#aaaaaa #bbbbbb 45": colors, then the angle
#   {{ toml_gradient key fallback }}    ["#aaaaaa", "#bbbbbb"], or "#aaaaaa"
#   {{ omniwm_borders key fallback }}   OmniWM's [borders.color] table (the
#                        first color), and a [borders.gradient] when there
#                        are two or more
#   {{ borders_color key fallback }}    a JankyBorders color: 0xAARRGGBB, or
#                        gradient(top_left=0x...,bottom_right=0x...) from the
#                        first and last colors when there are two or more
#
# A gradient helper reads key as "colors... angle" (hyprland_active_border);
# when the theme has no such key it uses fallback, another key or a color.
# A placeholder it cannot fill is left as is, with a warning.

function warn(msg) { printf "theme: %s: %s\n", FILENAME, msg > "/dev/stderr" }

function hexval(h,   i, n) {
    n = 0
    h = tolower(h)
    for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
    return n
}
function hex2(n) { n = int(n + 0.5); if (n < 0) n = 0; if (n > 255) n = 255; return sprintf("%02x", n) }
function is_color(v) { return v ~ /^#[0-9a-f]+$/ && length(v) == 7 }

# A key's color, or a literal color, or "".
function color(x,   h) {
    if ((x in P) && is_color(P[x])) return P[x]
    h = tolower(x); sub(/^0x/, "", h); sub(/^#/, "", h)
    if (h ~ /^[0-9a-f]+$/ && length(h) == 6) return "#" h
    return ""
}

function strip(c) { return substr(c, 2) }
function rgb(c) { return hexval(substr(c, 2, 2)) "," hexval(substr(c, 4, 2)) "," hexval(substr(c, 6, 2)) }
function argb(c, a) { return "0x" (a == "" ? "ff" : a) substr(c, 2) }

function mix(a, b, t,   ar, ag, ab, br, bg, bb) {
    ar = hexval(substr(a, 2, 2)); ag = hexval(substr(a, 4, 2)); ab = hexval(substr(a, 6, 2))
    br = hexval(substr(b, 2, 2)); bg = hexval(substr(b, 4, 2)); bb = hexval(substr(b, 6, 2))
    return "#" hex2(ar + (br - ar) * t) hex2(ag + (bg - ag) * t) hex2(ab + (bb - ab) * t)
}

# WCAG relative luminance and contrast ratio.
function lin(v) { v = v / 255; return v <= 0.04045 ? v / 12.92 : exp(2.4 * log((v + 0.055) / 1.055)) }
function rel_lum(c) {
    return 0.2126 * lin(hexval(substr(c, 2, 2))) + 0.7152 * lin(hexval(substr(c, 4, 2))) + 0.0722 * lin(hexval(substr(c, 6, 2)))
}
function contrast(a, b,   la, lb) {
    la = rel_lum(a); lb = rel_lum(b)
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05)
}
# c itself when it reads well enough on bg; else c blended in 5% steps toward
# black (light bg) or white (dark bg) until it does. Deterministic.
function readable(c, bg, ratio,   toward, t, out) {
    if (contrast(c, bg) >= ratio) return c
    toward = rel_lum(bg) > 0.18 ? "#000000" : "#ffffff"
    for (t = 0.05; t <= 1.0001; t += 0.05) {
        out = mix(c, toward, t)
        if (contrast(out, bg) >= ratio) return out
    }
    return toward
}

# Formats a color for a suffix: "" (#hex), strip, rgb, argb.
function as(c, form, alpha) {
    if (form == "strip") return strip(c)
    if (form == "rgb") return rgb(c)
    if (form == "argb") return argb(c, alpha)
    return c
}

# Splits a gradient into G[1..GN] (#rrggbb), GA[i] (alpha hex) and GANGLE
# (degrees, "" when none). Uses the key, else the fallback key or color.
function gradient(key, fallback,   spec, n, i, parts, t, h) {
    GN = 0; GANGLE = ""
    spec = (key in P) ? P[key] : ""
    if (spec == "") { spec = color(fallback); if (spec == "") return 0 }
    n = split(spec, parts, /[ \t]+/)
    for (i = 1; i <= n; i++) {
        t = tolower(parts[i])
        if (t == "") continue
        if (t ~ /^[0-9]+deg$/) { GANGLE = substr(t, 1, length(t) - 3) + 0; continue }
        h = t
        if (h ~ /^rgba?\(/) { h = substr(h, index(h, "(") + 1); sub(/\)$/, "", h) }
        else if (h ~ /^0x/) { h = substr(h, 5) substr(h, 3, 2) }   # 0xAARRGGBB -> RRGGBBAA
        else sub(/^#/, "", h)
        if (h !~ /^[0-9a-f]+$/ || (length(h) != 6 && length(h) != 8)) return 0
        GN++
        G[GN] = "#" substr(h, 1, 6)
        GA[GN] = length(h) == 8 ? substr(h, 7, 2) : "ff"
    }
    return GN > 0
}

# A color as an OmniWM settings.toml color table: 0.0-1.0 floats.
function omniwm_color(table, c, a) {
    return "[" table "]\n" \
        sprintf("alpha = %.4f\nblue = %.4f\ngreen = %.4f\nred = %.4f", hexval(a) / 255,
            hexval(substr(c, 6, 2)) / 255, hexval(substr(c, 4, 2)) / 255, hexval(substr(c, 2, 2)) / 255)
}

function amount(s) {
    if (s ~ /%$/) return substr(s, 1, length(s) - 1) / 100
    return s + 0
}

# The value of one placeholder's expression, or the unique NOFILL marker.
function evaluate(expr,   n, w, i, out, a, b, form, base, sfx) {
    gsub(/^[ \t]+|[ \t]+$/, "", expr)
    n = split(expr, w, /[ \t]+/)
    if (n == 1) {
        if (expr in P) return P[expr]
        if (match(expr, /_(strip|rgb|argb)$/)) {
            base = substr(expr, 1, RSTART - 1); sfx = substr(expr, RSTART + 1)
            if ((base in P) && is_color(P[base])) return as(P[base], sfx, "")
        }
        return NOFILL
    }
    if (w[1] ~ /^mix(_strip|_rgb|_argb)?$/ && n == 4) {
        a = color(w[2]); b = color(w[3])
        if (a == "" || b == "") return NOFILL
        form = (w[1] == "mix") ? "" : substr(w[1], 5)
        return as(mix(a, b, amount(w[4])), form, "")
    }
    if (w[1] == "readable" && n == 4) {
        a = color(w[2]); b = color(w[3])
        if (a == "" || b == "" || w[4] !~ /^[0-9]+(\.[0-9]+)?$/) return NOFILL
        return readable(a, b, w[4] + 0)
    }
    if (n == 3 && gradient(w[2], w[3])) {
        if (w[1] == "gradient_start") return G[1]
        if (w[1] == "hypr_gradient") {
            out = ""
            for (i = 1; i <= GN; i++) out = out (i > 1 ? " " : "") "rgba(" strip(G[i]) GA[i] ")"
            return out (GANGLE != "" ? " " GANGLE "deg" : "")
        }
        if (w[1] == "shell_gradient") {
            out = ""
            for (i = 1; i <= GN; i++) out = out (i > 1 ? " " : "") G[i]
            return out (GN > 1 ? " " (GANGLE == "" ? 0 : GANGLE) : "")
        }
        if (w[1] == "omniwm_borders") {
            out = omniwm_color("borders.color", G[1], GA[1])
            if (GN == 1) return out
            # OmniWM draws diagonal gradients only: angles from 90 to 180 (and
            # 270 to 360) run top right to bottom left, the rest top left to
            # bottom right.
            a = (GANGLE == "") ? 45 : GANGLE % 180
            return out "\n\n[borders.gradient]\ndirection = \"" (a > 90 ? "topRightToBottomLeft" : "topLeftToBottomRight") \
                "\"\nenabled = true\n\n" omniwm_color("borders.gradient.end", G[GN], GA[GN]) \
                "\n\n" omniwm_color("borders.gradient.start", G[1], GA[1])
        }
        if (w[1] == "borders_color") {
            if (GN == 1) return argb(G[1], GA[1])
            # JankyBorders draws two-color diagonal gradients: more colors keep
            # the first and the last, and the angle picks the diagonal (as for OmniWM).
            a = (GANGLE == "") ? 45 : GANGLE % 180
            if (a > 90) return "gradient(top_right=" argb(G[1], GA[1]) ",bottom_left=" argb(G[GN], GA[GN]) ")"
            return "gradient(top_left=" argb(G[1], GA[1]) ",bottom_right=" argb(G[GN], GA[GN]) ")"
        }
        if (w[1] == "toml_gradient") {
            if (GN == 1) return "\"" G[1] "\""
            out = "["
            for (i = 1; i <= GN; i++) out = out (i > 1 ? ", " : "") "\"" G[i] "\""
            return out "]"
        }
    }
    return NOFILL
}

BEGIN { NOFILL = "\001nofill\001" }

FNR == NR {
    tab = index($0, "\t")
    if (tab > 0) P[substr($0, 1, tab - 1)] = substr($0, tab + 1)
    next
}

{
    line = $0; out = ""
    while (match(line, /\{\{[^}]*\}\}/)) {
        # evaluate() calls match() too, so keep where this placeholder is.
        start = RSTART; len = RLENGTH
        expr = substr(line, start + 2, len - 4)
        value = evaluate(expr)
        if (value == NOFILL) {
            warn("line " FNR ": cannot fill {{" expr "}}")
            value = substr(line, start, len)
        }
        out = out substr(line, 1, start - 1) value
        line = substr(line, start + len)
    }
    print out line
}
