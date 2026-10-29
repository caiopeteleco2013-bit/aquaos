import QtQuick 2.0;
import calamares.slideshow 1.0;

// Slideshow exibido durante a instalação do AquaOS.
// Inspirado no show.qml do calamares-nixos-extensions (upstream).

Presentation
{
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 8000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        Text {
            id: titulo1
            anchors.centerIn: parent
            text: "Simples como o macOS"
            font.pixelSize: 30
            wrapMode: Text.WordWrap
            width: presentation.width
            horizontalAlignment: Text.Center
            color: "#5ac8fa"
        }
        Text {
            anchors.horizontalCenter: titulo1.horizontalCenter
            anchors.top: titulo1.bottom
            text: "Login, barra de menu, Dock, Spotlight: tudo onde você espera.<br/>" +
                  "Mas por baixo do capô roda o kernel Linux, com atualizações<br/>" +
                  "declarativas e impossíveis de deixar o sistema no meio do caminho."
            wrapMode: Text.WordWrap
            width: presentation.width
            horizontalAlignment: Text.Center
        }
    }

    Slide {
        Text {
            id: titulo2
            anchors.centerIn: parent
            text: "O que será instalado…"
            font.pixelSize: 30
            wrapMode: Text.WordWrap
            width: presentation.width
            horizontalAlignment: Text.Center
            color: "#64d2ff"
        }
        Text {
            anchors.horizontalCenter: titulo2.horizontalCenter
            anchors.top: titulo2.bottom
            text: "O AquaOS escreve um configuration.nix completo no seu disco:<br/>" +
                  "idioma, teclado, usuário, Hyprland e temas — tudo declarativo.<br/>" +
                  "<b>Toda mudança do sistema é um arquivo versionado,</b> e não um<br/>" +
                  "estado acumulado de pacotes."
        }
    }

    Slide {
        Text {
            id: titulo3
            anchors.centerIn: parent
            text: "Kernel Linux, imagem reproducible"
            font.pixelSize: 30
            wrapMode: Text.WordWrap
            width: presentation.width
            horizontalAlignment: Text.Center
            color: "#bf5af2"
        }
        Text {
            anchors.horizontalCenter: titulo3.horizontalCenter
            anchors.top: titulo3.bottom
            text: "A distribuição inteira é declarada em Nix, no formato de um flake:<br/>" +
                  "a mesma descrição gera a ISO, a VM e a máquina instalada.<br/>" +
                  "<b>Você pode rebuçar a sua AquaOS a qualquer momento.</b>"
        }
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
    }
}
