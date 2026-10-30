# 三平台 CI 計畫

對應 README Future TODOs 第 3 項：GitHub Actions 在 Linux / Windows / macOS 各自 build，回報 release 執行檔大小。

## 範圍

- 三個平台各跑一次 `cargo build --release`，確認能編過
- 量測 release 執行檔大小（bytes），寫進該次 run 的 summary，並把執行檔上傳成 artifact
- **不跑遊戲**：GitHub runner 沒有 GPU，遊戲無法啟動。CI 只保證「編得過」與「多大」

## Workflow

檔案：`.github/workflows/ci.yml`

| | Linux | Windows | macOS |
| --- | --- | --- | --- |
| runner | `ubuntu-latest` | `windows-latest` | `macos-latest`（arm64） |
| 執行檔 | `target/release/hopper` | `target/release/hopper.exe` | `target/release/hopper` |
| 額外系統套件 | 不需要（X11 / Vulkan 都是 runtime 才 dlopen） | 不需要 | 不需要 |

觸發條件：push 到 `main`、pull request。

草稿：

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - run: cargo build --release --locked
      - name: Report size
        shell: bash
        run: |
          bin=target/release/hopper
          [ -f "$bin.exe" ] && bin="$bin.exe"
          size=$(wc -c < "$bin" | tr -d ' ')
          {
            echo "| OS | rustc | 執行檔 | bytes |"
            echo "| --- | --- | --- | --- |"
            echo "| ${{ matrix.os }} | $(rustc --version) | \`$(basename "$bin")\` | $size |"
          } >> "$GITHUB_STEP_SUMMARY"
      - uses: actions/upload-artifact@v4
        with:
          name: hopper-${{ matrix.os }}
          path: target/release/hopper*
          if-no-files-found: error
```

`--locked` 確保 CI 用的是 `Cargo.lock` 裡的版本，大小才能和本機比較。

## 注意事項

1. **大小會隨 Rust 版本漂移**：repo 沒有 `rust-toolchain.toml`，CI 用當下的 stable，Rust 升版時程式碼沒變大小也可能變。
   summary 至少印出 `rustc --version`；要長期比較就加 `rust-toolchain.toml` 固定版本。
2. **Actions 分鐘數**：private repo 的 macOS 以 10 倍、Windows 以 2 倍計費。fat LTO + `codegen-units = 1` 單次 build 約數分鐘，
   加上 `rust-cache` 後依賴不必重編，整體用量不大。
3. **Repo 帳號**：目前 remote 是 `github.com/painfulexistence/...`。若不是公司 org（ikg.team / ikigai.team），
   依公司規範應先把 repo 移到公司 org 再開 CI。

## 之後可以加

- **大小回歸檢查**：和 `main` 上一次的大小比較，超過門檻（例如 +5%）就在 PR 留言或讓 job 失敗
- **Linux 上實際啟動**：裝 Mesa lavapipe（軟體 Vulkan）+ Xvfb，啟動幾秒確認沒 panic
- **macOS universal binary**：額外 build `x86_64-apple-darwin` 再用 `lipo` 合併

## 完成後

- README Future TODOs 移除第 3 項，「大小」表格改成三平台並註明數字來自 CI
