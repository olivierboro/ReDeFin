import QtQuick 2.0

// Faux lecteur du harnais, à la place de MediaPlayer de QtMultimedia : macOS ne
// sait pas lire les flux annoncés pour la Freebox (MKV, AC3, DTS…). Il ne
// télécharge rien et simule la lecture : chargement, avance de la position,
// pause, saut, fin. Seule l'API de Qt 5.15 utilisée par l'app est reprise.
//   --fake-duration-min=<minutes>  durée simulée (120 par défaut)
Item {
    id: player
    visible: false

    enum PlaybackState { StoppedState, PlayingState, PausedState }
    enum Status { UnknownStatus, NoMedia, Loading, Loaded, Stalled, Buffering, Buffered, EndOfMedia, InvalidMedia }
    enum Error { NoError, ResourceError, FormatError, NetworkError, AccessDenied, ServiceMissing }
    enum AudioRole { UnknownRole, AccessibilityRole, AlarmRole, GameRole, MusicRole, NotificationRole, RingtoneRole, SonificationRole, VideoRole, VoiceCommunicationRole }

    property url source
    property bool autoPlay: false
    property int audioRole: MediaPlayer.UnknownRole
    property int notifyInterval: 1000
    property real playbackRate: 1.0
    property real volume: 1.0
    property bool muted: false
    property int position: 0
    property int duration: 0
    property bool seekable: false
    property int status: MediaPlayer.NoMedia
    property int playbackState: MediaPlayer.StoppedState
    property string errorString: ""

    // Jamais émis : l'app ne fait que s'y abonner.
    signal error(int code, string message)

    readonly property int _simulatedDurationMs: {
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++) {
            if (args[i].indexOf("--fake-duration-min=") === 0)
                return Math.max(1, Number(args[i].substr(20))) * 60000
        }
        return 120 * 60000
    }
    property bool _playRequested: false

    function play() {
        if (String(source) === "") return
        if (status === MediaPlayer.Loading) { _playRequested = true; return }
        if (status === MediaPlayer.EndOfMedia) position = 0
        status = MediaPlayer.Buffered
        playbackState = MediaPlayer.PlayingState
        _clock.start()
    }
    function pause() {
        if (String(source) === "") return
        _playRequested = false
        _clock.stop()
        playbackState = MediaPlayer.PausedState
    }
    function stop() {
        _playRequested = false
        _clock.stop()
        playbackState = MediaPlayer.StoppedState
        position = 0
    }
    function seek(ms) {
        if (!seekable) return
        position = Math.max(0, Math.min(duration, Math.round(ms)))
        status = MediaPlayer.Buffering
        _settle.restart()
    }

    onSourceChanged: {
        _clock.stop()
        _settle.stop()
        position = 0
        seekable = false
        playbackState = MediaPlayer.StoppedState
        if (String(source) === "") {
            _loading.stop()
            duration = 0
            status = MediaPlayer.NoMedia
            return
        }
        _playRequested = autoPlay
        status = MediaPlayer.Loading
        _loading.restart()
    }

    Timer {
        id: _loading
        interval: 500
        onTriggered: {
            player.duration = player._simulatedDurationMs
            player.seekable = true
            player.status = MediaPlayer.Loaded
            if (player._playRequested) {
                player._playRequested = false
                player.play()
            }
        }
    }

    Timer {
        id: _settle
        interval: 200
        onTriggered: player.status = MediaPlayer.Buffered
    }

    Timer {
        id: _clock
        interval: Math.max(50, player.notifyInterval)
        repeat: true
        onTriggered: {
            var next = player.position + Math.round(interval * player.playbackRate)
            if (next < player.duration) {
                player.position = next
                return
            }
            player.position = player.duration
            stop()
            player.playbackState = MediaPlayer.StoppedState
            player.status = MediaPlayer.EndOfMedia
        }
    }
}
