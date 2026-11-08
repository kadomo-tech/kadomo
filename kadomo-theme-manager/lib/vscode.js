// VS Code's files, edited for lib/vscode.sh. JavaScript for Automation, so
// nothing beyond macOS is needed. Run as: osascript -l JavaScript vscode.js <command> ...
//
//   register <extensions dir> <id> <version>   list a local extension folder <dir>/<id> in extensions.json
//   unregister <extensions dir> <id>     take it out again; prints the folder names it had
//   get <settings.json> [key]            the setting (workbench.colorTheme unless key names
//                                        another string setting); exit 1 when it is not set
//   set <settings.json> <value> [key]    prints settings.json with it set
//   unset <settings.json> [key]          prints settings.json without it
//   bare <settings.json>                 exit 0 when it holds nothing but {}
//
// settings.json is JSONC (comments, trailing commas), so it is edited as text:
// only the setting's line changes, the rest stays exactly as written.

ObjC.import('Foundation');
ObjC.import('stdlib');

const THEME = 'workbench.colorTheme';
const VALUE = '"(?:[^"\\\\\\n]|\\\\.)*"';
// A setting's name, quoted, as a regular expression.
function keyRe(key) { return JSON.stringify(key).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

// A setting's name: dotted words.
const KEY_OK = /^[A-Za-z0-9_.-]{1,100}$/;
// A theme's label: printable, and nothing that would need escaping in JSON.
const NAME_OK = /^[^\x00-\x1f\x7f"\\]{1,100}$/;
// Any other value (a font list quotes its names): printable, on one line.
const VALUE_OK = /^[^\x00-\x1f\x7f]{1,200}$/;
function checkKey(key) { if (!KEY_OK.test(key)) fail('not a setting: ' + key); return key; }

function abs(path) {
    return path.charAt(0) === '/' ? path : $.NSFileManager.defaultManager.currentDirectoryPath.js + '/' + path;
}
function read(path) {
    path = abs(path);
    const s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    return s.isNil() ? null : s.js;
}
function write(path, text) {
    path = abs(path);
    $(text).writeToFileAtomicallyEncodingError(path, false, $.NSUTF8StringEncoding, null) || fail('cannot write ' + path);
}
function out(text) {
    $.NSFileHandle.fileHandleWithStandardOutput.writeData($(text).dataUsingEncoding($.NSUTF8StringEncoding));
}
function fail(msg) { throw new Error(msg); }
function exists(path) { return $.NSFileManager.defaultManager.fileExistsAtPath(abs(path)); }
function parse(path, fallback) {
    const text = read(path);
    if (text === null) return fallback;
    try { return JSON.parse(text); } catch (e) { fail(path + ' is not valid JSON'); }
}

// Where the setting is: [index, prefix, quoted value], or null. On a line of
// its own, else anywhere on a line not commented out.
function find(text, key) {
    let m = new RegExp('^([ \\t]*' + keyRe(key) + '[ \\t]*:[ \\t]*)(' + VALUE + ')', 'm').exec(text);
    if (m) return [m.index, m[1], m[2]];
    const re = new RegExp('(' + keyRe(key) + '\\s*:\\s*)(' + VALUE + ')', 'g');
    while ((m = re.exec(text))) {
        const lineStart = text.lastIndexOf('\n', m.index) + 1;
        if (text.slice(lineStart, m.index).indexOf('//') < 0) return [m.index, m[1], m[2]];
    }
    return null;
}

function registry(dir) { return dir + '/extensions.json'; }

const commands = {
    register(dir, id, version) {
        const list = parse(registry(dir), []).filter(e => !(e.identifier && String(e.identifier.id).toLowerCase() === id.toLowerCase()));
        const path = dir + '/' + id;
        list.push({
            identifier: { id: id },
            version: version,
            location: { $mid: 1, fsPath: path, external: 'file://' + encodeURI(path), path: path, scheme: 'file' },
            relativeLocation: id,
        });
        write(registry(dir), JSON.stringify(list));
        // VS Code skips a folder it has marked for deletion.
        const obsolete = parse(dir + '/.obsolete', null);
        if (obsolete && (id in obsolete)) {
            delete obsolete[id];
            write(dir + '/.obsolete', JSON.stringify(obsolete));
        }
        return 0;
    },

    unregister(dir, id) {
        if (!exists(registry(dir))) return 0;
        const list = parse(registry(dir), []);
        const keep = [], gone = [];
        for (const e of list) {
            if (e.identifier && String(e.identifier.id).toLowerCase() === id.toLowerCase()) gone.push(e);
            else keep.push(e);
        }
        if (!gone.length) return 0;
        write(registry(dir), JSON.stringify(keep));
        for (const e of gone) {
            const rel = e.relativeLocation || String((e.location && (e.location.path || e.location.fsPath)) || '').split('/').pop();
            if (rel && rel.indexOf('/') < 0 && rel !== '.' && rel !== '..') out(rel + '\n');
        }
        return 0;
    },

    get(file, key) {
        key = checkKey(key || THEME);
        const text = read(file);
        const at = text === null ? null : find(text, key);
        if (!at) return 1;
        out(JSON.parse(at[2]) + '\n');
        return 0;
    },

    set(file, name, key) {
        key = checkKey(key || THEME);
        if (!(key === THEME ? NAME_OK : VALUE_OK).test(name)) fail('not a value for ' + key + ': ' + name);
        let text = read(file);
        if (text === null || !/\{/.test(text)) text = '{\n}\n';
        const at = find(text, key);
        const value = JSON.stringify(name);
        if (at) {
            text = text.slice(0, at[0]) + at[1] + value + text.slice(at[0] + at[1].length + at[2].length);
        } else {
            const open = text.indexOf('{') + 1;
            const empty = /^\s*\}/.test(text.slice(open));
            text = empty
                ? text.slice(0, open) + '\n    ' + JSON.stringify(key) + ': ' + value + '\n' + text.slice(open).replace(/^\s*/, '')
                : text.slice(0, open) + '\n    ' + JSON.stringify(key) + ': ' + value + ',' + text.slice(open);
        }
        out(text);
        return 0;
    },

    unset(file, key) {
        key = checkKey(key || THEME);
        let text = read(file);
        if (text === null) return 0;
        const line = new RegExp('^[ \\t]*' + keyRe(key) + '[ \\t]*:[ \\t]*' + VALUE + '[ \\t]*,?[ \\t]*\\r?\\n', 'm');
        if (line.test(text)) text = text.replace(line, '');
        else {
            const at = find(text, key);
            if (at) text = text.slice(0, at[0]) + text.slice(at[0] + at[1].length + at[2].length).replace(/^\s*,?/, '');
        }
        out(text);
        return 0;
    },

    bare(file) {
        const text = read(file);
        return text !== null && /^\s*\{\s*\}\s*$/.test(text) ? 0 : 1;
    },
};

function run(argv) {
    const fn = commands[argv[0]];
    if (!fn) { console.log('vscode.js: unknown command ' + argv[0]); $.exit(2); }
    let status;
    try { status = fn.apply(null, argv.slice(1)); } catch (e) { console.log('vscode.js: ' + e.message); $.exit(2); }
    $.exit(status || 0);
}
