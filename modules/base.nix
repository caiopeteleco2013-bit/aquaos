# modules/base.nix — a plataforma AquaOS.
#
# Este é o coração do sistema: o kernel atualizado, a sessão gráfica com
# cara de macOS (compositor KWin do KDE — sem plasmashell — mais uma shell
# própria: barra de menu Waybar, Dock, Spotlight Wofi), a tela de login
# (ReGreet) e o tema visual mesmo.
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

  # ==================================================================
  # Sessão AquaOS: KWin como compositor + shell própria (sem plasmashell).
  # Janelas flutuam de graça (KWin não tileia), sombras/blur nativos do
  # KWin, e o modo gráfico se adapta à VM (llvmpipe incluso).
  # ==================================================================
  startSessao = pkgs.writeShellScriptBin "aquaos-desktop" ''
    export PATH="/run/current-system/sw/bin:$PATH"
    export XDG_CURRENT_DESKTOP="AquaOS:KDE"
    export XDG_SESSION_TYPE="wayland"
    export QT_QPA_PLATFORM="''${QT_QPA_PLATFORM:-wayland}"
    LOG="$HOME/.cache/aquaos-session.log"
    mkdir -p "$(dirname "$LOG")"
    echo "==== $(date) — sessão AquaOS (KWin + shell própria)" >>"$LOG"

    # compositor (equivalente ao papel do Hyprland no design original)
    "${pkgs.kdePackages.kwin}/bin/kwin_wayland" --xwayland &
    KWIN=$!

    # ============================================================
    # IMPORTANTE: os clientes da shell NÃO são filhos do compositor
    # (eram, no Hyprland, via exec-once), então o ambiente de sessão —
    # WAYLAND_DISPLAY/DISPLAY — não nasce com eles: descobrimos aqui,
    # observando os sockets que o KWin/XWayland acabaram de criar.
    # ============================================================
    SOCK=""
    for i in $(seq 1 100); do
      for s in "$XDG_RUNTIME_DIR"/wayland-*; do
        [ -S "$s" ] && SOCK="$s"
      done
      [ -n "$SOCK" ] && break
      sleep 0.2
    done
    if [ -z "$SOCK" ]; then
      echo "ERRO: compositor não criou socket em 20s" >>"$LOG"
      exit 1
    fi
    export WAYLAND_DISPLAY="${SOCK##*/}"

    XD=""
    for d in /tmp/.X11-unix/X*; do [ -S "$d" ] && XD="${d##*/X}"; done
    [ -n "$XD" ] && export DISPLAY=":$XD"

    echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=${DISPLAY:-—}" >>"$LOG"

    # ---------- shell própria AquaOS (no lugar do plasmashell) ----------
    # papel de parede Sonoma (layer-shell, desenha sobre o KWin)
    "${pkgs.swaybg}/bin/swaybg" -i /run/current-system/sw/share/backgrounds/sonoma.png -m fill &
    # menu bar (topo) + dock (base) — Waybar em duas barras
    "${pkgs.waybar}/bin/waybar" -c /etc/aquaos/waybar-top.jsonc -s /etc/aquaos/waybar-style.css &
    "${pkgs.waybar}/bin/waybar" -c /etc/aquaos/waybar-dock.jsonc -s /etc/aquaos/waybar-style.css &
    # agente polkit (diálogos de senha; cobre o kpmcore do Calamares)
    "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent" &
    # daemon de atalhos globais do KDE (resolve [services] e [kwin]);
    # o binário varia entre bin/ e libexec/ conforme a versão
    ${lib.optionalString (pkgs.kdePackages ? kglobalaccel) ''
      for KGA in "${pkgs.kdePackages.kglobalaccel}/bin/kglobalaccel" \
                 "${pkgs.kdePackages.kglobalaccel}/libexec/kglobalaccel"; do
        if [ -x "$KGA" ]; then "$KGA" & break; fi
      done
    ''}
    # na ISO: abre o instalador AquaOS automaticamente (no-op fora dela)
    /run/current-system/sw/bin/aquaos-start-installer >/dev/null 2>&1 &

    # a sessão termina quando o compositor termina
    wait "$KWIN"
    "${pkgs.procps}/bin/pkill" -P "$$" || true
  '';

  # Sessão registrada — aparece na tela de login (ReGreet) do sistema
  # instalado como "AquaOS".
  sessaoAquaOS = pkgs.writeTextDir "share/wayland-sessions/aquaos.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=AquaOS
    Comment=AquaOS — KWin + shell própria (macOS-style)
    Exec=/run/current-system/sw/bin/aquaos-desktop
    DesktopNames=AquaOS
  '';

  # Aplicativos da shell (também alimentam o Spotlight e os atalhos
  # [services] do kglobalaccel — os nomes dos arquivos são o elo).
  itemTerminal = pkgs.makeDesktopItem {
    name = "aquaos-terminal";
    desktopName = "Terminal";
    exec = "${pkgs.kitty}/bin/kitty";
    categories = [ "System" "TerminalEmulator" ];
  };
  menuItem = pkgs.makeDesktopItem {
    name = "aquaos-menu";
    desktopName = "Spotlight";
    exec = "${pkgs.wofi}/bin/wofi --show drun --prompt Buscar --style /etc/aquaos/wofi.css";
    categories = [ "Utility" ];
  };
  itemFinder = pkgs.makeDesktopItem {
    name = "aquaos-finder";
    desktopName = "Finder";
    exec = "${pkgs.nautilus}/bin/nautilus";
    categories = [ "GTK" "Utility" ];
  };
  itemCaptura = pkgs.makeDesktopItem {
    name = "aquaos-captura";
    desktopName = "Captura de tela";
    exec = "${pkgs.kdePackages.spectacle}/bin/spectacle -r";
    categories = [ "Utility" ];
  };
  scriptSair = pkgs.writeShellScriptBin "aquaos-sair"
    "exec ${pkgs.systemd}/bin/loginctl terminate-session";
  itemSair = pkgs.makeDesktopItem {
    name = "aquaos-sair";
    desktopName = "Encerrar sessão";
    exec = "${scriptSair}/bin/aquaos-sair";
    categories = [ "System" ];
  };
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
    kdePackages.kwin           # compositor/WM (sem plasmashell)
    swaybg                     # papel de parede (layer-shell)
    kdePackages.spectacle      # captura de tela (⇧⌘S)
    hyprpolkitagent            # agente polkit Qt6 do projeto Hyprland
    waybar                     # barra de menu (topo) + Dock (base)
    wofi                       # Spotlight (⌘Espaço)
    kitty                      # Terminal
    nautilus                    # Finder
    firefox                     # Safari

    # Shell própria: sessão, atalhos e ícones de lançamento
    startSessao
    sessaoAquaOS
    itemTerminal
    menuItem
    itemFinder
    itemCaptura
    scriptSair
    itemSair
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
  # KWin entra pelo aquaos.desktop (share/wayland-sessions, listado na
  # ReGreet) e executa o aquaos-desktop – nenhuma shell Plasma é ligada.
  # O agente polkit, a barra e o dock sobem dentro do próprio script.

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
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
  # O módulo services.greetd do nixpkgs já declara o usuário `greeter`
  # como isSystemUser (grupo "greeter"). Aqui só completamos o que o
  # ReGreet precisa — NÃO declarar isNormalUser junto com o greetd:
  # os dois marcados violam a asserção "Exactly one of ..." do módulo users.
  users.users.greeter = {
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
    # ---- Compositor KWin (comportamento macOS; sem plasmashell) ----
    "xdg/kwinrc".source = ../assets/kwinrc;
    # Atalhos globais (kwin + serviços) e preferências Qt globais
    "xdg/kglobalshortcutsrc".source = ../assets/kglobalshortcutsrc;
    "xdg/kdeglobals".source = ../assets/kdeglobals;

    # ---- Barra de menu (topo) + Dock (base): shell própria ----
    "aquaos/waybar-top.jsonc".source = ../assets/waybar/top.jsonc;
    "aquaos/waybar-dock.jsonc".source = ../assets/waybar/dock.jsonc;
    "aquaos/waybar-style.css".source = ../assets/waybar/style.css;

    # ---- Spotlight (Wofi) ----
    "aquaos/wofi.css".source = ../assets/wofi.css;

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
