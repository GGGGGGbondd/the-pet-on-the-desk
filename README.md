# 灵感小宠物 Linggan Pet 🐾

一个无需安装的 Windows 桌面灵感收集器：平时是一个小圆球悬浮在屏幕右下角，点它展开成输入面板，随时记录一闪而过的念头。

A lightweight, install-free Windows desktop idea catcher: a small floating ball sits at the bottom-right of your screen — click it to expand an input panel and jot down ideas anytime.

## 功能 Features

-  常驻小圆球，点击展开输入面板 / Persistent ball, click to expand
-  输入灵感，Ctrl + Enter 快速保存 / Type an idea, Ctrl + Enter to save
-  “看看以前的” 回看最近 30 条记录 / Review the last 30 saved ideas
-  小球和面板都可以按住拖动 / Drag the ball or the panel to reposition
-  Ctrl + Alt + I 随时隐藏 / 唤回（唯一能让宠物消失的快捷键）/ Hide & recall anytime (the only way to make the pet fully disappear)
-  数据只保存在本地，不上传网络 / All data stays local — nothing is uploaded
-  支持开机自启 / Auto-start on boot

## 使用方法 Usage

1. 双击 `启动灵感小宠物.bat` 即可运行，无需安装。
   Double-click `启动灵感小宠物.bat` to run — no installation needed.
2. 想开机自动出现：`Win + R` 输入 `shell:startup`，把 `启动灵感小宠物.bat` 的快捷方式放进去。
   For auto-start: press `Win + R`, type `shell:startup`, and put a shortcut to the launcher in that folder.

### 快捷键 Shortcuts

| 操作 Action | 快捷键 Keys |
|---|---|
| 隐藏 / 唤回宠物 Hide / Recall | `Ctrl + Alt + I` |
| 保存灵感 Save idea | `Ctrl + Enter`（在输入框内 inside the box）|

## 数据存储 Data Storage

所有灵感保存在同目录下 `data\ideas.jsonl`（每行一条 JSON），删掉即清空。

Ideas are stored locally in `data\ideas.jsonl` next to the script (one JSON per line). Delete it to clear all records.

## 目录结构 Structure

```
linggan-pet/
├── 灵感小宠物.ps1       # 主程序脚本 Main script
├── 启动灵感小宠物.bat    # 启动器 Launcher
├── 使用说明.txt         # 使用说明 Usage notes
└── data/               # 灵感数据（本地，不入库）Local data (git-ignored)
```

## 环境要求 Requirements

- Windows 10 / 11
- 无需安装任何依赖（使用系统自带 PowerShell 5.1 + WPF）No dependencies (built-in PowerShell 5.1 + WPF)

## 技术说明 Technical notes

- 进程固定为 DPI 无关（1:1 像素），保证高分屏下拖动与点击精确
  Process is pinned to DPI-unaware (1:1 pixels) for pixel-accurate dragging on HiDPI displays
- 使用 WPF `AllowsTransparency` 无边框置顶窗口
  WPF borderless always-on-top window with transparency
- 隐藏采用“移出屏幕”而非 `Hide()`，规避透明窗口的原生崩溃
  Hiding moves the window off-screen instead of calling `Hide()`, avoiding a native crash with transparent windows
