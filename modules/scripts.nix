{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.scripts;

  scripts = [
    {
      description = "Show processes listening on TCP ports";
      example = "listening 3000";
      package = pkgs.writeShellApplication {
        name = "listening";
        runtimeInputs = [ pkgs.lsof ];
        text = ''
          pid_only=false
          port=""

          while [[ $# -gt 0 ]]; do
            case $1 in
              -p|--pid)
                pid_only=true
                shift
                ;;
              -h|--help)
                echo "Usage: listening [-p|--pid] [port]"
                echo "  -p, --pid    Show only PIDs"
                echo "  port         Filter by port number"
                exit 0
                ;;
              *)
                if [[ -z "$port" ]]; then
                  port="$1"
                else
                  echo "Usage: listening [-p|--pid] [port]"
                  exit 1
                fi
                shift
                ;;
            esac
          done

          if [[ -z "$port" ]]; then
            if [[ "$pid_only" == true ]]; then
              lsof -iTCP -sTCP:LISTEN -n -P | awk 'NR > 1 {print $2}' | sort -u
            else
              lsof -iTCP -sTCP:LISTEN -n -P
            fi
          else
            if [[ "$pid_only" == true ]]; then
              lsof -iTCP -sTCP:LISTEN -n -P | rg -i "$port" | awk '{print $2}' | sort -u
            else
              lsof -iTCP -sTCP:LISTEN -n -P | rg -i "$port"
            fi
          fi
        '';
      };
    }

    {
      description = "Interactively select and delete git branches with fzf";
      example = "clean-git-branches";
      package = pkgs.writeShellApplication {
        name = "clean-git-branches";
        runtimeInputs = [
          pkgs.git
          pkgs.fzf
        ];
        text = ''
          git branch | fzf -m | xargs git branch -D
        '';
      };
    }

    {
      description = "Copy stdin to clipboard, stripping trailing newline";
      example = "echo hello | copy";
      package = pkgs.writeShellApplication {
        name = "copy";
        runtimeInputs = [ pkgs.perl ];
        text = ''
          if hash pbcopy 2>/dev/null; then
            cmd='pbcopy'
          elif hash xclip 2>/dev/null; then
            cmd='xclip -selection clipboard'
          else
            echo 'cannot find a copy program' >&2
            exit 1
          fi

          perl -pe 'chomp if eof' | $cmd
        '';
      };
    }

    {
      description = "Paste from clipboard to stdout";
      example = "pasta | grep error";
      package = pkgs.writeShellApplication {
        name = "pasta";
        text = ''
          if hash pbpaste 2>/dev/null; then
            exec pbpaste
          elif hash xclip 2>/dev/null; then
            exec xclip -selection clipboard -o
          else
            echo 'cannot find a paste program' >&2
            exit 1
          fi
        '';
      };
    }

    {
      description = "Stream clipboard changes to stdout in real time";
      example = "pastas";
      package = pkgs.writeShellApplication {
        name = "pastas";
        text = ''
          trap 'exit 0' SIGINT

          last_value=""

          while true
          do
            value="$(pasta)"

            if [ "$last_value" != "$value" ]; then
              echo "$value"
              last_value="$value"
            fi

            sleep 0.1
          done
        '';
      };
    }

    {
      description = "Move files to system trash instead of deleting";
      example = "trash old-file.txt";
      package = pkgs.writeShellApplication {
        name = "trash";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          # Based on morgant/tools-osx (MIT License)
          for file in "$@"; do
            abs_path="$(realpath "$file")"
            if [[ "$(uname)" == 'Darwin' ]]; then
              osascript -e "tell application \"Finder\" to delete POSIX file \"$abs_path\"" >/dev/null
            else
              gio trash "$abs_path"
            fi
          done
        '';
      };
    }

    {
      description = "Parse and display components of a URL";
      example = "url 'https://example.com/path?q=1'";
      package = pkgs.writers.writePython3Bin "url" { } ''
        import sys
        from urllib.parse import urlparse, parse_qsl

        if len(sys.argv) < 2:
            print("Usage: url <url>")
            sys.exit(1)

        url = sys.argv[1]
        parsed = urlparse(url)

        if parsed.scheme:
            print(f"Protocol: {parsed.scheme}")
        if parsed.username:
            print(f"Username: {parsed.username}")
        if parsed.password:
            print(f"Password: {parsed.password}")
        if parsed.hostname:
            print(f"Host: {parsed.hostname}")
        if parsed.port:
            print(f"Port: {parsed.port}")
        if parsed.path:
            print(f"Path: {parsed.path}")
        if parsed.query:
            print("Query parameters:")
            for key, value in parse_qsl(parsed.query):
                print(f"  {key}: {value}")
        if parsed.fragment:
            print(f"Fragment: {parsed.fragment}")
      '';
    }

    {
      description = "Open a temp file in your editor for quick notes";
      example = "scratch";
      package = pkgs.writeShellApplication {
        name = "scratch";
        text = ''
          file="$(mktemp)"
          echo "Editing $file"
          exec "$EDITOR" "$file"
        '';
      };
    }

    {
      description = "Show current date/time with a calendar";
      example = "rn";
      package = pkgs.writeShellApplication {
        name = "rn";
        runtimeInputs = [ pkgs.ncurses ];
        text = ''
          date "+%l:%M%p on %A, %B %e, %Y"
          echo

          bold=$(tput bold)
          reset=$(tput sgr0)
          cyan=$(tput setaf 6)
          dim=$(tput dim)

          today=$(date '+%e' | tr -d ' ')

          cal | while IFS= read -r line; do
            # Header lines (month/year and day names) — print as-is
            if echo "$line" | grep -qE '^[[:space:]]*[A-Z]'; then
              echo "$line"
              continue
            fi

            result=""
            # Process each 3-character day column (Su Mo Tu We Th Fr Sa)
            col=0
            i=0
            while [ $i -lt ''${#line} ]; do
              # Extract a 3-char chunk (or remaining)
              chunk="''${line:$i:3}"
              day=$(echo "$chunk" | tr -d ' ')

              if [ -z "$day" ]; then
                result="$result$chunk"
              elif [ "$day" = "$today" ]; then
                # Highlight today: bold cyan + reverse
                padded=$(printf '%3s' "$day")
                result="$result''${bold}''${cyan}$(tput rev)$padded''${reset}"
              elif [ "$col" -eq 0 ] || [ "$col" -eq 6 ]; then
                # Dim weekends
                padded=$(printf '%3s' "$day")
                result="$result''${dim}$padded''${reset}"
              else
                result="$result$chunk"
              fi

              col=$(( (col + 1) % 7 ))
              i=$(( i + 3 ))
            done
            echo "$result"
          done
        '';
      };
    }

    {
      description = "Print today's date in YYYY-MM-DD format";
      example = "hoy | copy";
      package = pkgs.writeShellApplication {
        name = "hoy";
        text = ''
          echo -n "$(date '+%Y-%m-%d')"
        '';
      };
    }

    {
      description = "Run a command in the background, silencing output";
      example = "bb open .";
      package = pkgs.writeShellApplication {
        name = "bb";
        text = ''
          if test -t 1; then
            exec 1>/dev/null
          fi

          if test -t 2; then
            exec 2>/dev/null
          fi

          "$@" &
        '';
      };
    }

    {
      description = "Interactively kill processes by pid, name, or port";
      example = "murder :3000";
      package = pkgs.writers.writeRubyBin "murder" { } ''
        SIGNALS = [
          ['SIGTERM', 0.5],
          ['SIGINT', 1],
          ['SIGHUP', 2],
          ['SIGKILL', 0],
        ]

        def confirm(prompt)
          print "#{prompt} [y/n] "
          response = $stdin.gets.to_s.strip.downcase
          ['y', 'yes', 'yas'].include?(response)
        end

        def kill_pid(pid)
          SIGNALS.each do |signal, wait_time|
            begin
              Process.kill(signal, pid)
              sleep(wait_time) if wait_time > 0
              Process.kill(0, pid)
            rescue Errno::ESRCH
              puts "Killed #{pid}"
              return true
            end
          end
          false
        end

        def murder_by_pid(pid_str)
          pid = pid_str.to_i
          return unless confirm("Kill process #{pid}?")
          kill_pid(pid)
        end

        def murder_by_name(name)
          pids = `pgrep -f #{name}`.split.map(&:to_i) - [Process.pid]
          pids.each do |pid|
            cmd = `ps -p #{pid} -o comm=`.strip
            next unless confirm("Kill #{cmd} (#{pid})?")
            kill_pid(pid)
          end
        end

        def murder_by_port(port)
          lines = `lsof -i :#{port} -t 2>/dev/null`.split
          lines.map(&:to_i).uniq.each do |pid|
            next if pid == Process.pid
            cmd = `ps -p #{pid} -o comm=`.strip
            next unless confirm("Kill #{cmd} (#{pid}) on port #{port}?")
            kill_pid(pid)
          end
        end

        def murder(arg)
          if arg =~ /^\d+$/
            murder_by_pid(arg)
          elsif arg =~ /^:(\d+)$/
            murder_by_port($1)
          else
            murder_by_name(arg)
          end
        end

        ARGV.each { |arg| murder(arg) }
      '';
    }

    {
      description = "Put the system to sleep";
      example = "sleepybear";
      package = pkgs.writeShellApplication {
        name = "sleepybear";
        text = ''
          if [[ "$(uname)" == 'Darwin' ]]; then
            exec /usr/bin/osascript -e 'tell application "System Events" to sleep'
          else
            systemctl suspend
          fi
        '';
      };
    }

    {
      description = "Extract words from your last command via atuin";
      example = "lastarg -1";
      package = pkgs.writeShellApplication {
        name = "lastarg";
        runtimeInputs = [ pkgs.atuin ];
        text = ''
          cmd="$(atuin history last --cmd-only)"

          # Split into array, respecting quotes via eval
          # (safe here since it's our own history)
          eval "parts=($cmd)" 2>/dev/null || IFS=' ' read -ra parts <<< "$cmd"

          if [[ $# -eq 0 ]]; then
            echo "$cmd"
            exit 0
          fi

          selector="$1"
          len=''${#parts[@]}

          # Resolve a possibly-negative index to a positive one
          resolve_index() {
            local i=$1
            if (( i < 0 )); then
              i=$(( len + i ))
            fi
            echo "$i"
          }

          # Slice notation: start:end
          if [[ "$selector" == *:* ]]; then
            start="''${selector%%:*}"
            end="''${selector##*:}"

            start="''${start:-0}"
            end="''${end:-$len}"

            start=$(resolve_index "$start")
            end=$(resolve_index "$end")

            echo "''${parts[@]:$start:$((end - start))}"
          else
            # Single index
            idx=$(resolve_index "$selector")
            echo "''${parts[$idx]}"
          fi
        '';
      };
    }
    {
      description = "Organize Beatport tracks and upload to Jellyfin server";
      example = "beatport-upload ~/Downloads/tracks/";
      package = pkgs.writeShellApplication {
        name = "beatport-upload";
        runtimeInputs = [ pkgs.ffmpeg pkgs.fzf pkgs.openssh ];
        text = ''
          REMOTE_HOST="liveoak"
          REMOTE_PATH="/mnt/storage/media/music"
          TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
          OUTPUT_DIR="''${HOME}/Downloads/beatport_organized_''${TIMESTAMP}"

          usage() {
              echo "Usage: beatport-upload [OPTIONS] [PATH...]"
              echo ""
              echo "Organize Beatport tracks into Jellyfin structure and optionally upload."
              echo ""
              echo "If no PATHs given, opens fzf to pick files/dirs from the current directory."
              echo ""
              echo "Options:"
              echo "  -o DIR    Output directory (default: ~/Downloads/beatport_organized_<timestamp>)"
              echo "  -h HOST   Remote host (default: liveoak)"
              echo "  -p PATH   Remote path (default: /mnt/storage/media/music)"
              echo "  -y        Skip confirmation prompts"
              echo "  --dry-run Show what would be done without copying/converting"
              echo "  --help    Show this help"
          }

          AUTO_YES=false
          DRY_RUN=false
          while [[ $# -gt 0 ]]; do
              case "$1" in
                  -o) OUTPUT_DIR="$2"; shift 2 ;;
                  -h) REMOTE_HOST="$2"; shift 2 ;;
                  -p) REMOTE_PATH="$2"; shift 2 ;;
                  -y) AUTO_YES=true; shift ;;
                  --dry-run) DRY_RUN=true; shift ;;
                  --help) usage; exit 0 ;;
                  *) break ;;
              esac
          done

          # Collect input files
          input_files=()

          collect_audio_from_dir() {
              local dir="$1"
              while IFS= read -r -d "" f; do
                  input_files+=("$f")
              done < <(find "$dir" -maxdepth 1 -type f \( -iname '*.flac' -o -iname '*.wav' -o -iname '*.mp3' -o -iname '*.aiff' \) -print0 | sort -z)
          }

          if [[ $# -gt 0 ]]; then
              for arg in "$@"; do
                  if [[ -d "$arg" ]]; then
                      collect_audio_from_dir "$arg"
                  elif [[ -f "$arg" ]]; then
                      input_files+=("$arg")
                  else
                      echo "Warning: '$arg' not found, skipping"
                  fi
              done
          else
              echo "Select files/directories (TAB to multi-select, ENTER to confirm):"
              picks=()
              while IFS= read -r line; do
                  picks+=("$line")
              done < <(
                  find . -maxdepth 3 \( -iname '*.flac' -o -iname '*.wav' -o -iname '*.mp3' -o -iname '*.aiff' -o -type d \) \
                      | sort \
                      | fzf --multi --height=40% --reverse --prompt="Beatport tracks> " \
                            --preview='if [ -d {} ]; then ls -1 {}/*.flac {}/*.wav 2>/dev/null | head -20; else ffprobe -v quiet -show_entries format_tags=artist,album,title -of default=noprint_wrappers=1 {} 2>/dev/null; fi'
              )
              for pick in "''${picks[@]}"; do
                  if [[ -d "$pick" ]]; then
                      collect_audio_from_dir "$pick"
                  elif [[ -f "$pick" ]]; then
                      input_files+=("$pick")
                  fi
              done
          fi

          if [[ ''${#input_files[@]} -eq 0 ]]; then
              echo "No audio files selected."
              exit 1
          fi

          echo ""
          echo "Found ''${#input_files[@]} track(s) to process."

          # Process each file
          if ! $DRY_RUN; then
              mkdir -p "$OUTPUT_DIR"
          fi
          organized=()
          errors=()

          for f in "''${input_files[@]}"; do
              filename="$(basename "$f")"
              ext="''${filename##*.}"
              ext_lower="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
              needs_convert=false

              if [[ "$ext_lower" != "flac" ]]; then
                  needs_convert=true
              fi

              artist="$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null)"
              album="$(ffprobe -v quiet -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null)"
              title="$(ffprobe -v quiet -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null)"
              track="$(ffprobe -v quiet -show_entries format_tags=track -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null)"

              if [[ -z "$artist" || -z "$album" || -z "$title" ]]; then
                  echo "  SKIP (missing metadata): $filename"
                  errors+=("$filename")
                  continue
              fi

              safe_artist="$(echo "$artist" | sed 's/[\/:]/_/g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
              safe_album="$(echo "$album" | sed 's/[\/:]/_/g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
              safe_title="$(echo "$title" | sed 's/[\/:]/_/g; s/^[[:space:]]*//; s/[[:space:]]*$//')"

              if [[ -n "$track" ]]; then
                  padded="$(printf '%02d' "$track")"
                  dest_name="''${safe_artist} - ''${safe_album} - ''${padded} ''${safe_title}.flac"
              else
                  dest_name="''${safe_artist} - ''${safe_album} - ''${safe_title}.flac"
              fi

              dest_dir="''${OUTPUT_DIR}/''${safe_artist}/''${safe_album}"
              if ! $DRY_RUN; then
                  mkdir -p "$dest_dir"
              fi
              dest_path="''${dest_dir}/''${dest_name}"

              if $DRY_RUN; then
                  if $needs_convert; then
                      echo "  WOULD CONVERT: $filename -> ''${safe_artist}/''${safe_album}/''${dest_name}"
                  else
                      echo "  WOULD COPY: $filename -> ''${safe_artist}/''${safe_album}/''${dest_name}"
                  fi
              else
                  if $needs_convert; then
                      echo "  CONVERT: $filename -> flac"
                      ffmpeg -v quiet -y -i "$f" -compression_level 8 "$dest_path"
                  else
                      cp "$f" "$dest_path"
                  fi
                  echo "  OK: ''${safe_artist}/''${safe_album}/''${dest_name}"
              fi
              organized+=("''${safe_artist}/''${safe_album}")
          done

          echo ""
          echo "Organized ''${#organized[@]} track(s) to: $OUTPUT_DIR"

          if [[ ''${#errors[@]} -gt 0 ]]; then
              echo "Skipped ''${#errors[@]} file(s) with missing metadata."
          fi

          if [[ ''${#organized[@]} -eq 0 ]]; then
              exit 0
          fi

          echo ""
          if $AUTO_YES; then
              do_upload="y"
          else
              read -rp "Upload to ''${REMOTE_HOST}:''${REMOTE_PATH}? [y/N] " do_upload
          fi

          if [[ "$do_upload" =~ ^[Yy]$ ]]; then
              echo "Uploading..."
              while IFS= read -r artist_dir; do
                  scp -r "''${OUTPUT_DIR}/''${artist_dir}" "''${REMOTE_HOST}:''${REMOTE_PATH}/"
              done < <(printf '%s\n' "''${organized[@]}" | cut -d'/' -f1 | sort -u)
              echo ""
              echo "Upload complete. Run on ''${REMOTE_HOST}:"
              echo "  sudo chown -R copyparty:copyparty ''${REMOTE_PATH}/"
          else
              echo ""
              echo "Skipped upload. To upload manually:"
              echo "  scp -r ''${OUTPUT_DIR}/* ''${REMOTE_HOST}:''${REMOTE_PATH}/"
              echo ""
              echo "Then on ''${REMOTE_HOST}:"
              echo "  sudo chown -R copyparty:copyparty ''${REMOTE_PATH}/"
          fi
        '';
      };
    }
  ];
in
{
  options.profiles.scripts = {
    enable = lib.mkEnableOption "Custom shell scripts and utilities";

    tips = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.str);
      readOnly = true;
      default = map (s: {
        name = s.package.name;
        inherit (s) description example;
      }) scripts;
      description = "Script metadata for use in MOTD";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = map (s: s.package) scripts;
  };
}
