// Edits LinearMouse's linearmouse.json for Kadomo: adds, updates, or removes
// the one Moonlight profile Kadomo owns, and leaves every other scheme and key
// as it was.
//
// osascript -l JavaScript linearmouse.js <command> <arguments>:
//   apply  <config> <scheme JSON> <recorded.json or ""> <$schema URL or ""> <dry run: 0 or 1>
//          prints "<outcome> <other schemes>", the outcome being
//            added      Kadomo's profile was not there
//            updated    it was, as Kadomo last wrote it, and now differs or was not last
//            unchanged  it is there, last, and as wanted
//            edited     it was changed since Kadomo wrote it: left alone
//            conflict   another Moonlight profile is there: nothing added
//   remove <config> <recorded.json> <dry run: 0 or 1>
//          prints "<outcome> <other schemes>": removed, edited (removed, and it
//          had been changed since Kadomo wrote it), or absent
//   count  <config>
//          prints how many schemes there are
//
// Kadomo's profile is the scheme whose "if" is exactly Kadomo's. LinearMouse
// rewrites the file in its own canonical form and drops keys it does not know,
// so a marker inside the scheme would not survive, and every comparison goes
// through canon() so a rewrite by LinearMouse does not count as an edit.

ObjC.import('Foundation');
ObjC.import('stdio');

const MOONLIGHT = 'com.moonlight-stream.Moonlight';
const files = $.NSFileManager.defaultManager;

// LinearMouse's canonical form: a one-element array is saved as its element,
// and { vertical: x, horizontal: x } as x. Keys are sorted.
function canon(value) {
    if (Array.isArray(value)) return value.length === 1 ? canon(value[0]) : value.map(canon);
    if (value && typeof value === 'object') {
        const keys = Object.keys(value).sort();
        if (keys.length === 2 && keys[0] === 'horizontal' && keys[1] === 'vertical' &&
            same(value.horizontal, value.vertical)) {
            return canon(value.vertical);
        }
        const out = {};
        keys.forEach(key => { out[key] = canon(value[key]); });
        return out;
    }
    return value;
}

function same(a, b) {
    return JSON.stringify(canon(a)) === JSON.stringify(canon(b));
}

function conditions(scheme) {
    const c = scheme && scheme['if'];
    if (c == null) return [];
    return Array.isArray(c) ? c : [c];
}

// Whether a scheme applies to Moonlight in any of the ways LinearMouse can match an app.
function targetsMoonlight(scheme) {
    return conditions(scheme).some(c => c && (
        [c.app, c.parentApp, c.groupApp].indexOf(MOONLIGHT) >= 0 ||
        c.processName === 'Moonlight' ||
        String(c.processPath || '').indexOf('/Moonlight.app/') >= 0));
}

function readText(path) {
    const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    if (text.isNil()) throw new Error('could not read ' + path);
    return ObjC.unwrap(text);
}

function readJSON(path, what) {
    try {
        return JSON.parse(readText(path));
    } catch (e) {
        throw new Error(what + ' is not valid JSON: ' + path + ' (' + e.message + ')');
    }
}

// The config, or null when there is none yet. An empty file counts as an empty config.
function loadConfig(path) {
    if (!files.fileExistsAtPath(path)) return null;
    const text = readText(path);
    if (text.trim() === '') return {};
    let config;
    try {
        config = JSON.parse(text);
    } catch (e) {
        throw new Error(path + ' is not valid JSON, so it was left alone (' + e.message + ')');
    }
    if (!config || typeof config !== 'object' || Array.isArray(config) ||
        (config.schemes != null && !Array.isArray(config.schemes))) {
        throw new Error(path + ' is not a LinearMouse configuration, so it was left alone');
    }
    return config;
}

// Writes through a symbolic link, as LinearMouse does, rather than replacing it.
function saveConfig(path, config) {
    const target = ObjC.unwrap($(path).stringByResolvingSymlinksInPath);
    const dir = ObjC.unwrap($(target).stringByDeletingLastPathComponent);
    files.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $.NSDictionary.dictionary, null);
    // Written next to it, then renamed over it: LinearMouse never reads half a file.
    const temp = target + '.kadomo-' + $.NSProcessInfo.processInfo.processIdentifier;
    const ok = $(JSON.stringify(config, null, 2) + '\n')
        .writeToFileAtomicallyEncodingError(temp, false, $.NSUTF8StringEncoding, null);
    if (!ok || $.rename(temp, target) !== 0) {
        files.removeItemAtPathError(temp, null);
        throw new Error('could not write ' + target);
    }
}

function apply(path, schemeText, recordFile, schemaURL, dryRun) {
    const wanted = JSON.parse(schemeText);
    const recorded = recordFile ? readJSON(recordFile, 'the recorded profile') : null;
    const config = loadConfig(path);
    const schemes = (config && config.schemes) || [];
    const ours = s => same(s && s['if'], wanted['if']);
    const mine = schemes.filter(ours);
    const others = schemes.filter(s => !ours(s));

    let outcome;
    if (mine.length === 0) {
        if (others.some(targetsMoonlight)) return 'conflict ' + others.length;
        outcome = 'added';
    } else if (recorded ? !same(mine[0], recorded) : !same(mine[0], wanted)) {
        // Changed since Kadomo wrote it, or written by someone else with the same "if".
        return (recorded ? 'edited ' : 'conflict ') + others.length;
    } else {
        outcome = 'updated';
    }

    // Last, so it wins over any broader scheme (such as "every mouse") while Moonlight is in front.
    const next = others.concat([wanted]);
    if (outcome === 'updated' && JSON.stringify(next.map(canon)) === JSON.stringify(schemes.map(canon))) {
        return 'unchanged ' + others.length;
    }
    if (!dryRun) {
        if (config) {
            config.schemes = next;
            saveConfig(path, config);
        } else {
            const fresh = schemaURL ? { '$schema': schemaURL } : {};
            fresh.schemes = next;
            saveConfig(path, fresh);
        }
    }
    return outcome + ' ' + others.length;
}

function remove(path, recordFile, dryRun) {
    const recorded = readJSON(recordFile, 'the recorded profile');
    const config = loadConfig(path);
    const schemes = (config && config.schemes) || [];
    const ours = s => same(s && s['if'], recorded['if']);
    const mine = schemes.filter(ours);
    const others = schemes.filter(s => !ours(s));
    if (mine.length === 0) return 'absent ' + others.length;
    const outcome = mine.some(s => !same(s, recorded)) ? 'edited' : 'removed';
    if (!dryRun) {
        config.schemes = others;
        saveConfig(path, config);
    }
    return outcome + ' ' + others.length;
}

function run(argv) {
    switch (argv[0]) {
        case 'apply': return apply(argv[1], argv[2], argv[3], argv[4], argv[5] === '1');
        case 'remove': return remove(argv[1], argv[2], argv[3] === '1');
        case 'count': {
            const config = loadConfig(argv[1]);
            return String(((config && config.schemes) || []).length);
        }
        default: throw new Error('unknown command: ' + argv[0]);
    }
}
