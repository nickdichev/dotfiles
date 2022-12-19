#!/bin/sh

sudo eopkg install -y \
  neovim \
  ripgrep \
  fd \
  tealdeer \
  zsh \
  antibody \
  git \
  shellcheck \
  docker \
  kitty \
  jq

# Elixir / Erlang
sudo eopkg it -yc system.devel
sudo epokg install -y \
  wxwidgets-devel \ 
  mesalib-devel \
  libglu-devel \ 
  fop

# Docker
sudo systemctl enable docker.service
sudo systemctl start docker.service
sudo groupadd docker
sudo usermod -aG docker $USER

# Personal Github keygen
[[ -d "$HOME/.ssh" ]] || mkdir ~/.ssh

if [[ ! -f "$HOME/.ssh/personal_github" ]]; then
  echo "#########################"
  echo "# Creating SSH keypair. #"
  echo "#########################"
  ssh-keygen -b 4096 -f "$HOME/.ssh/personal_github"
  
  echo "####################################"
  echo "# Copying public key to clipboard. #"
  echo "####################################"
  cat "$HOME/.ssh/personal_github.pub" | xclip -sel clip

  # TODO: wait for input
fi

ssh-add "$HOME/.ssh/personal_github"

# Language Servers
[[ -d "$HOME/.ls" ]] || mkdir "$HOME/.ls"
[[ -d "$HOME/.ls/elixir_ls" ]] || git clone git@github.com:elixir-lsp/elixir-ls.git "$HOME/.ls/elixir_ls"

# Dotfiles
[[ -d "$HOME/Workspace" ]] || mkdir -p "$HOME/Workspace"
[[ -d "$HOME/.config" ]] || mkdir -p "$HOME/.config"
[[ -d "$HOME/Workspace/dotfiles" ]] || git clone git@github.com:nickdichev/dotfiles.git "$HOME/Workspace/dotfiles"

[[ -f "$HOME/.config/nvim" ]] || ln -s "$HOME/Workspace/dotfiles/nvim" "$HOME/.config/nvim"

[[ -f "$HOME/.zshrc" ]] || ln -s "$HOME/Workspace/dotfiles/.zshrc" "$HOME/.zshrc"
[[ -d "$HOME/.scripts" ]] ||  ln -s "$HOME/Workspace/dotfiles/.scripts" "$HOME/.scripts"
[[ -f "$HOME/.aliases" ]] ||  ln -s "$HOME/Workspace/dotfiles/.aliases" "$HOME/.aliases"

# ASDF
[[ -d "$HOME/.asdf" ]] || git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.8.0

# Vim Plugged
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# TLDR cache
tldr --update

CURR_SHELL=$(echo $SHELL)
ZSH=$(which zsh)
if [[ "$CURR_SHELL" != "$ZSH" ]]; then
  echo "##################################"
  echo "# Changing default shell to $ZSH #"
  echo "##################################"
  chsh -s $ZSH
fi
