{
  writeShellApplication,
  git,
  fzf,
}:

writeShellApplication {
  name = "clean-git-branches";

  runtimeInputs = [
    git
    fzf
  ];

  text = ''
    git branch | fzf -m | xargs git branch -D
  '';
}
