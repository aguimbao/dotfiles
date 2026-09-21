{
  description = "Flat-root modular NixOS config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, disko, impermanence, ... }@inputs:
    let
      lib = nixpkgs.lib;

      hostDir = ./hosts;
      hostFiles =
        if builtins.pathExists hostDir
        then builtins.filter (n: lib.hasSuffix ".nix" n)
          (builtins.attrNames (lib.filterAttrs (_: t: t == "regular") (builtins.readDir hostDir)))
        else throw "Missing ./hosts/*.nix (see hosts/nixos-host.nix)";

      loadHost = file:
        let
          raw = import (hostDir + "/${file}");
          m = if builtins.isFunction raw then raw { inherit inputs; } else raw;
        in
          if !(m ? "configuration-id") then throw "hosts/${file}: missing configuration-id"
          else if !(m ? "home-manager-user") then throw "hosts/${file}: missing home-manager-user"
          else m;

      manifests =
        if hostFiles == [] then throw "No hosts found in ./hosts/*.nix"
        else map loadHost hostFiles;

      entrySegments = e: builtins.filter (s: s != "") (lib.splitString "." e);
      flattenSegs = segs: builtins.concatMap (s: lib.splitString "_" s) segs;

      pathContains = entry: pathSegs:
        let
          e = entrySegments entry;
          flat = flattenSegs pathSegs;
          nE = builtins.length e;
          nP = builtins.length flat;
          matchAt = i: builtins.all (j: builtins.elemAt flat (i + j) == builtins.elemAt e j) (builtins.genList (j: j) nE);
        in
          if nE == 0 || nE > nP then false
          else builtins.any matchAt (builtins.genList (i: i) (nP - nE + 1));

      dirChildNames = dir:
        if builtins.pathExists dir
          then builtins.filter
            (k: builtins.match "\\..*" k == null && builtins.match "result.*" k == null)
            (builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)))
          else [];

      walk = disabledEntries: dir: pathSegs:
        if builtins.any (e: pathContains e pathSegs) disabledEntries
        then { nixosTop = []; hm = []; tags = [ pathSegs ]; }
        else
          let
            defaultPath = dir + "/default.nix";
            homePath = dir + "/home.nix";
            systemPath = dir + "/system.nix";
            hasDefault = builtins.pathExists defaultPath;
            hasHome = builtins.pathExists homePath;
            hasSystem = builtins.pathExists systemPath;
            defaultIsBoth = hasDefault && lib.hasInfix "options ?" (builtins.readFile defaultPath);
            hereNixosTop =
              (if hasSystem then [ systemPath ] else [])
              ++ (if defaultIsBoth then [ defaultPath ] else []);
            hereHm =
              (if hasHome then [ homePath ] else [])
              ++ (if hasDefault && !defaultIsBoth then [ defaultPath ] else [])
              ++ (if defaultIsBoth then [ defaultPath ] else []);
            rawChildren = dirChildNames dir;
            children = rawChildren;
            childResults = map (k: walk disabledEntries (dir + "/${k}") (pathSegs ++ [ k ])) children;
            mergedNixosTop = hereNixosTop ++ builtins.concatLists (map (r: r.nixosTop) childResults);
            mergedHm = hereHm ++ builtins.concatLists (map (r: r.hm) childResults);
            mergedTags = [ pathSegs ] ++ builtins.concatLists (map (r: r.tags) childResults);
          in
            { nixosTop = mergedNixosTop; hm = mergedHm; tags = mergedTags; };

      buildFor = manifest:
        let
          disabledEntries = manifest.disabled or [];
          extraDirs = manifest.extraDirs or [];
          sys = manifest.system or "x86_64-linux";
          pkgs = import nixpkgs {
            system = sys;
            config.allowUnfreePredicate = pkg:
              let name = lib.getName pkg; in
              (lib.hasPrefix "steam" name)
              || (builtins.elem name [ "unityhub" "discord" "protonvpn" "proton-pass" ]);
          };
          getParams = nodePath: defaults:
            let tag = builtins.head nodePath; in
            defaults // (manifest.params.${tag} or {});
          homeManagerUser = manifest."home-manager-user";
          configurationId = manifest."configuration-id";
          mySpecialArgs = { inherit manifest getParams homeManagerUser inputs; };

          base = walk disabledEntries ./dotfiles [];
          extras = map (d: walk disabledEntries d []) extraDirs;
          nixosTopImports = base.nixosTop ++ builtins.concatLists (map (r: r.nixosTop) extras);
          hmImports = base.hm ++ builtins.concatLists (map (r: r.hm) extras);
          allTags = base.tags ++ builtins.concatLists (map (r: r.tags) extras);

          isUsed = entry: builtins.any (t: pathContains entry t) allTags;
          unusedDisabled = builtins.filter (e: !isUsed e) disabledEntries;
          paramNames = builtins.attrNames (manifest.params or {});
          flatTags = lib.unique (builtins.concatMap flattenSegs allTags);
          unusedParams = builtins.filter (p: !(builtins.elem p flatTags)) paramNames;
          warningsModule = {
            warnings =
              (map (e: "dotfiles: disabled '${e}' matches nothing") unusedDisabled)
              ++ (map (p: "dotfiles: params '${p}' matches no tool") unusedParams);
          };

          useDisko = !(builtins.any (e: pathContains e [ "disko" ]) disabledEntries);
          useImpermanence = !(builtins.any (e: pathContains e [ "impermanence" ]) disabledEntries);

          nixosSystem = nixpkgs.lib.nixosSystem {
            system = sys;
            specialArgs = mySpecialArgs;
            modules = nixosTopImports
              ++ lib.optional useDisko disko.nixosModules.disko
              ++ lib.optional useImpermanence impermanence.nixosModules.impermanence
              ++ [
              warningsModule
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs = mySpecialArgs;
                home-manager.users.${homeManagerUser} = {
                  imports = hmImports ++ [ warningsModule ];
                  home.stateVersion = "24.05";
                };
              }
            ];
          };

          homeConfig = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = mySpecialArgs;
            modules = hmImports ++ [
              warningsModule
              {
                home.username = homeManagerUser;
                home.homeDirectory =
                  if pkgs.stdenv.isDarwin
                  then "/Users/${homeManagerUser}"
                  else "/home/${homeManagerUser}";
                home.stateVersion = "24.05";
              }
            ];
          };
        in
          { inherit nixosSystem homeConfig homeManagerUser configurationId; };
    in
      let
        built = map buildFor manifests;
        nixosPairs = map (b: { name = b.configurationId; value = b.nixosSystem; }) built;
        homePairs = map (b: { name = "${b.homeManagerUser}@${b.configurationId}"; value = b.homeConfig; }) built;
      in
      {
        nixosConfigurations = builtins.listToAttrs nixosPairs;
        homeConfigurations = builtins.listToAttrs homePairs;
      };
}
