{
  description = "The Opentracing Project";
  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils, haskellNix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            haskellNix.overlay
            (self: super: {
              opentracing =
                super.haskell-nix.project' {
                  compiler-nix-name = "ghc8107";
                  src = ./.;
                };
            })
          ];
        };
        flake = pkgs.opentracing.flake { };
      in
      flake // {
        checks = flake.checks;
        defaultPackage = flake.packages."opentracing:exe:opentracing";
        devShell = pkgs.opentracing.shellFor {
          packages = ps: with ps; [
            opentracing
            opentracing-examples
            opentracing-http-client
            opentracing-jaeger
            opentracing-wai
            opentracing-zipkin-common
            opentracing-zipkin-v1
            opentracing-zipkin-v2
          ];
          tools = {
            cabal-install = "latest";
            cabal-plan = "latest";
            ghcid = "latest";
            haskell-language-server = "latest";
            hlint = "latest";
            hoogle = "latest";
            ormolu = "latest";
          };
        };
      });
}
