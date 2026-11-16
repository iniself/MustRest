# MustRest

一个 macOS 番茄钟 / 休息提醒应用。

## 功能

1. 通过定时提醒用户休息。
2. 遮罩默认全屏显示，遮罩颜色为 `#ffb3a7`。开关打开（“遮罩全屏”）时禁止提前退出，必须等计时结束；关闭（“允许退出”）时，遮罩中的“退出”按钮可以提前结束本次计时任务。
3. 弹出的提醒默认显示该任务的名称，例如目前是“休息眼睛”。
4. 默认任务：
   - 15 分钟工作后，进行 15 秒的休息眼睛。
   - 1 小时工作后，进行 5 分钟的站立运动。
   - 2 小时工作后，进行 10 分钟的站立运动。
5. 以上默认值都可以在设置中自行修改。

## 构建

本项目使用 Swift Package Manager 管理，系统要求 macOS 12 及以上（Apple Silicon / Intel）。

```bash
swift build
swift run MustRestApp
```

## 测试

```bash
swift test
```

## 项目结构

- `Sources/MustRest` - 核心逻辑（任务、计时引擎、设置）。
- `Sources/MustRestApp` - macOS 应用界面（菜单栏、遮罩提醒窗口、设置窗口）。
- `Tests/MustRestTests` - 单元测试。
