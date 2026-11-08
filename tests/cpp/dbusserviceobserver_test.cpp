// Regression test for DBusServiceObserver.
//
// ListNames is asked again every time the enabled-plugins list changes, and the
// reply repeats names that were already seen. The observer used to count each
// repeat, so after one such refresh a D-Bus activated applet (the media
// controller, for example) was never unloaded again when its service went away.

#include <QLoggingCategory>
#include <QSignalSpy>
#include <QTest>

// The behaviour under test is private; the test drives it directly instead of
// needing a session bus.
#define private public
#include "dbusserviceobserver.h"
#undef private

#include "systemtraysettings.h"
#include <KPluginMetaData>

Q_LOGGING_CATEGORY(SYSTEM_TRAY, "systemtray.test")

class DBusServiceObserverTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void stopsAfterRepeatedSnapshots()
    {
        Fixture f;
        f.observer.sessionBusNameFetchFinished({"org.test.Player.one", ":1.5"});
        f.observer.sessionBusNameFetchFinished({"org.test.Player.one", ":1.5"});
        f.observer.sessionBusNameFetchFinished({"org.test.Player.one", ":1.5"});
        QVERIFY(f.started.count() >= 1);

        f.observer.serviceUnregistered("org.test.Player.one");
        QCOMPARE(f.stopped.count(), 1);
    }

    void stopsOnlyWhenTheLastServiceLeaves()
    {
        Fixture f;
        f.observer.serviceRegistered("org.test.Player.a");
        f.observer.serviceRegistered("org.test.Player.b");

        f.observer.serviceUnregistered("org.test.Player.a");
        QCOMPARE(f.stopped.count(), 0);
        f.observer.serviceUnregistered("org.test.Player.b");
        QCOMPARE(f.stopped.count(), 1);
    }

    void ignoresServicesItNeverSaw()
    {
        Fixture f;
        f.observer.serviceUnregistered("org.test.Player.ghost");
        QCOMPARE(f.stopped.count(), 0);
    }

    void followsAPluginThatIsSwitchedOnLater()
    {
        Fixture f;
        f.settings.setEnabled("p", false);
        f.observer.serviceRegistered("org.test.Player.c");
        QCOMPARE(f.started.count(), 0);

        f.settings.setEnabled("p", true);
        f.observer.sessionBusNameFetchFinished({"org.test.Player.c"});
        QCOMPARE(f.started.count(), 1);

        f.observer.serviceUnregistered("org.test.Player.c");
        QCOMPARE(f.stopped.count(), 1);
    }

private:
    struct Fixture {
        SystemTraySettings settings;
        DBusServiceObserver observer{QPointer<SystemTraySettings>(&settings)};
        QSignalSpy started{&observer, &DBusServiceObserver::serviceStarted};
        QSignalSpy stopped{&observer, &DBusServiceObserver::serviceStopped};

        Fixture()
        {
            settings.setEnabled("p", true);
            observer.registerPlugin(KPluginMetaData("p", "org.test.Player.*"));
        }
    };
};

QTEST_GUILESS_MAIN(DBusServiceObserverTest)
#include "dbusserviceobserver_test.moc"
