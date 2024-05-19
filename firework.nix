{pkgs, ...}:

{
  home.packages = [
    pkgs.kubectl
    pkgs.google-cloud-sdk
  ];

  programs.awscli = {
    enable = true;
    package = pkgs.awscli2.overrideAttrs (oldAttrs: {
      nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ pkgs.makeWrapper ];

      doCheck = false;

      # Run any postInstall steps from the original definition, and then wrap the
      # aws program with a wrapper that sets the PYTHONPATH env var to the empty
      # string
      postInstall = ''
        ${oldAttrs.postInstall}
        wrapProgram $out/bin/aws --set PYTHONPATH=
      '';
    });

    settings = {
      "profile loop-staging-data" = {
        sso_session = "loop-staging-data";
        sso_account_id = "170553093583";
        sso_role_name = "DataTeam-Staging";
        region = "us-west-2";
        output = "json";
        sso_start_url = "https://d-926766cbd3.awsapps.com/start";
        sso_region = "us-west-2";
      };

      "sso-session loop-staging-data" = {
        sso_start_url = "https://d-926766cbd3.awsapps.com/start";
        sso_region = "us-west-2";
        sso_registration_scopes = "sso:account:access";
      };

      "profile loop-staging-backend" = {
        sso_session = "loop-staging-backend";
        sso_account_id = "170553093583";
        sso_role_name = "BackendTeam-Staging";
        region = "us-west-2";
        output = "json";
      };
      "sso-session loop-staging-backend" = {
        sso_start_url = "https://d-926766cbd3.awsapps.com/start";
        sso_region = "us-west-2";
        sso_registration_scopes = "sso:account:access";
      };
    };
  };

  programs.zsh.shellAliases = {
    nb = "cd ~/Workspace/naboo";
    sv = "cd ~/Workspace/stream_vortex";
  };
}
