#!/usr/bin/env python3
"""Audit pinned GUI app versions in this home-manager repo."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


GITHUB_PACKAGES = {
    "pencil": {
        "file": "pkgs/pencil/default.nix",
        "repo": "highagency/pencil-desktop-releases",
    },
    "hammerspoon": {
        "file": "pkgs/hammerspoon/default.nix",
        "repo": "Hammerspoon/hammerspoon",
    },
    "hunk": {
        "file": "pkgs/hunk/default.nix",
        "repo": "modem-dev/hunk",
    },
    "tablepro": {
        "file": "pkgs/tablepro/default.nix",
        "repo": "TableProApp/TablePro",
        "asset_regex": r"TablePro-.*-(arm64|x86_64)\.(zip|dmg)$",
    },
    "redisinsight": {
        "file": "pkgs/redisinsight/default.nix",
        "repo": "redis/RedisInsight",
    },
    "handy": {
        "file": "pkgs/handy/default.nix",
        "repo": "cjpais/Handy",
    },
    "rustdesk": {
        "file": "pkgs/rustdesk/default.nix",
        "repo": "rustdesk/rustdesk",
    },
    "telegram-desktop": {
        "file": "pkgs/telegram-desktop/default.nix",
        "repo": "telegramdesktop/tdesktop",
    },
}

BREW_CASKS = {
    "alt-tab-macos": "alt-tab",
    "blackhole": "blackhole-2ch",
    "godot": "godot",
    "obsidian": "obsidian",
    "raycast": "raycast",
    "redisinsight": "redis-insight",
    "rustdesk": "rustdesk",
    "slack": "slack",
}

NIX_EVAL_EXPR = r'''
let
  flake = builtins.getFlake "path:%s";
  system = builtins.currentSystem;
  stable = import flake.inputs.nixpkgs { inherit system; config.allowUnfree = true; };
  unstable = import flake.inputs.nixpkgs-unstable { inherit system; config.allowUnfree = true; };
  get = pkg: { version = pkg.version or null; name = pkg.name or null; };
in {
  stable = {
    obsidian = get stable.obsidian;
    slack = get stable.slack;
    redisinsight = get stable.redisinsight;
  };
  unstable = {
    alt-tab-macos = get unstable.alt-tab-macos;
    blackhole = get unstable.blackhole;
    godot = get unstable.godot;
    raycast = get unstable.raycast;
  };
}
'''


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return Path(result.stdout.strip())


def read_url_json(url: str):
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "audit-nix-app-updates",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)


def normalize_version(version: str | None) -> str | None:
    if version is None:
        return None
    version = version.strip()
    if version.startswith("v") and re.match(r"^v\d", version):
        version = version[1:]
    return version


def pinned_version(path: Path) -> str | None:
    text = path.read_text()
    match = re.search(r'\bversion\s*=\s*"([^"]+)"', text)
    return match.group(1) if match else None


def latest_github(repo: str, tag_regex: str | None = None, asset_regex: str | None = None) -> str | None:
    releases = read_url_json(f"https://api.github.com/repos/{repo}/releases?per_page=30")
    tag_pattern = re.compile(tag_regex) if tag_regex else None
    asset_pattern = re.compile(asset_regex) if asset_regex else None

    for release in releases:
        if release.get("prerelease") or release.get("draft"):
            continue
        tag = release.get("tag_name")
        if not tag:
            continue
        if tag_pattern and not tag_pattern.search(tag):
            continue
        if asset_pattern:
            asset_names = [asset.get("name", "") for asset in release.get("assets", [])]
            if not any(asset_pattern.search(name) for name in asset_names):
                continue
        return normalize_version(tag)
    return None


def brew_version(cask: str) -> str | None:
    try:
        data = read_url_json(f"https://formulae.brew.sh/api/cask/{cask}.json")
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
        return None
    version = data.get("version")
    if not version:
        return None
    return str(version).split(",")[0]


def nix_versions(root: Path):
    expr = NIX_EVAL_EXPR % str(root)
    result = subprocess.run(
        ["nix", "eval", "--impure", "--json", "--expr", expr],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if result.returncode != 0:
        return {}
    return json.loads(result.stdout)


def row_status(current: str | None, latest: str | None) -> str:
    if not current or not latest:
        return "unknown"
    return "current" if normalize_version(current) == normalize_version(latest) else "update"


def print_table(rows):
    print("| Package | Source | Current | Latest | Status |")
    print("|---|---|---:|---:|---|")
    for package, source, current, latest in rows:
        print(
            f"| {package} | {source} | {current or '?'} | {latest or '?'} | "
            f"{row_status(current, latest)} |"
        )


def main() -> int:
    root = repo_root()
    rows = []

    for package, info in GITHUB_PACKAGES.items():
        path = root / info["file"]
        current = pinned_version(path) if path.exists() else None
        latest = latest_github(
            info["repo"],
            tag_regex=info.get("tag_regex"),
            asset_regex=info.get("asset_regex"),
        )
        rows.append((package, f"github:{info['repo']}", current, latest))

    nix = nix_versions(root)
    for channel, packages in nix.items():
        for package, value in packages.items():
            latest = brew_version(BREW_CASKS.get(package, package))
            source = f"nixpkgs-{channel}, homebrew"
            rows.append((package, source, value.get("version"), latest))

    print_table(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
