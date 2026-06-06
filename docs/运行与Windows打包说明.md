# 运行与 Windows 打包说明

## 环境要求

- Windows 10/11 64 位。
- Go 版本以 `go.mod` 为准。
- Fyne 桌面程序依赖 CGO，因此需要可用的 GCC。
- 截图、节点抓取和 App 信息功能需要 `adb`，并且 Android 设备已连接。

推荐使用 Scoop 安装 GCC：

```powershell
scoop install gcc
```

## 开发运行

在项目根目录执行：

```powershell
$gccBin = "$env:USERPROFILE\scoop\apps\gcc\current\bin"
$env:PATH = "$gccBin;$env:PATH"
$env:CGO_ENABLED = "1"
$env:CC = "$gccBin\gcc.exe"
go run .
```

如果 GCC 已经在 `PATH` 中，可以直接执行：

```powershell
go run .
```

不启动桌面 OpenGL 窗口的单元测试：

```powershell
go test -tags ci ./...
```

## 打包 Windows EXE

项目根目录提供了 `build-windows.ps1`。脚本会：

1. 查找 Scoop、MSYS2 或系统 `PATH` 中的 GCC。
2. 自动安装缺失的 `rsrc` 工具。
3. 将 `build/logo.ico` 和 `windows_icon.manifest` 写入 EXE。
4. 使用 `-H=windowsgui` 隐藏控制台窗口。
5. 输出 64 位 Windows EXE。

执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1
```

默认产物：

```text
build\AutoGo图色助手.exe
```

指定输出路径：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -Output "dist\AutoGo图色助手.exe"
```

## 手动打包命令

```powershell
$gccBin = "$env:USERPROFILE\scoop\apps\gcc\current\bin"
$env:PATH = "$gccBin;$env:PATH"
$env:CGO_ENABLED = "1"
$env:GOOS = "windows"
$env:GOARCH = "amd64"
$env:CC = "$gccBin\gcc.exe"

go install github.com/akavel/rsrc@latest
& "$(go env GOPATH)\bin\rsrc.exe" -ico "build\logo.ico" -manifest "windows_icon.manifest" -arch amd64 -o "rsrc_windows_amd64.syso"
go build -ldflags "-s -w -H=windowsgui" -o "build\AutoGo图色助手.exe" .
Remove-Item "rsrc_windows_amd64.syso"
```

## 发布与使用

- `AutoGo图色助手.exe` 可以直接运行。
- 需要使用 Android 功能时，请确保 `adb.exe` 在系统 `PATH` 中，或与 EXE 放在同一目录。
- 仓库的 `.github/workflows/release.yml` 也支持通过 GitHub Actions 构建 Windows amd64 发布产物。

## 本次本机验证

2026 年 6 月 6 日已在 Windows amd64 环境完成：

- `go test -tags ci ./...` 测试通过。
- 成功生成 `build\AutoGo图色助手.exe`。
- EXE 大小约 24.3 MB。
- 启动后进程持续正常运行，完成基础启动验证。
