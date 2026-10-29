# modules/base.nix — a plataforma AquaOS.
#
# Este é o coração do sistema: o kernel atualizado, a sessão gráfica com
# cara de macOS (Hyprland), a tela de login (ReGreet), a barra de menu
# (Waybar), o Dock (nwg-dock), o Spotlight (Wofi) e o tema visual mesmo.
#
# Ele é usado em dois lugares com o MESMO conteúdo:
#   * pela ISO live (importado por configuration.nix);
#   * pelo instalador Calamares, que o copia para /etc/nixos/modules/
#     do disco alvo antes de rodar `nixos-install`.
{ lib, pkgs, ... }:

let
  # Papel de parede padrão, gerado em tempo de build (sem binários no repo).
  wallpaper = pkgs.runCommand "aquaos-wallpaper"
    { nativeBuildInputs = [ pkgs.python3 ]; }
    ''
      mkdir -p $out/share/backgrounds
      python3 ${../assets/wallpaper.py} --out $out/share/backgrounds/sonoma.png
    '';
  wallpaperPath = "${wallpaper}/share/backgrounds/sonoma.png";

  # Tema GTK estilo macOS. Fallback seguro entre versões do nixpkgs.
  # (A fonte SF Pro/ícones da Apple NÃO são redistribuíveis — daí o WhiteSur.)
  tema-gtk =
    if pkgs ? whitesur-gtk-theme then pkgs.whitesur-gtk-theme else pkgs.orchis-theme;

  # Ícones estilo macOS (idem: fallback seguro entre versões do nixpkgs).
  tema-icone =
    if pkgs ? whitesur-icon-theme then pkgs.whitesur-icon-theme else pkgs.adwaita-icon-theme;
in
{
  # ============================================================ FONTES
  fonts.packages = with pkgs; [
    inter                      # substitui a SF Pro (proprietária da Apple)
    jetbrains-mono             # terminal
    nerd-fonts.jetbrains-mono  # glifos/ícones usados pela barra Waybar
    noto-fonts
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Inter" "Noto Sans" ];
    monospace = [ "JetBrains Mono" "JetBrainsMono Nerd Font" ];
  };

  # ========================================================= PACOTES
  environment.systemPackages = with pkgs; [
    wallpaper                   # papel de parede padrão (Sonoma-style)
    tema-gtk                    # GTK estilo macOS (WhiteSur/Orchis)
    tema-icone                 # ícones estilo macOS (fallback: Adwaita)
    bibata-cursors              # cursor branco estilo macOS
    adwaita-icon-theme
    gvfs                        # montagem/disco no Finder (nautilus)

    # Interface e serviços de sessão
    waybar                      # barra de menu
    nwg-dock-hyprland           # Dock inferior
    wofi                        # Spotlight (⌘Espaço)
    kitty                       # Terminal
    nautilus                    # Finder
    firefox                     # Safari
    swww                        # papel de parede
    grim
    slurp                       # capturas de tela (⇧⌘3 / ⇧⌘4)
    polkit_gnome                # agente de autenticação
  ];

  # =================================================== REDE E ÁUDIO
  # (Rede como no macOS: um único NetworkManager, visível na barra.)
  networking.networkmanager.enable = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  hardware.bluetooth.enable = true;

  # Firmware livre+aço para Wi-Fi/GPU em máquinas físicas.
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # ========================================================= SESSÃO
  programs.hyprland.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
  };

  programs.dconf.enable = true;
  security.polkit.enable = true;

  # ==================================================
  # TELA DE LOGIN (ReGreet dentro do cage — visual mac-ish)
  # ==================================================
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.cage}/bin/cage -s -- ${pkgs.regreet}/bin/regreet";
      user = "greeter";
    };
  };
  users.users.greeter = {
    isNormalUser = true;
    home = "/var/lib/greeter";
    createHome = true;
    extraGroups = [ "video" "input" ];
  };

  # ===================================================== TEMA/SHELL
  # Zsh, como no macOS.
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # Cursor estilo macOS para aplicações Wayland.
  environment.variables = {
    XCURSOR_THEME = "Bibata-Modern-Ice";
    XCURSOR_SIZE = "24";
  };

  # ==================================================================
  # Configurações globais (todos os arquivos vivem em assets/, referen-
  # ciados por caminhos relativos — a mesma árvore copiada ao disco).
  # ==================================================================
  environment.etc = {
    # ---- Compositor Hyprland (comportamento macOS) ----
    "hypr/hyprland.conf".source = ../assets/hyprland.conf;
    # Fallback via XDG (alguns builds do Hyprland só olham /etc/xdg):
    "xdg/hypr/hyprland.conf".source = ../assets/hyprland.conf;

    # ---- Barra de menu ----
    "xdg/waybar/config.jsonc".source = ../assets/waybar/config.jsonc;
    "xdg/waybar/style.css".source = ../assets/waybar/style.css;

    # ---- Spotlight (Wofi) e Dock (lista fixa) ----
    "aquaos/wofi.css".source = ../assets/wofi.css;
    "aquaos/nwg-dock-pinned".source = ../assets/nwg-dock-pinned;

    # ---- Tema global GTK3/GTK4 (botões à esquerda, como o macOS) ----
    "xdg/gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-theme-name = WhiteSur
      gtk-icon-theme-name = WhiteSur
      gtk-cursor-theme-name = Bibata-Modern-Ice
      gtk-font-name = Inter 10
      gtk-decoration-layout = close,minimize,maximize:
      gtk-xft-antialias = 1
      gtk-xft-hinting = 1
    '';
    "xdg/gtk-4.0/settings.ini".text = ''
      [Settings]
      gtk-theme-name = WhiteSur
      gtk-icon-theme-name = WhiteSur
      gtk-cursor-theme-name = Bibata-Modern-Ice
      gtk-font-name = Inter 10
      gtk-decoration-layout = close,minimize,maximize:
    '';

    # ---- Tela de login (ReGreet) ----
    "greetd/regreet.toml".text = ''
      # Tela de login AquaOS
      [background]
      path = "${wallpaperPath}"
      fit = "Cover"

      [GTK]
      application_prefer_dark_theme = false
      cursor_theme = "Bibata-Modern-Ice"
      font_name = "Inter 11"
      icon_theme = "WhiteSur"
      theme_name = "WhiteSur"
    '';
  };
}
