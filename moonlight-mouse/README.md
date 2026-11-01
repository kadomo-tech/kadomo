# Moonlight Mouse Optimization (LinearMouse)

Makes a mouse in [Moonlight](https://moonlight-stream.org) behave like one on a
Windows PC, without changing the mouse anywhere else on the Mac.

```sh
./install.sh            # or pick it in Kadomo's ./install.sh checklist (it starts unchecked)
./install.sh --dry-run  # show what would change
./uninstall.sh          # undo it; --yes also removes a LinearMouse Kadomo installed
```

## What it does

1. Installs [LinearMouse](https://linearmouse.app) with `brew install --cask linearmouse`,
   unless it is already on this Mac (however it got there).
2. Adds one profile (a LinearMouse *scheme*) to LinearMouse's config,
   `~/.config/linearmouse/linearmouse.json`, or
   `~/Library/Application Support/linearmouse/linearmouse.json` when that file
   exists, since LinearMouse reads that one first:

   ```json
   {
     "if": { "app": "com.moonlight-stream.Moonlight", "device": { "category": "mouse" } },
     "pointer": { "disableAcceleration": true },
     "scrolling": {
       "acceleration": 1, "distance": 3, "reverse": true,
       "smoothed": { "enabled": false }, "speed": 0
     }
   }
   ```

   It applies only to a mouse (not a trackpad), and only while Moonlight is the
   frontmost app. `"distance": 3` is LinearMouse's "By Lines" mode: each wheel
   step is exactly 3 lines, with no acceleration and no momentum. Acceleration 1
   and speed 0 are LinearMouse's "no change" values, set explicitly so that a
   broader profile of yours (say, one for every mouse) cannot add acceleration
   back inside Moonlight. The profile goes last in the list, so it wins over
   broader ones.
3. Adds a launch agent, `~/Library/LaunchAgents/com.kadomo.linearmouse.plist`,
   that opens LinearMouse each time you log in. It runs once and exits, needs
   no permission, and shows up in System Settings › General › Login Items.
   (LinearMouse's own *Start at login* can only be switched from inside
   LinearMouse, so Kadomo can't turn that on for you. Turning it on as well
   does no harm.)
4. Starts LinearMouse if it isn't running, in the foreground, so you see
   macOS's prompts, and checks that it really started. LinearMouse watches its
   config and reloads it by itself, so nothing needs a restart.

Anything that still needs you, such as allowing Accessibility, is listed under
**Still needs you** at the end of the installer's output.

macOS's own mouse settings are not changed. LinearMouse needs **Accessibility**
access, which only you can grant: the first time it starts, it asks, and you
allow it in System Settings › Privacy & Security › Accessibility.

### Your LinearMouse settings

- Every other profile and setting in `linearmouse.json` is kept as it is.
- The file is backed up next to itself (`linearmouse.json.bak.<timestamp>`)
  before Kadomo changes it, unless Kadomo created it.
- Running the installer again changes nothing when nothing needs changing.
- If you edit Kadomo's profile, the installer leaves your version alone.
- If there is already a Moonlight profile that isn't Kadomo's, the installer
  doesn't touch it and doesn't add its own. Delete that profile in
  LinearMouse and run the installer again if you want Kadomo's instead.

Kadomo recognises its profile by its exact `if`, and keeps a copy of what it
wrote in `~/Library/Application Support/kadomo/moonlight-mouse/`. A marker
inside the profile wouldn't survive, because LinearMouse rewrites the file in
its own form and drops keys it doesn't know.

## Scroll direction

Moonlight gets the wheel from macOS after natural scrolling has already been
applied, and passes it to Windows unchanged except for its own **Reverse mouse
scrolling direction** option. So the profile's `reverse` is worked out at
install time, to make wheel-down scroll down in Windows:

| macOS natural scrolling | Moonlight's reverse option | `reverse` |
| --- | --- | --- |
| on (macOS default) | off (Moonlight default) | `true` |
| on | on | `false` (Moonlight already undoes it; no double reverse) |
| off | off | `false` |
| off | on | `true` |

If you change either setting later, run `./install.sh` again and it updates the
profile.

## What it can't promise

- **Scroll distance in Windows.** On macOS, Moonlight sends each wheel event to
  Windows as at most one notch. A wheel step therefore scrolls whatever
  Windows' *Settings › Bluetooth & devices › Mouse › Lines to scroll at a time*
  says (3 by default). What LinearMouse fixes is that one step is now always
  exactly one event: no acceleration, no momentum, and no bursts of extra
  notches.
- **In-game acceleration.** LinearMouse turns off macOS pointer acceleration
  for the mouse while Moonlight is in front. With Moonlight's default game mode
  (the pointer captured), Moonlight sends the movement macOS reports. That
  should now be unaccelerated, but Kadomo hasn't verified it inside a game.
  Windows' **Enhance pointer precision** and any acceleration setting in the
  game are separate, and only you can turn them off.
- **"Optimize mouse for remote desktop instead of games"** in Moonlight makes
  the Windows cursor follow the Mac pointer, so there the Mac pointer settings
  above are exactly what you feel.

## Troubleshooting

- **Nothing changed in Moonlight.** Check that LinearMouse is running (its icon
  is in the menu bar, or `pgrep -fl LinearMouse.app` prints a line) and has
  Accessibility access. If you had to grant it, quit and reopen LinearMouse.
- **Is the profile being used?** Run
  `log stream --info --predicate 'subsystem == "com.lujjjh.LinearMouse"' | grep --line-buffered "Initialize EventTransformer"`,
  then click into Moonlight and scroll. A line naming
  `com.moonlight-stream.Moonlight` with `"distance":3` means it is. LinearMouse
  only logs this when it builds settings it hasn't cached yet, so quit and
  reopen LinearMouse first if nothing shows up.
- **Scrolling is backwards in Windows.** Check Moonlight's Settings › Input ›
  *Reverse mouse scrolling direction* and macOS natural scrolling, then run
  `./install.sh` again.
- **Scrolling is too fast or slow in Windows.** Change *Lines to scroll at a
  time* in Windows, or the scroll setting in the game.
- **The mouse still feels accelerated in a game.** Turn off *Enhance pointer
  precision* in Windows (Mouse › Additional mouse settings › Pointer Options)
  and any mouse acceleration or smoothing in the game.

## Uninstall

`./uninstall.sh` (or Kadomo's `./uninstall.sh`):

- takes Kadomo's profile out of `linearmouse.json` (backed up first; if you had
  edited it, the backup keeps your version). Your other profiles stay, and a
  file Kadomo created that holds nothing else is deleted.
- removes the launch agent that opens LinearMouse at login.
- uninstalls LinearMouse with Homebrew only if Kadomo installed it **and**
  nothing else is set up in it, and only after asking (`--yes` doesn't ask).
  A LinearMouse you installed yourself is never removed.

Moonlight, macOS mouse settings, and the Windows host are left as they are. It's
safe to run more than once.
