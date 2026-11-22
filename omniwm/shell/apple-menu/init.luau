-- Kadomo: the Omarchy logo in place of the Apple logo in OmniWM's menu bar.
-- omniwm/install.sh puts this in ~/.config/omniwm/shell/widgets/apple-menu,
-- where OmniWM uses it over its own apple-menu widget, and omniwm/uninstall.sh
-- takes it away again. Clicking it still opens the Apple menu. The logo is the
-- glyph Omarchy's own bar shows (U+E900 in Omarchy's omarchy.ttf, MIT
-- licensed), as a path on a 24 by 24 grid.

local LOGO = "M1.641 22.359H12.867V24H0V0H24V24H14.672V22.359H22.359V1.641H1.641Z"
    .. "M20.719 20.719H3.281V3.281H12.914V4.922H4.922V19.078H19.078V4.922H17.25V3.281H20.719Z"
    .. "M11.039 20.719H12.867V22.359H11.039ZM11.086 1.641H12.914V3.281H11.086ZM0 11.086H4.922V12.914H0Z"
-- Room between the screen's left edge and the logo, in points.
local GAP = 6

function render(ctx: Context)
    local style = ctx.data.bar.style
    -- Like OmniWM's own, only when its bar stands in for the macOS menu bar.
    if not style.hidesMenuBar then
        return ui.box{ w = 0, h = 0 }
    end
    local size = math.max(16, style.height - 4)
    local logo = math.min(18, math.max(12, size - 8))
    local capsule = style.transparent and style.backgrounds
    return ui.row{ ui.box{ w = GAP, h = size },
        ui.stack{ w = size, h = size, onClick = "menu apple", help = omniwm.l10n("Apple Menu"),
            radius = if capsule then size / 2 else 4, hover = if style.solidBlack then "#FFFFFF1F" else "foreground/0.12",
            ui.path{ w = logo, h = logo, viewBox = { 0, 0, 24, 24 }, d = LOGO,
                fill = if style.solidBlack then "#FFFFFF" else "foreground" } } }
end
