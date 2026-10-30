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

        // Avec --trace-frames, une animation permanente force une trame à chaque
        // tour : un écart entre deux trames mesure alors un vrai blocage, pas un
        // écran au repos que Qt ne redessine pas.
        Rectangle {
            id: _frameTicker
            width: 1
            height: 1
            color: "#01000000"
            visible: Qt.application.arguments.indexOf("--trace-frames") >= 0
            NumberAnimation on rotation {
                running: _frameTicker.visible
                from: 0
                to: 360
                duration: 1000
                loops: Animation.Infinite
            }
        }

        // Avec --trace-focus, journalise les appuis souris. Pendant un rejeu
        // --keys, les bloque : un clic dans la fenêtre fausserait la séquence.
        MouseArea {
            readonly property bool tracing: Qt.application.arguments.indexOf("--trace-focus") >= 0
            readonly property bool replaying: self._argument("--keys=") !== ""

            anchors.fill: parent
            z: 1000000
            enabled: (tracing || replaying) && !self._clicking
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
    //                     « *x:y » où cliquer et « **x:y » où double-cliquer
    //                     (coordonnées 1280×720 de la box), « >x:y » où amener
    //                     le pointeur, « ~x:y:delta » un coup de molette
    //                     (delta 120 = un cran vers le haut),
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

    //   --open-item=<id>[:serie]  choisit le premier profil enregistré puis ouvre
    //                     la fiche du film (ou de la série) dès que l'accueil est prêt,
    //                     par la même navigation qu'un clic sur une affiche
    function _findItem(node, accept) {
        if (!node) return null;
        if (accept(node)) return node;
        var kids = node.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = _findItem(kids[i], accept);
            if (found) return found;
        }
        return null;
    }

    property Timer _openItemTimer: Timer {
        property int homeSeenTicks: 0
        interval: 300
        repeat: true
        running: self._argument("--open-item=") !== ""
        onTriggered: {
            var home = self._findItem(self.contentItem, function(o) {
                return typeof o._navRoute === "function" && typeof o._applyContextToPosterGrid === "function";
            });
            if (!home) {
                homeSeenTicks = 0;
                var tile = self._findItem(self.contentItem, function(o) {
                    return typeof o.selectThis === "function" && !!o.uid && !o._selecting;
                });
                if (tile) tile.selectThis();
                return;
            }
            // Deux sondes de suite : la page doit être câblée à la navigation du shell.
            if (++homeSeenTicks < 2) return;
            stop();
            var spec = self._argument("--open-item=").split(":");
            var page = spec[1] === "serie" ? "detailSeriePage.qml" : "detailMoviePage.qml";
            home.requestNavigation(home._navRoute(page, { itemId: spec[0] }));
        }
    }

    // Vrai le temps d'un clic simulé, que le blocage de la souris laisse passer.
    property bool _clicking: false

    //   --trace-frames    journalise chaque trame arrivée plus de 50 ms après la
    //                     précédente (à-coup visible), avec l'heure depuis le lancement
    property double _lastFrameMs: 0
    property double _startMs: Date.now()
    onFrameSwapped: {
        if (Qt.application.arguments.indexOf("--trace-frames") < 0) return;
        var now = Date.now();
        if (_lastFrameMs > 0 && now - _lastFrameMs > 50)
            console.log("[trame]", ((now - _startMs) / 1000).toFixed(2) + "s", "à-coup de", now - _lastFrameMs, "ms");
        _lastFrameMs = now;
    }

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
        } else if (step.charAt(0) === "*") {
            var doubleClick = step.charAt(1) === "*";
            var xy = step.substr(doubleClick ? 2 : 1).split(":");
            var point = scaler.mapToItem(contentItem, Number(xy[0]), Number(xy[1]));
            _clicking = true;
            if (doubleClick)
                _keys.mouseDoubleClickSequence(contentItem, point.x, point.y, Qt.LeftButton, Qt.NoModifier, -1);
            else
                _keys.mouseClick(contentItem, point.x, point.y, Qt.LeftButton, Qt.NoModifier, -1);
            _clicking = false;
        } else if (step.charAt(0) === ">") {
            var moveArgs = step.substr(1).split(":");
            var movePoint = scaler.mapToItem(contentItem, Number(moveArgs[0]), Number(moveArgs[1]));
            _clicking = true;
            _keys.mouseMove(contentItem, movePoint.x, movePoint.y, -1, Qt.NoButton);
            _clicking = false;
        } else if (step.charAt(0) === "~") {
            var wheelArgs = step.substr(1).split(":");
            var wheelPoint = scaler.mapToItem(contentItem, Number(wheelArgs[0]), Number(wheelArgs[1]));
            _clicking = true;
            _keys.mouseWheel(contentItem, wheelPoint.x, wheelPoint.y, Qt.NoButton, Qt.NoModifier, 0, Number(wheelArgs[2]), -1);
            _clicking = false;
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
