# FinderBack

Right-click empty space in Finder and get **Back** and **Forward** controls directly on the context menu.

> **Want the quickest installation?**
>
> A ready-to-run Apple Silicon build is available for **$9.99**. It avoids installing developer tools or compiling the app yourself.
>
> **Ready-to-run download — $9.99. Checkout link coming shortly.**

The source code remains free under the MIT License. The paid download is a convenience build of the same app; it does not hide extra features.

## Before you buy

- Requires **Apple Silicon** and **macOS 26 or later**.
- FinderBack is currently distributed without an Apple Developer ID. On first launch, macOS will block it until you choose **System Settings → Privacy & Security → Open Anyway**.
- FinderBack also requires Accessibility permission to detect right-clicks in Finder and trigger Back/Forward.
- This is a digital download. Please check compatibility before purchasing. Refunds are not offered after delivery except where required by law or the payment platform.

## What it does

Finder has Back and Forward navigation through keyboard shortcuts (⌘[ and ⌘]) and toolbar controls. FinderBack adds them to the right-click menu: right-click empty space in a Finder window, then choose Back or Forward from the small attached control bar.

Two looks are available from Settings:

- **Labels** — Back and Forward as two stacked rows.
- **Arrows** — a compact ← | → row.

The app lives in the menu bar under the `⇄` icon and includes Settings, the style switch, Open at Login, and Quit.

## Privacy and Accessibility permission

Accessibility is a powerful permission, so FinderBack deliberately does very little:

- Reads mouse coordinates using a listen-only event tap. It cannot swallow, modify, or delay clicks.
- Reads only the accessibility role under the cursor and the position and size of Finder's context menu.
- Sends only ⌘[ and ⌘] to Finder.

FinderBack never reads filenames or paths, never accesses files, never makes network requests, and contains no analytics or crash reporting. Keystrokes are not logged or stored. The complete source is in this repository for inspection.

## Install the ready-to-run build

1. Buy and download FinderBack using the checkout link at the top of this page once it is live.
2. Unzip the download and drag `FinderBack.app` to `/Applications`.
3. Try to open FinderBack. macOS will block the unsigned app.
4. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
5. In **System Settings → Privacy & Security → Accessibility**, enable FinderBack.

The paid download includes its SHA-256 checksum so you can verify that the file was not corrupted after packaging.

## Build it yourself for free

Building requires the Xcode Command Line Tools:

```bash
xcode-select --install
git clone https://github.com/adfd3ewdf3/FinderBack.git
cd FinderBack
./build.sh
```

This creates `FinderBack.app` in the project folder. Drag it to `/Applications` and open it using the same **Open Anyway** and Accessibility steps above.

Each locally compiled build has a new ad-hoc signing identity, so macOS may ask you to grant Accessibility permission again after rebuilding.

## Development

```bash
./run.sh                  # run in the foreground
./run.sh --debug          # trace mouse and key events
./run.sh --style=arrows   # temporarily use the arrow style
./run-bundle.sh           # launch the app bundle and stream its logs
./kill.sh                 # stop FinderBack
```

Source files are under `Sources/`; visual constants live in `Sources/Config.swift`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the architecture and design decisions.

## Known limitations

- Apple Silicon and macOS 26+ only.
- Multi-monitor behavior is not yet verified.
- The attached navigation bar is always dark.
- Row height does not scale with the system large-text setting.
- Because the app is not Developer ID-signed or notarized, macOS displays an extra first-launch warning.

## License

MIT. See [`LICENSE`](LICENSE).
