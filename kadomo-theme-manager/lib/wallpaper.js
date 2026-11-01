// Sets or reads the desktop picture of every display, through NSWorkspace, so
// no app needs permission to control another. Run as
// osascript -l JavaScript wallpaper.js <command>:
//
//   set <image>             shows the image on every display and every Space
//   spread [store]          copies the newest desktop picture in macOS's
//                           wallpaper store to every Space and display
//   set-each <image>... [-- <dir>...]
//                           one image per display, as get lists them; with
//                           dirs, every other Space still showing an image
//                           under one of them then gets that display's new one
//   get                     prints each display's picture, one path per line
//   save <file>             copies macOS's wallpaper store (every Space and
//                           display, dynamic and aerial pictures too) to file
//   restore <file> <dir>... puts back, from a store saved with save, every
//                           Space's and display's desktop picture that now
//                           shows an image under one of the dirs (all of them
//                           when no dir is given); the screen saver and any
//                           picture chosen since are left alone
//   render <out.png> <background> <accent>
//                           draws a wallpaper from two #rrggbb colors, the size
//                           of the largest display: the background, deepening
//                           toward one corner, with a soft glow of the accent
//
// NSWorkspace only changes the Space showing on each display. set then copies
// that new entry (macOS's own, so its format is always right) to every other
// Space and display in the wallpaper store, and restarts WallpaperAgent so the
// other Spaces show it too.
ObjC.import('AppKit');
ObjC.import('stdio');

function run(argv) {
    var workspace = $.NSWorkspace.sharedWorkspace;
    var screens = $.NSScreen.screens;
    var count = Number(screens.count), i;
    if (argv[0] === 'get') {
        var paths = [];
        for (i = 0; i < count; i++) {
            var url = workspace.desktopImageURLForScreen(screens.objectAtIndex(i));
            if (!url.isNil()) paths.push(url.path.js);
        }
        return paths.join('\n');
    }
    if (argv[0] === 'render') return render(argv[1], argv[2], argv[3], screens, count);
    if (argv[0] === 'spread') return spread(argv[1] || STORE, 0, !argv[1]);
    if (argv[0] === 'save') return save(argv[1]);
    if (argv[0] === 'restore') return restore(argv[1], argv.slice(2));
    var started = Date.now() / 1000;
    var each = argv[0] === 'set-each';
    var cut = argv.indexOf('--'), dirs = [];
    if (each && cut > 0) { dirs = argv.slice(cut + 1); argv = argv.slice(0, cut); }
    if ((argv[0] !== 'set' && !each) || !argv[1]) throw new Error('usage: wallpaper.js set <image> | set-each <image>... | get | save <file> | restore <file> [dir...]');
    var options = $.NSDictionary.dictionary;
    var failed = 0;
    for (i = 0; i < count; i++) {
        // set-each gives each display its own image, in the order get printed them.
        var path = each ? argv[Math.min(i + 1, argv.length - 1)] : argv[1];
        var image = $.NSURL.fileURLWithPath($(path));
        if (!workspace.setDesktopImageURLForScreenOptionsError(image, screens.objectAtIndex(i), options, null)) failed++;
    }
    if (failed) throw new Error('could not set the wallpaper on ' + failed + ' display(s)');
    if (!each) {
        try { spread(STORE, started, true); }
        catch (e) { console.log('wallpaper: set on this Space only (' + e.message + ')'); }
    } else if (dirs.length) {
        // The uninstaller putting each display's old picture back: every
        // other Space showing Kadomo's gets the one just set on its display.
        try { return replaceOurs(started, dirs); }
        catch (e) { console.log('wallpaper: set on this Space only (' + e.message + ')'); }
    }
}

function replaceOurs(since, dirs) {
    var root, all, fresh, tries = 0, i;
    for (;;) {
        root = readStore(STORE);
        all = desktops(root, []);
        fresh = all.filter(function (d) { return lastSet(d.entry) >= since - 1; });
        if (fresh.length) break;
        if (++tries > 50) throw new Error('macOS did not record the new picture');
        $.NSThread.sleepForTimeInterval(0.1);
    }
    var newest = function (list) { var best = null; list.forEach(function (d) { if (!best || lastSet(d.entry) > lastSet(best)) best = d.entry; }); return best; };
    var display = function (key) { var m = /(?:^|\/)Displays\/([^\/]+)/.exec(key); return m ? m[1] : null; };
    var fallback = newest(fresh), changed = 0;
    for (i = 0; i < all.length; i++) {
        if (lastSet(all[i].entry) >= since - 1 || !showsUnder(all[i].entry, dirs)) continue;
        var id = display(all[i].key);
        var same = id ? fresh.filter(function (d) { return display(d.key) === id; }) : [];
        all[i].parent.setObjectForKey(newest(same) || fallback, 'Desktop');
        changed++;
    }
    if (!changed) return '';
    write(root, STORE);
    if (TEST_STORE.isNil()) $.NSTask.launchedTaskWithLaunchPathArguments('/usr/bin/killall', ['WallpaperAgent']).waitUntilExit;
    return changed + ' entr' + (changed === 1 ? 'y' : 'ies') + ' updated';
}

// Whether a Desktop entry shows a file under one of the dirs.
function showsUnder(entry, dirs) {
    var files = filesIn(entry, []);
    return dirs.some(function (d) {
        d = d.replace(/\/+$/, '') + '/';
        return files.some(function (f) { return f.indexOf(d) === 0; });
    });
}

// KADOMO_WALLPAPER_STORE stands in for it in the tests, and WallpaperAgent is
// then left running.
var TEST_STORE = $.NSProcessInfo.processInfo.environment.objectForKey('KADOMO_WALLPAPER_STORE');
var STORE = TEST_STORE.isNil() ? $.NSHomeDirectory().js + '/Library/Application Support/com.apple.wallpaper/Store/Index.plist' : TEST_STORE.js;

// Every Desktop entry in the store: Displays/<display>, Spaces/<space>/Default,
// Spaces/<space>/Displays/<display>, and AllSpacesAndDisplays when it has one.
// `key` is where it sits (Spaces/<space>/Default, say), to find it in another store.
function desktops(node, out, key) {
    if (!node.isKindOfClass($.NSDictionary)) return out;
    var keys = node.allKeys, n = Number(keys.count), i;
    for (i = 0; i < n; i++) {
        var name = keys.objectAtIndex(i), value = node.objectForKey(name);
        if (name.js === 'Desktop' && value.isKindOfClass($.NSDictionary) && !value.objectForKey('Content').isNil()) out.push({ parent: node, entry: value, key: key || '' });
        else desktops(value, out, (key ? key + '/' : '') + name.js);
    }
    return out;
}

function lastSet(entry) {
    var date = entry.objectForKey('LastSet');
    return date.isNil() || !date.isKindOfClass($.NSDate) ? 0 : Number(date.timeIntervalSince1970);
}

function readStore(path) {
    var data = $.NSData.dataWithContentsOfFile(path);
    if (data.isNil()) throw new Error('cannot read the wallpaper store');
    // 1: mutable containers, so the entries can be replaced in place.
    var root = $.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 1, null, null);
    if (root.isNil() || !root.isKindOfClass($.NSDictionary)) throw new Error('the wallpaper store is not a property list');
    return root;
}

// Copies the newest Desktop entry (set at or after `since`) over every other.
// macOS writes the store a moment after NSWorkspace returns: wait up to 5 s.
function spread(path, since, restart) {
    var root, all, newest, tries = 0, i;
    for (;;) {
        root = readStore(path);
        all = desktops(root, []);
        newest = null;
        for (i = 0; i < all.length; i++) if (!newest || lastSet(all[i].entry) > lastSet(newest)) newest = all[i].entry;
        if (newest && lastSet(newest) >= since - 1) break;
        if (++tries > 50) throw new Error('macOS did not record the new picture');
        $.NSThread.sleepForTimeInterval(0.1);
    }
    var changed = 0;
    for (i = 0; i < all.length; i++) {
        if (all[i].entry.isEqual(newest)) continue;
        all[i].parent.setObjectForKey(newest, 'Desktop');
        changed++;
    }
    if (!changed) return '';
    write(root, path);
    // WallpaperAgent reads the store when it starts; launchd starts it again.
    if (restart) $.NSTask.launchedTaskWithLaunchPathArguments('/usr/bin/killall', ['WallpaperAgent']).waitUntilExit;
    return changed + ' entr' + (changed === 1 ? 'y' : 'ies') + ' updated';
}

function write(root, path) {
    // 200: binary, as macOS writes it.
    var data = $.NSPropertyListSerialization.dataWithPropertyListFormatOptionsError(root, 200, 0, null);
    if (data.isNil()) throw new Error('cannot encode the wallpaper store');
    // Written beside it, then renamed over it, so WallpaperAgent never reads
    // half a file.
    var temp = path + '.kadomo-tmp';
    if (!data.writeToFileOptionsError($(temp), 0, null) || $.rename(temp, path) !== 0) {
        $.NSFileManager.defaultManager.removeItemAtPathError($(temp), null);
        throw new Error('cannot write the wallpaper store');
    }
}

function save(file) {
    if (!file) throw new Error('usage: wallpaper.js save <file>');
    readStore(STORE); // a store that is there and readable, or an error
    var fm = $.NSFileManager.defaultManager;
    fm.removeItemAtPathError($(file), null);
    if (!fm.copyItemAtPathToPathError($(STORE), $(file), null)) throw new Error('cannot copy the wallpaper store to ' + file);
    return file;
}

// The file paths a Desktop entry shows: its file URLs, including those inside
// the encoded configuration data macOS keeps for some choices.
function filesIn(node, out) {
    if (node.isNil()) return out;
    var i, n;
    if (node.isKindOfClass($.NSString)) {
        var s = node.js;
        if (s.indexOf('file://') === 0) { var url = $.NSURL.URLWithString(node); if (!url.isNil() && !url.path.isNil()) out.push(url.path.js); }
        else if (s.charAt(0) === '/') out.push(s);
    } else if (node.isKindOfClass($.NSURL)) {
        if (!node.path.isNil()) out.push(node.path.js);
    } else if (node.isKindOfClass($.NSData)) {
        var inner = $.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(node, 0, null, null);
        if (!inner.isNil()) filesIn(inner, out);
    } else if (node.isKindOfClass($.NSDictionary)) {
        var keys = node.allKeys;
        for (i = 0, n = Number(keys.count); i < n; i++) filesIn(node.objectForKey(keys.objectAtIndex(i)), out);
    } else if (node.isKindOfClass($.NSArray)) {
        for (i = 0, n = Number(node.count); i < n; i++) filesIn(node.objectAtIndex(i), out);
    }
    return out;
}

function restore(file, dirs) {
    if (!file) throw new Error('usage: wallpaper.js restore <file> [dir...]');
    var saved = desktops(readStore(file), []);
    var byKey = {}, fallback = null, i;
    for (i = 0; i < saved.length; i++) {
        byKey[saved[i].key] = saved[i].entry;
        if (!fallback || lastSet(saved[i].entry) > lastSet(fallback)) fallback = saved[i].entry;
    }
    var root = readStore(STORE), all = desktops(root, []), changed = 0;
    for (i = 0; i < all.length; i++) {
        if (dirs.length && !showsUnder(all[i].entry, dirs)) continue;
        // A Space made since has no saved entry: it gets the picture shown last before.
        var before = byKey.hasOwnProperty(all[i].key) ? byKey[all[i].key] : fallback;
        if (before) all[i].parent.setObjectForKey(before, 'Desktop');
        else all[i].parent.removeObjectForKey('Desktop'); // macOS's default then
        changed++;
    }
    if (!changed) return '';
    write(root, STORE);
    if (TEST_STORE.isNil()) $.NSTask.launchedTaskWithLaunchPathArguments('/usr/bin/killall', ['WallpaperAgent']).waitUntilExit;
    return changed + ' entr' + (changed === 1 ? 'y' : 'ies') + ' restored';
}

function color(hex) {
    var m = /^#?([0-9a-fA-F]{6})$/.exec(hex || '');
    if (!m) throw new Error('not a #rrggbb color: ' + hex);
    var v = parseInt(m[1], 16);
    return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
}

function mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
function ns(c, alpha) { return $.NSColor.colorWithSRGBRedGreenBlueAlpha(c[0], c[1], c[2], alpha === undefined ? 1 : alpha); }

function render(out, backgroundHex, accentHex, screens, count) {
    if (!out) throw new Error('usage: wallpaper.js render <out.png> <background> <accent>');
    var bg = color(backgroundHex), accent = color(accentHex);
    var width = 3840, height = 2160, i;
    for (i = 0; i < count; i++) {
        var screen = screens.objectAtIndex(i), scale = Number(screen.backingScaleFactor);
        var w = Math.round(Number(screen.frame.size.width) * scale), h = Math.round(Number(screen.frame.size.height) * scale);
        if (w * h > width * height || i === 0) { width = w; height = h; }
    }
    width = Math.max(1280, Math.min(width, 7680)); height = Math.max(720, Math.min(height, 4320));
    var light = 0.2126 * bg[0] + 0.7152 * bg[1] + 0.0722 * bg[2] > 0.5;
    var deep = mix(bg, light ? [1, 1, 1] : [0, 0, 0], light ? 0.35 : 0.45);
    var rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
        null, width, height, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
    if (rep.isNil()) throw new Error('could not make an image');
    $.NSGraphicsContext.saveGraphicsState;
    // A JXA property assignment does not call the setter: set the context explicitly.
    $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep));
    var rect = $.NSMakeRect(0, 0, width, height);
    $.NSGradient.alloc.initWithStartingColorEndingColor(ns(bg), ns(deep)).drawInRectAngle(rect, -35);
    // The accent as light from the lower right, fading out well before the middle.
    var glow = $.NSGradient.alloc.initWithStartingColorEndingColor(ns(accent, light ? 0.22 : 0.30), ns(accent, 0));
    // Drawn over the whole picture (a smaller rect would clip it to hard edges).
    glow.drawInRectRelativeCenterPosition(rect, $.NSMakePoint(0.7, -0.75));
    $.NSGraphicsContext.restoreGraphicsState;
    var png = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $.NSDictionary.dictionary);
    if (png.isNil() || !png.writeToFileAtomically(out, false)) throw new Error('could not write ' + out);
    return out;
}
