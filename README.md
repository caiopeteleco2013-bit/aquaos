# AquaOS

Um **sistema operacional real** (na verdade, uma distribuição Linux declarativa
construída com Nix) com a experiência **totalmente inspirada no macOS**:
tela de login estilo ReGreet, barra de menu translúcida, Dock, Spotlight,
janelas flutuantes com cantos arredondados e animação, papéis de parede
gradiente estilo Sonoma — tudo por cima do **kernel Linux** que você pode
trocar em uma linha.

| Ingrediente | Papel |
|---|---|
| kernel Linux (`linuxPackages_latest`) | o coração do sistema (troque por `zen`/`hardened` em uma linha) |
| Nix + flakes | as ferramentas de build da distribuição inteira |
| Hyprland | compositor Wayland (cantos, blur, sombras, animações "mac") |
| ReGreet (greetd + cage) | tela de login estilo macOS |
| Waybar | barra de menu (topo) |
| nwg-dock-hyprland | Dock (base) |
| Wofi | Spotlight (⌘Espaço) |
| WhiteSur + Bibata + Inter | temas/ícones/cursor/fonte estilo macOS (a SF Pro é proprietária da Apple) |
| Calamares | instalador gráfico (integração oficial `calamares-nixos-extensions`) |

## Estrutura dos arquivos (só o necessário)

```
aquaos/
├── flake.nix                    # build da distribuição (ISO e VM)
├── configuration.nix            # base declarativa: kernel, boot, idioma, Nix
├── modules/
│   ├── base.nix                 # a plataforma AquaOS: sessão gráfica + tema
│   └── live.nix                 # extras da ISO: Calamares + autologin
├── assets/
│   ├── hyprland.conf            # compositor (comportamento macOS)
│   ├── waybar/{config.jsonc,style.css}  # barra de menu
│   ├── wofi.css                 # Spotlight
│   ├── nwg-dock-pinned          # apps fixos do Dock
│   └── wallpaper.py             # gera o papel de parede (stdlib pura)
└── installer/
    ├── settings.conf            # fluxo de telas do Calamares
    ├── branding/aquaos/         # logo, cores e slideshow do instalador
    └── nixos/{module.desc,main.py}  # módulo que instala o sistema
```

## Requisitos

- Uma máquina **Linux ou WSL2 com Nix** instalado
  (no Ubuntu/Debian: `curl -L https://nixos.org/nix/install | sh -s -- daemon`,
  e no `/etc/nix/nix.conf`: `experimental-features = nix-command flakes`).
- ~10 GB livres para o build da ISO.

No Windows, a receita é: `wsl --install -d Ubuntu`, instale o Nix, e depois
copie este projeto para dentro do WSL (ex.: `cp -r /mnt/c/Users/sansb/Documents/codes/aquaos ~/aquaos`)
— builds no `/mnt/c` são bem mais lentos.

## Construir a ISO

```bash
cd ~/aquaos
nix build .#aquaos-iso
# resultado: result/iso/aquaos-*.iso
```

O build compila tudo (kernel Linux incluído) de forma reprodutível: o mesmo
flake gera a ISO, a VM e a máquina instalada com a plataforma AquaOS idêntica.

## Buildar na nuvem (GitHub Actions) — sem instalar nada

O projeto já vem com um workflow que constrói a ISO num runner Linux do
GitHub (nada é transmitido para terceiros além do próprio GitHub):

1. Suba o repositório (passos no fim deste guia).
2. No GitHub: **Actions → build-iso → Run workflow**.
3. Ao final, baixe a ISO como *artefato* do job (disponível por 14 dias).

Rodada típica: **~15–30 min** — o pino do nixpkgs aponta para um commit de
canal (release) da `nixos-26.05` já construído 100% pela Hydra, então nada
pesado é compilado. Repositório público tem minutos ilimitados; privado
tem 2.000 min/mês no plano gratuito.

## Testar em VirtualBox

1. Crie uma VM: tipo *Linux*, **habilitar EFI** (Settings → System → EFI),
   4 GB+ de RAM, vídeo VMSVGA com 64 MB+.
2. Anexe a ISO e boot.
3. A sessão sobe direto no desktop AquaOS (autologin do usuário `nixos`)
   e o instalador abre automaticamente.

Dica: no VirtualBox, a aceleração 3D do Hyprland pode falhar.
Para o melhor resultado, use hardware real ou uma máquina Linux
com QEMU/KVM.

## Instalar em disco (o Calamares)

1. Boot na ISO (autologin) → o instalador abre (ou clique "Instalar
   AquaOS" no menu ⌘Espaço; log em `~/.cache/aquaos-installer.log`).
2. Telas: idioma → teclado → usuário → particionamento → resumo → instalar.
3. O instalador:
   - particiona o disco e monta o sistema;
   - copia `modules/base.nix` e `assets/` para `/etc/nixos/` da máquina alvo;
   - gera um `configuration.nix` com hostname/idioma/teclado/disco/LUKS/btrfs;
   - roda `nixos-install` (com barra de progresso real do Nix).
4. Reinicie: aparece a tela de login AquaOS → Desktop.

Login do sistema instalado: a conta que você criou no passo 2. A senha de
root fica vazia (`nixos-install --no-root-passwd`, como o NixOS oficial
recomenda) — torne-a útil com `sudo passwd root` se quiser.

## Atalhos de teclado (SUPER = tecla ⌘/Windows)

| Atalho | Função |
|---|---|
| ⌘Espaço | Spotlight (buscar e abrir apps) |
| ⌘Enter | Terminal |
| ⌘E | Finder |
| ⌘Q | fechar janela |
| ⌘↑ ou ⌃⌘F | tela cheia |
| ⇧⌘F | ligar/desligar modo mosaico |
| ⇧⌘Q | encerrar sessão (volta ao login) |
| ⌘1–4 / ⌘←→ | alternar espaços (Spaces) |
| ⇧⌘3 / ⇧⌘4 | captura de tela: cheia / de área |

## Personalização rápida

- **Kernel:** `configuration.nix` → `boot.kernelPackages = pkgs.linuxPackages_zen;`
- **Papel de parede:** `assets/wallpaper.py` → lista `PARADAS` (cores do gradiente).
- **Atalhos/gestos/estética:** `assets/hyprland.conf`.
- **Barra e Dock:** `assets/waybar/` e `assets/nwg-dock-pinned`.
- **Tema/tema GTK:** `modules/base.nix` (WhiteSur; fallback automático para Orchis).

Depois de editar, basta reconstruir: `nix build .#aquaos-iso` (nova ISO).
Na máquina **instalada**, o equivalente é editar `/etc/nixos/…` e executar
`sudo nixos-rebuild switch` — como qualquer NixOS.

## Notas

- O logotipo é uma silhueta de maçã genérica; **não** usamos a marca da
  Apple nem fontes proprietárias (Inter substitui a SF Pro).
- Integração do Calamares via `calamares-nixos-extensions` (incluída no
  nixpkgs, licença GPL/CC-BY); o módulo `aquaos` é uma adaptação GPL
  compatível do módulo `nixos` upstream.
- Pino do nixpkgs: `nixos-26.05` (troque em `flake.nix`).
