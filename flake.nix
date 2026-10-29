{
  description = "AquaOS — sistema operacional real inspirado no macOS, construído sobre o kernel Linux";

  inputs = {
    # Pino do nixpkgs: versão do kernel Linux, pacotes e módulos da ISO.
    # Fixado no último commit do canal nixos-26.05 ANTES do início das
    # iterações de staging (2026-10-13): já avaliado e construído 100%
    # pela Hydra há semanas. Isso garante cache binário completo — a ISO
    # não compila o kernel, nem local nem no GitHub Actions (~15–30 min).
    # Para atualizar depois: pegue o novo SHA em
    #   https://channels.nixos.org/nixos-26.05/git-revision
    # e substitua abaixo (evitando commits de mesclagem de staging).
    nixpkgs.url = "github:NixOS/nixpkgs/952dd4355e1932709b993aa31de5e5b7bbe114f7";
  };

  outputs = { self, nixpkgs }: {
    # ISO live com instalador gráfico Calamares.
    #   nix build .#aquaos-iso   →  result/iso/aquaos-*.iso
    nixosConfigurations.aquaos-iso = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Base canônica dos CDs de instalação do NixOS (ISO híbrida UEFI/USB).
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-base.nix"
        ./configuration.nix
        ./modules/base.nix
        ./modules/live.nix
      ];
    };

    packages."x86_64-linux" = rec {
      aquaos-iso = self.nixosConfigurations.aquaos-iso.config.system.build.isoImage;
      default = aquaos-iso;
    };
  };
}
