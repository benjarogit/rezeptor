// Rezeptor: Text-Anti-Alias → Scharf/Glatt (Wine ohne PS-GPU).
// Pixelige Canvas-Schrift: Zeichen-Panel Anti-Alias oft „Ohne“.
// Stiller Lauf: REZEPTOR_TEXT_SILENT=true oder Dateiname *Silent*.
#target photoshop

function s2t(s) { return app.stringIDToTypeID(s); }
function c2t(s) { return app.charIDToTypeID(s); }

function rezeptorTextSilent() {
    try {
        if (typeof REZEPTOR_TEXT_SILENT !== "undefined" && REZEPTOR_TEXT_SILENT) {
            return true;
        }
    } catch (e) {}
    try {
        var n = File($.fileName).name;
        if (n && n.indexOf("Silent") >= 0) {
            return true;
        }
    } catch (e2) {}
    return false;
}

function selectTypeTool() {
    try {
        var d = new ActionDescriptor();
        var r = new ActionReference();
        r.putClass(s2t("typeCreateOrEditTool"));
        d.putReference(c2t("null"), r);
        executeAction(c2t("slct"), d, DialogModes.NO);
        return true;
    } catch (e) {
        return false;
    }
}

// Unter Wine ohne PS-GPU: CRISP/SHARP oft klarer als SMOOTH.
function setTypeToolAntiAlias() {
    selectTypeTool();
    var modes = ["antiAliasCrisp", "antiAliasSharp", "antiAliasSmooth", "antiAliasStrong"];
    var i, desc, ref, opts, mode;
    for (i = 0; i < modes.length; i++) {
        mode = modes[i];
        try {
            desc = new ActionDescriptor();
            ref = new ActionReference();
            ref.putProperty(c2t("Prpr"), s2t("textToolOptions"));
            ref.putEnumerated(c2t("capp"), c2t("Ordn"), c2t("Trgt"));
            desc.putReference(c2t("null"), ref);
            opts = new ActionDescriptor();
            opts.putEnumerated(s2t("antiAlias"), s2t("antiAliasType"), s2t(mode));
            desc.putObject(c2t("T   "), s2t("textToolOptions"), opts);
            executeAction(c2t("setd"), desc, DialogModes.NO);
            return mode;
        } catch (e1) {}
        try {
            desc = new ActionDescriptor();
            ref = new ActionReference();
            ref.putProperty(c2t("Prpr"), s2t("currentToolOptions"));
            ref.putEnumerated(c2t("capp"), c2t("Ordn"), c2t("Trgt"));
            desc.putReference(c2t("null"), ref);
            opts = new ActionDescriptor();
            opts.putEnumerated(s2t("antiAlias"), s2t("antiAliasType"), s2t(mode));
            desc.putObject(c2t("T   "), s2t("currentToolOptions"), opts);
            executeAction(c2t("setd"), desc, DialogModes.NO);
            return mode;
        } catch (e2) {}
    }
    return "";
}

function applyLayerAntiAlias(L) {
    var methods = [];
    try { methods.push(AntiAlias.CRISP); } catch (e0) {}
    try { methods.push(AntiAlias.SHARP); } catch (e1) {}
    try { methods.push(AntiAlias.SMOOTH); } catch (e2) {}
    try { methods.push(AntiAlias.STRONG); } catch (e3) {}
    var j;
    for (j = 0; j < methods.length; j++) {
        try {
            L.textItem.antiAliasMethod = methods[j];
            return true;
        } catch (e) {}
    }
    return false;
}

function fixTextLayersInDoc(doc) {
    var n = 0;
    function walk(layers) {
        for (var i = 0; i < layers.length; i++) {
            var L = layers[i];
            if (L.typename === "LayerSet") {
                walk(L.layers);
            } else if (L.kind === LayerKind.TEXT) {
                if (applyLayerAntiAlias(L)) {
                    n++;
                }
            }
        }
    }
    walk(doc.layers);
    return n;
}

function ensureNewTextNotifier() {
    // Bei neuer Ebene erneut AA setzen (falls Tool-Default „Ohne“ bleibt).
    try {
        app.notifiersEnabled = true;
        var dir = new File($.fileName).parent;
        var silent = new File(dir + "/Event Scripts Only/Rezeptor-Text-Glatt-Silent.jsx");
        if (!silent.exists) {
            silent = new File(dir + "/Rezeptor-Text-Glatt-Silent.jsx");
        }
        if (!silent.exists) {
            return;
        }
        var target = silent.fsName;
        var i, n = app.notifiers.length;
        for (i = 0; i < n; i++) {
            try {
                if (app.notifiers[i].event === "Mk  " && app.notifiers[i].eventFile &&
                    app.notifiers[i].eventFile.fsName === target) {
                    return;
                }
            } catch (e1) {}
        }
        app.notifiers.add("Mk  ", silent);
    } catch (e2) {}
}

// Vermeide Rekursion, wenn wir selbst durch Notifier „Mk  “ laufen.
var _rezeptorFromNotifier = false;
try {
    if (typeof REZEPTOR_TEXT_FROM_NOTIFIER !== "undefined" && REZEPTOR_TEXT_FROM_NOTIFIER) {
        _rezeptorFromNotifier = true;
    }
} catch (eN) {}

var toolMode = "";
var toolOk = false;
// Auf leerer Startseite (Notifier „Start Application“) kein Type-Tool anfassen —
// unter Wine → oft Dialog „Programmfehler“.
try {
    if (!_rezeptorFromNotifier || app.documents.length > 0) {
        toolMode = setTypeToolAntiAlias();
        toolOk = toolMode !== "";
    }
} catch (eTool) {}
var fixed = 0;
if (app.documents.length > 0) {
    fixed = fixTextLayersInDoc(app.activeDocument);
}
if (!_rezeptorFromNotifier) {
    ensureNewTextNotifier();
}

if (!rezeptorTextSilent()) {
    alert(
        "Rezeptor Text-Glatt\n\n" +
        "Tool-Default: " + (toolOk ? toolMode : "manuell: Zeichen → Anti-Alias → Scharf/Stark") + "\n" +
        "Textebenen angepasst: " + fixed + "\n\n" +
        "Wichtig: Zoom 100 % prüfen (Ansicht → 100 %).\n" +
        "Unter 100 % wirkt Text unter Wine oft pixelig — Export/Druck\n" +
        "ist davon unabhängig.\n" +
        "Falls weiter „Ohne“: Zeichen-Panel → Glättung → Scharf."
    );
}
