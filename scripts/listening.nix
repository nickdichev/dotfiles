{
  writeShellApplication,
  lsof,
}:

writeShellApplication {
  name = "listening";

  runtimeInputs = [
    lsof
  ];

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
}
