# Keeps only the colors of a btop.theme someone else wrote, each written back
# as theme[key]="value". Run as: awk -f btop.awk btop.theme > clean
# A value is "#hex", "r g b", or empty; real themes also have spaces around the
# =, comments after the value, and stray text, which btop itself ignores.

BEGIN { HEX = "^#[0-9a-fA-F]+$" }

{
    line = $0
    sub(/\r$/, "", line)
    if (line ~ /^[ \t]*(#.*)?$/) next
    if (line !~ /^[ \t]*theme\[[a-zA-Z0-9_]+\][ \t]*=[ \t]*"[^"]*"[ \t]*(#.*)?$/) { dropped++; next }
    key = line; sub(/^[ \t]*theme\[/, "", key); sub(/\].*$/, "", key)
    value = line; sub(/^[^"]*"/, "", value); sub(/".*$/, "", value)
    n = length(value)
    if (value == "" || (value ~ HEX && (n == 3 || n == 4 || n == 7)) || value ~ /^[0-9]+ +[0-9]+ +[0-9]+$/) {
        printf "theme[%s]=\"%s\"\n", key, value
    } else {
        dropped++
    }
}

END { if (dropped) printf("theme: btop.theme: dropped %d line%s that were not colors\n", dropped, (dropped == 1 ? "" : "s")) > "/dev/stderr" }
