// Stand-in for SystemTraySettings: only the part DBusServiceObserver uses.
#pragma once
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>

class SystemTraySettings : public QObject
{
    Q_OBJECT
public:
    bool isEnabledPlugin(const QString &id) const
    {
        return m_enabled.contains(id);
    }
    void setEnabled(const QString &id, bool on)
    {
        if (on) {
            m_enabled.insert(id);
        } else {
            m_enabled.remove(id);
        }
    }

Q_SIGNALS:
    void enabledPluginsChanged(const QStringList &enabled, const QStringList &disabled);

private:
    QSet<QString> m_enabled;
};
