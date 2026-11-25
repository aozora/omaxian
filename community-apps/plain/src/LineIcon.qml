import QtQuick
import QtQuick.Window

// A small line icon, drawn rather than loaded, in the color it's given:
// save, open, lock and help in the footer, sidebar to show the files, and
// folder, file and chevron in the files. From Omawrite (MIT, David
// Heinemeier Hansson), with the lock, help and the sidebar's added.
Item {
    id: icon

    property string name
    property color color: "#666666"

    width: 16
    height: 16

    Canvas {
        id: canvas

        // Canvas rasterizes one surface pixel per logical pixel and gets
        // upscaled blurry on hidpi screens. Draw at the physical size and
        // scale the item back down so surface pixels match screen pixels.
        readonly property real dpr: Screen.devicePixelRatio
        width: icon.width * dpr
        height: icon.height * dpr
        transformOrigin: Item.TopLeft
        scale: 1 / dpr
        onDprChanged: requestPaint()

        onPaint: {
            var context = getContext("2d");
            context.setTransform(dpr * icon.width / 16, 0, 0, dpr * icon.height / 16, 0, 0);
            context.clearRect(0, 0, 16, 16);
            context.strokeStyle = icon.color;
            context.fillStyle = icon.color;
            context.lineWidth = 1.4;
            context.lineCap = "round";
            context.lineJoin = "round";
            context.beginPath();
            if (icon.name === "save") {
                context.moveTo(2.5, 2.5);
                context.lineTo(10.5, 2.5);
                context.lineTo(13.5, 5.5);
                context.lineTo(13.5, 13.5);
                context.lineTo(2.5, 13.5);
                context.closePath();
                context.moveTo(5.5, 2.5);
                context.lineTo(5.5, 6);
                context.lineTo(10, 6);
                context.lineTo(10, 2.5);
                context.moveTo(4.5, 13.5);
                context.lineTo(4.5, 9.5);
                context.lineTo(11.5, 9.5);
                context.lineTo(11.5, 13.5);
            } else if (icon.name === "lock") {
                context.moveTo(5.5, 7.5);
                context.lineTo(5.5, 5);
                context.arc(8, 5, 2.5, Math.PI, 0, false);
                context.lineTo(10.5, 7.5);
                context.moveTo(3.5, 7.5);
                context.lineTo(12.5, 7.5);
                context.lineTo(12.5, 13.5);
                context.lineTo(3.5, 13.5);
                context.closePath();
            } else if (icon.name === "help") {
                // A question mark in a circle.
                context.moveTo(13.5, 8);
                context.arc(8, 8, 5.5, 0, 2 * Math.PI, false);
                context.moveTo(6.3, 6.6);
                context.quadraticCurveTo(6.4, 4.9, 8, 4.9);
                context.quadraticCurveTo(9.7, 4.9, 9.7, 6.4);
                context.quadraticCurveTo(9.7, 7.4, 8.6, 7.9);
                context.quadraticCurveTo(8, 8.2, 8, 9.1);
                context.moveTo(8, 11.1);
                context.lineTo(8, 11.2);
            } else if (icon.name === "sidebar" || icon.name === "sidebarOpen") {
                // A window with its left pane: outlined while the files are
                // hidden, filled while they show.
                context.rect(2.5, 3, 11, 10);
                context.moveTo(6.5, 3);
                context.lineTo(6.5, 13);
                context.stroke();
                if (icon.name === "sidebarOpen")
                    context.fillRect(2.5, 3, 4, 10);
                return;
            } else if (icon.name === "file") {
                context.moveTo(4, 2.5);
                context.lineTo(9, 2.5);
                context.lineTo(12, 5.5);
                context.lineTo(12, 13.5);
                context.lineTo(4, 13.5);
                context.closePath();
                context.moveTo(9, 2.5);
                context.lineTo(9, 5.5);
                context.lineTo(12, 5.5);
            } else if (icon.name === "chevron") {
                // Pointing right; rotated where it's used.
                context.moveTo(6.5, 5);
                context.lineTo(9.5, 8);
                context.lineTo(6.5, 11);
            } else {
                // A folder: Open's icon, and the files' folders.
                context.moveTo(2.5, 13);
                context.lineTo(2.5, 3.5);
                context.lineTo(6.5, 3.5);
                context.lineTo(8.5, 5.5);
                context.lineTo(13.5, 5.5);
                context.lineTo(13.5, 13);
                context.closePath();
            }
            context.stroke();
        }

        Connections {
            target: icon
            function onColorChanged() { canvas.requestPaint(); }
            function onNameChanged() { canvas.requestPaint(); }
        }
    }
}
