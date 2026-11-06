// Registers a font file with macOS for this user, as Font Book does, or takes
// that back. A file in ~/Library/Fonts is not always enough: macOS can leave it
// out of its list of fonts, and the bar then draws in a fallback font.
//
// Usage: osascript -l JavaScript fonts.js register|unregister <file>
// Prints "registered" or "unregistered" when it changed something, else nothing.

ObjC.import('CoreText');
ObjC.import('Foundation');

const USER_SCOPE = 2; // kCTFontManagerScopeUser
const NO_SCOPE = 0;

function run(argv) {
    const action = argv[0];
    const url = $.NSURL.fileURLWithPath(argv[1]);
    const scope = $.CTFontManagerGetScopeForURL(url);
    if (action === 'register') {
        if (scope !== NO_SCOPE) return '';
        if (!$.CTFontManagerRegisterFontsForURL(url, USER_SCOPE, null)) throw new Error('could not register ' + argv[1]);
        return 'registered';
    }
    if (action === 'unregister') {
        if (scope !== USER_SCOPE) return '';
        if (!$.CTFontManagerUnregisterFontsForURL(url, USER_SCOPE, null)) throw new Error('could not unregister ' + argv[1]);
        return 'unregistered';
    }
    throw new Error('unknown action: ' + action);
}
