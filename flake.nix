{
  description = "Home Manager configuration of kamana";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aider-nixpkgs = {
      url = "github:nickdichev-firework/nixpkgs/be60d3450f68e7cb47f3359011cb378af38f3073";
    };

  };

  outputs =
    {
      nixpkgs,
      home-manager,
      aider-nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      aider-pkgs = aider-nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations.kamana = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./home.nix ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;
          inherit aider-pkgs;
        };

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}
