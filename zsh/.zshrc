[ -r "$HOME/.functions" ] && source "$HOME/.functions"
[ -r "$HOME/.aliases" ] && source "$HOME/.aliases"
[ -r "$HOME/.exports" ] && source "$HOME/.exports"

[ -d "$HOME/.scripts" ] && export PATH="$HOME/.scripts":"$PATH"

[ -r "$HOME/.firework/exports" ] && source "$HOME/.firework/exports"
[ -r "$HOME/.firework/aliases" ] && source "$HOME/.firework/aliases"
[ -r "$HOME/.firework/functions" ] && source "$HOME/.firework/functions"

eval "$(direnv hook zsh)"
eval "$(starship init zsh)"
eval "$(atuin init zsh --disable-up-arrow)"
