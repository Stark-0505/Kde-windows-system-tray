.pragma library

// Text shown in tray tooltips comes from other programs (a status-notifier
// icon's title and description), so it must never be allowed to pull in
// content: an <img src="..."> would make plasmashell load a local file or
// fetch a URL, and links/styles/tables have no business in a tooltip.
//
// Approach (so it cannot be out-flanked by odd spellings of a tag, such as
// "< img>" or whitespace characters Qt's parser accepts but regexes don't):
//   1. keep plain formatting tags written with NO attributes: <b> <i> <u> <s>
//      <br> <p> (and their closing forms)
//   2. remove things that look like tags, so a tooltip reads cleanly
//   3. turn EVERY remaining "<" into the literal text "&lt;"
// Step 3 is what makes it safe: a "<" that is only text cannot begin a tag, no
// matter how the surrounding text was arranged, so step 2 only has to be good
// enough for readability, not perfect.
function sanitizeMarkup(text) {
    if (text === undefined || text === null) {
        return "";
    }
    // our own markers must not be forgeable from outside
    var s = String(text).replace(/[\u0001\u0002]/g, "");
    if (s.indexOf("<") === -1) {
        return s;
    }

    // 1. protect the allowed tags (canonical spelling only)
    s = s.replace(/<(\/?(?:b|i|u|s|br|p))( ?\/?)>/gi, "\u0001$1$2\u0002");

    // 2. drop tag-like runs: "<", optional whitespace, then a letter, "/", "!" or "?"
    //    (a single linear scan; a regex here would rescan the text for every "<")
    var out = [];
    var n = s.length;
    var i = 0;
    var lastGt = s.lastIndexOf(">");
    while (i < n) {
        var lt = s.indexOf("<", i);
        if (lt === -1 || lt > lastGt) {
            out.push(s.slice(i));
            break;
        }
        out.push(s.slice(i, lt));
        var k = lt + 1;
        while (k < n && /[\s\u0085]/.test(s.charAt(k))) {
            ++k;
        }
        if (k < n && /[A-Za-z\/!?]/.test(s.charAt(k))) {
            i = s.indexOf(">", lt + 1) + 1; // drop the whole tag (a ">" exists: lt < lastGt)
        } else {
            out.push("<");
            i = lt + 1;
        }
    }
    s = out.join("");

    // 3. neutralise every "<" that is left: it is now plain text
    s = s.replace(/</g, "&lt;");

    return s.replace(/\u0001/g, "<").replace(/\u0002/g, ">");
}
