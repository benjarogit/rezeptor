// Rezeptor: Event „Start Application“ → Text-Glatt-Silent + einmal Text-AA setzen.
#target photoshop
var REZEPTOR_TEXT_SILENT = true;

(function () {
    function mainJsx() {
        var dir = new File($.fileName).parent;
        var main = new File(dir + "/Rezeptor-Text-Glatt.jsx");
        if (!main.exists) {
            main = new File(dir.parent + "/Rezeptor-Text-Glatt.jsx");
        }
        return main;
    }

    function silentJsx() {
        var dir = new File($.fileName).parent;
        var s = new File(dir + "/Event Scripts Only/Rezeptor-Text-Glatt-Silent.jsx");
        if (!s.exists) {
            s = new File(dir + "/Rezeptor-Text-Glatt-Silent.jsx");
        }
        return s;
    }

    function alreadyRegistered(scriptFile, eventId) {
        try {
            var n = app.notifiers.length;
            var target = scriptFile.fsName;
            var want = eventId || "Ntfy";
            for (var i = 0; i < n; i++) {
                try {
                    var ev = app.notifiers[i].event;
                    var f = app.notifiers[i].eventFile;
                    if (ev === want && f && f.fsName === target) {
                        return true;
                    }
                } catch (e1) {}
            }
        } catch (e2) {}
        return false;
    }

    try {
        app.notifiersEnabled = true;
        var silent = silentJsx();
        if (silent.exists) {
            // Start Application
            if (!alreadyRegistered(silent, "Ntfy")) {
                app.notifiers.add("Ntfy", silent);
            }
            // Neue Ebene/Objekt (inkl. Text) — Tool-Default „Ohne“ korrigieren
            if (!alreadyRegistered(silent, "Mk  ")) {
                app.notifiers.add("Mk  ", silent);
            }
        }
    } catch (eReg) {}

    try {
        var marker = new File(app.preferencesFolder + "/.rezeptor-startup-event");
        marker.open("w");
        marker.write("1");
        marker.close();
    } catch (eMark) {}

    // Kein $.evalFile(Text-Glatt) hier: setTypeToolAntiAlias auf der Startseite
    // löst unter Wine oft „Programmfehler“ aus. AA kommt über Notifier „Mk  “.
})();
