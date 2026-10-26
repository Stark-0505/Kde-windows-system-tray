/*
    SPDX-FileCopyrightText: 2019 Konrad Materka <materka@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once
#include <QPointer>
#include <QSortFilterProxyModel>
#include <QStringList>

class SystemTraySettings;

class SortedSystemTrayModel : public QSortFilterProxyModel {
    Q_OBJECT
public:
    enum class SortingType { ConfigurationPage, SystemTray };
    explicit SortedSystemTrayModel(SortingType sorting, QObject *parent = nullptr);

    // Lets the SystemTray sorting follow the user's manual icon order
    // (itemOrder / autoSort). Ignored for the ConfigurationPage sorting.
    void setSettings(SystemTraySettings *settings);
protected:
    bool lessThan(const QModelIndex &source_left, const QModelIndex &source_right) const override;
private Q_SLOTS:
    void onSettingsChanged();

private:
    bool lessThanConfigurationPage(const QModelIndex &left, const QModelIndex &right) const;
    bool lessThanSystemTray(const QModelIndex &left, const QModelIndex &right) const;
    int compareCategoriesAlphabetically(const QModelIndex &left, const QModelIndex &right) const;
    int compareCategoriesOrderly(const QModelIndex &left, const QModelIndex &right) const;
    SortingType m_sorting;
    QPointer<SystemTraySettings> m_settings;
    bool m_manualOrder = false;
    QStringList m_itemOrder;
};
