/*
    SPDX-FileCopyrightText: 2020 Konrad Materka <materka@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "systemtraysettings.h"
#include "debug.h"

#include <KConfigLoader>

static const QString KNOWN_ITEMS_KEY = QStringLiteral("knownItems");
static const QString EXTRA_ITEMS_KEY = QStringLiteral("extraItems");
static const QString SHOW_ALL_ITEMS_KEY = QStringLiteral("showAllItems");
static const QString SHOWN_ITEMS_KEY = QStringLiteral("shownItems");
static const QString HIDDEN_ITEMS_KEY = QStringLiteral("hiddenItems");
static const QString DISABLED_SNIS_KEY = QStringLiteral("disabledStatusNotifiers");
static const QString AUTO_SORT_KEY = QStringLiteral("autoSort");
static const QString ITEM_ORDER_KEY = QStringLiteral("itemOrder");
static const QString DISMISSED_ITEMS_KEY = QStringLiteral("dismissedItems");

SystemTraySettings::SystemTraySettings(KConfigLoader *config, QObject *parent)
    : QObject(parent)
    , config(config)
{
    m_changeTimer.setSingleShot(true);
    m_changeTimer.setInterval(0);
    connect(&m_changeTimer, &QTimer::timeout, this, &SystemTraySettings::configurationChanged);
    connect(config, &KConfigLoader::configChanged, this, [this]() {
        if (!updatingConfigValue) {
            loadConfig();
        }
    });

    loadConfig();
}

bool SystemTraySettings::isKnownPlugin(const QString &pluginId)
{
    return m_knownItems.contains(pluginId);
}

const QStringList SystemTraySettings::knownPlugins() const
{
    return m_knownItems;
}

void SystemTraySettings::addKnownPlugin(const QString &pluginId)
{
    if (pluginId.isEmpty() || m_knownItems.contains(pluginId)) {
        return;
    }
    m_knownItems << pluginId;
    writeConfigValue(KNOWN_ITEMS_KEY, m_knownItems);
}

void SystemTraySettings::removeKnownPlugin(const QString &pluginId)
{
    if (!m_knownItems.removeAll(pluginId)) {
        return;
    }
    writeConfigValue(KNOWN_ITEMS_KEY, m_knownItems);
}

bool SystemTraySettings::isEnabledPlugin(const QString &pluginId) const
{
    return m_extraItems.contains(pluginId);
}

const QStringList SystemTraySettings::enabledPlugins() const
{
    return m_extraItems;
}

void SystemTraySettings::addEnabledPlugin(const QString &pluginId)
{
    if (pluginId.isEmpty() || m_extraItems.contains(pluginId)) {
        return;
    }
    m_extraItems << pluginId;
    writeConfigValue(EXTRA_ITEMS_KEY, m_extraItems);
    Q_EMIT enabledPluginsChanged({pluginId}, {});
}

void SystemTraySettings::removeEnabledPlugin(const QString &pluginId)
{
    if (!m_extraItems.removeAll(pluginId)) {
        return;
    }
    writeConfigValue(EXTRA_ITEMS_KEY, m_extraItems);
    Q_EMIT enabledPluginsChanged({}, {pluginId});
}

bool SystemTraySettings::isDisabledStatusNotifier(const QString &pluginId)
{
    return m_disabledStatusNotifiers.contains(pluginId);
}

bool SystemTraySettings::isShowAllItems() const
{
    return config->property(SHOW_ALL_ITEMS_KEY).toBool();
}

const QStringList SystemTraySettings::shownItems() const
{
    return config->property(SHOWN_ITEMS_KEY).toStringList();
}

const QStringList SystemTraySettings::hiddenItems() const
{
    return config->property(HIDDEN_ITEMS_KEY).toStringList();
}

bool SystemTraySettings::isAutoSort() const
{
    return config->property(AUTO_SORT_KEY).toBool();
}

const QStringList SystemTraySettings::itemOrder() const
{
    return config->property(ITEM_ORDER_KEY).toStringList();
}

const QStringList SystemTraySettings::dismissedItems() const
{
    return config->property(DISMISSED_ITEMS_KEY).toStringList();
}

void SystemTraySettings::setItemDismissed(const QString &itemId, bool dismissed)
{
    QStringList list = dismissedItems();
    if (dismissed == list.contains(itemId)) {
        return; // nothing to change: don't write or refresh anything
    }
    if (dismissed) {
        list << itemId;
    } else {
        list.removeAll(itemId);
    }
    writeConfigValue(DISMISSED_ITEMS_KEY, list);
}

void SystemTraySettings::scheduleConfigurationChanged()
{
    m_changeTimer.start();
}

void SystemTraySettings::cleanupPlugin(const QString &pluginId)
{
    removeKnownPlugin(pluginId);
    removeEnabledPlugin(pluginId);

    QStringList shown = shownItems();
    shown.removeAll(pluginId);
    writeConfigValue(SHOWN_ITEMS_KEY, shown);

    QStringList hidden = hiddenItems();
    hidden.removeAll(pluginId);
    writeConfigValue(HIDDEN_ITEMS_KEY, hidden);

    setItemDismissed(pluginId, false);
}

void SystemTraySettings::loadConfig()
{
    if (!config) {
        return;
    }
    config->load();

    m_knownItems = config->property(KNOWN_ITEMS_KEY).toStringList();

    QStringList extraItems = config->property(EXTRA_ITEMS_KEY).toStringList();
    if (extraItems != m_extraItems) {
        QStringList extraItemsOld = m_extraItems;
        m_extraItems = extraItems;
        notifyAboutChangedEnabledPlugins(extraItemsOld, m_extraItems);
    }
    m_disabledStatusNotifiers = config->property(DISABLED_SNIS_KEY).toStringList();

    scheduleConfigurationChanged();
}

void SystemTraySettings::writeConfigValue(const QString &key, const QVariant &value)
{
    if (!config) {
        return;
    }

    KConfigSkeletonItem *item = config->findItemByName(key);
    if (item) {
        updatingConfigValue = true;
        item->setWriteFlags(KConfigBase::Notify);
        item->setProperty(value);
        config->save();
        config->read();
        updatingConfigValue = false;
    }

    scheduleConfigurationChanged();
}

void SystemTraySettings::notifyAboutChangedEnabledPlugins(const QStringList &enabledPluginsOld, const QStringList &enabledPluginsNew)
{
    QStringList newlyEnabled;
    QStringList newlyDisabled;

    for (const QString &pluginId : enabledPluginsOld) {
        if (!enabledPluginsNew.contains(pluginId)) {
            newlyDisabled << pluginId;
        }
    }

    for (const QString &pluginId : enabledPluginsNew) {
        if (!enabledPluginsOld.contains(pluginId)) {
            newlyEnabled << pluginId;
        }
    }

    Q_EMIT enabledPluginsChanged(newlyEnabled, newlyDisabled);
}

#include "moc_systemtraysettings.cpp"
