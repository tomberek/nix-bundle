# use like this:
# nix-build appimage-bundle.nix --argstr package hello --argstr exec hello
# nix-build appimage-bundle.nix --arg package 'with import <nixpkgs>{}; writers.writePython3Bin "helloThere.py" {} "print(1)\n"' --argstr exec helloThere.py


{nixpkgs ? import <nixpkgs>{}, 
package,
exec,
... }:
let
  appimage_src = drv : exec : with nixpkgs;
    self.stdenv.mkDerivation rec {
      name = drv.name + "-appdir";
      env = buildEnv {
        inherit name;
        paths = buildInputs;
      };
      src = env;
      inherit exec;
      buildInputs = [ drv ];
      usr_fonts = buildEnv {
        name = "fonts";
        paths = [noto-fonts];
      };
      buildCommand = ''
        source $stdenv/setup
        mkdir $out
        shopt -s extglob
        ln -s ${env}/!(share) $out/
        mkdir -p $out/share/fonts
        ln -s ${env}/share/* $out/share/

        cp ${usr_fonts}/share/fonts/* $out/share/fonts -R

        mkdir -p $out/share/icons
        mkdir -p $out/share/icons/hicolor/256x256/apps
        touch $out/share/icons/hicolor/256x256/apps/${drv.name}.png
        touch $out/share/icons/${drv.name}.png

        mkdir -p $out/share/applications
        cat <<EOF > $out/share/applications/${drv.name}.desktop
        [Desktop Entry]
        Type=Application
        Version=1.0
        Name=${drv.name}
        Path=${env}
        Icon=${drv.name}
        Exec=$exec
        Terminal=true
        EOF
        '';
        system = builtins.currentSystem;
  };

in
  let results = 
      if (nixpkgs.lib.isDerivation package && !(nixpkgs.lib.isString package))
      then { 
          name = package.name;
          target = appimage_src package "${exec}";
          extraTargets = [];
        }
        else { 
          name = nixpkgs."${package}".name;
          target = appimage_src (nixpkgs."${package}") "${exec}";
          extraTargets = [];
        };
  in
  with (import (./appimage-top.nix){nixpkgs' = nixpkgs.path;});
  (appimage (appdir results )).overrideAttrs (old: {name = results.name;})