return {
  cmd = { "nil" },
  filetypes = {"nix", "nixflake", "nixlib", "nixpkgs", "nixos", "nixos-config"},
  root_markers = {
    "flake.nix",
    "nixpkgs.json",
    "nixpkgs.toml",
    "nixos.json",
    "nixos.toml",
    "default.nix",
    "shell.nix",
    "devenv.nix"
  },
}
