⚠️ PoC only. Built fast with Claude Code, not audited. If you’re learning wgpu, start with the official examples instead.

# Hopper

用 **wgpu-hal (Vulkan) + winit + 一支 raw SPIR-V shader** 做的極簡無盡跑酷小遊戲。

- 整個畫面只有一個 fullscreen triangle，所有東西（天空、山、角色、障礙物、分數）都在 fragment shader 裡用 SDF 畫出來
- 遊戲狀態每幀透過 128 bytes 的 push constants（wgpu-hal 稱為 immediates）傳給 GPU，沒有 vertex buffer、uniform buffer、texture 或 bind group
- `src/shader.wgsl` 在 build time 由 `build.rs` 編成 SPIR-V 並 `include_bytes!` 進執行檔，runtime 以 `ShaderInput::SpirV` 直接餵給 Vulkan

## 操作

| 按鍵 | 動作 |
| --- | --- |
| Space / ↑ / W / 滑鼠左鍵 | 跳（按住跳更高）／開始／重來 |
| ↓ / S | 蹲下（空中按則加速下墜） |
| Esc | 離開 |

分數 120 之後會出現無人機：低的要跳過、高的要蹲過。

## Vulkan Setup

從 [LunarG](https://vulkan.lunarg.com/sdk/home) 下載並安裝 Vulkan SDK。macOS 上安裝時勾選 **System Global Installation**，
loader（`libvulkan.dylib`）與 MoltenVK 會裝到 `/usr/local/lib`，ICD 設定檔裝到 `/usr/local/share/vulkan/icd.d`。

### macOS

wgpu-hal 以檔名 `dlopen("libvulkan.dylib")` 載入 loader，但 2023 秋季以後 build 的執行檔 dyld 不再有預設的 fallback 搜尋路徑
（見 `man dyld` 的 `DYLD_FALLBACK_LIBRARY_PATH`），找不到 `/usr/local/lib`，啟動時會 panic：`Vulkan is not available ... missing Vulkan entry points`。

在 `~/.zshrc` 加上以下其中一種，再開新的 terminal：

```bash
# 做法一：只補 dyld 搜尋路徑（需要 System Global Installation）
export DYLD_FALLBACK_LIBRARY_PATH=/usr/local/lib
```

```bash
# 做法二：LunarG 官方的環境設定腳本，另外設定 VULKAN_SDK、PATH、layers 與 ICD
# 路徑含版本號，升級 SDK 後要跟著改
source ~/VulkanSDK/1.4.363.0/setup-env.sh
```

## Build

```bash
cargo build --release
```

Linux 執行需要 Vulkan driver 與 `libxkbcommon-x11`。預設只開 X11（Wayland 下走 XWayland）；要原生 Wayland：

```bash
cargo build --release --no-default-features --features wayland
```

## 大小

release profile 已開 `opt-level = "z"`、fat LTO、`codegen-units = 1`、`panic = "abort"`、`strip`。

| | 大小 |
| --- | --- |
| 執行檔（x86_64 Linux） | 1,094,640 bytes（~1.04 MB，低於 1.44 MB 磁碟片） |
| 其中 SPIR-V shader | ~17 KB |

### wgpu-hal patch

`vendor/wgpu-hal` 是 wgpu-hal 30.0.1，透過 `[patch.crates-io]` 取代 crates.io 版本。唯一的修改在 `src/vulkan/device.rs`：
把 `ShaderInput::Naga` 與 `ShaderModule::Intermediate` 兩條在 runtime 把 naga IR 轉成 SPIR-V 的路徑改成直接回錯誤。
沒有呼叫端之後，LTO 就能把 naga 的 SPIR-V writer、`proc`、`pipeline_constants` 等整包丟掉，執行檔從 ~1.74 MB 降到 ~1.09 MB。

代價：這份 wgpu-hal 只吃 `ShaderInput::SpirV`。本專案的 shader 本來就在 build time 編好，所以沒有影響。
升級 wgpu-hal 時要重新 vendor 並套用同樣的修改（`git show` 這個 patch 的 commit 即可看到 diff）。

## Future TODOs

依優先順序：

1. **DX12 後端**：給沒有 Vulkan 的 Windows 電腦（舊內顯、虛擬機、沒裝廠商驅動）。Windows 10 以後內建 D3D12，還有 WARP 軟體繪圖兜底。
   shader 需另外產生一份 HLSL（build time 由 naga `hlsl-out` 產生），並比照 Vulkan 把 wgpu-hal DX12 後端的 naga 轉換路徑 patch 掉。
2. **Metal 後端**：macOS 沒有原生 Vulkan，不能要求評審安裝 Vulkan SDK。shader 在 build time 由 naga `msl-out` 產生 MSL 字串，以 `ShaderInput::Msl` 傳入；
   同樣要 patch 掉 Metal 後端的 naga → MSL 路徑，並確認 push constants 綁定的 buffer index 與 wgpu-hal 預期一致。
3. **三平台 CI**：GitHub Actions 在 Linux / Windows / macOS 各自 build，回報 release 執行檔大小。

其他：

- **啟動失敗時顯示錯誤訊息框**：目前找不到 Vulkan（例如 macOS 沒裝 MoltenVK）或沒有可用 GPU 時會直接 abort，從檔案總管／Finder 點兩下啟動的玩家看不到任何訊息。
  winit 不提供對話框，打算用 `std::panic::set_hook` 統一攔截，各平台各一個小函式顯示：
  Windows 用 `user32` 的 `MessageBoxW`、macOS 用 CoreFoundation 的 `CFUserNotificationDisplayAlert`、Linux 依序嘗試 `zenity` / `kdialog`，都沒有就印到 stderr。
  不用 `rfd` 等現成 crate，因為它們在 Linux 上會拉進 GTK 或 D-Bus，體積代價太高。
