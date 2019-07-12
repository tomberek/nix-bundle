{nixpkgs ? import <nixpkgs> {}}:

with nixpkgs;

let
  arx' = haskellPackages.arx.overrideAttrs (o: {
    patchPhase = (o.patchPhase or "") + ''
      substituteInPlace model-scripts/tmpx.sh \
        --replace /tmp/ \$HOME/.cache/
    '';
  });
in rec {
  arx = { archive, startup}:
    stdenv.mkDerivation {
      name = "arx";
      buildCommand = ''
        ${arx'}/bin/arx tmpx --shared -rm! ${archive} -o $out // ${startup}
        chmod +x $out
      '';
    };

  maketar = { targets }:
    stdenv.mkDerivation {
      name = "maketar";
      buildInputs = [ perl ];
      exportReferencesGraph = map (x: [("closure-" + baseNameOf x) x]) targets;
      buildCommand = ''
        storePaths=$(perl ${pathsFromGraph} ./closure-*)
        mkdir bin
        ln -s ${nixpkgs.bash}/bin/sh ./bin/sh

        tar -cf - \
          --owner=0 --group=0 --mode=u+rw,uga+r \
          --hard-dereference \
          $storePaths ./bin/sh | bzip2 -z > $out
      '';
    };

  # TODO: eventually should this go in nixpkgs?
  nix-user-chroot = stdenv.lib.makeOverridable stdenv.mkDerivation {
    name = "nix-user-chroot-2c52b5f";
    src = ./nix-user-chroot;

    makeFlags = [];

    # hack to use when /nix/store is not available
    postFixup = ''
      exe=$out/bin/nix-user-chroot
      patchelf \
        --set-interpreter .$(patchelf --print-interpreter $exe) \
        --set-rpath $(patchelf --print-rpath $exe | sed 's|/nix/store/|./nix/store/|g') \
        $exe
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin/
      cp nix-user-chroot $out/bin/nix-user-chroot

      runHook postInstall
    '';
  };

  makebootstrap = { targets, startup }:
    arx {
      inherit startup;
      archive = maketar {
        inherit targets;
      };
    };

  makeStartup = { target, nixUserChrootFlags, nix-user-chroot', run }:
  writeScript "startup" ''
    #!/bin/sh
    .${nix-user-chroot'}/bin/nix-user-chroot -n ./nix ${nixUserChrootFlags} -- ${target}${run} $@
  '';

  nix-bootstrap = { target, extraTargets ? [], run, nix-user-chroot' ? nix-user-chroot, nixUserChrootFlags ? "" }:
    let
      script = makeStartup { inherit target nixUserChrootFlags nix-user-chroot' run; };
    in makebootstrap {
      startup = ".${script} '\"$@\"'";
      targets = [ "${script}" ] ++ extraTargets;
    };

  nix-bootstrap-nix = {target, run, extraTargets ? []}:
    nix-bootstrap-path {
      inherit target run;
      extraTargets = [ nix gnutar bzip2 xz gzip coreutils bash ];
    };

  # special case adding path to the environment before launch
  nix-bootstrap-path = let
    nix-user-chroot'' = targets: nix-user-chroot.overrideDerivation (o: {
      buildInputs = o.buildInputs ++ targets;
      makeFlags = o.makeFlags ++ [
        ''ENV_PATH="${stdenv.lib.makeBinPath targets}"''
      ];
    }); in { target, extraTargets ? [], run }: nix-bootstrap {
      inherit target extraTargets run;
      nix-user-chroot' = nix-user-chroot'' extraTargets;
    };
}
