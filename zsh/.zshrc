source $HOME/.asdf/asdf.sh

[ -r "$HOME/.functions" ] && source "$HOME/.functions"
[ -r "$HOME/.aliases" ] && source "$HOME/.aliases"
[ -r "$HOME/.exports" ] && source "$HOME/.exports"

[ -d "$HOME/.scripts" ] && export PATH="$HOME/.scripts":"$PATH"

[ -r "$HOME/.firework/exports" ] && source "$HOME/.firework/exports"

