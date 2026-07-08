---
name: audit-nix-app-updates
description: Audit and update Nix/Home Manager desktop application pins in this dotfiles repo. Use when the user asks whether pinned apps can be updated, mentions app packages such as AltTab, Raycast, TablePro, Pencil, RedisInsight, Handy, RustDesk, Hunk, Slack, Obsidian, Telegram, or wants a repeatable app update check before editing Nix package hashes.
---

# Audit Nix App Updates

## Workflow

1. Run `scripts/audit_apps.py` from the repository root to collect local versions and upstream versions.
2. Treat the script output as an audit, not an edit plan. Verify unusual results by checking the upstream release page or package metadata directly.
3. Prioritize local packages in `pkgs/*/default.nix` before flake lock updates. They are narrow changes and require only version/hash edits plus package builds.
4. For packages supplied by `nixpkgs` or `nixpkgs-unstable`, prefer updating the relevant flake input rather than overriding individual app versions unless the user asks for a one-off override.
5. When updating a macOS binary app, build the package and run signature checks on the resulting `.app`:

```bash
codesign --verify --deep --strict --verbose=4 /nix/store/.../Applications/App.app
spctl -a -vv -t exec /nix/store/.../Applications/App.app
```

6. If the user specifically worries about macOS signing or permissions, launch the app briefly with `open -n /nix/store/.../Applications/App.app`, confirm a process starts, then quit it.

## Script

Use:

```bash
python3 config/codex/skills/audit-nix-app-updates/scripts/audit_apps.py
```

The script checks:

- Local binary packages under `pkgs/`
- GUI apps declared in `modules/applications.nix`
- GitHub releases for locally pinned packages
- Homebrew cask versions for common macOS GUI apps
- Current locked `nixpkgs` and `nixpkgs-unstable` package versions via `nix eval`

## Update Rules

- Preserve upstream Developer ID signatures when the original app already passes `spctl`; avoid ad-hoc re-signing unless the existing package pattern or app requires it.
- Prefer ZIP assets over DMGs when both contain a complete `.app` and the ZIP preserves signing; ZIPs are easier to unpack reproducibly.
- Keep comments for intentional Nix fixup exceptions, such as upstream dangling symlinks in signed app bundles.
- After edits, run `nixfmt` on touched Nix files, build the changed package, and commit only the related files.
