#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Módulo Calamares da AquaOS.

Adaptado do módulo oficial "nixos" do projeto calamares-nixos-extensions
(https://github.com/NixOS/calamares-nixos-extensions, GPL-3.0-or-later),
com as mudanças do AquaOS:

  * todo o fluxo de desktop/packagechooser foi removido — o sistema alvo
    é sempre a plataforma AquaOS, que mora em ./modules/base.nix;
  * os arquivos compartilhados da distribuição (modules/base.nix e assets/)
    são copiados do instalador para o disco alvo antes do nixos-install;
  * senhas de autologin, `cfgtail` e a verificação de unfree foram
    removidas (o base.nix já decide essas políticas).
"""

import json
import libcalamares
import os
import shutil
import subprocess
import re

import gettext

_ = gettext.translation(
    "calamares-python",
    localedir=libcalamares.utils.gettext_path(),
    languages=libcalamares.utils.gettext_languages(),
    fallback=True,
).gettext

# Onde a ISO guarda a árvore compartilhada (modules/base.nix + assets/).
BASE_DIR = "/etc/aquaos/base"


# As strings abaixo formam o configuration.nix da máquina alvo.
# A plataforma AquaOS inteira mora em ./modules/base.nix (copiado junto).

cfghead = """\
# Este arquivo foi gerado pelo instalador AquaOS (Calamares).
# Edite-o livremente e aplique com `sudo nixos-rebuild switch`.

{ config, pkgs, ... }:

{
  imports =
    [ # Configuração automática do hardware desta máquina.
      ./hardware-configuration.nix
      # Plataforma AquaOS: compositor KWin, tela de login, barra de menu,
      # Dock, Spotlight, temas e aplicações base.
      ./modules/base.nix
    ];

"""

cfgbootefi = """\
  # Boot via systemd-boot (UEFI), como nos Macs modernos.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

"""

cfgbootbios = """\
  # Boot via GRUB 2 (BIOS/CSM).
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "@@bootdev@@";
  boot.loader.grub.useOSProber = true;

"""

cfgbootbiosbtrfs = """\
  # Boot via GRUB 2 (BIOS/CSM).
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "@@bootdev@@";
  boot.loader.grub.useOSProber = true;
  # Use UUIDs fornecidos em vez de sondagem blkid (necessário p/ subvolumes btrfs)
  boot.loader.grub.fsIdentifier = "provided";

"""

cfgbootnone = """\
  # Bootloader desativado.
  boot.loader.grub.enable = false;

"""

cfgbootgrubcrypt = """\
  # Setup do keyfile
  boot.initrd.secrets = {
    "/boot/crypto_keyfile.bin" = null;
  };

  boot.loader.grub.enableCryptodisk = true;

"""

cfgnetwork = """\
  networking.hostName = "@@hostname@@"; # Nome da máquina.

"""

cfgtime = """\
  # Fuso horário.
  time.timeZone = "@@timezone@@";

"""

cfglocale = """\
  # Localização.
  i18n.defaultLocale = "@@LANG@@";

"""

cfglocaleextra = """\
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "@@LC_ADDRESS@@";
    LC_IDENTIFICATION = "@@LC_IDENTIFICATION@@";
    LC_MEASUREMENT = "@@LC_MEASUREMENT@@";
    LC_MONETARY = "@@LC_MONETARY@@";
    LC_NAME = "@@LC_NAME@@";
    LC_NUMERIC = "@@LC_NUMERIC@@";
    LC_PAPER = "@@LC_PAPER@@";
    LC_TELEPHONE = "@@LC_TELEPHONE@@";
    LC_TIME = "@@LC_TIME@@";
  };

"""

cfgkeymap = """\
  # Layout de teclado (X11/teclado físico).
  services.xserver.xkb = {
    layout = "@@kblayout@@";
    variant = "@@kbvariant@@";
  };

"""

cfgconsole = """\
  # Teclado do console (tty).
  console.keyMap = "@@vconsole@@";

"""

cfgusers = """\
  # Conta de usuário criada pelo instalador.
  users.users."@@username@@" = {
    isNormalUser = true;
    description = "@@fullname@@";
    extraGroups = [ "wheel" "networkmanager" ];
  };

"""


def env_is_set(name):
    envValue = os.environ.get(name)
    return not (envValue is None or envValue == "")


def generateProxyStrings():
    proxyEnv = []
    if env_is_set('http_proxy'):
        proxyEnv.append('http_proxy={}'.format(os.environ.get('http_proxy')))
    if env_is_set('https_proxy'):
        proxyEnv.append('https_proxy={}'.format(os.environ.get('https_proxy')))
    if env_is_set('HTTP_PROXY'):
        proxyEnv.append('HTTP_PROXY={}'.format(os.environ.get('HTTP_PROXY')))
    if env_is_set('HTTPS_PROXY'):
        proxyEnv.append('HTTPS_PROXY={}'.format(os.environ.get('HTTPS_PROXY')))

    if len(proxyEnv) > 0:
        proxyEnv.insert(0, "env")

    return proxyEnv


def pretty_name():
    return _("Instalando o AquaOS.")


status = pretty_name()


def pretty_status_message():
    return status


def catenate(d, key, *values):
    """
    Define d[key] como a concatenação dos valores, apenas se nenhum deles
    for None. Útil para definir chaves condicionalmente.
    """
    if [v for v in values if v is None]:
        return

    d[key] = "".join(values)


def fix_btrfs_subvolumes(hardware_config, partitions):
    """
    Corrige opções de subvolumes btrfs no hardware-configuration.nix.

    O nixos-generate-config gera opções `subvol=` com pontos de montagem em
    vez dos nomes reais dos subvolumes; esta função ajusta para o que o
    Calamares configurou (mount.conf → btrfsSubvolumes).
    """
    subvol_map = {
        "/home": "home",
        "/nix": "nix",
    }

    root_is_btrfs = False
    for part in partitions:
        if part.get("mountPoint") == "/" and part.get("fs") == "btrfs":
            root_is_btrfs = True
            break

    if not root_is_btrfs:
        return hardware_config

    libcalamares.utils.debug("Corrigindo subvolumes btrfs em hardware-configuration.nix")

    for mount_point, correct_subvol in subvol_map.items():
        pattern = r'(fileSystems\."{}"[^;]*"subvol=)[^"]*"'.format(re.escape(mount_point))
        replacement = r'\g<1>{}"'.format(correct_subvol)
        hardware_config = re.sub(pattern, replacement, hardware_config, flags=re.DOTALL)

    return hardware_config


# Tipos de atividade/resultado do internal-json do Nix
_ACT_COPY_PATH = 100
_ACT_COPY_PATHS = 103
_ACT_BUILDS = 104
_RES_PROGRESS = 105


class NixProgress:
    """Interpreta a saída internal-json do Nix e acompanha o progresso."""

    def __init__(self):
        self._builds_done = 0
        self._builds_expected = 0
        self._copies_done = 0
        self._copies_expected = 0
        self._per_act_progress = {}
        self._copy_bytes = {}
        self._activities = {}
        self.fraction = 0.0
        self._floor = 0.0
        self._floor_done = 0
        self.log_messages = []

    def handle(self, line):
        """Processa uma linha. Retorna True para linhas @nix, ou False."""
        line = line.strip()
        if not line:
            return True
        if not line.startswith("@nix "):
            return False
        try:
            msg = json.loads(line[5:])
        except (json.JSONDecodeError, ValueError):
            return False

        action = msg.get("action")
        if action == "start":
            self._on_start(msg)
        elif action == "stop":
            self._on_stop(msg)
        elif action == "result":
            self._on_result(msg)
        elif action == "msg":
            level = msg.get("level", 0)
            text = msg.get("msg", "")
            if level <= 1 and text:
                self.log_messages.append(text)

        self._update()
        return True

    def _on_start(self, msg):
        act_id = msg["id"]
        act_type = msg.get("type", 0)
        self._activities[act_id] = act_type
        text = msg.get("text", "")
        if text and msg.get("level", 5) <= 3:
            self.log_messages.append(text)

    def _on_stop(self, msg):
        act_id = msg["id"]
        self._activities.pop(act_id, None)
        self._copy_bytes.pop(act_id, None)

    def _on_result(self, msg):
        act_id = msg["id"]
        res_type = msg.get("type", 0)
        fields = msg.get("fields", [])
        act_type = self._activities.get(act_id, 0)

        if res_type != _RES_PROGRESS or len(fields) < 2:
            return
        if act_type == _ACT_BUILDS:
            self._per_act_progress[(act_type, act_id)] = ("builds", fields[0], fields[1])
            self._recompute_counts()
        elif act_type == _ACT_COPY_PATHS:
            self._per_act_progress[(act_type, act_id)] = ("copies", fields[0], fields[1])
            self._recompute_counts()
        elif act_type == _ACT_COPY_PATH:
            self._copy_bytes[act_id] = (fields[0], max(fields[1], 1))

    def _update(self):
        count_total = self._builds_expected + self._copies_expected
        count_done = self._builds_done + self._copies_done
        if count_total <= 0:
            return

        effective_total = max(count_total, 3)
        count_frac = count_done / effective_total

        total_bytes = sum(t for _, t in self._copy_bytes.values())
        done_bytes = sum(d for d, _ in self._copy_bytes.values())
        if total_bytes > 0:
            byte_sub = done_bytes / total_bytes
            step = len(self._copy_bytes) / effective_total
            raw = count_frac + byte_sub * step
        else:
            raw = count_frac
        raw = max(0.0, min(1.0, raw))

        if raw >= self._floor:
            self._floor = raw
            self._floor_done = count_done
        else:
            new_items = count_done - self._floor_done
            remaining = effective_total - self._floor_done
            if remaining > 0 and new_items >= 0:
                raw = self._floor + (new_items / remaining) * (1.0 - self._floor)
            else:
                raw = self._floor
            raw = max(0.0, min(1.0, raw))
            if raw > self._floor:
                self._floor = raw
                self._floor_done = count_done

        self.fraction = raw

    def _recompute_counts(self):
        bd = be = cd = ce = 0
        for kind, done, expected in self._per_act_progress.values():
            if kind == "builds":
                bd += done
                be += expected
            else:
                cd += done
                ce += expected
        self._builds_done = bd
        self._builds_expected = be
        self._copies_done = cd
        self._copies_expected = ce


def run():
    """Instalação da AquaOS no disco escolhido."""

    INSTALL_PROGRESS_START = 0.1
    INSTALL_PROGRESS_END = 1.0

    global status
    status = _("Configurando o AquaOS")
    libcalamares.job.setprogress(0.01)

    # Montagem inicial do configuration.nix
    cfg = cfghead
    gs = libcalamares.globalstorage
    variables = dict()

    root_mount_point = gs.value("rootMountPoint")
    config = os.path.join(root_mount_point, "etc/nixos/configuration.nix")
    fw_type = gs.value("firmwareType")
    bootdev = (
        "nodev"
        if gs.value("bootLoader") is None
        else gs.value("bootLoader")["installPath"]
    )

    root_is_btrfs = False
    for part in gs.value("partitions"):
        if part.get("mountPoint") == "/" and part.get("fs") == "btrfs":
            root_is_btrfs = True
            break

    # ---------------- bootloader + partição/criptografia ----------------
    if fw_type == "efi":
        cfg += cfgbootefi
    elif bootdev != "nodev":
        if root_is_btrfs:
            cfg += cfgbootbiosbtrfs
        else:
            cfg += cfgbootbios
        catenate(variables, "bootdev", bootdev)
    else:
        cfg += cfgbootnone

    # Swap criptografado: o nixos-generate-config não o percebe sozinho.
    for part in gs.value("partitions"):
        if (
            part["claimed"] is True
            and (part["fsName"] == "luks" or part["fsName"] == "luks2")
            and part["device"] is not None
            and part["fs"] == "linuxswap"
        ):
            cfg += """  boot.initrd.luks.devices."{}".device = "/dev/disk/by-uuid/{}";\n""".format(
                part["luksMapperName"], part["uuid"]
            )

    root_is_encrypted = False
    boot_is_encrypted = False
    boot_is_partition = False

    for part in gs.value("partitions"):
        if part["mountPoint"] == "/":
            root_is_encrypted = part["fsName"] in ["luks", "luks2"]
        elif part["mountPoint"] == "/boot":
            boot_is_partition = True
            boot_is_encrypted = part["fsName"] in ["luks", "luks2"]

    # keyfile em /boot para LUKS no modo BIOS (GRUB cryptodisk)
    if fw_type != "efi" and (
        (boot_is_partition and boot_is_encrypted)
        or (root_is_encrypted and not boot_is_partition)
    ):
        cfg += cfgbootgrubcrypt
        status = _("Configurando o LUKS")
        libcalamares.job.setprogress(0.02)
        try:
            libcalamares.utils.host_env_process_output(
                ["mkdir", "-p", root_mount_point + "/boot"], None
            )
            libcalamares.utils.host_env_process_output(
                ["chmod", "0700", root_mount_point + "/boot"], None
            )
            libcalamares.utils.host_env_process_output(
                [
                    "dd",
                    "bs=512",
                    "count=4",
                    "if=/dev/random",
                    "of=" + root_mount_point + "/boot/crypto_keyfile.bin",
                    "iflag=fullblock",
                ],
                None,
            )
            libcalamares.utils.host_env_process_output(
                ["chmod", "600", root_mount_point + "/boot/crypto_keyfile.bin"], None
            )
        except subprocess.CalledProcessError:
            libcalamares.utils.error("Falhou ao criar /boot/crypto_keyfile.bin")
            return (
                _("Falha ao criar /boot/crypto_keyfile.bin"),
                _("Verifique se há espaço livre suficiente na partição."),
            )

        for part in gs.value("partitions"):
            if (
                part["claimed"] is True
                and (part["fsName"] == "luks" or part["fsName"] == "luks2")
                and part["device"] is not None
            ):
                cfg += """  boot.initrd.luks.devices."{}".keyFile = "/boot/crypto_keyfile.bin";\n""".format(
                    part["luksMapperName"]
                )
                try:
                    # GRUB só suporta pbkdf2 para LUKS2
                    libcalamares.utils.host_env_process_output(
                        [
                            "cryptsetup",
                            "luksConvertKey",
                            "--hash",
                            "sha256",
                            "--pbkdf",
                            "pbkdf2",
                            part["device"],
                        ],
                        None,
                        part["luksPassphrase"],
                    )
                    libcalamares.utils.host_env_process_output(
                        [
                            "cryptsetup",
                            "luksAddKey",
                            "--hash",
                            "sha256",
                            "--pbkdf",
                            "pbkdf2",
                            part["device"],
                            root_mount_point + "/boot/crypto_keyfile.bin",
                        ],
                        None,
                        part["luksPassphrase"],
                    )
                except subprocess.CalledProcessError:
                    libcalamares.utils.error(
                        "Falhou ao adicionar {} ao /boot/crypto_keyfile.bin".format(
                            part["luksMapperName"]
                        )
                    )
                    return (
                        _("cryptsetup falhou"),
                        _("Falha ao adicionar {} ao /boot/crypto_keyfile.bin".format(
                            part["luksMapperName"]
                        )),
                    )

    status = _("Configurando o AquaOS")
    libcalamares.job.setprogress(0.03)

    # ---------------- - hostname / hora / idioma / teclado ----------------
    cfg += cfgnetwork
    if gs.value("hostname") is None:
        catenate(variables, "hostname", "aquaos")
    else:
        catenate(variables, "hostname", gs.value("hostname"))

    if gs.value("locationRegion") is not None and gs.value("locationZone") is not None:
        cfg += cfgtime
        catenate(
            variables,
            "timezone",
            gs.value("locationRegion"),
            "/",
            gs.value("locationZone"),
        )

    if gs.value("localeConf") is not None:
        localeconf = gs.value("localeConf")
        locale = localeconf.pop("LANG").split("/")[0]
        cfg += cfglocale
        catenate(variables, "LANG", locale)
        if (
            len(set(localeconf.values())) != 1
            or list(set(localeconf.values()))[0] != locale
        ):
            cfg += cfglocaleextra
            for conf in localeconf:
                catenate(variables, conf, localeconf.get(conf).split("/")[0])

    if (
        gs.value("keyboardLayout") is not None
        and gs.value("keyboardVariant") is not None
    ):
        cfg += cfgkeymap
        catenate(variables, "kblayout", gs.value("keyboardLayout"))
        catenate(variables, "kbvariant", gs.value("keyboardVariant"))

        if gs.value("keyboardVConsoleKeymap") is not None:
            try:
                subprocess.check_output(
                    ["pkexec", "loadkeys", gs.value("keyboardVConsoleKeymap").strip()],
                    stderr=subprocess.STDOUT,
                )
                cfg += cfgconsole
                catenate(
                    variables, "vconsole", gs.value("keyboardVConsoleKeymap").strip()
                )
            except subprocess.CalledProcessError as e:
                libcalamares.utils.error("loadkeys: {}".format(e.output))
                libcalamares.utils.error(
                    "O keymap vconsole {} falhará; usando o padrão".format(
                        gs.value("keyboardVConsoleKeymap").strip()
                    )
                )
        else:
            kbdmodelmap = open(
                "/run/current-system/sw/share/systemd/kbd-model-map", "r"
            )
            kbd = kbdmodelmap.readlines()
            out = []
            for line in kbd:
                if line.startswith("#"):
                    continue
                out.append(line.split())
            # Encontrar linhas com o mesmo layout
            find = []
            for row in out:
                if gs.value("keyboardLayout") == row[1]:
                    find.append(row)
            if find != []:
                vconsole = find[0][0]
            else:
                vconsole = ""
            if gs.value("keyboardVariant") is not None:
                variant = gs.value("keyboardVariant")
            else:
                variant = "-"
            # Encontrar linhas com o mesmo variante
            for row in find:
                if variant in row[3]:
                    vconsole = row[0]
                    break
            if vconsole != "" and vconsole != "us" and vconsole is not None:
                try:
                    subprocess.check_output(
                        ["pkexec", "loadkeys", vconsole], stderr=subprocess.STDOUT
                    )
                    cfg += cfgconsole
                    catenate(variables, "vconsole", vconsole)
                except subprocess.CalledProcessError as e:
                    libcalamares.utils.error("loadkeys: {}".format(e.output))
                    libcalamares.utils.error("valor de vconsole: {}".format(vconsole))
                    libcalamares.utils.error(
                        "O keymap vconsole falhará; usando o padrão"
                    )

    # -------------------------- usuário --------------------------
    if gs.value("username") is not None:
        # O "nome exibido" é opcional no Calamares; cai para o username.
        fullname = gs.value("fullname") or gs.value("username")

        cfg += cfgusers
        catenate(variables, "username", gs.value("username"))
        catenate(variables, "fullname", fullname)

    # -------- copytree: plataforma AquaOS → disco alvo --------
    # Copia modules/base.nix e assets/ para /etc/nixos na máquina alvo —
    # exatamente a mesma árvore descrita pelo projeto flake.
    status = _("Copiando a plataforma AquaOS")
    libcalamares.job.setprogress(0.04)
    try:
        shutil.copytree(
            BASE_DIR, os.path.join(root_mount_point, "etc", "nixos"),
            dirs_exist_ok=True,
        )
    except Exception as e:
        libcalamares.utils.error(
            "Falhou ao copiar a plataforma: {}".format(e)
        )
        return (
            _("Falha ao copiar a plataforma AquaOS"),
            str(e),
        )

    # Confere se todas as variáveis do template foram usadas/definidas
    for key in variables.keys():
        pattern = "@@{key}@@".format(key=key)
        if pattern not in cfg:
            libcalamares.utils.warning("Variável '{key}' não foi usada.".format(key=key))

    variable_pattern = re.compile(r"@@\w+@@")
    for match in variable_pattern.finditer(cfg):
        variable_name = cfg[match.start() + 2 : match.end() - 2]
        if variable_name not in variables:
            libcalamares.utils.warning(
                "A variável '{key}' é usada mas não está definida.".format(key=variable_name)
            )

    for key in variables.keys():
        pattern = "@@{key}@@".format(key=key)
        cfg = cfg.replace(pattern, str(variables[key]))

    status = _("Gerando a configuração do NixOS")
    libcalamares.job.setprogress(0.05)

    try:
        # hardware.nix gerado com o swap montado
        subprocess.check_output(
            ["pkexec", "nixos-generate-config", "--root", root_mount_point],
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        if e.output is not None:
            libcalamares.utils.error(e.output.decode("utf8"))
        return (_("nixos-generate-config falhou"), _(e.output.decode("utf8")))

    hf = open(root_mount_point + "/etc/nixos/hardware-configuration.nix", "r")
    htxt = hf.read()
    hf.close()

    hardware_modified = False

    htxt_fixed = fix_btrfs_subvolumes(htxt, gs.value("partitions"))
    if htxt_fixed != htxt:
        htxt = htxt_fixed
        hardware_modified = True

    if hardware_modified:
        libcalamares.utils.host_env_process_output(
            [
                "cp",
                "/dev/stdin",
                root_mount_point + "/etc/nixos/hardware-configuration.nix",
            ],
            None,
            htxt,
        )

    # Escreve o configuration.nix
    libcalamares.utils.host_env_process_output(["cp", "/dev/stdin", config], None, cfg)

    # --------------------------- nixos-install ---------------------------
    status = _("Instalando o AquaOS")
    libcalamares.job.setprogress(INSTALL_PROGRESS_START)

    try:
        subprocess.check_output(
            ["pkexec", "chmod", "755", root_mount_point],
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        libcalamares.utils.warning(
            "Falhou ao chmod 755 em {}: {}".format(root_mount_point, e.output)
        )

    nixosInstallCmd = ["pkexec"]
    nixosInstallCmd.extend(generateProxyStrings())
    nixosInstallCmd.extend(
        [
            "nixos-install",
            "--no-root-passwd",
            "--root",
            root_mount_point,
            "--log-format",
            "internal-json",
            # O build-dir do Nix não pode ter diretórios pais world-writable;
            # alinha com o state dir do host.
            "--option",
            "build-dir",
            "/nix/var/nix/builds",
        ]
    )

    progress = NixProgress()

    try:
        output = ""
        proc = subprocess.Popen(
            nixosInstallCmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        while True:
            line = proc.stdout.readline().decode("utf-8")
            if not line:
                break

            was_json = progress.handle(line)

            if not was_json:
                output += line
            for log_line in progress.log_messages:
                output += log_line + "\n"

            mapped = INSTALL_PROGRESS_START + progress.fraction * (
                INSTALL_PROGRESS_END - INSTALL_PROGRESS_START
            )
            libcalamares.job.setprogress(mapped)

            for log_line in progress.log_messages:
                libcalamares.utils.debug("nixos-install: {}".format(log_line))
            progress.log_messages.clear()

            if not was_json:
                libcalamares.utils.debug("nixos-install: {}".format(line.strip()))

        exit = proc.wait()
        if exit != 0:
            return (_("nixos-install falhou"), _(output))
    except:
        return (_("nixos-install falhou"), _("A instalação não foi concluída"))

    libcalamares.job.setprogress(INSTALL_PROGRESS_END)
    return None
