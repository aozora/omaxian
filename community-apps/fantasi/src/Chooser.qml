import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// A first run: what this machine can make, Images, Music and Video, each with
// what it downloads and the memory it runs in. A pick downloads in its card,
// the next waits its turn, and once one is ready the prompt bar below opens.
Item {
    id: root
    required property var models
    required property color muted
    required property color line

    readonly property var locale: Qt.locale(translator.language)
    // The first ready, by kind, which the title greets.
    readonly property var ready: models.offers.find(offer => offer.phase === "ready")
    readonly property bool busy: models.offers.some(offer => ["waiting", "downloading", "starting"].indexOf(offer.phase) >= 0)

    function kindName(kind) {
        return kind === "music" ? qsTr("Music") : kind === "video" ? qsTr("Video") : qsTr("Images")
    }
    function blurb(kind) {
        return kind === "music" ? qsTr("Songs with vocals, from a style and lyrics")
             : kind === "video" ? qsTr("Clips with sound, from a prompt or a picture")
             : qsTr("Pictures from a prompt, or changes to your own")
    }
    function size(bytes) {
        return locale.formattedDataSize(bytes, 1)
    }
    function progress(offer) {
        const parts = [qsTr("%1 of %2").arg(size(offer.doneBytes)).arg(size(offer.totalBytes))]
        if (offer.rateBytes > 0) {
            parts.push(qsTr("%1/s").arg(size(offer.rateBytes)))
            const minutes = Math.round((offer.totalBytes - offer.doneBytes) / offer.rateBytes / 60)
            parts.push(minutes >= 1 ? qsTr("about %Ln minutes left", "", minutes) : qsTr("less than a minute left"))
        }
        return parts.join(" · ")
    }

    // As many cards across as fit at 240 or more each, up to three; what's
    // too tall for the stage scrolls, centred while it fits.
    readonly property int across: Math.max(1, Math.min(models.offers.length, Math.floor((width - 40 + 18) / (240 + 18))))
    readonly property int cardWidth: Math.min(300, Math.floor((width - 40 - (across - 1) * 18) / across))

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, page.implicitHeight + 40)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: page
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 980)
            spacing: 10

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 28
                font.weight: Font.DemiBold
                color: theme.foreground
                text: !root.ready ? qsTr("What would you like to make?")
                    : root.ready.kind === "music" ? qsTr("Music is ready. Try something!")
                    : root.ready.kind === "video" ? qsTr("Video is ready. Try something!")
                    : qsTr("Images are ready. Try something!")
            }
            Label {
                Layout.fillWidth: true
                Layout.bottomMargin: 22
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 15
                color: root.muted
                visible: text !== ""
                text: !root.ready ? qsTr("Each runs right here on this machine. Pick one to download, or more.")
                    : root.busy ? qsTr("The rest keeps downloading underneath.") : ""
            }

            // Cards side by side, or stacked in a narrow window.
            GridLayout {
                id: cards
                Layout.alignment: Qt.AlignHCenter
                columns: root.across
                columnSpacing: 18
                rowSpacing: 12
                Repeater {
                    model: root.models.offers
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        readonly property string phase: modelData.phase
                        readonly property bool working: ["waiting", "downloading", "starting"].indexOf(phase) >= 0
                        objectName: "offer-" + modelData.kind
                        Layout.preferredWidth: root.cardWidth
                        Layout.preferredHeight: cards.columns > 1 ? 290 : implicitHeight
                        implicitHeight: content.implicitHeight + 44
                        radius: theme.radius
                        color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.85)
                        border.color: phase === "offer" || phase === "installed" ? root.line : phase === "failed" ? theme.colors.red || theme.accent : theme.accent
                        border.width: 1

                        ColumnLayout {
                            id: content
                            anchors.fill: parent
                            anchors.margins: 22
                            spacing: 6
                            RowLayout {
                                spacing: 12
                                Image {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    sourceSize: Qt.size(56, 56)
                                    fillMode: Image.PreserveAspectFit
                                    source: root.models.logo(card.modelData.vendor, theme.light) || "qrc:/icons/model.svg"
                                }
                                Label {
                                    text: root.kindName(card.modelData.kind)
                                    font.pixelSize: 21
                                    font.weight: Font.DemiBold
                                    color: theme.foreground
                                }
                            }
                            Label {
                                Layout.topMargin: 4
                                text: card.modelData.name
                                font.pixelSize: 15
                                color: theme.foreground
                            }
                            Label {
                                Layout.fillWidth: true
                                text: root.blurb(card.modelData.kind)
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                color: root.muted
                            }
                            Item { Layout.fillHeight: true; Layout.minimumHeight: 12 }
                            // What it takes: the download and the memory it runs in.
                            GridLayout {
                                columns: 2
                                columnSpacing: 14
                                rowSpacing: 3
                                Label { visible: card.modelData.downloadBytes > 0; text: qsTr("Download"); font.pixelSize: 13; color: root.muted }
                                Label { visible: card.modelData.downloadBytes > 0; text: root.size(card.modelData.downloadBytes); font.pixelSize: 13; color: theme.foreground }
                                Label { visible: card.modelData.memoryBytes > 0; text: qsTr("Memory"); font.pixelSize: 13; color: root.muted }
                                Label { visible: card.modelData.memoryBytes > 0; text: root.size(card.modelData.memoryBytes); font.pixelSize: 13; color: theme.foreground }
                            }
                            Item { Layout.preferredHeight: 8 }

                            // An offer is a button; a setup a bar with its numbers;
                            // a model set up says so.
                            Button {
                                id: get
                                objectName: "download"
                                visible: card.phase === "offer" || card.phase === "failed"
                                Layout.fillWidth: true
                                highlighted: true
                                enabled: !root.models.working
                                Material.roundedScale: theme.radius
                                text: card.phase === "failed" ? qsTr("Try again")
                                    : card.modelData.downloadBytes > 0 ? qsTr("Download %1").arg(root.size(card.modelData.downloadBytes)) : qsTr("Download")
                                onClicked: root.models.download(card.modelData.id)
                                // A highlighted button colors its caption by Material's own
                                // rule, which doesn't read on every accent.
                                contentItem: Label {
                                    text: get.text
                                    font: get.font
                                    color: theme.accentForeground
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            ColumnLayout {
                                visible: card.working
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 4
                                    color: root.line
                                    Rectangle {
                                        height: parent.height
                                        width: parent.width * (card.phase === "downloading" && card.modelData.totalBytes > 0
                                                               ? Math.min(1, card.modelData.doneBytes / card.modelData.totalBytes) : card.phase === "starting" ? 1 : 0)
                                        color: theme.accent
                                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    font.pixelSize: 12
                                    color: root.muted
                                    text: card.phase === "downloading" && card.modelData.totalBytes > 0 ? root.progress(card.modelData)
                                        : card.phase === "starting" ? qsTr("Starting %1…").arg(card.modelData.name)
                                        : qsTr("Next, once the one before it is in")
                                }
                            }
                            Label {
                                visible: card.phase === "failed" && card.modelData.error !== ""
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: 12
                                color: theme.colors.red || theme.foreground
                                text: card.modelData.error
                            }
                            Button {
                                objectName: "start"
                                visible: card.phase === "installed"
                                Layout.fillWidth: true
                                flat: true
                                enabled: !root.models.working
                                Material.roundedScale: theme.radius
                                text: qsTr("Start %1").arg(card.modelData.name)
                                onClicked: root.models.choose(card.modelData.id)
                            }
                            Label {
                                visible: card.phase === "ready"
                                Layout.preferredHeight: 36
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 14
                                color: theme.accent
                                text: "✓  " + qsTr("Ready")
                            }
                        }
                    }
                }
            }
        }
    }
}
