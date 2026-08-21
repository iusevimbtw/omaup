# omaup

Omarchy bar uptime watcher. Plugin id is `iusevimbtw.omaup`. This is **not**
[Omarchy](https://omarchy.org/) itself and never edits `/usr/share/omarchy`.

## Identity

This checkout lives under a GitHub directory. Never use the local account
username in plugin ids, author fields, docs, comments, sample config, or
commit metadata you generate. The only public identity is the GitHub handle
**iusevimbtw** (same prefix as `iusevimbtw.omatab`).

- Plugin id: `iusevimbtw.omaup`
- Author: `iusevimbtw`
- Do not use the reserved `omarchy.*` plugin id namespace

## Layout

```text
manifest.json   Bar-widget plugin (id iusevimbtw.omaup)
Panel.qml       Bar icon + KeyboardPanel dropdown
Service.qml     HTTP checks, persist, theme green
Model.js        URL normalize and status helpers
```

Treat this tree as the source of truth. For local use, symlink it to
`~/.config/omarchy/plugins/iusevimbtw.omaup` so saves hot-reload.
