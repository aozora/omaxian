import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Every image, video and music model for this machine, and the memory they
// run in: set one up, start, stop or switch to it, update it, or remove it.
// Opened from the model's mark in the prompt bar, or with Ctrl+M.
Popup {
    id: root
    objectName: "library"
    required property var models
    required property color muted
    required property color line
    // Something is being made: nothing may stop or swap the model under it.
    required property bool busy

    // The row asking whether to remove its model, by id.
    property string confirming: ""
    readonly property var language: Qt.locale(translator.language)
    readonly property color warning: theme.colors.yellow || theme.accent
    readonly property color danger: theme.colors.red || theme.foreground

    anchors.centerIn: Overlay.overlay
    width: Math.min(parent ? parent.width - 80 : 640, 640)
    height: Math.min(parent ? parent.height - 80 : 720, content.implicitHeight)
    modal: true
    focus: true
    padding: 0
    Overlay.modal: Rectangle { color: root.Material.backgroundDimColor }
    background: Rectangle {
        color: theme.background
        border.color: root.line
        radius: theme.radius
    }
    onOpened: models.watching = true
    onClosed: {
        models.watching = false
        confirming = ""
    }

    // Memory in whole GB, but a tenth under one, so a model that has let go
    // of nearly everything doesn't read as holding nothing at all.
    function gb(value) {
        return Number(value).toLocaleString(language, 'f', value > 0 && value < 0.95 ? 1 : 0)
    }
    function size(bytes) {
        return language.formattedDataSize(bytes, 1, Locale.DataSizeTraditionalFormat)
    }
    function kindName(section) {
        return section === "music" ? qsTr("Music") : section === "video" ? qsTr("Video")
             : section === "unavailable" ? qsTr("Not for this machine") : qsTr("Images")
    }
    function names(list) {
        const all = list.map(holder => holder.name)
        return all.length < 2 ? all.join("") : qsTr("%1 and %2").arg(all.slice(0, -1).join(", ")).arg(all[all.length - 1])
    }
    // Who holds the memory a model needs: "Qwen3.8 27B is using 40 GB".
    function holding(room) {
        const gib = room.reduce((sum, holder) => sum + holder.gib, 0)
        return (room.length === 1 ? qsTr("%1 is using %2 GB") : qsTr("%1 are using %2 GB")).arg(names(room)).arg(gb(gib))
    }
    function needLine(row) {
        return qsTr("Needs %1 GB RAM (%2 GB is free)").arg(gb(row.needs)).arg(gb(Math.floor(models.memoryFree)))
    }
    // The engine's reason a model isn't for this machine, said plainly.
    function why(reason) {
        const needs = /needs ([\d.]+) GiB.*has ([\d.]+)/.exec(reason)
        if (needs)
            return qsTr("Needs %1 GB of memory, and this machine has %2 GB").arg(gb(Number(needs[1]))).arg(gb(Number(needs[2])))
        if (reason.indexOf("can't run on") >= 0)
            return qsTr("Not made for this machine's graphics yet")
        return reason
    }
    function progress(row) {
        const parts = [qsTr("%1 of %2").arg(size(row.doneBytes)).arg(size(row.totalBytes))]
        if (row.rateBytes > 0) {
            parts.push(qsTr("%1/s").arg(size(row.rateBytes)))
            const minutes = Math.round((row.totalBytes - row.doneBytes) / row.rateBytes / 60)
            parts.push(minutes >= 1 ? qsTr("about %Ln minutes left", "", minutes) : qsTr("less than a minute left"))
        }
        return parts.join(" · ")
    }
    // What a row says under its name.
    function detail(row) {
        switch (row.state) {
        case "running": return row.held > 0 ? qsTr("Using %1 GB RAM").arg(gb(row.held)) : qsTr("Running")
        case "starting": return qsTr("Starting…")
        case "stopping": return qsTr("Stopping…")
        case "removing": return qsTr("Removing…")
        case "failed": return row.error
        case "unavailable": return why(row.reason)
        case "installing":
        case "updating":
            if (row.phase === "downloading" && row.totalBytes > 0)
                return progress(row)
            if (row.phase === "waiting")
                return qsTr("Next, once the one before it is in")
            return row.state === "updating" ? qsTr("Updating…") : qsTr("Getting ready…")
        default: return row.needs > 0 && models.memoryTotal > 0 ? needLine(row) : ""
        }
    }
    // What's in the way of a stopped model, when it doesn't fit now.
    function note(row) {
        if (["stopped", "offer"].indexOf(row.state) < 0 || row.fits)
            return ""
        const parts = []
        if (row.room.length > 0)
            parts.push(holding(row.room))
        if (row.shortBy > 0)
            parts.push(qsTr("Close other apps to free %1 GB more").arg(gb(row.shortBy)))
        return parts.join(". ")
    }

    contentItem: ColumnLayout {
        id: content
        spacing: 0
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        // ------------------------------------------------- title and memory
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.bottomMargin: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Models")
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: theme.foreground
                }
                Label {
                    visible: models.memoryTotal > 0
                    text: qsTr("%1 GB free of %2 GB").arg(root.gb(models.memoryFree)).arg(root.gb(models.memoryTotal))
                    font.pixelSize: 13
                    color: root.muted
                }
            }

            // The machine's memory as one bar: each running model, then the
            // desktop and its apps, then what's free, to scale.
            Item {
                id: bar
                objectName: "memory"
                visible: models.memoryTotal > 0
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                readonly property real held: models.holders.reduce((sum, holder) => sum + holder.gib, 0)
                readonly property real apps: Math.max(0, models.memoryTotal - models.memoryFree - held)
                function share(gib) { return models.memoryTotal > 0 ? width * Math.min(gib, models.memoryTotal) / models.memoryTotal : 0 }
                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(4, theme.radius)
                    color: root.line
                }
                Row {
                    height: parent.height
                    Repeater {
                        model: models.holders
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: bar.share(modelData.gib)
                            height: bar.height
                            color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 1 - index * 0.25)
                        }
                    }
                    Rectangle {
                        width: bar.share(bar.apps)
                        height: bar.height
                        color: root.muted
                        opacity: 0.45
                    }
                }
            }

            // What holds it, by name: the coding models too.
            Flow {
                visible: models.memoryTotal > 0
                Layout.fillWidth: true
                spacing: 16
                Repeater {
                    model: models.holders.concat(bar.apps >= 0.5 ? [{ name: qsTr("Desktop and apps"), gib: bar.apps, apps: true }] : [])
                    delegate: Row {
                        required property var modelData
                        required property int index
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: modelData.apps ? root.muted : Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 1 - index * 0.25)
                            opacity: modelData.apps ? 0.45 : 1
                        }
                        Label {
                            text: modelData.name + "  " + qsTr("%1 GB").arg(root.gb(modelData.gib))
                            font.pixelSize: 12
                            color: root.muted
                        }
                    }
                }
            }

            Label {
                visible: models.error !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: root.danger
                text: models.error
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.line }

        // ------------------------------------------------------ the models
        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: rows.implicitHeight + 24
            contentHeight: rows.implicitHeight + 24
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: rows
                x: 24
                y: 4
                width: scroller.width - 48
                spacing: 0

                Repeater {
                    model: models.libraryIds
                    delegate: ColumnLayout {
                        id: entry
                        required property string modelData
                        readonly property var row: models.library[modelData] || ({})
                        readonly property bool asking: root.confirming === modelData
                        readonly property bool settled: ["running", "stopped"].indexOf(row.state) >= 0
                        objectName: "row-" + modelData
                        Layout.fillWidth: true
                        spacing: 0

                        Label {
                            visible: entry.row.first === true
                            Layout.topMargin: 18
                            Layout.bottomMargin: 2
                            text: root.kindName(entry.row.section)
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: root.muted
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            Layout.bottomMargin: 8
                            spacing: 14
                            opacity: entry.row.state === "unavailable" ? 0.6 : 1

                            Image {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 2
                                sourceSize: Qt.size(56, 56)
                                fillMode: Image.PreserveAspectFit
                                source: root.models.logo(entry.row.vendor || "", theme.light) || "qrc:/icons/model.svg"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                RowLayout {
                                    spacing: 8
                                    Label {
                                        text: entry.row.name || ""
                                        font.pixelSize: 15
                                        color: theme.foreground
                                    }
                                    Label {
                                        visible: entry.row.inUse === true && entry.row.state === "running"
                                        text: qsTr("In use")
                                        font.pixelSize: 12
                                        color: theme.accent
                                    }
                                    Label {
                                        visible: entry.row.state === "offer" && entry.row.best === true
                                        text: qsTr("Best for this machine")
                                        font.pixelSize: 12
                                        color: root.muted
                                    }
                                }
                                Label {
                                    objectName: "detail"
                                    Layout.fillWidth: true
                                    // Mirrored with the layout, whichever script the text starts in.
                                    horizontalAlignment: Text.AlignLeft
                                    visible: text !== ""
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 12
                                    color: entry.row.state === "failed" ? root.danger
                                         : ["stopped", "offer"].indexOf(entry.row.state) >= 0 && !entry.row.fits ? root.warning : root.muted
                                    text: root.detail(entry.row)
                                }
                                Label {
                                    objectName: "note"
                                    Layout.fillWidth: true
                                    // Mirrored with the layout, whichever script the text starts in.
                                    horizontalAlignment: Text.AlignLeft
                                    visible: text !== ""
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 12
                                    color: theme.foreground
                                    text: root.note(entry.row)
                                }
                                // A download, an update's, or a start timed against
                                // the last one.
                                Rectangle {
                                    id: track
                                    readonly property bool downloading: entry.row.phase === "downloading" && entry.row.totalBytes > 0
                                                                       && (entry.row.state === "installing" || entry.row.state === "updating")
                                    visible: downloading || entry.row.state === "starting"
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    implicitHeight: 4
                                    radius: 2
                                    color: root.line
                                    property real fill: 0
                                    readonly property bool starting: entry.row.state === "starting"
                                    onStartingChanged: {
                                        startFill.stop()
                                        if (!starting)
                                            return
                                        const expected = entry.row.loadSeconds > 0 ? entry.row.loadSeconds * 1000 : 30000
                                        const elapsed = entry.row.sinceMs > 0 ? Math.max(0, Date.now() - entry.row.sinceMs) : 0
                                        startFill.from = Math.min(0.9, 0.9 * elapsed / expected)
                                        startFill.duration = Math.max(0, expected - elapsed)
                                        startFill.start()
                                    }
                                    Component.onCompleted: startingChanged()
                                    NumberAnimation { id: startFill; target: track; property: "fill"; to: 0.9 }
                                    Rectangle {
                                        height: parent.height
                                        radius: parent.radius
                                        color: theme.accent
                                        width: parent.width * (track.downloading ? Math.min(1, entry.row.doneBytes / entry.row.totalBytes) : track.fill)
                                        Behavior on width {
                                            enabled: track.downloading
                                            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }
                            }

                            // Its actions, on the far side.
                            RowLayout {
                                Layout.alignment: Qt.AlignTop
                                spacing: 2
                                visible: !entry.asking
                                enabled: !root.models.working && !root.busy

                                Button {
                                    objectName: "update"
                                    visible: entry.row.update === true && entry.settled
                                    flat: true
                                    Material.roundedScale: theme.radius
                                    text: qsTr("Update")
                                    ToolTip.visible: hovered && entry.row.updateBytes > 0
                                    ToolTip.text: qsTr("Download %1").arg(root.size(entry.row.updateBytes))
                                    ToolTip.delay: 300
                                    onClicked: root.models.update(entry.modelData)
                                }
                                Button {
                                    objectName: "use"
                                    visible: entry.row.state === "running" && !entry.row.inUse
                                    flat: true
                                    Material.roundedScale: theme.radius
                                    text: qsTr("Use")
                                    onClicked: {
                                        root.models.choose(entry.modelData)
                                        root.close()
                                    }
                                }
                                Button {
                                    objectName: "stop"
                                    visible: entry.row.state === "running" || entry.row.state === "starting"
                                    flat: true
                                    Material.roundedScale: theme.radius
                                    text: qsTr("Stop")
                                    onClicked: root.models.stop(entry.modelData)
                                }
                                Button {
                                    objectName: "cancel"
                                    visible: entry.row.state === "installing" || entry.row.state === "failed"
                                    flat: true
                                    Material.roundedScale: theme.radius
                                    text: entry.row.state === "failed" ? qsTr("Dismiss") : qsTr("Cancel")
                                    onClicked: root.models.remove(entry.modelData)
                                }
                                Button {
                                    objectName: "start"
                                    // Starting stops what's in its way, by name in the note.
                                    readonly property bool makesRoom: !entry.row.fits && entry.row.room.length > 0 && entry.row.shortBy <= 0
                                    visible: entry.row.state === "stopped" || entry.row.state === "failed"
                                    enabled: entry.row.state === "failed" || entry.row.fits || makesRoom
                                    flat: true
                                    Material.roundedScale: theme.radius
                                    text: entry.row.state === "failed" ? qsTr("Try again") : makesRoom ? qsTr("Make room and start") : qsTr("Start")
                                    onClicked: {
                                        if (entry.row.state === "failed") {
                                            root.models.setUp(entry.modelData)
                                        } else {
                                            root.models.startModel(entry.modelData)
                                            root.close()
                                        }
                                    }
                                }
                                Button {
                                    id: download
                                    objectName: "download"
                                    visible: entry.row.state === "offer"
                                    highlighted: true
                                    Material.roundedScale: theme.radius
                                    text: entry.row.downloadBytes > 0 ? qsTr("Download %1").arg(root.size(entry.row.downloadBytes)) : qsTr("Download")
                                    onClicked: root.models.setUp(entry.modelData)
                                    // A highlighted button colors its caption by Material's own
                                    // rule, which doesn't read on every accent.
                                    contentItem: Label {
                                        text: download.text
                                        font: download.font
                                        color: theme.accentForeground
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                                ToolButton {
                                    objectName: "remove"
                                    visible: entry.settled
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    display: AbstractButton.IconOnly
                                    icon.source: "qrc:/icons/delete.svg"
                                    icon.color: hovered ? theme.foreground : root.muted
                                    icon.width: 18
                                    icon.height: 18
                                    Accessible.name: qsTr("Remove")
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Remove")
                                    ToolTip.delay: 300
                                    onClicked: root.confirming = entry.modelData
                                }
                            }
                        }

                        // Removing asks first, saying what it frees.
                        RowLayout {
                            visible: entry.asking
                            enabled: !root.busy
                            Layout.fillWidth: true
                            Layout.leftMargin: 42
                            Layout.bottomMargin: 8
                            spacing: 8
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: 13
                                color: theme.foreground
                                text: entry.row.downloadBytes > 0
                                      ? qsTr("Remove %1 and free about %2?").arg(entry.row.name).arg(root.size(entry.row.downloadBytes))
                                      : qsTr("Remove %1?").arg(entry.row.name)
                            }
                            Button {
                                objectName: "keep"
                                flat: true
                                Material.roundedScale: theme.radius
                                text: qsTr("Keep")
                                onClicked: root.confirming = ""
                            }
                            Button {
                                id: confirmRemove
                                objectName: "confirmRemove"
                                highlighted: true
                                Material.roundedScale: theme.radius
                                text: qsTr("Remove")
                                onClicked: {
                                    root.confirming = ""
                                    root.models.remove(entry.modelData)
                                }
                                contentItem: Label {
                                    text: confirmRemove.text
                                    font: confirmRemove.font
                                    color: theme.accentForeground
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
