# プロジェクト計画: ContentViewのリファクタリング
**Status**: Completed

## 1. 目的と背景 (Goal & Context)
SwiftUIのベストプラクティスに従い、ContentViewに書かれているビジネスロジックをViewModelに移行する。

**問題点**:
- ContentViewがSwiftDataのビジネスロジックを直接持っている
- Viewのテストが困難
- 単一責任原則 위반

**成功の定義**:
- ContentViewが「見た目」onlyになる
- ConversationListViewModelが会話リストの管理を担当する

## 2. 要件定義 (Requirements)
- **機能要件**:
  - 会話リストの作成・削除機能が引き続き動作する
  - 会話のグループ化とタイトル表示が動作する
- **非機能要件**:
  - SwiftUI + SwiftData のベストプラクティスに従う
  - 既存のテストが動作する

## 3. 基本設計 (Architecture & Design)

### 技術スタック
- 言語: Swift
- FW: SwiftUI + SwiftData
- パターン: MVVM（ハイブリッド型）

### 重要: SwiftDataとSwiftUIの制約
1. **`@Query`はSwiftUI View内でのみ動作する** - Viewに残す（データの読み出し・監視）
2. **`@Environment`の初期化タイミング問題** - ViewModelのinit時点でEnvironmentの値にアクセスできないため、modelContextは保持せずメソッド引数で渡す

### ディレクトリ構成案
```
nemo/
  ViewModels/
    ChatViewModel.swift              (既存 - 単一会話内メッセージ管理)
    ConversationListViewModel.swift  (新規作成 - 会話リスト管理)
```

### ConversationListViewModelの設計
```swift
@MainActor
class ConversationListViewModel: ObservableObject {
    // ナビゲーション状態
    @Published var selectedConversationId: UUID?
    @Published var showingSettings: Bool = false
    
    init() {}
    
    // MARK: - Actions (Write)
    // modelContextを引数で受け取る
    
    func createNewConversation(in context: ModelContext) -> UUID {
        let conversationId = UUID()
        selectedConversationId = conversationId
        return conversationId
    }
    
    func deleteConversation(conversationId: UUID, in context: ModelContext, from conversations: [Conversation]) {
        let conversationsToDelete = conversations.filter { $0.conversationId == conversationId }
        for conversation in conversationsToDelete {
            context.delete(conversation)
        }
        if selectedConversationId == conversationId {
            selectedConversationId = nil
        }
    }
    
    func deleteConversations(at offsets: IndexSet, in context: ModelContext, from conversations: [Conversation]) {
        let titles = buildConversationTitles(from: conversations)
        for index in offsets {
            let conversationId = titles[index].0
            deleteConversation(conversationId: conversationId, in: context, from: conversations)
        }
    }
    
    // MARK: - Presentation Logic (Transform)
    // conversationTitlesを生成（Context不要）
    func buildConversationTitles(from conversations: [Conversation]) -> [(UUID, String, Date)]
}
```

## 4. 実装ステップ (Implementation Steps)

- [ ] **Step 1: ConversationListViewModelの作成**
  - selectedConversationId, showingSettings の Published プロパティ
  - 空の init()
  - `createNewConversation(in:)` の実装
  - `deleteConversation(conversationId:in:from:)` の実装
  - `deleteConversations(at:in:from:)` の実装
  - `buildConversationTitles(from:)` の実装（conversationTitlesのロジックを移行）
  
- [ ] **Step 2: ContentViewの更新**
  - `@StateObject private var viewModel: ConversationListViewModel` を追加
  - `@Query` は維持（データの監視用）
  - `selectedConversationId` を `@State` から ViewModel の Published に変更
  - `showingSettings` を `@State` から ViewModel の Published に変更
  - `conversationGroups`, `conversationTitles` コンピューテッドプロパティを削除
  - `deleteConversation()`, `deleteConversations(at:)`, `createNewConversation()` を viewModel へ委譲（modelContextを渡す）
  - セル表示部分を `viewModel.buildConversationTitles(from: conversations)` を使用するよう修正
  
- [ ] **Step 3: ビルド確認**
  - Xcodeでビルドしてエラーがないことを確認

- [ ] **Step 4: Class Diagramの更新**
  - ConversationListViewModel を追加
  - ContentView のメソッドを削除

## 5. 決定事項・履歴 (Decision Log)
- [x] ConversationListViewModelを新規作成（既存のViewModelが単一会話管理のため分離）
- [x] conversationGroups/conversationTitlesはA案（コンピューテッドプロパティ/メソッド）
- [x] selectedConversationIdはA案（ConversationListViewModelで管理）
- [x] @QueryはViewに残す（SwiftDataの制約によりハイブリッド型を採用）
- [x] modelContextはinitで 받지ずにメソッド引数で渡す（@StateObject初期化タイミング問題への対応）

## 6. 未決事項 (Open Questions)
- [ ] なし（すべて決定済み、GO状態）
