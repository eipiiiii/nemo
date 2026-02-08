# PlantUML Generator Rules

あなたはSwiftUIの構造解析と可視化を行います。
指示があった場合、対象のコードを解析し **PlantUML (.puml)** 形式のファイルをdocsディレクトリ配下に出力、またはすでに存在する場合は更新してください。

## 1. Class Diagram (MVVM)
- **目的**: アプリの構造把握
- **重点項目**:
  - View, ViewModel, Model(Service) の依存関係
  - SwiftUI特有のProperty Wrapper (`@StateObject`, `@Published`, `@Binding` 等) の明記

## 2. State Diagram (Status)
- **目的**: 画面状態の遷移把握
- **重点項目**:
  - `enum` で管理される状態遷移 (Idle -> Loading -> Success/Error)
  - 遷移のトリガー (onAppear, Button Tap, API Response)

## 3. Sequence Diagram (Async Flow)
- **目的**: 非同期処理の流れ把握
- **重点項目**:
  - ユーザー操作(View) → ロジック(ViewModel) → API通信(Service) の時系列
  - `async/await` の待機区間と、UIスレッド(`MainActor`)への復帰タイミング