# configuration.nix — a base declarativa do AquaOS.
#
# O instalador Calamares gera uma versão deste mesmo formato no disco alvo
# (hostname, locale, teclado, usuário e disco escolhidos na GUI), enquanto
# este arquivo descreve a configuração de referência da distribuição.
{ lib, pkgs, ... }:

{
  # ============================================================ KERNEL
  # O coração do sistema é o kernel Linux. Alternativas de patchset:
  # pkgs.linuxPackages_zen, pkgs.linuxPackages_hardened, pkgs.linuxPackages_lts…
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.tmp.cleanOnBoot = true;

  # ==================================================== BOOT (UEFI)
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # ===================================================== IDIOMA/HORA
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "pt_BR.UTF-8";
  i18n.supportedLocales = [ "pt_BR.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];
  console.keyMap = "br-abnt2";

  # ============================================================ REDE
  networking.hostName = "aquaos";

  # ============================================================= NIX
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # A plataforma AquaOS (compositor, tela de login, tema, dock…):
  imports = [ ./modules/base.nix ];

  system.stateVersion = "26.05";
}
