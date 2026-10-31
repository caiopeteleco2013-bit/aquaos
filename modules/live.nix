# live.nix — ajustes exclusivos da ISO live.
# Inclui o instalador gráfico Calamares (integração oficial NixOS) e o
# boot direto na sessão AquaOS (KWin + shell própria), sem tela de login.
{ lib, pkgs, ... }:

let
  # Lançador do instalador. Na ISO, sobe o Calamares via sudo (o perfil
  # installation-device do NixOS libera sudo SEM SENHA para o grupo wheel —
  # nada de agente na corrida de boot). O modo gráfico padrão é xcb
  # (XWayland), exatamente como os desktops grandes fazem; sem modo X11,
  # cai para wayland. No-op fora da ISO. Log em ~/.cache/aquaos-installer.log.
  startInstalador = pkgs.writeShellScriptBin "aquaos-start-installer" ''
    test -e /etc/aquaos/live || exit 0
    LOG="$HOME/.cache/aquaos-installer.log"
    mkdir -p "$(dirname "$LOG")"
    # xcb = XWayland (modo dos desktops grandes); sem X11, cai para wayland.
    if [ -n "''${DISPLAY:-}" ]; then PLAT=xcb; else PLAT=wayland; fi
    {
      echo "==== $(date) — Instalador AquaOS"
      echo "DISPLAY=''${DISPLAY:-} WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-} QT_QPA_PLATFORM=$PLAT"
    } >>"$LOG"
    /run/wrappers/bin/sudo env \
      QT_QPA_PLATFORM="$PLAT" DISPLAY="''${DISPLAY:-}" \
      WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}" XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-}" \
      "${pkgs.calamares-nixos}/bin/calamares" >>"$LOG" 2>&1
  '';

  # Atalho de segurança: o instalador fica no menu (Wofi/Dock) para
  # ser relançado à mão se a sessão não o abrir por qualquer motivo.
  instaladorItem = pkgs.makeDesktopItem {
    name = "aquaos-installer";
    desktopName = "Instalar AquaOS";
    exec = "/run/current-system/sw/bin/aquaos-start-installer";
    comment = "Instalador gráfico do AquaOS";
    categories = [ "System" ];
  };
in
{
  # ==================================================================
  # Calamares — o instalador gráfico do AquaOS
  # ==================================================================

  # Exigido pelo kpmcore (motor de particionamento do Calamares).
  programs.partition-manager.enable = true;

  environment.systemPackages = with pkgs; [
    calamares-nixos             # Calamares já embrulhado com os caminhos oficiais do NixOS
    calamares-nixos-extensions  # módulos/branding oficiais base
    glibcLocales
  ]
  # Calamares é Qt 6 neste pino do nixpkgs: plugin Wayland da Qt6
  # (o modo gráfico padrão do lançador é xcb/XWayland; o wayland é fallback).
  ++ lib.optionals (pkgs ? qt6 && pkgs.qt6 ? qtwayland) [ pkgs.qt6.qtwayland ]
  ++ [ startInstalador instaladorItem ];

  # O instalador pode escolher qualquer locale do glibc.
  i18n.supportedLocales = [ "all" ];

  # Política polkit com os action ids REAIS usados nesta cadeia:
  #  - "org.freedesktop.policykit.exec": o id que o pkexec usa quando o
  #    programa não tem .policy própria (confirmado em src/programs/pkexec.c,
  #    linhas 366–367 do polkit) — é por isso que a regra antiga, que só
  #    citava "com.github.calamares.calamares", nunca casava;
  #  - "com.ubuntu.pkexec.*": id derivado do nome do programa pelo pkexec;
  #  - "com.github.calamares.calamares": action do Calamares;
  #  - "com.kde.kpmcore.*" e "org.kde.kpmcore.*": motor de partição
  #    (as duas formas de prefixo usadas pelas versões do kpmcore).
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (!subject.isInGroup("wheel")) return;
      if (action.id == "org.freedesktop.policykit.exec" ||
          action.id == "com.github.calamares.calamares" ||
          action.id.indexOf("com.ubuntu.pkexec.") === 0 ||
          action.id.indexOf("com.kde.kpmcore.") === 0 ||
          action.id.indexOf("org.kde.kpmcore.") === 0) {
        return polkit.Result.YES;
      }
    });
  '';

  # ==================================================================
  # Arquivos do instalador AquaOS (sobrepõem os "nixos" upstream:
  # o Calamares busca /etc/calamares com precedência sobre o wrapper).
  # ==================================================================
  environment.etc = {
    "calamares/settings.conf".source = ../installer/settings.conf;
    "calamares/branding/aquaos".source = ../installer/branding/aquaos;
    "calamares/modules/aquaos".source = ../installer/nixos;

    # Árvore copiada para o disco alvo pelo módulo python ("aquaos"):
    # modules/base.nix + assets/, idênticos ao projeto do flake.
    "aquaos/base/modules/base.nix".source = ../modules/base.nix;
    "aquaos/base/assets".source = ../assets;

    # Marcador: a sessão AquaOS abre o Calamares automaticamente na ISO.
    "aquaos/live".text = "1\n";
  };

  # ==================================================================
  # Autologin: a ISO sobe direto no desktop AquaOS com o usuário
  # `nixos` (criado pelo perfil installation-device do nixpkgs).
  # ==================================================================
  services.greetd.settings.initial_session = {
    command = "/run/current-system/sw/bin/aquaos-desktop";
    user = "nixos";
  };

  environment.variables = {
    # Calamares (Qt) nativo na Wayland.
    QT_QPA_PLATFORM = lib.mkDefault "wayland";
  };
}
