# プロジェクト計画: チャットビューのツールバー統合
**Status**: Draft

## 1. 目的と背景 (Goal & Context)
チャットビューの上部にあるバー（ウィンドウタイトルバーとツールバー）が区切られていて、ツールバーとコンテンツエリアの間に境界線があるため、一体化させる。

**問題点**:
1. ツールバーとコンテンツエリアの間に境界線があり、見た目が分断されている
2. ウィンドウタイトルバーとツールバーが別々に表示されている

**成功の定義**:
- ツールバー背景を非表示にし、タイトル表示モードをインラインに設定
- チャットビューのコンテンツとツールバーが一体化する

## 2. 要件定義 (Requirements)
- **機能要件**:
  - ツールバー背景を非表示にする
  - タイトル表示モードをインラインに設定
  - チャットビューのコンテンツとツールバーが一体化する
- **非機能要件**:
  - 既存の機能は維持
  - ダーク/ライトモード両方で正常に表示

## 3. 基本設計 (Architecture & Design)

### 技術スタック
- SwiftUI
- macOS ウィンドウスタイル

### 修正対象
- `nemo/ContentView.swift` の `ChatView` 部分
- `nemo/Views/ChatView.swift` の全体

### 修正内容
```swift
// ContentView.swiftのChatView部分
ChatView(conversationId: selectedId, modelContext: modelContext)
    .id(selectedId)
    .toolbarBackground(.hidden, for: .windowToolbar)  // ツールバー背景を非表示
    .toolbarTitleDisplayMode(.inline)  // タイトル表示モードをインラインに

// ChatView.swiftの全体
var body: some View {
    VStack(spacing: 0) {
        // 既存のチャットビューコンテンツ
    }
    .toolbarBackground(.hidden, for: .windowToolbar)
    .background(Color(nsColor: .windowBackgroundColor))
}
```

## 4. 実装ステップ (Implementation Steps)

- [ ] **Step 1: ContentView.swiftの修正**
  - ChatViewにtoolbarBackgroundとtoolbarTitleDisplayModeモディファイアを追加

- [ ] **Step 2: ChatView.swiftの修正**
  - VStackのスペーシングを0に設定
  - toolbarBackgroundとbackgroundモディファイアを追加

- [ ] **Step 3: ビルド確認**
  - Xcodeでビルドしてエラーがないことを確認
  - プレビューで表示を確認

## 5. 決定事項・履歴 (Decision Log)
- [ ] ツールバー背景を非表示にする
- [ ] タイトル表示モードをインラインにする
- [ ] スペーシングを0にして一体化する

## 6. 未決事項 (Open Questions)
- [ ] なし（すべて決定済み）

## 7. 実装コード案

```swift
// ContentView.swift
.detail: {
    if let selectedId = viewModel.selectedConversationId {
        ChatView(conversationId: selectedId, modelContext: modelContext)
            .id(selectedId)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbarTitleDisplayMode(.inline)
    } else {
        // 既存のコード
    }
}

// ChatView.swift
var body: some View {
    VStack(spacing: 0) {
        // 既存のチャットビューコンテンツ
    }
    .toolbarBackground(.hidden, for: .windowToolbar)
    .background(Color(nsColor: .windowBackgroundColor))
}
```

## 8. テスト計画 (Testing Plan)
- [ ] macOS 26+ での動作確認
- [ ] ウィンドウリサイズ時の表示確認
- [ ] サイドバー表示/非表示の切り替え確認
- [ ] 既存の全ツールバーボタンの動作確認
- [ ] Before/After のスクリーンショット比較

## 9. リスクと代替案 (Risks & Alternatives)
**リスク**:
- NavigationSplitView との相性問題
- macOS 26+ での動作確認が必要

**代替案**:
1. `.windowToolbarStyle(.unified)` の使用
2. カスタム NSHostingView での実装
3. `.safeAreaInset` による手動調整