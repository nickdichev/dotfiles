source $HOME/.asdf/asdf.sh

autoload -Uz compinit && compinit

source <(antibody init)
antibody bundle zsh-users/zsh-completions
antibody bundle zsh-users/zsh-autosuggestions
antibody bundle zdharma/fast-syntax-highlighting
antibody bundle mafredri/zsh-async
antibody bundle denysdovhan/spaceship-prompt

SPACESHIP_PROMPT_ORDER=(
  dir           # Current directory section
  host          # Hostname section
  git           # Git section (git_branch + git_status)
  exec_time     # Execution time
  line_sep      # Line break
  jobs          # Background jobs indicator
  exit_code     # Exit code section
  char          # Prompt character
)

[ -r "$HOME/.aliases" ] && source "$HOME/.aliases"

[ -r "$HOME/.exports" ] && source "$HOME/.exports"

[ -d "$HOME/.scripts" ] && export PATH="$HOME/.scripts":"$PATH"
