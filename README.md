# PanePon

SwiftUIで実装したiOS向けパネル交換パズルの試作です。パネルの入れ替え、消去、落下と連鎖を扱います。盤面ロジックと画面は `PanePon/ContentView.swift` にあります。

## 起動

1. iOS 17.5以降のSDKに対応するXcodeで `PanePon.xcodeproj` を開きます。
2. Signing & Capabilitiesで自分のTeamを設定します。必要に応じてBundle Identifierを変更してください。
3. PanePonターゲットを選び、シミュレータまたは実機でRunを実行します。

外部APIキーは不要です。`PanePonTests` と `PanePonUITests` はXcodeのTestから実行できます。

## リポジトリに含めないもの

ビルド生成物、個人のXcode設定、署名証明書、実端末のログは `.gitignore` で除外します。実際の利用者データや画面記録を保存する場合は `private-data/` または `exports/` を使ってください。
