-- Kadomo: OmniWM's volume widget with the speaker icon alone, no percentage.
-- SPDX-License-Identifier: GPL-2.0-only
-- Based on OmniWM's volume widget and its lib/skin and lib/audio helpers,
-- Copyright (C) 2026 OmniNull (https://github.com/OmniNull/OmniWM).
--
-- omniwm/install.sh puts this in ~/.config/omniwm/shell/widgets/volume, where
-- OmniWM uses it over its own volume widget, and omniwm/uninstall.sh takes it
-- away again. The speaker's waves still show roughly how loud it is; clicking
-- it opens the same sound panel, and scrolling over it changes the volume.
-- OmniWM lets only its own widgets require its helpers, so the parts of them
-- this needs are copied in below.

---------------------------------------------------------------------------
-- look: OmniWM's default bar skin (lib/skin.luau with capsules on), only the
-- parts the volume button and its panel use.
---------------------------------------------------------------------------
local look = { base = 32, hover = "foreground/0.08", width = 320 }

function look.scale(ctx)
    return ctx.data.bar.style.height / look.base
end

local function capsuled(ctx)
    local bar = ctx and ctx.data.bar and ctx.data.bar.style
    return bar and bar.transparent and bar.backgrounds
end

function look.text(props)
    return ui.text(props)
end

function look.glyph(props)
    return ui.symbol(props)
end

function look.bar(ctx, props)
    local bar = ctx.data.bar.style
    local scale = look.scale(ctx)
    local capsule = capsuled(ctx)
    local size = bar.height - 4
    props.gap = props.gap or 5 * scale
    props.pad = props.pad or 4 * scale
    props.radius = 6 * scale
    if props.onClick or props.onRightClick then
        props.hover = props.hover or look.hover
    end
    if capsule then
        props.radius = size / 2
        props.fill = props.fill or "surface"
        props.border = props.border or "border"
        props.borderWidth = props.borderWidth or 0.5
        local edge = math.max(0, math.round(size * 0.3) - props.gap)
        if not bar.vertical and not props.w then
            props.pad = 0
            table.insert(props, 1, ui.box{ w = edge, h = 1 })
            props[#props + 1] = ui.box{ w = edge, h = 1 }
        elseif bar.vertical and not props.h then
            props.pad = 0
            table.insert(props, 1, ui.box{ w = 1, h = edge })
            props[#props + 1] = ui.box{ w = 1, h = edge }
        end
    elseif bar.backgrounds then
        props.fill = props.fill or "foreground/0.06"
    end
    if bar.vertical then
        props.w = props.w or size
        return ui.column(props)
    end
    props.h = props.h or size
    return ui.row(props)
end

function look.panel(ctx, props)
    props.pad = props.pad or 14
    props.gap = props.gap or 12
    props.radius = 20
    props.material = "glass"
    props.center = false
    if capsuled(ctx) then
        props.radius = 14
        props.material = "clear"
        props.fill = "background"
        props.border = "border"
        props.borderWidth = 1
    end
    return ui.column(props)
end

function look.group(props)
    props.pad = props.pad or 12
    props.gap = props.gap or 8
    props.radius = 12
    props.fill = props.fill or "surface"
    props.center = false
    return ui.column(props)
end

function look.heading(text, width)
    return ui.row{ w = width, look.text{ text = text, size = 14, weight = "semibold" } }
end

function look.button(name, action)
    return ui.stack{ w = 28, h = 28, radius = 7, hover = look.hover, onClick = action,
        look.glyph{ name = name, size = 14, weight = "medium" } }
end

---------------------------------------------------------------------------
-- audio: OmniWM's lib/audio.luau.
---------------------------------------------------------------------------
local audio = {}
local PRECISE_POINTS_PER_STEP = 12
local TRANSPORT = {
    builtin = "laptopcomputer", usb = "cable.connector", bluetooth = "headphones", hdmi = "display",
    displayport = "display", airplay = "airplayaudio", thunderbolt = "bolt.horizontal",
}

function audio.symbol(volume: number?, muted: boolean?): string
    if not volume then
        return "speaker.fill"
    end
    if muted or volume == 0 then
        return "speaker.slash.fill"
    end
    return if volume < 34 then "speaker.wave.1.fill" elseif volume < 67 then "speaker.wave.2.fill"
        else "speaker.wave.3.fill"
end

function audio.scroll(ctx, event)
    local delta = if event.precise then event.dy / PRECISE_POINTS_PER_STEP else event.dy
    local total = ctx.state.scroll or 0
    if total * delta < 0 then
        total = 0
    end
    total += delta
    local steps = if total >= 0 then math.floor(total) else math.ceil(total)
    ctx.state.scroll = total - steps
    if steps ~= 0 then
        local size = tonumber((ctx.data.settings or {}).step) or 6.25
        omniwm.run(string.format("volume %s %g", if steps > 0 then "up" else "down", math.abs(steps) * size))
    end
end

local function setVolume(_, event)
    if event.value then
        omniwm.run(string.format("volume set %d", math.round(event.value * 100)))
    end
end

function audio.state(ctx)
    local volume = ctx.data.volume
    local muted = ctx.data.muted == true
    return { volume = volume, muted = muted, level = volume and volume / 100, symbol = audio.symbol(volume, muted),
        percent = volume and ctx.format.percent(volume / 100), set = setVolume, mute = "volume mute",
        muteSymbol = if muted then "speaker.wave.2" else "speaker.slash" }
end

function audio.model(ctx)
    local m = audio.state(ctx)
    m.outputs = {}
    for _, device in ctx.data.outputs or {} do
        m.outputs[#m.outputs + 1] = { name = device.name, default = device.default == true,
            symbol = TRANSPORT[device.transport] or "hifispeaker.fill", select = "volume output " .. device.id }
    end
    local apps = ctx.data.audioApps
    m.permission = if apps and apps.access == "denied" then "volume permission" else nil
    m.apps = {}
    for _, entry in if apps then apps.apps else {} do
        if entry.playing or entry.muted or entry.volume < 100 then
            local id = entry.id
            m.apps[#m.apps + 1] = { id = id, name = entry.name, playing = entry.playing, muted = entry.muted,
                level = entry.volume / 100,
                symbol = if entry.muted then "speaker.slash.fill" else "speaker.wave.2.fill",
                mute = "volume app " .. id .. " mute",
                set = function(_, event)
                    if event.value then
                        omniwm.run(string.format("volume app %s set %d", id, math.round(event.value * 100)))
                    end
                end }
        end
    end
    return m
end

function audio.level(ctx, width, m)
    local inner = width - 24
    if not m.volume then
        return look.group{ w = width,
            look.text{ text = omniwm.l10n("Unavailable"), size = 13, color = "secondaryForeground" } }
    end
    return look.group{ w = width,
        look.heading(omniwm.l10n("Sound")),
        ui.row{ w = inner, gap = 8,
            look.glyph{ name = m.symbol, w = 18, h = 18 },
            ui.slider{ value = m.level, w = inner - 112, h = 16, color = if m.muted then "mutedForeground" else "accent",
                onChange = m.set },
            look.text{ text = m.percent, size = 12, w = 42, reserve = ctx.format.percent(1) },
            look.button(m.muteSymbol, m.mute) } }
end

function audio.content(ctx, width, m)
    local inner = width - 24
    local rows = { w = width, gap = 12, center = false, audio.level(ctx, width, m) }
    local outputs = { w = width, gap = 4, look.heading(omniwm.l10n("Output")) }
    for _, output in m.outputs do
        outputs[#outputs + 1] = ui.row{ w = inner, gap = 8, pad = 6, radius = 7, hover = look.hover,
            onClick = output.select,
            look.glyph{ name = output.symbol, w = 18, h = 18 },
            look.text{ text = output.name, size = 13, grow = 1, maxWidth = inner - 62,
                weight = if output.default then "semibold" else nil },
            look.glyph{ name = "checkmark", w = 14, h = 14, color = "accent", opacity = if output.default then 1 else 0 } }
    end
    if #outputs > 1 then
        rows[#rows + 1] = look.group(outputs)
    end
    if m.permission then
        rows[#rows + 1] = look.group{ w = width, hover = look.hover, onClick = m.permission,
            ui.row{ w = inner, gap = 8,
                look.glyph{ name = "lock.fill", w = 16, h = 16, color = "secondaryForeground" },
                look.text{ text = omniwm.l10n("Allow System Audio Recording to set app volumes"), size = 13,
                    maxWidth = inner - 24, lines = 2 } } }
    end
    local mixer = { w = width, look.heading(omniwm.l10n("Applications")) }
    for _, app in m.apps do
        mixer[#mixer + 1] = ui.row{ w = inner, gap = 8,
            ui.icon{ app = app.id, w = 18, h = 18, opacity = if app.playing then 1 else 0.6 },
            look.text{ text = app.name, size = 13, w = 92, maxWidth = 92 },
            ui.slider{ value = app.level, w = inner - 162, h = 14, color = if app.muted then "mutedForeground" else "accent",
                onChange = app.set },
            look.button(app.symbol, app.mute) }
    end
    if #mixer > 1 then
        rows[#rows + 1] = look.group(mixer)
    end
    return ui.column(rows)
end

---------------------------------------------------------------------------
-- The widget: OmniWM's, without the percentage next to the speaker.
---------------------------------------------------------------------------
function render(ctx)
    local m = audio.state(ctx)
    return look.bar(ctx, { onClick = ui.popout, onScroll = audio.scroll, help = omniwm.l10n("Volume"),
        look.glyph{ name = m.symbol, size = 14 * look.scale(ctx) } })
end

function popout(ctx)
    return look.panel(ctx, { w = look.width + 28, audio.content(ctx, look.width, audio.model(ctx)) })
end
