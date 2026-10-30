import QtQuick 2.0

// Mire du faux lecteur du harnais, à la place de VideoOutput : barres de
// couleur 16:9 et position simulée du MediaPlayer donné en source.
Item {
    id: output

    enum FillMode { Stretch, PreserveAspectFit, PreserveAspectCrop }

    property var source: null
    property int fillMode: VideoOutput.PreserveAspectFit
    property int orientation: 0

    function _clock(ms) {
        var s = Math.floor(Math.max(0, ms) / 1000)
        var h = Math.floor(s / 3600)
        var m = Math.floor(s / 60) % 60
        s = s % 60
        return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    Item {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height * 16 / 9)
        height: width * 9 / 16
        visible: !!output.source && output.source.duration > 0

        Row {
            anchors.fill: parent
            Repeater {
                model: ["#C0C0C0", "#C0C000", "#00C0C0", "#00C000", "#C000C0", "#C00000", "#0000C0"]
                Rectangle { width: parent.width / 7; height: parent.height; color: modelData; opacity: 0.55 }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: label.implicitWidth + 48
            height: label.implicitHeight + 32
            radius: 12
            color: "#CC000000"

            Text {
                id: label
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                color: "white"
                font.pixelSize: 28
                textFormat: Text.PlainText
                text: "Lecture simulée (harnais)\n"
                      + output._clock(output.source ? output.source.position : 0)
                      + " / " + output._clock(output.source ? output.source.duration : 0)
                      + (output.source && output.source.playbackState === MediaPlayer.PausedState ? "  ⏸" : "")
            }
        }
    }
}
