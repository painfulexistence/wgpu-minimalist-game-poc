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
