# ユーザーバブル色変更計画
**Status**: Draft

## 目的と背景 (Goal & Context)
ユーザーのバブル色を青色からグレーに変更する。

**問題点**:
1. 現在のユーザーバブルは青色で表示されている
2. ユーザーバブルの色をグレーに変更したい

**成功の定義**:
- ユーザーバブルの色がグレーに変更される
- アシスタントバブルの色は変更されない
- 完全に動作する

## 2. 要件定義 (Requirements)
- **機能要件**:
  - ユーザーバブルの色を青色からグレーに変更
  - アシスタントバブルの色は変更されない
  - 完全に動作する
- **非機能要件**:
  - 現在のファンクションは維持
  - **UIKitに依存しない（SwiftUIネイティブ実装）**
  - ダーク/ライトモード両方で正常に表示
  - パフォーマンスに影響を与えない

## 3. 基本設計 (Architecture & Design)

### 技術スタック
- SwiftUI
- macOS ウィンドウスタイル

### 修正対象
- `nemo/Views/ChatView.swift` のユーザーバブル色定義

### 修正内容
```swift
// 現在のユーザーバブル色定義
if message.role == "user" {
    Text(message.content)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // ここを薄いグレーに変更
        .background(Color.gray.opacity(0.25)) 
        .cornerRadius(18)
        // 文字色も背景に合わせて標準色を明示（青背景時の白文字指定などが残っていないか注意）
        .foregroundColor(.primary) 
}
```

## 4. 実装ステップ (Implementation Steps)

- [ ] **Step 1: ChatView.swiftの修正**
  - ユーザーバブルの背景色を `.blue` から `Color.gray.opacity(0.25)` に変更
  - 文字色が `.white` などに固定されている場合は `.primary` (自動)に変更する
  - ビルドエラーを確認

- [ ] **Step 2: ビルド確認**
  - Xcodeでビルドしてエラーがないことを確認
  - プレビューで表示を確認
  - ユーザーバブルが**適切な薄さのグレー**で表示されることを確認

## 5. 決定事項・履歴 (Decision Log)
- [ ] ユーザーバブルの色を `Color.gray.opacity(0.25)` に変更
- [ ] UIKit (`UIColor`)は使用せず、SwiftUI標準カラーを使用する
- [ ] アシスタントバブルの色は変更されない

## 6. 未決事項 (Open Questions)
- [ ] ダークモード時の視覚性は十分か？（不足な場合、opacityを0.3〜0.4に調整する必要があるか）

## 7. 実装コード案

```swift
// ChatView.swiftの修正部分
if message.role == "user" {
    Text(message.content)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // SwiftUIネイティブな指定。0.25程度がシステム標準に近い薄さになります
        .background(Color.gray.opacity(0.25))  
        .foregroundColor(.primary) // 文字色はモードに合わせて自動黒/白
        .cornerRadius(18)
}
```

## 8. 詳細設計

### グレーの選定理由
- `Color.gray`: そのまま使用すると不透光度100%のグレーとなり、UIとしては重すぎる（濃すぎる）。
- `Color.gray.opacity(0.25)`: 
  - **ライトモード**: 薄いグレー（iMessageの受信バブルに近い色味）となり、壊張感がない。
  - **ダークモード**: 背景よりあまりわずかに明るいグレーとなり、自然なハイライトとして機能する。
  - **互換性**: SwiftUI純粋な実装であり、macOS/iOSの両方で意固通りに動作する。

## 9. リスク評価
- **安全性**: 低い。純粋なSwiftUIカラー定義のみの変更。
- **完全性**: 文字色（foregroundColor）との組み合わせさえ確認すれば完全。
- **保存性**: UIKit依存を排除したため、将来のメンテナンス性は向上。
- **時間**: 極めて短い。単行の変更のみ。

## 10. 最後の確認
上記の実装ステップを実行し、ユーザーバブルの色が正常にグレーに変更されることを確認する。特にダークモード時の文字の読みやすさを重点的に確認する。