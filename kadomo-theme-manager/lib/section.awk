# Replaces one [section] of a generated TOML file with a theme's own version
# (kadomo-menu.colors.toml replaces [colors] of kadomo-menu.toml).
# Run as: awk -v section=colors -f section.awk override.toml generated.toml
# The section runs from its header to the next header. A section the file
# does not have yet is added at the end. The override may leave out its header.

function header(line,   h) {
    h = line
    sub(/^[ \t]*\[/, "", h); sub(/\][ \t]*(#.*)?$/, "", h)
    gsub(/[ \t]/, "", h)
    return h
}
function emit_override(   i) {
    if (!has_header) print "[" section "]"
    for (i = 1; i <= n; i++) print over[i]
    done = 1
}

FNR == NR {
    if ($0 ~ /^[ \t]*\[[^]]+\]/ && header($0) == section) { has_header = 1 }
    over[++n] = $0
    next
}

/^[ \t]*\[[^]]+\]/ {
    if (header($0) == section) { emit_override(); skipping = 1; next }
    skipping = 0
}
!skipping { print }
END { if (!done) { print ""; emit_override() } }
