# live.nix — ajustes exclusivos da ISO live.
# Inclui o instalador gráfico Calamares (integração oficial NixOS) e o
# boot direto na sessão Hyprland, sem tela de login.
{ lib, pkgs, ... }:

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
  # Plugin Qt para Wayland (Calamares nativo na sessão Hyprland).
  # Protegido contra variações de nome entre versões do nixpkgs —
  # se ausente, o Calamares cai no XWayland do Hyprland.
  ++ lib.optionals (pkgs ? libsForQt5 && pkgs.libsForQt5 ? qt5 && pkgs.libsForQt5.qt5 ? qtwayland) [
    pkgs.libsForQt5.qt5.qtwayland
  ];

  # O instalador pode escolher qualquer locale do glibc.
  i18n.supportedLocales = [ "all" ];

  # Sobe o Calamares via pkexec sem senha para usuários do grupo wheel (ISO).
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "com.github.calamares.calamares" && subject.isInGroup("wheel")) {
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

    # Marcador: o Hyprland abre o Calamares automaticamente na ISO.
    "aquaos/live".text = "1\n";
  };

  # ==================================================================
  # Autologin: a ISO sobe direto no desktop AquaOS com o usuário
  # `nixos` (criado pelo perfil installation-device do nixpkgs).
  # ==================================================================
  services.greetd.settings.initial_session = {
    command = "${pkgs.hyprland}/bin/Hyprland";
    user = "nixos";
  };

  environment.variables = {
    # Calamares (Qt) nativo na Wayland.
    QT_QPA_PLATFORM = lib.mkDefault "wayland";
  };
}
