param(
    [string]$Output = "build/AutoGo图色助手.exe"
)

$ErrorActionPreference = "Stop"

function Resolve-Gcc {
    $command = Get-Command gcc -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:USERPROFILE "scoop/apps/gcc/current/bin/gcc.exe"),
        "C:\msys64\ucrt64\bin\gcc.exe",
        "C:\msys64\mingw64\bin\gcc.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    throw "未找到 gcc。可执行 scoop install gcc，或安装 MSYS2 UCRT64 的 gcc。"
}

$gcc = Resolve-Gcc
$gccBin = Split-Path $gcc -Parent
$env:PATH = "$gccBin;$env:PATH"
$env:CGO_ENABLED = "1"
$env:GOOS = "windows"
$env:GOARCH = "amd64"
$env:CC = $gcc

$goBin = Join-Path (go env GOPATH) "bin"
$rsrc = Join-Path $goBin "rsrc.exe"
if (!(Test-Path $rsrc)) {
    Write-Host "正在安装 Windows 资源工具 rsrc..."
    go install github.com/akavel/rsrc@latest
}
if (!(Test-Path $rsrc)) {
    throw "rsrc 安装失败：$rsrc"
}

$outputPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Output))
$outputDir = Split-Path $outputPath -Parent
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$resourceFile = Join-Path (Get-Location) "rsrc_windows_amd64.syso"
try {
    & $rsrc -ico "build/logo.ico" -manifest "windows_icon.manifest" -arch amd64 -o $resourceFile
    go build -ldflags "-s -w -H=windowsgui" -o $outputPath .
} finally {
    Remove-Item -LiteralPath $resourceFile -ErrorAction SilentlyContinue
}

if (!(Test-Path $outputPath)) {
    throw "Windows EXE 未生成。"
}

$file = Get-Item $outputPath
Write-Host "打包完成：$($file.FullName)"
Write-Host "文件大小：$([math]::Round($file.Length / 1MB, 2)) MB"
