#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function loadQmlLibrary(relativePath) {
    const file = path.join(__dirname, "..", relativePath);
    const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, "");
    const context = {};
    vm.runInNewContext(source, context, { filename: file });
    return context;
}

function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

const order = loadQmlLibrary("system-tray/contents/ui/js/trayorder.js");
assert.equal(order.slotForPosition([10, 20, 30], 21), 2);
assert.deepEqual(plain(order.zoneAfterDrop(["a", "b", "c"], "a", 3)), ["b", "c", "a"]);
assert.deepEqual(
    plain(order.newOrder(["a", "b", "c"], ["d"], "a", "panel", "popup", 1, ["x"])),
    ["b", "c", "d", "a", "x"],
);

assert.deepEqual(
    plain(order.pin(["a"], ["b"], ["c"], "b")),
    { shown: ["a", "b"], hidden: [], dismissed: ["c"] },
);
assert.deepEqual(
    plain(order.unpin(["a"], [], [], "a")),
    { shown: [], hidden: [], dismissed: ["a"] },
);
assert.deepEqual(
    plain(order.pin(["a"], ["b"], [], "x".repeat(257))),
    { shown: ["a"], hidden: ["b"], dismissed: [] },
);

const safeText = loadQmlLibrary("system-tray/contents/ui/js/safetext.js");
assert.equal(safeText.sanitizeMarkup("<b>safe</b>"), "<b>safe</b>");
assert.equal(safeText.sanitizeMarkup("2 < 3"), "2 &lt; 3");
assert.equal(safeText.sanitizeMarkup('<img src="file:///etc/passwd">hello'), "hello");
assert.equal(safeText.sanitizeMarkup("< img src=x>text"), "text");
assert.equal(safeText.sanitizeMarkup(null), "");

console.log("QML helper tests passed.");
