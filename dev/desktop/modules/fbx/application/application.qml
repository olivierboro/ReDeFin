import QtQuick 2.0
import QtQuick.Window 2.1
import QtTest 1.2

// Remplaçant poste de travail de fbx.application.Application : une fenêtre
// redimensionnable au lieu du plein écran du Player. UiScaler garde la surface
// logique 1280×720 de la box, quelle que soit la taille de la fenêtre.
Window {
    id: self

    property string identifier
    property string name
    property int profileId

    objectName: "fbx.application.Application"
    default property alias contents: surface.data
    property alias scaler: scaler

    color: "black"
    title: "ReDeFin — poste de travail"
    visible: true

    // Sur le Player, lan.hosts() liste les appareils connus de la Freebox ; la
    // découverte Jellyfin de l'app les sonde puis balaie leur /24. Ici, la liste
    // vient de --lan-hosts=<ip,ip…>, que run.sh tire de la table ARP du poste.
    readonly property var lan: ({
        hosts: function() {
            var ips = self._argument("--lan-hosts=");
            return ips ? ips.split(",").map(function(ip) {
                return {
                    active: true,
                    reachable: true,
                    l3connectivities: [{ addr: ip, af: "ipv4", active: true, reachable: true }]
                };
            }) : [];
        }
    })

    data: UiScaler {
        id: scaler

        FocusScope {
            id: surface

            anchors.fill: parent
            focus: true

            // Un Retour que l'app n'a pas traité ne remonte pas plus haut.
            Keys.onPressed: event.accepted = event.key === Qt.Key_Escape || event.key === Qt.Key_Back
        }

        // Enfant d'un Item : TestEvent retrouve la fenêtre par son parent.
        TestEvent {
            id: _keys
        }

        // Avec --trace-focus, journalise les appuis souris. Pendant un rejeu
        // --keys, les bloque : un clic dans la fenêtre fausserait la séquence.
        MouseArea {
            readonly property bool tracing: Qt.application.arguments.indexOf("--trace-focus") >= 0
            readonly property bool replaying: self._argument("--keys=") !== ""

            anchors.fill: parent
            z: 1000000
            enabled: tracing || replaying
            acceptedButtons: Qt.AllButtons
            onPressed: {
                if (tracing)
                    console.log("[souris] appui", Math.round(mouse.x), Math.round(mouse.y), replaying ? "(bloqué)" : "");
                mouse.accepted = replaying;
            }
        }
    }

    // main.qml impose 1920×1080, plus grand qu'un écran de portable : la taille
    // 720p est appliquée après cette affectation.
    Component.onCompleted: Qt.callLater(function() {
        self.width = 1280;
        self.height = 720;
    })

    // Pilotage sans permission d'accessibilité ni d'enregistrement d'écran, les
    // événements restant internes à la fenêtre :
    //   --keys=<étapes>   après --grab-delay (6 s), rejoue des étapes séparées par
    //                     des virgules : nom de touche Qt sans « Key_ » (Return,
    //                     Down…), « =texte » à taper, « +ms » à attendre,
    //                     « @fichier.png » à capturer
    //   --grab=<fichier>  capture la fenêtre après les étapes puis quitte
    //   --trace-focus     journalise chaque changement d'élément actif
    function _argument(prefix) {
        var args = Qt.application.arguments;
        for (var i = 0; i < args.length; i++) {
            if (args[i].indexOf(prefix) === 0)
                return args[i].substr(prefix.length);
        }
        return "";
    }

    property var _steps: self._argument("--keys=") ? self._argument("--keys=").split(",") : []

    onActiveFocusItemChanged: {
        if (Qt.application.arguments.indexOf("--trace-focus") >= 0)
            console.log("[focus]", activeFocusItem, activeFocusItem ? "dans " + activeFocusItem.parent : "");
    }

    function _nextStep() {
        if (_steps.length === 0) {
            if (_argument("--grab="))
                contentItem.grabToImage(function(result) {
                    result.saveToFile(self._argument("--grab="));
                    Qt.quit();
                });
            return;
        }

        var step = _steps.shift();
        var wait = 300;
        if (step.charAt(0) === "+") {
            wait = Number(step.substr(1));
        } else if (step.charAt(0) === "=") {
            for (var i = 1; i < step.length; i++)
                _keys.keyClickChar(step.charAt(i), Qt.NoModifier, -1);
        } else if (step.charAt(0) === "@") {
            contentItem.grabToImage(function(result) { result.saveToFile(step.substr(1)); });
        } else if (Qt["Key_" + step] !== undefined) {
            _keys.keyClick(Qt["Key_" + step], Qt.NoModifier, -1);
        } else {
            console.warn("[harnais] étape inconnue :", step);
        }
        _player.interval = wait;
        _player.start();
    }

    property Timer _player: Timer {
        running: self._argument("--keys=") !== "" || self._argument("--grab=") !== ""
        interval: Number(self._argument("--grab-delay=") || 6000)
        onTriggered: {
            if (self._steps.length > 0)
                self.requestActivate();
            self._nextStep();
        }
    }
}
