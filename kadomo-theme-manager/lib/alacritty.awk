# Turns an older theme's alacritty.toml into a colors.toml, for themes that
# predate colors.toml. Run as: awk -f alacritty.awk alacritty.toml > colors.toml
# Reads [colors.primary], [colors.normal], [colors.bright], [colors.cursor] and
# [colors.selection]; the ANSI slots are kept exactly, as color0 to color15.
# Only hex colors are copied; palette.awk checks them again.

function norm(v,   h) {
    h = tolower(v); sub(/^0x/, "", h); sub(/^#/, "", h)
    return (h ~ /^[0-9a-f]+$/ && length(h) == 6) ? "#" h : ""
}

/^[ \t]*\[/ {
    section = $0
    gsub(/[][ \t]/, "", section)
    next
}
{
    line = $0
    if (line !~ /=/) next
    key = line; sub(/[ \t]*=.*/, "", key); gsub(/[ \t"']/, "", key)
    val = line; sub(/^[^=]*=[ \t]*/, "", val); gsub(/["']/, "", val); sub(/[ \t#].*$/, "", val)
    c = norm(val)
    if (c != "") C[section "." key] = c
}

function out(key, from) { if (from in C) printf "%s = \"%s\"\n", key, C[from] }

END {
    print "# Imported from alacritty.toml."
    out("background", "colors.primary.background")
    out("foreground", "colors.primary.foreground")
    out("bright_foreground", "colors.primary.bright_foreground")
    out("cursor", "colors.cursor.cursor")
    out("selection", "colors.selection.background")
    out("selection_foreground", "colors.selection.text")
    split("black red green yellow blue magenta cyan white", names, " ")
    for (i = 1; i <= 8; i++) {
        if (names[i] != "black" && names[i] != "white") {
            out(names[i], "colors.normal." names[i])
            out("bright_" names[i], "colors.bright." names[i])
        }
        out("color" (i - 1), "colors.normal." names[i])
        out("color" (i + 7), "colors.bright." names[i])
    }
    out("muted", "colors.bright.black")
    out("accent", "colors.normal.blue")
}
