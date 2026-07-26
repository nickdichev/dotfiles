{ config, lib, ... }:
let
  cfg = config.profiles.ssh;
in
{
  options.profiles.ssh.enable = lib.mkEnableOption "SSH client configuration with per-host identities";

  config = lib.mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      # These tools manage their own SSH host entries. Missing include files
      # are ignored by OpenSSH, so this remains portable to non-Darwin hosts.
      includes = [
        "~/.orbstack/ssh/config"
        "~/.colima/ssh_config"
      ];

      settings = {
        "github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = "~/.ssh/personal/github";
          IdentitiesOnly = true;
        };

        liveoak = {
          HostName = "liveoak.serval-butterfly.ts.net";
        };

        "Match originalhost liveoak user forgejo" = lib.hm.dag.entryAfter [ "liveoak" ] {
          Port = 2222;
          HostKeyAlias = "[liveoak]:2222";
          IdentityFile = "~/.ssh/personal/forgejo";
          IdentitiesOnly = true;
        };

        "5.78.139.90" = {
          HostName = "5.78.139.90";
          User = "root";
          PreferredAuthentications = "publickey";
          IdentityFile = "~/.ssh/portal/prod-hetzner";
          IdentitiesOnly = true;
        };

        "exe.dev" = {
          IdentityFile = "~/.ssh/portal/exe-dev";
          IdentitiesOnly = true;
        };

        target = {
          HostName = "10.0.100.225";
          User = "root";
          ProxyJump = "liveoak";
          IdentityFile = "~/.ssh/personal/dichevnet-clan";
          IdentitiesOnly = true;
        };

        # Servers commonly disconnect after only a few rejected keys. For
        # unconfigured hosts, do not offer every identity loaded in ssh-agent.
        # Add a specific block above when a host should use a particular key.
        "*" = {
          IdentitiesOnly = true;
        };
      };
    };
  };
}
