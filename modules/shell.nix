{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.shell;
  wt = inputs.worktrunk.packages.${pkgs.system}.default;
in
{
  options.profiles.shell.enable = lib.mkEnableOption "Zsh shell with starship, atuin, and plugins";

  config = lib.mkIf cfg.enable {
    home.packages = [ wt ];

    programs.atuin = {
      enable = true;
      flags = [ "--disable-up-arrow" ];
      settings = {
        filter_mode_shell_up_key_binding = "session";
        history_filter = [
          "^export .*_API_KEY"
          "DATABASE_URL="
        ];
        auto_sync = true;
        sync_frequency = "60m";
        sync_address = "https://atuin.serval-butterfly.ts.net:4443";
      };
    };

    programs.starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        username = {
          format = "[$user]($style)@";
          show_always = true;
        };
        hostname = {
          format = "[$hostname]($style) in ";
          ssh_only = false;
          style = "bold yellow";
        };
        character = {
          success_symbol = "[~>](bold green)";
          error_symbol = "[~>](bold red)";
        };
        elixir = {
          format = "[$version OTP $otp_version]($style) ";
          style = "bold red";
        };
        package = {
          disabled = true;
        };
        gcloud.disabled = true;
        aws.disabled = true;
        custom = {
          bw-locked = {
            command = "echo 🔒";
            when = "! ${pkgs.rbw}/bin/rbw unlocked";
          };
        };
      };
    };
    programs.zsh = {
      enable = true;
      dotDir = "${config.home.homeDirectory}/.config/zsh";
      autocd = true;
      autosuggestion.enable = true;
      enableCompletion = true;

      initContent = ''
        export LANG="en_US.UTF-8"
        export LC_ALL="en_US.UTF-8"

        bindkey -e

        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ];
        then
          . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi

        # SSH from Tailscale network (100.x.x.x CGNAT range)
        _is_tailscale_ssh() {
          if [[ -n "$SSH_CLIENT" ]]; then
            local src_ip="''${SSH_CLIENT%% *}"
            [[ "$src_ip" == 100.* ]] && return 0
          fi
          return 1
        }

        # Detect if we're in a nested session (local zellij or SSH from Tailscale)
        _is_nested_session() {
          [[ -n "$ZELLIJ" ]] && return 0
          _is_tailscale_ssh && return 0
          return 1
        }

        # Auto-start zellij if not nested
        if ! _is_nested_session; then
          zellij attach -c main 2>/dev/null || zellij -s main
        fi

        export HISTORY_FILTER_EXCLUDE=("_KEY" "Bearer" "_TOKEN" "DATABASE_URL=")

        # Worktrunk shell integration
        eval "$(${wt}/bin/wt config shell init zsh)"

        # SSH agent setup (silent) - skip if nested to avoid duplicate agents
        if ! _is_nested_session && [[ -z "$SSH_AUTH_SOCK" ]]; then
          eval "$(ssh-agent -s)" > /dev/null 2>&1
        fi

        load_ssh_keys() {
          local reset=$'\e[0m'
          local dim=$'\e[2m'
          local bold=$'\e[1m'
          local green=$'\e[32m'
          local yellow=$'\e[33m'
          local red=$'\e[31m'

          echo ""
          echo "  ''${bold}''${yellow}SSH Keys''${reset}"
          echo "  ''${dim}────────────────────────────────────────────''${reset}"

          # Directories to scan for SSH keys (only existing ones are used)
          local potential_dirs=(
            "$HOME/.ssh/personal"
            "$HOME/.ssh/portal"
            "$HOME/.ssh/server"
          )

          local results=()
          for dir in "''${potential_dirs[@]}"; do
            [[ -d "$dir" ]] || continue
            local group=$(basename "$dir")
            for key in "$dir"/*; do
              [[ -f "$key" ]] || continue
              [[ "$key" == *.pub ]] && continue
              head -1 "$key" 2>/dev/null | grep -q "PRIVATE KEY" || continue

              local name=$(basename "$key")
              if ssh-add "$key" 2>/dev/null; then
                results+=("''${green}✓''${reset}|''${dim}$group''${reset}|$name")
              else
                results+=("''${red}✗''${reset}|''${dim}$group''${reset}|''${red}$name (failed)''${reset}")
              fi
            done
          done

          if [[ ''${#results[@]} -eq 0 ]]; then
            echo "  ''${dim}No keys found''${reset}"
          else
            for entry in "''${results[@]}"; do
              IFS='|' read -r icon group name <<< "$entry"
              printf "  %s  ''${dim}%-10s''${reset} %s\n" "$icon" "$group" "$name"
            done
          fi
          echo ""
        }

        # Message of the day - Shell hotkeys
        motd() {
          local reset=$'\e[0m'
          local dim=$'\e[2m'
          local bold=$'\e[1m'
          local cyan=$'\e[36m'
          local yellow=$'\e[33m'
          local blue=$'\e[34m'
          local green=$'\e[32m'
          local magenta=$'\e[35m'

          local key="''${bold}''${cyan}"
          local desc="''${dim}"
          local sep="''${blue}│''${reset}"

          echo "  ''${bold}''${yellow}Shell Hotkeys''${reset} ''${dim}(emacs mode)''${reset}"
          echo "  ''${dim}────────────────────────────────────────────''${reset}"
          echo "  ''${key}^A''${reset} ''${desc}line start''${reset}    $sep  ''${key}^E''${reset} ''${desc}line end''${reset}    $sep  ''${key}^L''${reset} ''${desc}clear''${reset}"
          echo "  ''${key}^B''${reset} ''${desc}char back''${reset}     $sep  ''${key}^F''${reset} ''${desc}char fwd''${reset}    $sep  ''${key}^R''${reset} ''${desc}history search''${reset}"
          echo "  ''${key}M-B''${reset} ''${desc}word back''${reset}    $sep  ''${key}M-F''${reset} ''${desc}word fwd''${reset}   $sep  ''${key}^Y''${reset} ''${desc}yank''${reset}"
          echo "  ''${key}^U''${reset} ''${desc}kill left''${reset}     $sep  ''${key}^K''${reset} ''${desc}kill right''${reset}  $sep  ''${key}^W''${reset} ''${desc}kill word''${reset}"
          echo ""

          # Random script tip (generated from profiles.scripts.tips)
          local scripts=(
            ${lib.concatMapStringsSep "\n            " (
              tip: "\"${tip.name}|${tip.description}|${tip.example}\""
            ) config.profiles.scripts.tips}
          )

          local idx=$((RANDOM % ''${#scripts[@]}))
          local entry="''${scripts[$idx]}"
          local name="''${entry%%|*}"
          local rest="''${entry#*|}"
          local description="''${rest%%|*}"
          local example="''${rest#*|}"

          echo "  ''${bold}''${yellow}Random Script''${reset}"
          echo "  ''${dim}────────────────────────────────────────────''${reset}"
          echo "  ''${bold}''${green}$name''${reset} ''${dim}— $description''${reset}"
          echo "  ''${dim}\$''${reset} ''${cyan}$example''${reset}"
          echo ""
        }

        # Show startup info in all local shells (suppress only for Tailscale SSH)
        if ! _is_tailscale_ssh; then
          load_ssh_keys
          motd
        fi

        # Wrapper for ripgrep that syncs search pattern with neovim
        # See: ripgrep-sync.lua
        rg() {
          local pattern=""
          local args=()
          local skip_next=false

          for arg in "$@"; do
            if $skip_next; then
              args+=("$arg")
              skip_next=false
            elif [[ "$arg" == -* ]]; then
              args+=("$arg")
              # Flags that take a value
              case "$arg" in
                -e|--regexp|-f|--file|-g|--glob|--iglob|-t|--type|-T|--type-not|\
                -A|--after-context|-B|--before-context|-C|--context|-M|--max-columns|\
                -m|--max-count|--max-filesize|-r|--replace|--path-separator|\
                --sort|--sortr|--colors|--color|--encoding|-E)
                  skip_next=true
                  ;;
              esac
            elif [[ -z "$pattern" ]]; then
              pattern="$arg"
              args+=("$arg")
            else
              args+=("$arg")
            fi
          done

          command rg "''${args[@]}"
          local exit_code=$?

          if [[ -n "$pattern" ]]; then
            echo -n "$pattern" > ~/.local/share/last-search
          fi

          return $exit_code
        }

        # Get the last commit hash (short by default, --long for full hash)
        git_last_commit() {
          if [[ "$1" == "--long" ]]; then
            git rev-parse HEAD
          else
            git rev-parse --short HEAD
          fi
        }
      '';

      shellAliases = {
        ".." = "cd ..";
        "..2" = "cd ../..";
        "..3" = "cd ../../..";
        "..4" = "cd ../../../..";
        "..5" = "cd ../../../../..";

        ga = "git add";
        gap = "git add -p";
        gb = "git branch";
        gbc = "git branch --show-current | tr -d '\n' | pbcopy";
        gc = "git commit";
        gcm = "git commit -m";
        gco = "git checkout";
        gcob = "git checkout -b";
        gf = "git fetch";
        glc = "git_last_commit";
        glcm = "git log --oneline | cut -d\" \" -f 2- | head -n 1";
        glo = "git log --oneline";
        gp = "git push";
        gpf = "git push --force-with-lease";
        gpsu = "git push --set-upstream origin HEAD";
        gra = "git rebase --abort";
        grc = "git rebase --continue";
        grhh = "git reset --hard HEAD";
        gri = "git rebase -i";
        gs = "git status";
        gsw = "git switch";

        vim = "nvim";
        watch = "viddy";
        lis = "listening";

        gg = "lazygit";
        gd = "lazydocker";

        drr = "direnv reload";

        cl = "claude";
        clc = "claude --continue";
        clr = "claude --resume";
        dclaude = "claude --dangerously-skip-permissions";
        dc = "dclaude";
        dcc = "dclaude --continue";
        dcr = "dclaude --resume";

        wtrm = "wt remove --force";
        wtrmm = "wt remove --force --no-verify -D";
      };

      plugins = [
        {
          name = "zsh-completions";
          src = pkgs.fetchFromGitHub {
            owner = "zsh-users";
            repo = "zsh-completions";
            rev = "0.35.0";
            sha256 = "GFHlZjIHUWwyeVoCpszgn4AmLPSSE8UVNfRmisnhkpg=";
          };
        }

        {
          name = "zsh-syntax-highlighting";
          src = pkgs.fetchFromGitHub {
            owner = "zsh-users";
            repo = "zsh-syntax-highlighting";
            rev = "0.8.0";
            sha256 = "iJdWopZwHpSyYl5/FQXEW7gl/SrKaYDEtTH9cGP7iPo=";
          };
        }

        {
          name = "zsh-history-filter";
          src = pkgs.fetchFromGitHub {
            owner = "MichaelAquilina";
            repo = "zsh-history-filter";
            rev = "0.4.1";
            sha256 = "sha256-OlGaBRD5F9z2WmhNp7nhs0B9mW4cLkkGeMYZq81uy44=";
          };
        }
      ];
    };
  };
}
