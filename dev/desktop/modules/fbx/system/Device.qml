pragma Singleton
import QtQuick 2.0

// Remplaçant poste de travail de fbx.system.Device, singleton natif du Player
// absent de libfbxqml. Le modèle choisit le profil de lecture de l'app :
// fbx6hd (Révolution) par défaut, fbx7hd-delta pour la Delta / Devialet.
QtObject {
    readonly property string model: argument("--fbx-model=", "fbx6hd")
    readonly property string firmwareVersion: argument("--fbx-firmware=", "desktop")

    function argument(prefix, fallback) {
        var args = Qt.application.arguments;
        for (var i = 0; i < args.length; i++) {
            if (args[i].indexOf(prefix) === 0)
                return args[i].substr(prefix.length);
        }
        return fallback;
    }
}
