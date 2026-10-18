import QtQuick 2.0
import Qt.labs.settings 1.1 as Labs

// Remplaçant poste de travail de fbx.application.Settings : le Player persiste
// lui-même les propriétés que l'app déclare et émet `ready` une fois chargées.
// Ici, elles sont gardées en JSON dans data/settings.ini. Ne rien journaliser :
// l'app y range ses données de session.
QtObject {
    id: self

    signal ready()

    property bool _loading: false

    property Labs.Settings _store: Labs.Settings {
        fileName: decodeURIComponent(String(Qt.resolvedUrl("../../../data/settings.ini")).replace(/^file:\/\//, ""))
        property string json: "{}"
    }

    property Timer _saveTimer: Timer {
        interval: 100
        onTriggered: self._save()
    }

    // Persistées : les propriétés déclarées par l'app, hors propriétés internes
    // préfixées par « _ », signaux, fonctions et objets.
    function _persistedKeys() {
        var keys = [];
        for (var key in self) {
            if (key === "objectName" || key.charAt(0) === "_" || !self[key + "Changed"])
                continue;
            var value = self[key];
            if (typeof value === "function" || Qt.isQtObject(value))
                continue;
            keys.push(key);
        }
        return keys;
    }

    function _save() {
        var values = {};
        _persistedKeys().forEach(function(key) { values[key] = self[key]; });
        _store.json = JSON.stringify(values);
    }

    // Différé pour que _store ait lu son fichier avant le chargement.
    Component.onCompleted: Qt.callLater(function() {
        var stored = {};
        try {
            stored = JSON.parse(self._store.json);
        } catch (e) {
        }

        var keys = self._persistedKeys();
        self._loading = true;
        keys.forEach(function(key) {
            if (stored[key] !== undefined)
                self[key] = stored[key];
        });
        self._loading = false;

        keys.forEach(function(key) {
            self[key + "Changed"].connect(function() {
                if (!self._loading)
                    self._saveTimer.restart();
            });
        });
        self.ready();
    })

    Component.onDestruction: {
        try {
            _save();
        } catch (e) {
        }
    }
}
