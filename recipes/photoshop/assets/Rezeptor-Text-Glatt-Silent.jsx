// Stiller Autostart-Wrapper (Event Scripts / Start ohne Dialog).
// Funktioniert aus Presets/Scripts und aus Event Scripts Only/ (../).
#target photoshop
var REZEPTOR_TEXT_SILENT = true;
var REZEPTOR_TEXT_FROM_NOTIFIER = true;
(function () {
    var dir = new File($.fileName).parent;
    var main = new File(dir + "/Rezeptor-Text-Glatt.jsx");
    if (!main.exists) {
        main = new File(dir.parent + "/Rezeptor-Text-Glatt.jsx");
    }
    if (!main.exists) {
        throw new Error("Rezeptor-Text-Glatt.jsx nicht gefunden neben " + dir.fsName);
    }
    $.evalFile(main);
})();
