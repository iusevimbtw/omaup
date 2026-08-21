# omaup

HTTP uptime watcher for the [Omarchy](https://omarchy.org/) bar. Plugin id is
`iusevimbtw.omaup`.

The bar icon is Omarchy’s generic browser glyph. It uses the active theme’s
green when every watched URL is up, and the theme’s red when something is
down. Click the icon for a list of sites; add and remove them in that panel.

## Install

From a clone of this repo:

```bash
ln -sfn "$(pwd)" ~/.config/omarchy/plugins/iusevimbtw.omaup
omarchy-shell shell rescanPlugins
omarchy plugin enable iusevimbtw.omaup --yes
```

Or, once this repo is on GitHub:

```bash
omarchy plugin add https://github.com/iusevimbtw/omaup.git --enable --yes
```

The widget lands in the right section of the bar. Move it with
`omarchy bar move iusevimbtw.omaup --section right`.

## Use

- Left click: open the status list
- Right click: refresh now
- In the panel: **Add** a name and URL, click a row to open it, trash to remove
- Keys: `j`/`k` move, Enter opens, `a` focuses add, `x` removes, `r` refreshes, Esc closes

A site is **up** when the final HTTP status after redirects is 2xx. Timeouts,
DNS failures, and other statuses are **down**. Checks run one at a time via
`curl`, every 30 seconds by default (`refreshIntervalSec` on the widget entry
in `~/.config/omarchy/shell.json`).

The watched list is stored on that same widget entry:

```json
{
  "id": "iusevimbtw.omaup",
  "refreshIntervalSec": 30,
  "targets": [
    { "id": "t1", "name": "Example", "url": "https://example.com" }
  ]
}
```
