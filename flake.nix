{
  description = "Nick's home-manager modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
    devenv.url = "github:cachix/devenv/v2.1";
    worktrunk.url = "github:max-sixty/worktrunk/v0.39.0";
    expert = {
      url = "github:elixir-lang/expert";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    herdr = {
      # Keep consumers such as the clan on the same stable client/server protocol.
      url = "github:herdrdev/herdr/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    portal-nix-overlay.url = "github:Portal-Wholesale/nix-overlay";

  };

  outputs =
    { self, ... }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          }
        );
    in
    {
      homeModules = {
        # Default: imports all modules, defines shared options. Modules are imported but nothing enabled by default.
        default = import ./modules { inherit inputs; };

        # Bundles: import all modules + set enable flags
        workstation = {
          imports = [
            (import ./modules { inherit inputs; })
            ./bundles/workstation.nix
          ];
        };
        server = {
          imports = [
            (import ./modules { inherit inputs; })
            ./bundles/server.nix
          ];
        };

        # Individual modules (for advanced users who want granular control)
        ai = import ./modules/ai.nix { inherit inputs; };
        applications = import ./modules/applications.nix { inherit inputs; };
        base = import ./modules/base.nix;
        dev = import ./modules/dev.nix { inherit inputs; };
        fonts = import ./modules/fonts.nix;
        git = import ./modules/git.nix;
        hammerspoon = import ./modules/hammerspoon.nix;
        herdr = import ./modules/herdr.nix { inherit inputs; };
        media-processing = import ./modules/media-processing.nix;
        maintenance = import ./modules/maintenance.nix { inherit inputs; };
        neovim = import ./modules/neovim.nix { inherit inputs; };
        scripts = import ./modules/scripts.nix;
        secrets = import ./modules/secrets.nix;
        shell = import ./modules/shell.nix { inherit inputs; };
        ssh = import ./modules/ssh.nix;
        terminal = import ./modules/terminal.nix { inherit inputs; };
        utils = import ./modules/utils.nix { inherit inputs; };
        sesame = import ./modules/sesame.nix;
        wrk = import ./modules/wrk.nix;
        zellij = import ./modules/zellij.nix { inherit inputs; };
      };

      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = pkgs.mkShellNoCC {
            packages = [
              self.formatter.${system}
            ];
          };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);
    };
}
