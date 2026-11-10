# Dockly

Custom docks and widgets for your Mac.

Dockly gives you a different Dock for whatever you are doing. Build a setup for
work, one for downtime, one for deep focus — then switch between them with a
keyboard shortcut, the menu bar, a two-finger swipe, or automatically with
macOS Focus.

## Build and run

```bash
./build.sh release
open build/Dockly.app
```

Requires Xcode's Swift toolchain and macOS 13 or later. The build script
compiles with SwiftPM, assembles `build/Dockly.app`, and ad-hoc signs it —
enough to run on the machine that built it.

### Signing and notarising for other Macs

An ad-hoc build will not open on someone else's Mac. Point the build at a
Developer ID identity, then notarise:

```bash
export DOCKLY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./build.sh release

xcrun notarytool store-credentials dockly \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
./Tools/notarize.sh
```

`build.sh` switches to a hardened-runtime signature when `DOCKLY_SIGN_IDENTITY`
is set, and `Tools/notarize.sh` submits, staples and repackages
`build/Dockly.zip`. Both need an Apple Developer account; nothing else about
the build changes.

### Updates

Dockly checks a JSON appcast every six hours and on launch. Publish one at the
feed address set in General → Updates:

```json
{
  "version": "1.1",
  "build": 2,
  "url": "https://example.com/Dockly-1.1.zip",
  "notes": "Two new widgets and faster switching.",
  "publishedAt": "2026-10-01T09:00:00Z"
}
```

A list of those objects works too — the highest `build` wins. Dockly downloads
the release and reveals it in Finder rather than replacing itself while it is
running.

To regenerate the app icon after editing `Tools/MakeIcon.swift`:

```bash
swift Tools/MakeIcon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

## What it does

**Custom Dock** — a floating dock that holds apps, folders, files, links,
macOS Shortcuts, spacers, dividers and widgets. It hides itself by default and
slides back when the pointer reaches the edge it hides against. If it is ever
out of sight, the menu bar has **Show Dockly Now** (⌃⌘S), which brings it back
even when the setup's dock had been switched off. Always-visible and
hide-in-full-screen live under Appearance → Behaviour → Hiding.

**Displays** — Appearance → Position → Display puts the dock on the screen with
the pointer, pins it to one display, or gives *every* display its own dock.
Each dock measures, positions and hides itself independently, and docks appear
and disappear as displays are plugged in and out.

**Dockly Mode** — General → Dockly Mode picks which Dock you actually see:

- *Custom docks* (default) — Dockly replaces the Dock and keeps the system one
  genuinely out of the way, so the two never fight over the same screen edge.
- *macOS Dock* — setups swap your familiar Dock only; Dockly stays off screen.
- *Both* — Dockly sits alongside the Dock you already have.

Whatever you pick, Dockly puts the macOS Dock back the way it found it when you
quit.

**Setups** — as many docks as you like, each with its own items, position and
look. Switch from the menu bar, with a per-setup hotkey, with ⌃⌥Tab to cycle,
or with a two-finger swipe over the dock.

**macOS Dock layouts** — a setup can also capture and restore your *system*
Dock, so your familiar Dock comes back with it. Turn on General → macOS Dock →
*Save changes I make to the macOS Dock* and Dockly keeps that snapshot in step
as you rearrange the real Dock by hand.

**Focus integration** — bind a setup to a macOS Focus and Dockly switches on
its own when that Focus turns on.

**27 widgets**

| Time & focus | Everyday | Your Mac | Business |
|---|---|---|---|
| Clock | Calendar | Battery | Stripe |
| World Clock | Reminders | System Activity | Paddle |
| Stopwatch | Now Playing | Network Activity | |
| Focus Timer | Sticky Note | AirDrop | |
| Countdown | Hydration | Shortcut | |
| Alarm | Weather | Recent Apps | |
| Time Progress | | Volume | |
| | | Keep Awake | |
| | | Disk Space | |
| | | Bluetooth Battery | |
| | | Screenshot | |
| | | Clipboard | |

*Clipboard* keeps the last twenty things you copied, in memory only — never on
disk — and skips anything a password manager marks as concealed. *Volume* sets
the level and switches output device. *Keep Awake* holds a power
assertion so the Mac stays up, with an optional timer. *Bluetooth Battery*
reads the same report System Information shows, so accessory levels need no
extra permission. *Screenshot* runs the same captures the ⇧⌘ shortcuts do, and
gets out of the picture first.

*Recent Apps* is the system Dock's recents section as a widget: the apps you
switched to most recently, with the ones already pinned in that dock filtered
out so it never shows you something sitting a few pixels away. Right-click it
to choose how many to show (1–6).

**Files and folders** — drop anything onto the dock to add it. Folders take a
colour and a letter so they are easy to spot, and clicking one opens a stack:
a grid of its contents you can open from, without a trip through Finder.
Right-click a folder to switch it back to plain "open in Finder". Small and
regular spacers, plus dividers, break a long dock into groups.

**It behaves like a Dock** — clicking a running app brings it forward instead
of relaunching it, and right-clicking offers Show, Hide, New Window, Quit and
Force Quit. Drop files on an app to open them with it, on a folder to move them
in, or on the Trash to throw them away. Appearance → Contents can append every
running app that is not already pinned, and keep a Trash tile at the end.

**Running apps and badges** — a dot marks what is running, and app icons carry
the same notification badges macOS draws on the system Dock. There is no public
API for another app's badge, so Dockly asks the Dock through Accessibility, the
same route a screen reader takes, and matches tiles to apps by their localised
display name. Grant the permission in General → Permissions; without it
everything else still works and badges simply do not appear.

**Menu bar** — switch setups, flip Dockly Mode, toggle auto-hide, and
optionally show the active setup's name next to the icon.

**AirDrop** — drop files onto the AirDrop widget to send them.

**Backup** — export every setup to a single JSON file and import it on another
Mac. No account, nothing leaves the machine. Saved libraries decode field by
field, so a newer Dockly never resets a setup it does not fully recognise, and
deleting a setup asks first and takes a backup on the way.

**It cleans up after itself** — the system Dock is put back on quit, on logout
and on SIGTERM, and a suppressed Dock left behind by a force-quit is repaired
at the next launch. Timers, hydration counts and notes survive a relaunch, and
an app that moves or is reinstalled is found again by its bundle identifier
rather than turning into a question mark.

## Language

Dockly ships in English and Japanese and follows the system language. Strings
live in `Resources/en.lproj/Localizable.strings` and
`Resources/ja.lproj/Localizable.strings`; keys are the English text, so an
untranslated string still reads correctly. To add a language, copy an `.lproj`
folder, translate the values, and add the code to `CFBundleLocalizations` in
`Resources/Info.plist` — `build.sh` copies every `.lproj` into the bundle.

## Where things live

- Library: `~/Library/Application Support/Dockly/library.json`
- Widget state (timers, hydration, notes): `~/Library/Application Support/Dockly/widget-state.json`
- Backups: `~/Library/Application Support/Dockly/Backups/`
- Stripe and Paddle API keys: the login Keychain, never the library file

## Layout

```
Sources/Dockly/
  App.swift            NSApplication entry point and lifecycle
  Model/               Library, profiles, dock items, persistence
  Dock/                The floating panel, its layout, its tiles and stacks
  Widgets/             The 20 widgets and the data sources behind them
  System/              Focus, hotkeys, Shortcuts, AirDrop, Trash, badges,
                       running apps, updates, the macOS Dock
  UI/                  Menu bar and the settings window
  Util/                Colours, key names, formatting helpers
```

## Permissions

Dockly asks only for what a feature needs, and only when that feature is used:
Calendar, Reminders, Location (weather), Apple Events (Music/Spotify transport)
and Accessibility (app badges). Everything else works with no permissions at
all, and every one of them can be declined without breaking the rest.
