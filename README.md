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
| 執行檔（x86_64 Linux） | ~1.7 MB |
| xz -9e 壓縮後 | ~0.6 MB |
| 其中 SPIR-V shader | ~17 KB |

執行檔內容大致分佈（未 strip 時以 symbol 估算）：naga ~410 KB、winit/X11 ~345 KB、std ~245 KB、wgpu-hal/ash ~115 KB、遊戲本身 ~13 KB。

naga 在 runtime 完全沒用到，但 wgpu-hal 的 Vulkan backend 在 `create_shader_module` 裡仍會 match `ShaderInput::Naga`，所以 spv-out 會被連結進來。要再縮就是 patch wgpu-hal 把那條路徑拿掉，或改用 nightly `-Z build-std` + `panic_immediate_abort`。
