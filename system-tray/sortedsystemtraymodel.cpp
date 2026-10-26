/*
    SPDX-FileCopyrightText: 2019 Konrad Materka <materka@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "sortedsystemtraymodel.h"
#include "debug.h"
#include "systemtraymodel.h"
#include "systemtraysettings.h"
#include <QList>

static const QList<QString> s_categoryOrder = {
    QStringLiteral("UnknownCategory"),
    QStringLiteral("ApplicationStatus"),
    QStringLiteral("Communications"),
    QStringLiteral("SystemServices"),
    QStringLiteral("Hardware"),
};

SortedSystemTrayModel::SortedSystemTrayModel(SortingType sorting, QObject *parent)
    : QSortFilterProxyModel(parent), m_sorting(sorting) { setSortLocaleAware(true); sort(0); }

void SortedSystemTrayModel::setSettings(SystemTraySettings *settings) {
    if (m_sorting != SortingType::SystemTray || m_settings == settings) return;
    m_settings = settings;
    if (m_settings) connect(m_settings, &SystemTraySettings::configurationChanged, this, &SortedSystemTrayModel::onSettingsChanged);
    onSettingsChanged();
}

void SortedSystemTrayModel::onSettingsChanged() {
    const bool manual = m_settings && !m_settings->isAutoSort();
    const QStringList order = m_settings ? m_settings->itemOrder() : QStringList();
    if (manual == m_manualOrder && order == m_itemOrder) return;
    m_manualOrder = manual;
    m_itemOrder = order;
    invalidate(); // re-sort with the new rule
}

bool SortedSystemTrayModel::lessThan(const QModelIndex &left, const QModelIndex &right) const {
    switch (m_sorting) {
    case SortingType::ConfigurationPage: return lessThanConfigurationPage(left, right);
    case SortingType::SystemTray: return lessThanSystemTray(left, right);
    }
    return QSortFilterProxyModel::lessThan(left, right);
}

bool SortedSystemTrayModel::lessThanConfigurationPage(const QModelIndex &left, const QModelIndex &right) const {
    int cmp = compareCategoriesAlphabetically(left, right);
    return cmp == 0 ? QSortFilterProxyModel::lessThan(left, right) : cmp < 0;
}

bool SortedSystemTrayModel::lessThanSystemTray(const QModelIndex &left, const QModelIndex &right) const {
    QVariant lid = left.data(static_cast<int>(BaseModel::BaseRole::ItemId));
    QVariant rid = right.data(static_cast<int>(BaseModel::BaseRole::ItemId));
    if (m_manualOrder) {
        // User-defined order: ids listed in itemOrder come first, in that order.
        // Unlisted ids (new icons) come after them, in the automatic order below,
        // which keeps this a valid strict weak ordering.
        const int lr = m_itemOrder.indexOf(lid.toString());
        const int rr = m_itemOrder.indexOf(rid.toString());
        if (lr != rr) {
            if (lr == -1) return false;
            if (rr == -1) return true;
            return lr < rr;
        }
    }
    if (rid.toString() == QLatin1String("org.kde.plasma.notifications")) return false;
    if (lid.toString() == QLatin1String("org.kde.plasma.notifications")) return true;
    int cmp = compareCategoriesOrderly(left, right);
    return cmp == 0 ? QSortFilterProxyModel::lessThan(left, right) : cmp < 0;
}

int SortedSystemTrayModel::compareCategoriesAlphabetically(const QModelIndex &left, const QModelIndex &right) const {
    QString lcat = left.data(static_cast<int>(BaseModel::BaseRole::Category)).toString();
    if (lcat.isEmpty()) lcat = QStringLiteral("UnknownCategory");
    QString rcat = right.data(static_cast<int>(BaseModel::BaseRole::Category)).toString();
    if (rcat.isEmpty()) rcat = QStringLiteral("UnknownCategory");
    return QString::localeAwareCompare(lcat, rcat);
}

int SortedSystemTrayModel::compareCategoriesOrderly(const QModelIndex &left, const QModelIndex &right) const {
    QString lcat = left.data(static_cast<int>(BaseModel::BaseRole::Category)).toString();
    if (lcat.isEmpty()) lcat = QStringLiteral("UnknownCategory");
    QString rcat = right.data(static_cast<int>(BaseModel::BaseRole::Category)).toString();
    if (rcat.isEmpty()) rcat = QStringLiteral("UnknownCategory");
    int li = s_categoryOrder.indexOf(lcat); if (li == -1) li = s_categoryOrder.indexOf(QStringLiteral("UnknownCategory"));
    int ri = s_categoryOrder.indexOf(rcat); if (ri == -1) ri = s_categoryOrder.indexOf(QStringLiteral("UnknownCategory"));
    return li - ri;
}

#include "moc_sortedsystemtraymodel.cpp"
