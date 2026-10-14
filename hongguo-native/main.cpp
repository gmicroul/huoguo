/*
 * hongguo-native —— 红果短剧本机原生壳（Qt Quick + mirclient）
 *
 * 数据链（全部已在本机验证）：
 *   榜单/搜索/详情/全集 vid_list：官网 H5，纯 HTTPS GET，无签名。
 *   非可看集高清流：node helper（vendored X-Gorgon 全套签名）+ 下载 + AES-CTR 解密，
 *   落盘到 ~/.cache/hongguo-native/<vid>.mp4，再走 QtMultimedia/media-hub 播放（和 mpv-ut 同链路）。
 */
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QEventLoop>
#include <QElapsedTimer>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcess>
#include <QCoreApplication>
#include <QDateTime>
#include <QSettings>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <QDebug>
#include <unistd.h>

class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString cacheDir READ cacheDir CONSTANT)
    Q_PROPERTY(QString nodeDir READ nodeDir CONSTANT)

public:
    explicit Backend(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
        QDir().mkpath(m_cache);
        m_nodeDir = QCoreApplication::applicationDirPath() + QStringLiteral("/node");
    }

    QString status() const { return m_status; }
    QString cacheDir() const { return m_cache; }
    QString nodeDir() const { return m_nodeDir; }

    // ---- 榜单 / 搜索：node hgweb.js（QtNetwork 会被服务端降级，不用） ----
    Q_INVOKABLE QVariantList rankList(const QString &rankId)
    {
        QVariantList out;
        bool ok = false;
        const QString s = runNode({m_nodeDir + QStringLiteral("/hgweb.js"),
                                   QStringLiteral("rank"), rankId}, 30000, &ok);
        if (!ok)
            return out;
        const QJsonArray arr = QJsonDocument::fromJson(s.toUtf8()).array();
        out = arr.toVariantList();
        qInfo() << "hongguo: 榜单" << rankId << "解析到" << out.size() << "部";
        return out;
    }

    Q_INVOKABLE QVariantList searchList(const QString &keyword)
    {
        QVariantList out;
        if (keyword.trimmed().isEmpty())
            return out;
        bool ok = false;
        const QString s = runNode({m_nodeDir + QStringLiteral("/hgweb.js"),
                                   QStringLiteral("search"), keyword.trimmed()}, 30000, &ok);
        if (!ok)
            return out;
        out = QJsonDocument::fromJson(s.toUtf8()).array().toVariantList();
        qInfo() << "hongguo: 搜索" << keyword << "到" << out.size() << "部";
        return out;
    }

    // ---- 详情（含全集 vid_list） ----
    Q_INVOKABLE QVariantMap detail(const QString &sid)
    {
        QVariantMap d;
        bool ok = false;
        const QString s = runNode({m_nodeDir + QStringLiteral("/hgweb.js"),
                                   QStringLiteral("detail"), sid}, 40000, &ok);
        if (ok)
            d = QJsonDocument::fromJson(s.toUtf8()).object().toVariantMap();
        if (d.isEmpty())
            d.insert(QStringLiteral("sid"), sid);
        qInfo() << "hongguo: 详情" << sid << d.value(QStringLiteral("title")).toString()
                << "共" << d.value(QStringLiteral("episodes")).toList().size() << "集";
        return d;
    }

    // ---- 网页直链（秒播用，不下载），无则返回 "" ----
    Q_INVOKABLE QString streamUrl(const QString &sid, const QString &vid)
    {
        bool ok = false;
        const QString s = runNode({m_nodeDir + QStringLiteral("/hgweb.js"),
                                   QStringLiteral("weburl"), sid, vid}, 25000, &ok);
        if (!ok)
            return QString();
        return QJsonDocument::fromJson(s.toUtf8()).object().value(QStringLiteral("url")).toString();
    }

    // ---- 后台预取下一集（脱离进程，下完即缓存，界面不等） ----
    Q_INVOKABLE void prefetch(const QString &sid, const QString &vid)
    {
        const QString out = m_cache + QLatin1Char('/') + vid + QStringLiteral(".mp4");
        QFileInfo fi(out);
        if (fi.exists() && fi.size() > 1024 * 1024)
            return;
        // 已有 .part 说明正在下（或上次异常中断不久），不重复开进程
        QFileInfo part(out + QStringLiteral(".part"));
        if (part.exists() && part.lastModified().secsTo(QDateTime::currentDateTime()) < 600)
            return;
        QProcess::startDetached(QStringLiteral("node"),
                                {m_nodeDir + QStringLiteral("/fullfetch.js"), sid, vid, m_cache});
        qInfo() << "hongguo: 后台预取" << vid;
    }

    // ---- 取可播本地文件（缓存命中 / 网页直链下载 / App 签名+解密），失败返回 "" ----
    Q_INVOKABLE QString ensureFile(const QString &sid, const QString &vid)
    {
        const QString out = m_cache + QLatin1Char('/') + vid + QStringLiteral(".mp4");
        QFileInfo fi(out);
        if (fi.exists() && fi.size() > 1024 * 1024) {
            setStatus(QStringLiteral("本地缓存"));
            return out;
        }
        setStatus(QStringLiteral("正在取流…"));
        QProcess p;
        p.setProgram(QStringLiteral("node"));
        p.setArguments({m_nodeDir + QStringLiteral("/fullfetch.js"), sid, vid, m_cache});
        p.setProcessChannelMode(QProcess::MergedChannels);
        p.start();
        if (!p.waitForStarted(10000)) {
            setStatus(QStringLiteral("node 启动失败"));
            return QString();
        }
        QByteArray acc;   // 涓涓细流：ST: 进度行只更新状态，{json} 结果行留到最后解析
        QElapsedTimer t;
        t.start();
        while (!p.waitForFinished(300)) {
            QCoreApplication::processEvents(QEventLoop::ExcludeUserInputEvents, 50);
            const QByteArray chunk = p.readAll();
            acc += chunk;
            for (const QString &ln : QString::fromUtf8(chunk).split(QLatin1Char('\n'))) {
                if (ln.startsWith(QStringLiteral("ST:")))
                    setStatus(ln.mid(3));
            }
            if (t.elapsed() > 300000) {
                p.kill();
                qWarning() << "hongguo: 取流超时" << sid << vid;
                setStatus(QStringLiteral("取流超时"));
                return QString();
            }
        }
        acc += p.readAll();
        // 最后一行 {…} 即结果（注意：不能提前丢弃，之前 bug 在此）
        QString lastJson;
        const QList<QByteArray> lines = acc.split('\n');
        for (const QByteArray &ln : lines) {
            const QString s = QString::fromUtf8(ln).trimmed();
            if (s.startsWith(QLatin1Char('{')))
                lastJson = s;
        }
        const QJsonObject o = QJsonDocument::fromJson(lastJson.toUtf8()).object();
        const QString f = o.value(QStringLiteral("file")).toString();
        if (!f.isEmpty() && QFileInfo(f).size() > 1024 * 1024) {
            setStatus(o.value(QStringLiteral("via")).toString() == QStringLiteral("cache")
                          ? QStringLiteral("本地缓存")
                          : QStringLiteral("取流成功"));
            return f;
        }
        const QString err = o.value(QStringLiteral("error")).toString();
        qWarning() << "hongguo: 取流失败" << sid << vid << err.left(120);
        setStatus(err.isEmpty() ? QStringLiteral("取流失败") : err.left(60));
        return QString();
    }

    Q_INVOKABLE bool cached(const QString &vid) const
    {
        QFileInfo fi(m_cache + QLatin1Char('/') + vid + QStringLiteral(".mp4"));
        return fi.exists() && fi.size() > 1024 * 1024;
    }

    Q_INVOKABLE void savePos(const QString &vid, qint64 ms)
    {
        QSettings().setValue(QStringLiteral("pos/") + vid, ms);
    }

    Q_INVOKABLE qint64 loadPos(const QString &vid)
    {
        return QSettings().value(QStringLiteral("pos/") + vid, 0).toLongLong();
    }

    Q_INVOKABLE void saveLast(const QString &sid, const QString &vid)
    {
        QSettings s;
        s.setValue(QStringLiteral("last/sid"), sid);
        s.setValue(QStringLiteral("last/vid"), vid);
    }

    Q_INVOKABLE QVariantMap loadLast()
    {
        QSettings s;
        QVariantMap m;
        m.insert(QStringLiteral("sid"), s.value(QStringLiteral("last/sid")).toString());
        m.insert(QStringLiteral("vid"), s.value(QStringLiteral("last/vid")).toString());
        return m;
    }

signals:
    void statusChanged();

private:
    // 同步跑 node 脚本并回 stdout（ pumping 事件让界面状态能刷新）
    QString runNode(const QStringList &args, int timeoutMs, bool *ok = nullptr)
    {
        QProcess p;
        p.setProgram(QStringLiteral("node"));
        p.setArguments(args);
        p.start();
        if (!p.waitForStarted(10000)) {
            if (ok)
                *ok = false;
            return QString();
        }
        QByteArray out;
        QElapsedTimer t;
        t.start();
        while (!p.waitForFinished(300)) {
            QCoreApplication::processEvents(QEventLoop::ExcludeUserInputEvents, 50);
            out += p.readAllStandardOutput();
            if (t.elapsed() > timeoutMs) {
                p.kill();
                if (ok)
                    *ok = false;
                return QString();
            }
        }
        out += p.readAllStandardOutput();
        if (ok)
            *ok = (p.exitCode() == 0);
        return QString::fromUtf8(out).trimmed();
    }

    void setStatus(const QString &s)
    {
        if (m_status == s)
            return;
        m_status = s;
        emit statusChanged();
    }

    QString m_status;
    QString m_cache;
    QString m_nodeDir;
};

int main(int argc, char *argv[])
{
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", QByteArray("ubuntumirclient"));
    if (qEnvironmentVariableIsEmpty("XDG_RUNTIME_DIR")) {
        QByteArray uid = qgetenv("UID");
        if (uid.isEmpty())
            uid = QByteArray::number(getuid());
        qputenv("XDG_RUNTIME_DIR", QByteArray("/run/user/") + uid);
    }
    if (qEnvironmentVariableIsEmpty("XDG_SESSION_TYPE"))
        qputenv("XDG_SESSION_TYPE", QByteArray("mir"));

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("hongguo-native"));
    app.setOrganizationName(QStringLiteral("hongguo"));
    app.setApplicationVersion(QStringLiteral("0.1"));

    Backend backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qWarning() << "hongguo-native: QML 加载失败";
        return 1;
    }
    return app.exec();
}
#include "main.moc"
