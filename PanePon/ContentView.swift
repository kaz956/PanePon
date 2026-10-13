import SwiftUI
import Combine
import UIKit

// ===== 共通方向 =====
enum Direction { case up, down, left, right }

// ===== モデル =====
struct Panel: Identifiable, Hashable {
    let id = UUID()
    var color: Color
}

struct Cell: Hashable {
    let r: Int
    let c: Int
}


final class GameBoard: ObservableObject {
    private static let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

    // 新規: 上部を空にする行数
    private static let initialEmptyRows: Int = 2

    @Published var rows: Int
    @Published var cols: Int
    @Published var panels: [[Panel?]]   // ← 消去に備えて Optional
    @Published var upcomingRow: [Panel?]
    /// 消去前にハイライトするセル
    @Published var highlightedCells: Set<Cell> = []
    /// 今の連鎖ステップで消えることが確定しているセル（スワイプ禁止用）
    @Published var lockedCells: Set<Cell> = []

    // 新規: 空行を含めた初期盤面生成
    private static func makeInitialPanels(rows: Int, cols: Int) -> [[Panel?]] {
        (0..<rows).map { r in
            (0..<cols).map { _ in
                r < initialEmptyRows ? nil : Panel(color: Self.palette.randomElement()!)
            }
        }
    }

    init(rows: Int = 12, cols: Int = 12) {
        self.rows = rows
        self.cols = cols
        self.panels = GameBoard.makeInitialPanels(rows: rows, cols: cols)
        self.upcomingRow = (0..<cols).map { _ in Panel(color: Self.palette.randomElement()!) as Panel? }
    }

    func panelAt(row r: Int, col c: Int) -> Panel? {
        panels[r][((c % cols) + cols) % cols]
    }

    func setPanel(_ p: Panel?, row r: Int, col c: Int) {
        panels[r][((c % cols) + cols) % cols] = p
    }

    /// 行 r の「左セルが c」の2枚を入替（ラップ対応）
    func swapAt(row r: Int, leftCol c: Int) {
        guard (0..<rows).contains(r) else { return }
        let aIdx = ((c % cols) + cols) % cols
        let bIdx = (((c + 1) % cols) + cols) % cols

        let cellA = Cell(r: r, c: aIdx)
        let cellB = Cell(r: r, c: bIdx)
        // 今回の連鎖ステップで消えることが確定しているセルは入れ替え禁止
        if lockedCells.contains(cellA) || lockedCells.contains(cellB) {
            return
        }

        let a = panels[r][aIdx]
        let b = panels[r][bIdx]

        // 両方とも空なら何もしない（完全な空同士の入れ替えは禁止）
        if a == nil && b == nil { return }

        panels[r][aIdx] = b
        panels[r][bIdx] = a
    }

    /// 下から1行せり上げ（上1行が消え、最下段に upcomingRow を追加し、新しい upcomingRow を準備）
    func riseFromBottom() {
        guard rows > 0 else { return }
        panels.removeFirst()
        panels.append(upcomingRow)
        upcomingRow = (0..<cols).map { _ in Panel(color: Self.palette.randomElement()!) as Panel? }
    }

    /// パネルでポン同様、消える → 落ちる → さらにそろえば消える…を
    /// 連鎖が起きなくなるまで繰り返す。
    /// 発生した連鎖数（1 以上）を返す。連鎖がなければ 0 を返す。
    func resolveMatchesAndFall() -> Int {
        var chainCount = 0

        while true {
            let toClear = findMatches()        // Set<Cell>
            if toClear.isEmpty { break }

            chainCount += 1

            for pos in toClear {
                setPanel(nil, row: pos.r, col: pos.c)
            }

            applyGravity()
        }

        return chainCount
    }


    /// 3個以上の直線（横はラップ対応／縦は非ラップ）を検出
    func findMatches() -> Set<Cell> {
        var clear = Set<Cell>()

        // 横（ラップあり）：1行ぶんを円環として扱い、同色が連続しているチェーンを検出
        for r in 0..<rows {
            var visited = Array(repeating: false, count: cols)
            for c in 0..<cols {
                if visited[c] { continue }
                guard let p0 = panelAt(row: r, col: c) else { continue }
                let color = p0.color

                var runCols: [Int] = [c]
                visited[c] = true

                var next = (c + 1) % cols
                while next != c {
                    guard let pn = panelAt(row: r, col: next), pn.color == color else {
                        break
                    }
                    runCols.append(next)
                    visited[next] = true
                    next = (next + 1) % cols
                }

                if runCols.count >= 3 {
                    for col in runCols {
                        clear.insert(Cell(r: r, c: col))
                    }
                }
            }
        }

        // 縦（ラップなし）
        for c in 0..<cols {
            var runColor: Color? = nil
            var run: [Cell] = []
            for r in 0..<rows {
                if let p = panelAt(row: r, col: c) {
                    if runColor == nil || runColor! == p.color {
                        runColor = p.color
                        run.append(Cell(r: r, c: c))
                    } else {
                        if run.count >= 3 { run.forEach { clear.insert($0) } }
                        runColor = p.color
                        run = [Cell(r: r, c: c)]
                    }
                } else {
                    if run.count >= 3 { run.forEach { clear.insert($0) } }
                    runColor = nil
                    run.removeAll()
                }
            }
            if run.count >= 3 { run.forEach { clear.insert($0) } }
        }

        return clear
    }


    func applyGravity() {
        for c in 0..<cols {
            var dst = rows - 1
            for r in stride(from: rows-1, through: 0, by: -1) {
                if let p = panels[r][c] {
                    if dst != r {
                        panels[dst][c] = p
                        panels[r][c] = nil
                    }
                    dst -= 1
                }
            }
            // 上は nil のまま（下からのせり上がりで埋まる）
        }
    }

    /// 重力を適用し、実際に移動したパネルの新しい位置を返す
    func applyGravityAndReturnMovedCells() -> Set<Cell> {
        var moved = Set<Cell>()
        for c in 0..<cols {
            var dst = rows - 1
            for r in stride(from: rows - 1, through: 0, by: -1) {
                if let p = panels[r][c] {
                    if dst != r {
                        panels[dst][c] = p
                        panels[r][c] = nil
                        moved.insert(Cell(r: dst, c: c))
                    }
                    dst -= 1
                }
            }
            // 上は nil のまま（下からのせり上がりで埋まる）
        }
        return moved
    }

    /// 一番上の行に1つでもパネルがあればゲームオーバー
    func hasReachedTop() -> Bool {
        guard rows > 0 else { return false }
        return panels[0].contains { $0 != nil }
    }

    /// 盤面を初期状態にリセット（ランダム配置、上部は空）
    func reset() {
        panels = GameBoard.makeInitialPanels(rows: rows, cols: cols)
        upcomingRow = (0..<cols).map { _ in Panel(color: Self.palette.randomElement()!) as Panel? }
    }
}

// ===== 状態 =====
struct Cursor { var x: Int = 2; var y: Int = 5 } // x: 6枚のうちの「左セル」(0...4)

final class GameState: ObservableObject {
    @Published var cursor = Cursor()
    /// 画面の左端フルセルが何列目か（小数で連続回転）
    @Published var viewOffsetCols: Double = 0.0
    /// 0→1 の間で1行ぶん上へ移動（常時増加）。1を超えたら board を1段上げて剰余にする
    @Published var riseOffset: CGFloat = 0

    /// プレイ中かどうか
    @Published var isPlaying: Bool = false
    /// ゲームオーバー状態
    @Published var isGameOver: Bool = false
    /// 連鎖発生時のテキスト表示
    @Published var chainText: String? = nil
    @Published var chainOpacity: Double = 0.0
    /// 現在のスコア
    @Published var score: Int = 0
    /// 経過時間（秒）
    @Published var elapsedTime: TimeInterval = 0

    private var ticker: AnyCancellable?
    private var lastTick: Date?
    /// 連鎖解決中かどうか（エフェクトを含む）
    private var isResolvingChain: Bool = false
    /// 現在進行中の連鎖数
    private var currentChainCount: Int = 0

    /// 行/秒（例：0.04 なら 約25秒で1行）—タッチ操作などからの一時的な上書き用
    var riseSpeedRowsPerSec: CGFloat = 0.04
    /// 経過時間によって少しずつ増加していくベースの上昇速度
    private var baseRiseSpeed: CGFloat = 0.04

    /// 連鎖時の「CHAIN!」テキスト演出
    private func showChainEffect(chain: Int) {
        guard chain >= 2 else { return }

        let text: String
        if chain == 2 {
            text = "2 CHAIN!"
        } else {
            text = "\(chain) CHAIN!"
        }

        chainText = text
        chainOpacity = 1.0

        withAnimation(.easeOut(duration: 0.45)) {
            self.chainOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if self.chainOpacity <= 0.001 {
                self.chainText = nil
            }
        }
    }

    func startContinuous(board: GameBoard, fps: Double = 60) {
        isGameOver = false
        isPlaying = true
        isResolvingChain = false
        currentChainCount = 0
        baseRiseSpeed = 0.04
        riseSpeedRowsPerSec = 0.04
        board.highlightedCells = []
        chainText = nil
        chainOpacity = 0.0
        score = 0
        elapsedTime = 0
        ticker?.cancel()
        lastTick = Date()
        ticker = Timer.publish(every: 1.0 / fps, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self = self else { return }
                let delta = now.timeIntervalSince(self.lastTick ?? now)
                self.lastTick = now
                let dt = CGFloat(delta)
                // 経過時間を加算（ゲームオーバーでなければ）
                if self.isPlaying && !self.isGameOver {
                    self.elapsedTime += delta
                }

                // 上昇（連鎖解決中は一時停止）
                if !self.isResolvingChain {
                    // ベースの上昇速度を時間経過に応じて線形に加速
                    // ・0.40 に達するまでは 1秒あたり 0.002 行/秒 ずつ増加
                    // ・0.40 を超えたら 1秒あたり 0.0005 行/秒 ずつ増加
                    // ・上限は 0.60 行/秒
                    let upperLimit: CGFloat = 0.6
                    var newBase = baseRiseSpeed

                    if newBase < 0.40 {
                        newBase += 0.0012 * dt
                        if newBase > 0.40 {
                            newBase = 0.40
                        }
                    } else if newBase < upperLimit {
                        newBase += 0.00025 * dt
                        if newBase > upperLimit {
                            newBase = upperLimit
                        }
                    }
                    baseRiseSpeed = min(newBase, upperLimit)

                    // 2本指ブーストなどで上書きされている速度と比較し、速い方を採用
                    let effectiveSpeed: CGFloat = max(baseRiseSpeed, self.riseSpeedRowsPerSec)

                    var off = self.riseOffset + effectiveSpeed * dt
                    var raisedLines = 0
                    while off >= 1.0 {
                        board.riseFromBottom()
                        off -= 1.0
                        raisedLines += 1
                    }
                    self.riseOffset = off
                    // せり上がりに合わせてカーソルも同じパネルを追従させる
                    if raisedLines > 0 {
                        self.cursor.y = max(self.cursor.y - raisedLines, 0)
                    }
                }

                // 消去＆落下（エフェクト付きで段階的に処理）
                // タイマーから新しく解決を始めるときは、毎回「新しい連鎖」としてカウントをリセットする
                if !self.isResolvingChain {
                    self.currentChainCount = 0
                    self.resolveMatchesStep(board: board)
                }

                // 一番上まで積み上がったらゲームオーバー
                if board.hasReachedTop() {
                    self.stopContinuous()
                    self.isGameOver = true
                }
            }
    }
    /// 今回の消去ステップで得られるスコアを計算する
    /// - Parameters:
    ///   - matches: このステップで消えるセル集合
    ///   - board: 現在の盤面（色情報取得用）
    ///   - chain: このステップの連鎖数（1,2,3,...）
    /// - Returns: 加算するスコア
    private func calculateScore(for matches: Set<Cell>, board: GameBoard, chain: Int) -> Int {
        if matches.isEmpty { return 0 }

        // 色ごとの個数をカウント
        var colorCounts: [Color: Int] = [:]
        for cell in matches {
            if let p = board.panelAt(row: cell.r, col: cell.c) {
                colorCounts[p.color, default: 0] += 1
            }
        }

        let totalCount = matches.count
        let distinctColors = colorCounts.keys.count

        // ベーススコア
        // 3個消し：1色あたり 100点
        // 4・5個以降：1個増えるごとに +50点
        // 単色：各色ごとに計算
        // 2色以上同時消し：全体を1つのグループ（合計個数）として計算
        var base = 0
        if totalCount >= 3 {
            if distinctColors <= 1 {
                // 単色消し
                for (_, count) in colorCounts {
                    if count >= 3 {
                        base += 100 + (count - 3) * 50
                    }
                }
            } else {
                // 複数色同時消し：合計個数で1グループとして扱う
                base = 100 + (totalCount - 3) * 50
            }
        }

        if base == 0 { return 0 }

        // 2色以上同時消しならボーナス倍率（例：3個+3個 → 6個消し扱いで、さらに全体に×1.2）
        var multiColorMultiplier: Double = 1.0
        if distinctColors >= 2 {
            multiColorMultiplier = 1.2
        }

        // 連鎖ボーナス：連鎖数が高いほど高得点になるよう倍率を設定
        // 1連鎖: x1.0, 2連鎖: x2.0, 3連鎖: x4.0, 4連鎖以降: x6.0
        let chainMultiplier: Double
        switch chain {
        case 1:
            chainMultiplier = 1.0
        case 2:
            chainMultiplier = 2.0
        case 3:
            chainMultiplier = 4.0
        default:
            chainMultiplier = 6.0
        }

        let total = Double(base) * multiColorMultiplier * chainMultiplier
        return Int(total.rounded())
    }

    /// 1ステップ分の「消える → 落ちる」をエフェクト付きで処理し、
    /// 連鎖が続く限り再帰的に呼び出す。
    private func resolveMatchesStep(board: GameBoard, fallenCells: Set<Cell>? = nil) {
        let matches = board.findMatches()
        if matches.isEmpty {
            // 連鎖終了
            if currentChainCount >= 2 {
                showChainEffect(chain: currentChainCount)
            }
            currentChainCount = 0
            isResolvingChain = false
            // もう消える予定のパネルはないのでロック解除
            board.lockedCells = []
            return
        }

        // ここから新たな連鎖ステップ
        // もし直前の落下で移動したパネルと今回消えるパネルに重なりがなければ、
        // 「落下でつながった連鎖」とはみなさず、新しい連鎖としてカウントをリセットする
        if let fallen = fallenCells, matches.isDisjoint(with: fallen) {
            currentChainCount = 0
        }
        isResolvingChain = true
        currentChainCount += 1

        // スコアを計算して加算（3個消しを基準に、4,5個・同時多色・連鎖で高得点に）
        let gained = calculateScore(for: matches, board: board, chain: currentChainCount)
        score += gained

        // このステップで消えることが確定しているセルをロック（スワイプ禁止用）
        board.lockedCells = matches

        // 消えるセルを「隣接（上下左右）」でつながったまとまりごとに巡回しながら順番を決める
        let allCells = Array(matches)
        let cellSet = Set(allCells)
        var remaining = cellSet
        var orderedCells: [Cell] = []

        func neighbors(of cell: Cell) -> [Cell] {
            var n: [Cell] = []
            let r = cell.r
            let c = cell.c
            // 上下（ラップなし）
            if r - 1 >= 0 {
                n.append(Cell(r: r - 1, c: c))
            }
            if r + 1 < board.rows {
                n.append(Cell(r: r + 1, c: c))
            }
            // 左右（ラップあり）
            let leftC = (c - 1 + board.cols) % board.cols
            let rightC = (c + 1) % board.cols
            n.append(Cell(r: r, c: leftC))
            n.append(Cell(r: r, c: rightC))
            return n
        }

        while let start = remaining.first {
            var queue: [Cell] = [start]
            remaining.remove(start)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                orderedCells.append(current)

                for nb in neighbors(of: current) {
                    if cellSet.contains(nb) && remaining.contains(nb) {
                        remaining.remove(nb)
                        queue.append(nb)
                    }
                }
            }
        }

        // 1セルあたりのハイライト時間と、落下前の待機時間（さらに長めに）
        let perHighlightDuration: TimeInterval = 0.22
        let pauseBeforeFall: TimeInterval = 0.5

        // 最初はハイライトなしで開始
        board.highlightedCells = []

        func highlightNext(_ index: Int) {
            // すべてのセルのハイライトが終わったら消去へ
            if index >= orderedCells.count {
                // 2) 実際にパネルを消去
                for cell in orderedCells {
                    board.setPanel(nil, row: cell.r, col: cell.c)
                }
                // このステップで消える予定だったセルのロックを解除（消えてから落下までの間はスワイプ可能にする）
                board.lockedCells = []
                // 消えるまではハイライトを維持し、消したタイミングでクリア
                board.highlightedCells = []

                // 3) 落下前に少し長めに静止
                DispatchQueue.main.asyncAfter(deadline: .now() + pauseBeforeFall) { [weak self] in
                    guard let self = self else { return }

                    // 4) 落下（実際に移動したパネルを取得）
                    let movedCells = board.applyGravityAndReturnMovedCells()

                    // 5) 次の連鎖があるかチェック（あれば続きのステップへ）
                    DispatchQueue.main.async {
                        self.resolveMatchesStep(board: board, fallenCells: movedCells)
                    }
                }
                return
            }

            // index 番目のセルをハイライトセットに追加（これまでのセルも光り続ける）
            let cell = orderedCells[index]
            var current = board.highlightedCells
            current.insert(cell)
            board.highlightedCells = current

            // 一定時間後に次のセルへ
            DispatchQueue.main.asyncAfter(deadline: .now() + perHighlightDuration) {
                highlightNext(index + 1)
            }
        }

        // 一つ目のセルから順番にハイライトを開始
        DispatchQueue.main.async {
            highlightNext(0)
        }
    }


    /// パネル入れ替え直後に消去＆落下のチェックを行う
    func checkMatchesAfterSwap(board: GameBoard) {
        // すでに連鎖解決中の場合は、そちらの処理を優先
        if isResolvingChain { return }

        let matches = board.findMatches()
        if matches.isEmpty {
            // 揃っていない場合でも、入れ替えによって生じた空きマスを埋めるために一度だけ落下させる
            // 落下前にも少し待機して、ハイライト時と同様に「タメ」を作る
            let pauseBeforeFallAfterSwipe: TimeInterval = 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseBeforeFallAfterSwipe) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    board.applyGravity()
                }
            }
        } else {
            // 揃っている場合は、スワイプ操作による「新しい連鎖」として開始する
            currentChainCount = 0
            // ハイライト→消去→落下→連鎖チェックのフローを実行
            resolveMatchesStep(board: board)
        }
    }

    func stopContinuous() {
        ticker?.cancel()
        ticker = nil
        lastTick = nil
        isPlaying = false
    }

    func rotateBy(cols: Double, duration: Double = 0.18) {
        withAnimation(.easeOut(duration: duration)) {
            viewOffsetCols += cols
        }
    }
}

// ===== メインビュー =====
struct ContentView: View {
    @StateObject private var board = GameBoard(rows: 12, cols: 12)
    @StateObject private var gs = GameState()
    @AppStorage("bestScore") private var bestScore: Int = 0
    @AppStorage("bestTime") private var bestTime: Double = 0

    private let visibleFull = 6                 // フルサイズ枚数（横）
    private var maxCursorX: Int { visibleFull - 2 } // 2枚選択なので 0...4

    // 通常時と2本指タップ時の上昇スピード（少し速く）
    private let normalRiseSpeed: CGFloat = 0.04
    private let boostedRiseSpeed: CGFloat = 0.80

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // 盤面全体（外側余白）
                CylinderStackView(
                    board: board,
                    viewOffsetCols: gs.viewOffsetCols,
                    cursor: gs.cursor,
                    riseOffset: gs.riseOffset
                )
                .padding(.horizontal, 36)
                .padding(.top, 64)

                // 非重複の4エリアタップ（上下左右）
                FourQuadrantTapOverlay { dir in moveCursor(dir) }

                // スコア＆タイム表示
                VStack(alignment: .leading, spacing: 4) {
                    Text("SCORE  \(gs.score)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("TIME   \(formatTime(gs.elapsedTime))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45))
                .cornerRadius(12)
                .padding(.top, 8)
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // ===== スタート画面（タイトル） =====
                if !gs.isPlaying && !gs.isGameOver {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 24) {
                                Text("PanePon 3D")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                Text("タップでスタート")
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.8))

                                Button(action: {
                                    startGame()
                                }) {
                                    Text("START")
                                        .font(.headline)
                                        .padding(.horizontal, 40)
                                        .padding(.vertical, 12)
                                        .background(Color.white)
                                        .foregroundColor(.black)
                                        .cornerRadius(24)
                                }
                            }
                            .padding(32)
                            .foregroundColor(.white)
                        )
                }

                // ===== ゲームオーバー画面 =====
                if gs.isGameOver {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 24) {
                                Text("GAME OVER")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)

                                VStack(spacing: 8) {
                                    Text("SCORE  \(gs.score)")
                                        .font(.headline)
                                    Text("TIME   \(formatTime(gs.elapsedTime))")
                                        .font(.subheadline)
                                    Divider()
                                        .background(Color.white.opacity(0.8))
                                    Text("BEST SCORE  \(bestScore)")
                                        .font(.headline)
                                    Text("BEST TIME   \(formatTime(bestTime))")
                                        .font(.subheadline)
                                }

                                Button(action: {
                                    startGame()
                                }) {
                                    Text("RETRY")
                                        .font(.headline)
                                        .padding(.horizontal, 40)
                                        .padding(.vertical, 12)
                                        .background(Color.white)
                                        .foregroundColor(.black)
                                        .cornerRadius(24)
                                }
                            }
                            .padding(32)
                            .foregroundColor(.white)
                        )
                }

                // 2本指タップ検出用オーバーレイ（プレイ中のみ有効にする）
                if gs.isPlaying && !gs.isGameOver {
                    MultiTouchGestureView { touchCount in
                        if touchCount >= 2 {
                            gs.riseSpeedRowsPerSec = boostedRiseSpeed
                        } else {
                            gs.riseSpeedRowsPerSec = normalRiseSpeed
                        }
                    }
                    .ignoresSafeArea()
                }

                // 連鎖テキスト演出
                if let chainText = gs.chainText {
                    Text(chainText)
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundColor(.yellow)
                        .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
                        .opacity(gs.chainOpacity)
                        .scaleEffect(1.0 + 0.15 * (1.0 - gs.chainOpacity))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(swapGesture)   // スワイプは親で拾う
            .background(Color(white: 0.95))
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            clampCursor()
            gs.riseSpeedRowsPerSec = normalRiseSpeed
        }
        .onDisappear { gs.stopContinuous() }
        .onChange(of: gs.isGameOver) { newValue in
            if newValue {
                if gs.score > bestScore {
                    bestScore = gs.score
                }
                if gs.elapsedTime > bestTime {
                    bestTime = gs.elapsedTime
                }
            }
        }
    }

    // ===== スワイプでカーソル内2枚を入替 =====
    private var swapGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onEnded { _ in
                withAnimation(.easeInOut(duration: 0.08)) {
                    let leftCol = Int(round(gs.viewOffsetCols)) + gs.cursor.x
                    board.swapAt(row: gs.cursor.y, leftCol: leftCol)
                }
                // 入れ替え直後に消去＆落下の確認を行う
                gs.checkMatchesAfterSwap(board: board)
            }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func clampCursor() {
        gs.cursor.x = min(max(gs.cursor.x, 0), maxCursorX)
        gs.cursor.y = min(max(gs.cursor.y, 0), board.rows - 1)
    }

    private func moveCursor(_ dir: Direction) {
        switch dir {
        case .up:
            gs.cursor.y = max(gs.cursor.y - 1, 0)
        case .down:
            gs.cursor.y = min(gs.cursor.y + 1, board.rows - 1)
        case .left:
            if gs.cursor.x > 0 {
                gs.cursor.x -= 1
            } else {
                // 端でさらに左→円筒を右回転（= 画面は右へ1列スクロール）
                gs.rotateBy(cols: -1)
            }
        case .right:
            if gs.cursor.x < maxCursorX {
                gs.cursor.x += 1
            } else {
                // 端でさらに右→円筒を左回転（= 画面は左へ1列スクロール）
                gs.rotateBy(cols: +1)
            }
        }
    }

    private func startGame() {
        board.reset()
        // スタート前に、すでに揃っているパネルがあれば事前に消去＆落下させておく
        _ = board.resolveMatchesAndFall()
        gs.riseOffset = 0
        clampCursor()
        gs.riseSpeedRowsPerSec = normalRiseSpeed
        gs.startContinuous(board: board, fps: 60)
    }
}

// ===== 全行スタック表示（各行を円筒切片としてレンダリング） =====
struct CylinderStackView: View {
    @ObservedObject var board: GameBoard
    let viewOffsetCols: Double   // 小数OK（連続回転）
    let cursor: Cursor
    let riseOffset: CGFloat      // 0..1 行ぶん上方向オフセット

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            // 各行の縦サイズ（画面に rows 行をすべて収める）
            let cellH = H / CGFloat(board.rows)
            // 横サイズ（8スロット：6枚＋左右半分）
            let fullSize = min(W / 8 * 0.96, cellH * 0.96)
            let halfSize = fullSize * 0.5
            let centerX = W / 2
            let radius: CGFloat = W * 0.42

            ZStack(alignment: .bottom) {
                // 盤面本体（全行＋せり上がり中の next 行）
                ZStack(alignment: .topLeading) {
                    // 既存の盤面
                    ForEach(0..<board.rows, id: \.self) { r in
                        let y = (CGFloat(r) + 0.5 - riseOffset) * cellH
                        RowSliceView(
                            board: board,
                            row: r,
                            viewOffsetCols: viewOffsetCols,
                            cursorX: (r == cursor.y ? cursor.x : nil),
                            centerX: centerX,
                            y: y,
                            radius: radius,
                            fullSize: fullSize,
                            halfSize: halfSize
                        )
                    }

                    // 次にせり上がってくる行（upcomingRow）を盤面の1段下から描画
                    UpcomingRowSliceView(
                        board: board,
                        viewOffsetCols: viewOffsetCols,
                        centerX: centerX,
                        y: (CGFloat(board.rows) + 0.5 - riseOffset) * cellH,
                        radius: radius,
                        fullSize: fullSize,
                        halfSize: halfSize
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // ===== 地面（前面に描画して、ブロックが“地面の後ろから”出てくるようにする） =====
                let groundHeight = fullSize * 0.9   // この高さから下側をすべて地面として塗る
                GroundShape(sagRatio: 0.35)
                    .fill(Color.gray)   // 透過なし（不透明）
                    .frame(height: groundHeight)
                    .overlay(
                        GroundShape(sagRatio: 0.35)
                            .stroke(Color.black.opacity(0.4),
                                    lineWidth: max(1.0, fullSize * 0.05))
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: -2)
                    .allowsHitTesting(false)

                // ===== ゲームオーバーになる高さの目印（天井ライン：赤の点線のみ） =====
                let dangerLineHeight = cellH * 0.8
                DangerLineShape(sagRatio: 0.35)
                    .stroke(
                        Color.red.opacity(0.9),
                        style: StrokeStyle(
                            lineWidth: max(1.5, fullSize * 0.06),
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [fullSize * 0.22, fullSize * 0.14]
                        )
                    )
                    .frame(height: dangerLineHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, cellH * 0.2)   // 一番上の行より少し上に配置
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// ===== 1 行ぶんの円筒切片描画（前面8スロット＋背面リング） =====
private struct RowSliceView: View {
    @ObservedObject var board: GameBoard
    let row: Int
    let viewOffsetCols: Double
    let cursorX: Int?         // この行にカーソルがいる場合のみ表示
    let centerX: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let fullSize: CGFloat
    let halfSize: CGFloat

    // スロット：左半（offset-1）・6枚（offset...offset+5）・右半（offset+6）
    private struct Slot { let colD: Double; let isHalf: Bool }
    private struct RenderItem: Identifiable {
        let id: Int
        let slot: Slot
        let angle: Double   // -90 ... +90
        let depth: Double   // cos(angle)  -1(back) .. +1(front)
    }

    var body: some View {
        // 前面：余白さらに小さく
        let hGap: CGFloat = max(0.5, fullSize * 0.02)
        let vGap: CGFloat = max(0.5, fullSize * 0.02)
        let tileH = fullSize - vGap
        let sagFront = fullSize * 0.28  // ご指定

        ZStack {
            // 背面リング：360°配置＋連続回転＋沈み
            BackRingRowSync(board: board,
                            row: row,
                            centerX: centerX,
                            yBase: y,
                            radius: radius,
                            baseSize: fullSize,
                            angleOffsetCols: viewOffsetCols)

            // 前面スロット（角度は固定8点、サンプル列だけ連続オフセット）
            let slots: [Slot] = makeSlots()
            let renderItems: [RenderItem] = slots.enumerated().map { (i, s) in
                let angle = -90.0 + (Double(i) / Double(slots.count - 1)) * 180.0
                return RenderItem(id: i, slot: s, angle: angle,
                                  depth: cos(angle * .pi / 180.0))
            }

            ForEach(renderItems.sorted(by: { $0.depth < $1.depth })) { item in
                let s = item.slot
                let rad = item.angle * .pi / 180.0
                let x = centerX + radius * CGFloat(sin(rad))
                let scaleY = 0.88 + 0.12 * abs(item.depth)
                // 連続オフセット：最も近い実列をサンプル
                let sampleCol = Int(round(s.colD))
                let cols = board.cols
                let wrappedCol = ((sampleCol % cols) + cols) % cols
                let p = board.panelAt(row: row, col: sampleCol)
                let isHighlight = board.highlightedCells.contains(Cell(r: row, c: wrappedCol))

                let tileW = (s.isHalf ? halfSize : fullSize) - hGap
                let dyFront = sagFront * CGFloat(abs(item.depth))

                let baseColor = p?.color ?? Color.clear
                let displayColor = isHighlight ? Color.white : baseColor
                let strokeOpacity: Double = isHighlight ? 1.0 : (p == nil ? 0.0 : 0.45)

                RoundedRectangle(cornerRadius: fullSize * 0.22)
                    .fill(displayColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: fullSize * 0.22)
                            .stroke(Color.white.opacity(strokeOpacity),
                                    lineWidth: max(0.8, fullSize * 0.08))
                    )
                    .frame(width: tileW, height: tileH)
                    // 円筒のつぶれ具合
                    .scaleEffect(x: 1.0, y: scaleY, anchor: .center)
                    // 消える／現れるときの縮小＋フェード
                    .opacity(p == nil ? 0.0 : 1.0)
                    .scaleEffect(p == nil ? 0.4 : 1.0)
                    .position(x: x, y: y + dyFront)
                    .shadow(color: .black.opacity(item.depth >= 0 ? 0.20 : 0.0),
                            radius: 3, x: 0, y: 2)
                    .zIndex(item.depth)
            }

            // カーソル（前面の沈みに追従）
            if let cx = cursorX {
                let leftIndex = 1 + cx   // 0=左半, 1..6=フル, 7=右半
                let rightIndex = leftIndex + 1
                let leftAngle = -90.0 + (Double(leftIndex)/7.0) * 180.0
                let rightAngle = -90.0 + (Double(rightIndex)/7.0) * 180.0
                let leftX = centerX + radius * CGFloat(sin(leftAngle * .pi / 180))
                let rightX = centerX + radius * CGFloat(sin(rightAngle * .pi / 180))
                let leftDepth = cos(leftAngle * .pi / 180)
                let rightDepth = cos(rightAngle * .pi / 180)
                let dyCursor = (fullSize * 0.28) * CGFloat((abs(leftDepth) + abs(rightDepth)) * 0.5)

                RoundedRectangle(cornerRadius: fullSize * 0.28)
                    .stroke(Color.black, lineWidth: max(2, fullSize * 0.08))
                    .frame(width: abs(rightX - leftX) + (fullSize - hGap),
                           height: (fullSize - vGap) * 1.05)
                    .position(x: (leftX + rightX)/2, y: y + dyCursor)
                    .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func makeSlots() -> [Slot] {
        var arr: [Slot] = []
        arr.append(Slot(colD: viewOffsetCols - 1.0, isHalf: true))
        for i in 0..<6 { arr.append(Slot(colD: viewOffsetCols + Double(i), isHalf: false)) }
        arr.append(Slot(colD: viewOffsetCols + 6.0, isHalf: true))
        return arr
    }
}

// ===== 地面の形状（上端を湾曲させて、ブロックの円筒に合わせたカーブに） =====
private struct GroundShape: Shape {
    /// 上端の中央がどれくらい沈むか（0.0〜1.0）。rect.height に対する比率。
    var sagRatio: CGFloat = 0.35

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let topY: CGFloat = 0
        let sag = rect.height * sagRatio

        // 上端のカーブ（左 → 中央を経由して → 右）
        path.move(to: CGPoint(x: rect.minX, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: topY),
            control: CGPoint(x: rect.midX, y: topY + sag)
        )

        // 下側を矩形で埋める
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

// ===== ゲームオーバー高さ用の点線カーブ（上端のみ） =====
private struct DangerLineShape: Shape {
    /// 上端の中央がどれくらい沈むか（0.0〜1.0）。rect.height に対する比率。
    var sagRatio: CGFloat = 0.35

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let topY: CGFloat = 0
        let sag = rect.height * sagRatio

        // 上端のカーブ（左 → 中央を経由して → 右）だけを描く
        path.move(to: CGPoint(x: rect.minX, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: topY),
            control: CGPoint(x: rect.midX, y: topY + sag)
        )

        return path
    }
}
// ===== 背景リング（全列 / 角度オフセットで連続回転 ＋ 前後とも沈み） =====
private struct BackRingRowSync: View {
    @ObservedObject var board: GameBoard
    let row: Int
    let centerX: CGFloat
    let yBase: CGFloat
    let radius: CGFloat
    let baseSize: CGFloat
    let angleOffsetCols: Double   // 連続オフセット

    var body: some View {
        let cols = board.cols
        // フロントの 6 枚（visibleFull）で 180° を使う前提で、
        // 列インデックスと angleOffsetCols の差から角度を決める
        let visibleFull = 6.0
        let anglePerCol = 180.0 / visibleFull    // 1列あたり 30°
        let centerCol = angleOffsetCols + (visibleFull - 1.0) / 2.0  // 中央付近（viewOffsetCols+2.5）

        // 背面を“さらに大きく”＆“余白もっと小さく”
        let ringScale: CGFloat = 0.78
        let ringGap: CGFloat = max(0.4, baseSize * 0.015)
        let ringW = baseSize * ringScale - ringGap
        let ringH = baseSize * ringScale - ringGap
        let sagBack = baseSize * 0.26   // ご指定

        return ZStack {
            ForEach(0..<cols, id: \.self) { c in
                // viewOffsetCols（angleOffsetCols）が変化すると、
                // フロントと同じ感覚で列が左右に回転して見える
                let angle = (Double(c) - centerCol) * anglePerCol
                let rad = angle * .pi / 180
                let x = centerX + radius * CGFloat(sin(rad))
                let depth = cos(rad) // -1(back) .. +1(front)
                let alpha = depth < 0 ? 0.22 : 0.10
                let scaleY = 0.86 + 0.10 * abs(depth)
                let p = board.panelAt(row: row, col: c)
                let dyBack = sagBack * CGFloat(abs(depth))

                RoundedRectangle(cornerRadius: baseSize * 0.2)
                    .fill((p?.color ?? Color.clear).opacity(p == nil ? alpha*0.6 : alpha))
                    .frame(width: ringW, height: ringH)
                    .scaleEffect(x: 1.0, y: scaleY, anchor: .center)
                    .position(x: x, y: yBase + dyBack)
            }
        }
    }
}

// ===== 画面全体のマルチタッチ（2本指タップ中のみ検出） =====
// UIWindow 全体に 2 本指ロングプレスの UIGestureRecognizer を仕込み、
// SwiftUI のタップ／ドラッグをブロックしないようにしている。
struct MultiTouchGestureView: UIViewRepresentable {
    var onTouchCountChanged: (Int) -> Void

    func makeUIView(context: Context) -> TouchObserverView {
        let view = TouchObserverView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false    // 自身ではヒットテストしない
        view.onTouchCountChanged = onTouchCountChanged
        return view
    }

    func updateUIView(_ uiView: TouchObserverView, context: Context) {
        uiView.onTouchCountChanged = onTouchCountChanged
    }

    // UIWindow に 2 本指ロングプレスを生やして、指の本数だけコールバックするビュー
    class TouchObserverView: UIView, UIGestureRecognizerDelegate {
        var onTouchCountChanged: ((Int) -> Void)?
        private var longPress: UILongPressGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()

            // 以前付けた recognizer があれば外す
            if let lp = longPress {
                lp.view?.removeGestureRecognizer(lp)
                longPress = nil
            }

            guard let window = self.window else { return }

            let recognizer = UILongPressGestureRecognizer(target: self,
                                                          action: #selector(handleLongPress(_:)))
            recognizer.numberOfTouchesRequired = 2          // 2本指のみ検出
            recognizer.minimumPressDuration = 0.05          // ごく短い長押し
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self

            window.addGestureRecognizer(recognizer)
            longPress = recognizer
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                onTouchCountChanged?(gesture.numberOfTouches)
            default:
                onTouchCountChanged?(0)
            }
        }

        // 他のジェスチャと同時認識を許可（スワイプやタップをブロックしない）
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

// ===== 非重複の4エリアタップ（上下：上下半分／左右：中央帯の左右半分） =====
struct FourQuadrantTapOverlay: View {
    var onTap: (Direction) -> Void
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // 左右端のみを左右移動用の当たり判定とし、
            // 画面中央の縦帯は上下判定に専念させる。
            // 上下の高さ比は 上:下 = 3:2 程度に設定。
            let edgeWidth = w * 0.18
            let centerWidth = w - edgeWidth * 2

            let topHeight = h * 3.0 / 5.0
            let bottomHeight = h * 2.0 / 5.0

            ZStack {
                // 上（中央帯のみ有効）
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: centerWidth, height: topHeight)
                    .position(x: w / 2, y: topHeight / 2)
                    .onTapGesture { onTap(.up) }

                // 下（中央帯のみ有効）
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: centerWidth, height: bottomHeight)
                    .position(x: w / 2, y: h - bottomHeight / 2)
                    .onTapGesture { onTap(.down) }

                // 左端（全高）— 左移動
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: edgeWidth, height: h)
                    .position(x: edgeWidth / 2, y: h / 2)
                    .onTapGesture { onTap(.left) }

                // 右端（全高）— 右移動
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: edgeWidth, height: h)
                    .position(x: w - edgeWidth / 2, y: h / 2)
                    .onTapGesture { onTap(.right) }
            }
        }
        .allowsHitTesting(true)
    }
}

// ===== せり上がり中の「次の1行」描画（前面スロットのみ） =====
private struct UpcomingRowSliceView: View {
    @ObservedObject var board: GameBoard
    let viewOffsetCols: Double
    let centerX: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let fullSize: CGFloat
    let halfSize: CGFloat

    private struct Slot { let colD: Double; let isHalf: Bool }
    private struct RenderItem: Identifiable {
        let id: Int
        let slot: Slot
        let angle: Double   // -90 ... +90
        let depth: Double   // cos(angle)  -1(back) .. +1(front)
    }

    var body: some View {
        let hGap: CGFloat = max(0.5, fullSize * 0.02)
        let vGap: CGFloat = max(0.5, fullSize * 0.02)
        let tileH = fullSize - vGap
        let sagFront = fullSize * 0.28  // RowSliceView と同じ沈み量

        ZStack {
            let slots: [Slot] = makeSlots()
            let renderItems: [RenderItem] = slots.enumerated().map { (i, s) in
                let angle = -90.0 + (Double(i) / Double(slots.count - 1)) * 180.0
                return RenderItem(id: i, slot: s, angle: angle,
                                  depth: cos(angle * .pi / 180.0))
            }

            ForEach(renderItems.sorted(by: { $0.depth < $1.depth })) { item in
                let s = item.slot
                let rad = item.angle * .pi / 180.0
                let x = centerX + radius * CGFloat(sin(rad))
                let scaleY = 0.88 + 0.12 * abs(item.depth)

                // upcomingRow からサンプル
                let sampleCol = Int(round(s.colD))
                let cols = board.cols
                let idx = ((sampleCol % cols) + cols) % cols
                let p = board.upcomingRow[idx]

                let tileW = (s.isHalf ? halfSize : fullSize) - hGap
                let dyFront = sagFront * CGFloat(abs(item.depth))

                RoundedRectangle(cornerRadius: fullSize * 0.22)
                    .fill((p?.color ?? Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: fullSize * 0.22)
                            .stroke(Color.white.opacity(p == nil ? 0.0 : 0.45),
                                    lineWidth: max(0.8, fullSize * 0.05))
                    )
                    .frame(width: tileW, height: tileH)
                    .scaleEffect(x: 1.0, y: scaleY, anchor: .center)
                    .opacity(p == nil ? 0.0 : 1.0)
                    .scaleEffect(p == nil ? 0.4 : 1.0)
                    .position(x: x, y: y + dyFront)
                    .shadow(color: .black.opacity(item.depth >= 0 ? 0.20 : 0.0),
                            radius: 3, x: 0, y: 2)
                    .zIndex(item.depth)
            }
        }
    }

    private func makeSlots() -> [Slot] {
        var arr: [Slot] = []
        arr.append(Slot(colD: viewOffsetCols - 1.0, isHalf: true))
        for i in 0..<6 { arr.append(Slot(colD: viewOffsetCols + Double(i), isHalf: false)) }
        arr.append(Slot(colD: viewOffsetCols + 6.0, isHalf: true))
        return arr
    }
}
