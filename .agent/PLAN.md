# プロジェクト計画: MarkdownUI表示の修正
**Status**: Draft

## 1. 目的と背景 (Goal & Context)
ChatViewでのMarkdownUI表示に以下の問題があるため修正する。

**問題点**:
1. 文字の後ろの背景色がウィンドウの背景色と異なる（不自然な背景色が表示される）
2. 文字サイズが大きすぎる

**成功の定義**:
- Markdown表示部分の背景色がウィンドウ背景色と統一される
- 文字サイズが適切な大きさになる

## 2. 要件定義 (Requirements)
- **機能要件**:
  - MarkdownUIの背景色を透明またはウィンドウ背景色に設定
  - MarkdownUIのフォントサイズを調整
- **非機能要件**:
  - 既存のMarkdownレンダリング機能は維持
  - ダーク/ライトモード両方で正常に表示

## 3. 基本設計 (Architecture & Design)

### 技術スタック
- SwiftUI
- MarkdownUIライブラリ

### 修正対象
- `nemo/Views/ChatView.swift` の `MessageBubbleView`

### 修正内容
```swift
// 現在のコード
Markdown(message.content)
    .markdownTheme(.gitHub)
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color(nsColor: .windowBackgroundColor))
```

**修正案**:
1. 背景色問題: Markdownコンポーネント自体の背景を透明にし、親Viewの背景色に統一
2. フォントサイズ: カスタムテーマを作成してフォントサイズを縮小

## 4. 実装ステップ (Implementation Steps)

- [x] **Step 1: 背景色の修正**
  - MarkdownViewの背景を透明に設定
  - 親Viewの背景設定を調整

- [x] **Step 2: フォントサイズとテーマの修正**
  - `.gitHub` テーマをベースに `.text` モディファイアを追加
  - `FontSize(13)` を適用（macOS標準サイズ）
  - `ForegroundColor(.primary)` を適用（ダークモード対応）

- [x] **Step 3: ビルド確認**
  - Xcodeでビルドしてエラーがないことを確認
  - プレビューで表示を確認

## 5. 決定事項・履歴 (Decision Log)
- [x] テーマは.gitHubをベースにカスタマイズ
- [x] 背景色は親Viewで制御
- [x] フォントサイズは13pt（macOS標準サイズ）

## 6. 未決事項 (Open Questions)
- [x] なし（すべて決定済み）

## 7. 実装コード案

```swift
Markdown(message.content)
    .markdownTheme(
        .gitHub
        .text {
            FontSize(13)
            ForegroundColor(.primary)
        }
    )
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color(nsColor: .windowBackgroundColor))
```
