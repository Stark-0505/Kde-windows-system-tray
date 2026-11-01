/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QHash>
#include <QString>

// Remembers the last native status seen for each tray item so the model can
// tell when it CHANGES (an app starting to need attention, or going idle).
//
// The first time an item is seen only seeds the table and never counts as a
// change, so items loading at startup don't look like new activity.
class ItemStatusTracker
{
public:
    // Records `status` for `id`. Returns true if it differs from the last
    // recorded status for that item.
    bool update(const QString &id, int status)
    {
        auto it = m_last.find(id);
        if (it == m_last.end()) {
            m_last.insert(id, status);
            return false;
        }
        if (it.value() == status) {
            return false;
        }
        it.value() = status;
        return true;
    }

    void forget(const QString &id)
    {
        m_last.remove(id);
    }

private:
    QHash<QString, int> m_last;
};
