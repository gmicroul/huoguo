import QtQuick 2.15
import QtQuick.Window 2.12
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.5
import QtMultimedia 5.15

ApplicationWindow {
    id: root
    width: 1080
    height: 2280
    visible: true
    color: "#101010"
    title: "红果短剧"

    property var rankTabs: [
        { id: "hot-drama", t: "热播" },
        { id: "hot-real-drama", t: "真人" },
        { id: "hot-ai-drama", t: "AI剧" },
        { id: "hot-comic-drama", t: "漫剧" }
    ]
    property int rankIdx: 0
    property var cardList: []
    property bool loading: false
    property string statusMsg: ""

    // 详情
    property string dSid: ""
    property string dTitle: ""
    property string dCover: ""
    property string dIntro: ""
    property string dTags: ""
    property string dTotal: ""
    property var episodes: []
    property int curIdx: -1

    // 播放
    property string curFile: ""
    property bool fetching: false
    property bool seekDragging: false
    property double lastSwitch: 0
    property bool headerVisible: true

    function fmt(ms) {
        if (ms === undefined || ms === null || ms < 0 || ms > 360000000)
            return "--:--";
        var sec = Math.floor(ms / 1000);
        var m = Math.floor(sec / 60);
        var s = sec % 60;
        return ((m < 10 ? "0" + m : "" + m) + ":" + (s < 10 ? "0" + s : "" + s));
    }

    function loadRank(i) {
        root.rankIdx = i
        root.loading = true
        root.statusMsg = "加载" + root.rankTabs[i].t + "榜…"
        root.cardList = backend.rankList(root.rankTabs[i].id)
        root.loading = false
        root.statusMsg = root.cardList.length === 0 ? "加载失败，点榜单重试" : ""
    }

    function doSearch() {
        if (searchField.text.trim() === "")
            return
        root.loading = true
        root.statusMsg = "搜索中…"
        root.cardList = backend.searchList(searchField.text.trim())
        root.loading = false
        root.statusMsg = root.cardList.length === 0 ? "没搜到，换个词" : ""
    }

    function openDetail(sid) {
        root.loading = true
        root.statusMsg = "取详情…"
        var d = backend.detail(sid)
        root.loading = false
        root.statusMsg = ""
        if (!d || !d.sid) {
            root.statusMsg = "详情失败，重试"
            return
        }
        root.dSid = d.sid
        root.dTitle = d.title || ""
        root.dCover = d.cover || ""
        root.dIntro = d.intro || ""
        root.dTotal = d.total || String((d.episodes || []).length)
        var tags = d.tags || []
        root.dTags = tags.join(" · ")
        root.episodes = d.episodes || []
        stack.push(detailPage)
    }

    function playAt(i) {
        if (i < 0 || i >= root.episodes.length)
            return
        // 播放页已在栈顶就复用（只换片源），避免销毁正在跑回调的页面导致闪退
        var reuse = stack.currentItem && stack.currentItem.objectName === "hgplayer"
        var now = Date.now()
        if (reuse) {
            // 防抖：连续快按只响应一次，保护 media-hub 不被频繁建连卡死
            if (now - root.lastSwitch < 800)
                return
            if (root.fetching)
                return
        }
        root.lastSwitch = now
        if (reuse && stack.currentItem.stopAndSave)
            stack.currentItem.stopAndSave()
        root.curIdx = i
        var ep = root.episodes[i]
        // 先进播放页（转圈），再取流，体感秒开
        root.curFile = ""
        root.fetching = true
        if (!reuse)
            stack.push(playerPage)
        var target = ""
        if (ep.web)
            target = backend.streamUrl(root.dSid, ep.vid) // 线上直链，直接播
        if (target === "")
            target = backend.ensureFile(root.dSid, ep.vid) // 下载/解密后播
        root.fetching = false
        if (target === "") {
            root.statusMsg = "取流失败，换一集或重试"
            if (!reuse)
                stack.pop()
            return
        }
        root.statusMsg = ""
        backend.saveLast(root.dSid, ep.vid)
        root.curFile = target
        // 非直链的下一集提前下好，点下集时秒开
        if (i + 1 < root.episodes.length && !root.episodes[i + 1].web)
            backend.prefetch(root.dSid, root.episodes[i + 1].vid)
    }

    header: ToolBar {
        visible: root.headerVisible
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8
            Button {
                text: "‹"
                font.pixelSize: 40
                flat: true
                enabled: stack.depth > 1
                onClicked: {
                    if (stack.currentItem && stack.currentItem.objectName === "hgplayer"
                            && stack.currentItem.stopAndSave)
                        stack.currentItem.stopAndSave()
                    stack.pop()
                }
            }
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "搜短剧…"
                font.pixelSize: 30
                inputMethodHints: Qt.ImhNoPredictiveText
                onAccepted: root.doSearch()
            }
            Button {
                text: "搜"
                font.pixelSize: 30
                onClicked: root.doSearch()
            }
        }
    }

    footer: Label {
        visible: (root.fetching ? backend.status : root.statusMsg) !== ""
        text: root.fetching ? backend.status : root.statusMsg
        color: "#9a9a9a"
        font.pixelSize: 24
        leftPadding: 16
        rightPadding: 16
        topPadding: 6
        bottomPadding: 6
        background: Rectangle { color: "#101010" }
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: listPage
        onCurrentItemChanged: {
            // 回到列表/详情时顶栏必现；播放页由 showUI 联动
            if (!currentItem || currentItem.objectName !== "hgplayer")
                root.headerVisible = true
        }
    }

    // ============ 榜单/搜索 ============
    Component {
        id: listPage
        Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
                    spacing: 6
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Repeater {
                        model: root.rankTabs
                        Button {
                            Layout.fillWidth: true
                            text: modelData.t
                            font.pixelSize: 30
                            highlighted: index === root.rankIdx
                            onClicked: root.loadRank(index)
                        }
                    }
                }
                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: width / 3
                    cellHeight: cellWidth * 1.75
                    model: root.cardList
                    delegate: Item {
                        width: grid.cellWidth
                        height: grid.cellHeight
                        Column {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6
                            Image {
                                width: parent.width
                                height: parent.height - 76
                                source: modelData.cover || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                            Text {
                                width: parent.width
                                height: 70
                                text: modelData.title || ""
                                color: "#e8e8e8"
                                font.pixelSize: 26
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.openDetail(modelData.sid)
                        }
                    }
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
            }
            BusyIndicator {
                anchors.centerIn: parent
                running: root.loading
                visible: root.loading
            }
        }
    }

    // ============ 详情/选集 ============
    Component {
        id: detailPage
        Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 12
                    spacing: 16
                    Image {
                        Layout.preferredWidth: 240
                        Layout.preferredHeight: 336
                        source: root.dCover
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: root.dTitle
                            color: "#ffffff"
                            font.pixelSize: 36
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            text: "共 " + root.dTotal + " 集" + (root.dTags !== "" ? " · " + root.dTags : "")
                            color: "#9a9a9a"
                            font.pixelSize: 26
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.dIntro
                            color: "#c8c8c8"
                            font.pixelSize: 26
                            wrapMode: Text.WordWrap
                            maximumLineCount: 5
                            elide: Text.ElideRight
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    text: "选集（● 已缓存）"
                    color: "#7f7f7f"
                    font.pixelSize: 26
                }
                GridView {
                    id: epGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    clip: true
                    cellWidth: width / 5
                    cellHeight: 104
                    model: root.episodes
                    delegate: Button {
                        width: epGrid.cellWidth - 8
                        height: 92
                        text: (backend.cached(modelData.vid) ? "●" : "") + modelData.index
                        font.pixelSize: 30
                        highlighted: index === root.curIdx
                        onClicked: root.playAt(index)
                    }
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
            }
            BusyIndicator {
                anchors.centerIn: parent
                running: root.loading
                visible: root.loading
            }
        }
    }

    // ============ 播放（悬浮控制条，3.5 秒自动隐藏） ============
    Component {
        id: playerPage
        Item {
            objectName: "hgplayer"
            property bool showUI: true
            onShowUIChanged: root.headerVisible = showUI || searchField.activeFocus
            function stopAndSave() {
                if (root.curIdx >= 0 && root.curIdx < root.episodes.length) {
                    video.stop()
                    backend.savePos(root.episodes[root.curIdx].vid, video.position)
                }
            }
            function pokeUI() {
                showUI = true
                hideUITimer.restart()
            }
            Rectangle { anchors.fill: parent; color: "black" }
            Video {
                id: video
                anchors.fill: parent
                autoLoad: true
                autoPlay: false
                fillMode: VideoOutput.PreserveAspectFit
                source: root.curFile === "" ? ""
                      : (root.curFile.indexOf("http") === 0 ? root.curFile : "file://" + root.curFile)
                onStatusChanged: {
                    if (status === MediaPlayer.LoadedMedia) {
                        var pos = backend.loadPos(root.episodes[root.curIdx].vid)
                        if (pos > 5000 && pos < duration - 10000)
                            video.seek(pos)
                        video.play()
                    } else if (status === MediaPlayer.EndOfMedia) {
                        backend.savePos(root.episodes[root.curIdx].vid, 0)
                        if (root.curIdx + 1 < root.episodes.length)
                            root.playAt(root.curIdx + 1)
                    }
                }
                onPlaybackStateChanged: {
                    if (playbackState === MediaPlayer.PlayingState)
                        hideUITimer.restart()
                    else
                        showUI = true
                }
                onErrorChanged: {
                    if (error !== MediaPlayer.NoError)
                        root.statusMsg = "播放出错：" + errorString
                }
            }
            // 点按呼出/隐藏控制条，左右拖快进退（垫在控制条之下）
            MouseArea {
                anchors.fill: parent
                property real pressX: 0
                property bool dragging: false
                onPressed: { pressX = mouse.x; dragging = false }
                onPositionChanged: {
                    if (!pressed || video.duration <= 0)
                        return
                    var dx = mouse.x - pressX
                    if (Math.abs(dx) > 14) {
                        dragging = true
                        root.seekDragging = true
                        seekBar.value = Math.max(0, Math.min(video.duration,
                            video.position + dx / width * video.duration))
                    }
                }
                onReleased: {
                    if (dragging) {
                        if (video.seekable)
                            video.seek(seekBar.value)
                        else
                            video.position = seekBar.value
                        root.seekDragging = false
                        pokeUI()
                    } else {
                        showUI = !showUI
                        if (showUI)
                            hideUITimer.restart()
                    }
                }
                onCanceled: root.seekDragging = false
            }
            Text {
                anchors.centerIn: parent
                visible: root.fetching
                text: backend.status
                color: "#cccccc"
                font.pixelSize: 32
            }
            Rectangle {
                id: uiBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 210
                color: "#000000"
                opacity: 0.72
                visible: showUI
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 4
                    anchors.bottomMargin: 10
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.dTitle + "  第" + (root.curIdx + 1) + "/" + root.episodes.length + "集"
                        color: "#cccccc"
                        font.pixelSize: 24
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        spacing: 10
                        Text {
                            text: fmt(root.seekDragging ? seekBar.value : video.position)
                            color: "#d8d8d8"
                            font.pixelSize: 24
                            Layout.preferredWidth: 120
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Slider {
                            id: seekBar
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            from: 0
                            to: Math.max(video.duration, 1)
                            enabled: video.duration > 0
                            onPressedChanged: {
                                if (pressed) {
                                    root.seekDragging = true
                                } else {
                                    root.seekDragging = false
                                    if (video.seekable)
                                        video.seek(value)
                                    else
                                        video.position = value
                                    pokeUI()
                                }
                            }
                        }
                        Text {
                            text: fmt(video.duration)
                            color: "#d8d8d8"
                            font.pixelSize: 24
                            Layout.preferredWidth: 120
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 80
                        spacing: 10
                        Button {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: "上集"
                            font.pixelSize: 26
                            enabled: root.curIdx > 0 && !root.fetching
                            onClicked: {
                                backend.savePos(root.episodes[root.curIdx].vid, video.position)
                                root.playAt(root.curIdx - 1)
                            }
                        }
                        Button {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: video.playbackState === MediaPlayer.PlayingState ? "暂停" : "播放"
                            font.pixelSize: 26
                            font.bold: true
                            enabled: !root.fetching && root.curFile !== ""
                            onClicked: {
                                if (video.playbackState === MediaPlayer.PlayingState) {
                                    video.pause()
                                    backend.savePos(root.episodes[root.curIdx].vid, video.position)
                                } else {
                                    video.play()
                                }
                                pokeUI()
                            }
                        }
                        Button {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: "下集"
                            font.pixelSize: 26
                            enabled: root.curIdx + 1 < root.episodes.length && !root.fetching
                            onClicked: {
                                backend.savePos(root.episodes[root.curIdx].vid, video.position)
                                root.playAt(root.curIdx + 1)
                            }
                        }
                    }
                }
            }
            Timer {
                id: hideUITimer
                interval: 3500
                repeat: false
                onTriggered: {
                    // 搜框有焦点时不藏顶栏
                    if (searchField.activeFocus) {
                        showUI = true
                        return
                    }
                    if (video.playbackState === MediaPlayer.PlayingState)
                        showUI = false
                }
            }
            Timer {
                interval: 300
                running: true
                repeat: true
                onTriggered: {
                    if (!root.seekDragging && video.duration > 0)
                        seekBar.value = video.position
                }
            }
            Timer {
                interval: 10000
                running: video.playbackState === MediaPlayer.PlayingState
                repeat: true
                onTriggered: backend.savePos(root.episodes[root.curIdx].vid, video.position)
            }
        }
    }

    Component.onCompleted: root.loadRank(0)
}
