# switch2pro-macos-sample

macOS で **kext も DriverKit も使わずに** USB デバイスを動かす「ユーザー空間ドライバ」の最小サンプルです。
題材は Nintendo Switch 2 Pro Controller（USB `057E:2069`）。

- 解説記事: Qiita（公開後にリンク）
- 完成版アプリ（メニューバー常駐・キー割り当て GUI 付き）: [Switch2ProBridge-releases](https://github.com/kakignu/Switch2ProBridge-releases)

## やっていること（約200行）

```
[Switch 2 Pro] --USB--> IF#0 HID          … macOS 標準 HID ドライバが掴む
                   └--> IF#1 Vendor(0xFF) … 誰も掴んでいない → IOUSBHost で開ける
```

1. IORegistry から `IOUSBHostDevice` を列挙し、VID/PID が一致するデバイスの子 `IOUSBHostInterface #1` を探す
2. `IOUSBHostInterface` / `IOUSBHostPipe` で Bulk OUT `0x02` に初期化コマンドを送り、Bulk IN `0x82` で応答を読む
3. 初期化後、IF#0 から HID 入力レポート `0x09` が流れ始める → `IOHIDManager` で**非排他**に読み、ボタン/スティックを表示

## 動かし方

```bash
git clone https://github.com/kakignu/switch2pro-macos-sample.git
cd switch2pro-macos-sample
swift run -c release switch2-sample
```

コントローラーを USB-C で接続してから実行してください。出力例:

```
HID ゲームパッドを検出
→ 07/01                ← 07 01 00 01 00 f8 00 00
→ feature mask         ← 0c 01 00 02 00 f8 00 00
…
初期化完了。ボタンを押すと表示されます（Ctrl-C で終了）
buttons: A  L(1985,2151) R(2089,2155)
```

- 要件: macOS 13+、Xcode または Command Line Tools（Swift 5.9+）
- 特別な entitlement・署名・SIP 無効化は不要

## ファイル

| パス | 内容 |
|---|---|
| `Sources/USBBulk/` | IOUSBHost の Objective-C ラッパー（Bulk 送受信） |
| `Sources/switch2-sample/main.swift` | デバイス検出・初期化コマンド・HID 読み取り |

## ハマりどころ

- **マッチング辞書に `idVendor` 等の数値を入れるとマッチしないことがある** → クラス名だけでマッチして VID/PID はコードで比較
- **SwiftPM の Objective-C ターゲットは ARC 無効がデフォルト** → `-fobjc-arc` を指定
- インターフェースはデバイス検出よりわずかに遅れて登録される → リトライする
- システムのドライバが掴んでいるインターフェース（ここでは IF#0 の HID）は `IOUSBHostInterface` で開けない。HID は `IOHIDManager` で読む

## 参考

- プロトコル: [ndeadly/switch2_controller_research](https://github.com/ndeadly/switch2_controller_research)
- 初期化シーケンス: SDL3 [`SDL_hidapi_switch2.c`](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_switch2.c)（zlib License, Valve Corporation）

## ライセンス

MIT。Nintendo Switch は任天堂の商標です。本プロジェクトは任天堂とは無関係の非公式サンプルです。
