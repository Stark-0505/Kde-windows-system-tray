.pragma library

// Pure helpers for reordering / pinning / unpinning tray icons.
//
// Deliberately free of any QML/Plasma types so the logic can be unit tested
// on its own. "Zone" = one of the two places an icon can live:
//   "panel" - pinned, always visible in the panel
//   "popup" - hidden, shown in the hidden-icons popup
//
// The stored order (config key `itemOrder`) is one flat list of item ids.
// Panel icons and popup icons are different sets, so one flat list is enough:
// each zone just shows its own members in the order they appear in the list.

function indexOf(list, id) {
    for (var i = 0; i < list.length; ++i) {
        if (list[i] === id) {
            return i;
        }
    }
    return -1;
}

function without(list, id) {
    var out = [];
    for (var i = 0; i < list.length; ++i) {
        if (list[i] !== id) {
            out.push(list[i]);
        }
    }
    return out;
}

// Appends id unless already present.
function withId(list, id) {
    return indexOf(list, id) === -1 ? list.concat([id]) : list.slice();
}

function sameList(a, b) {
    if (a.length !== b.length) {
        return false;
    }
    for (var i = 0; i < a.length; ++i) {
        if (a[i] !== b[i]) {
            return false;
        }
    }
    return true;
}

// Which slot (0..centers.length) a pointer is closest to.
//
// `centers` are the icon centres along the flow axis, in MODEL order, already
// flipped by the caller so that they increase with the model index (i.e. for
// a mirrored or bottom-to-top layout the caller negates both centres and pos).
// A slot s means "insert before the icon currently at index s"; s ==
// centers.length means "after the last icon".
function slotForPosition(centers, pos) {
    var s = 0;
    while (s < centers.length && centers[s] < pos) {
        ++s;
    }
    return s;
}

// Where `id` ends up when dropped at `slot` of a zone currently showing
// `zoneIds` (model order, may or may not already contain id).
// Returns the id list of that zone after the move.
function zoneAfterDrop(zoneIds, id, slot) {
    var current = indexOf(zoneIds, id);
    var others = without(zoneIds, id);
    var s = slot;
    // The dragged icon is removed from the list, so slots after it shift down.
    if (current !== -1 && current < slot) {
        s -= 1;
    }
    if (s < 0) {
        s = 0;
    }
    if (s > others.length) {
        s = others.length;
    }
    return others.slice(0, s).concat([id]).concat(others.slice(s));
}

// The new flat `itemOrder` after a drop.
//   panelIds / popupIds: ids currently in each zone, in display order
//   fromZone / toZone:   "panel" | "popup"
//   slot:                drop slot within toZone (see slotForPosition); pass
//                        -1 to append at the end of toZone
//   oldOrder:            the stored itemOrder (ids not shown in either zone,
//                        e.g. currently-invisible apps, keep their relative
//                        order after the zones)
function newOrder(panelIds, popupIds, id, fromZone, toZone, slot, oldOrder) {
    var panel = fromZone === "panel" ? without(panelIds, id) : panelIds.slice();
    var popup = fromZone === "popup" ? without(popupIds, id) : popupIds.slice();
    // Same-zone drops must keep the item's own position as a candidate for the
    // slot adjustment in zoneAfterDrop, so start from the unmodified list.
    var target = toZone === "panel" ? (fromZone === toZone ? panelIds : panel)
                                    : (fromZone === toZone ? popupIds : popup);
    var placed;
    if (slot < 0) {
        placed = without(target, id).concat([id]);
    } else {
        placed = zoneAfterDrop(target, id, slot);
    }
    if (toZone === "panel") {
        panel = placed;
    } else {
        popup = placed;
    }
    var all = panel.concat(popup);
    var rest = [];
    for (var i = 0; i < oldOrder.length; ++i) {
        if (indexOf(all, oldOrder[i]) === -1) {
            rest.push(oldOrder[i]);
        }
    }
    return all.concat(rest);
}

// Pin: always show in the panel.
function pin(shown, hidden, id) {
    return {
        shown: withId(shown, id),
        hidden: without(hidden, id)
    };
}

// Unpin: keep in the popup.
function unpin(shown, hidden, id) {
    return {
        shown: without(shown, id),
        hidden: withId(hidden, id)
    };
}
