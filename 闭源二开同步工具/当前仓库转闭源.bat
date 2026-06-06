@echo off
chcp 65001 >nul
setlocal

set "SCRIPT_DIR=%~dp0"
for %%i in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fi"
pushd "%REPO_ROOT%" >nul 2>nul
if errorlevel 1 (
    echo [错误] 无法进入目标仓库目录：%REPO_ROOT%
    pause
    exit /b 1
)

set "COMMAND=%~1"
if "%COMMAND%"=="" goto menu
if /I "%COMMAND%"=="help" goto help
if /I "%COMMAND%"=="status" goto status
if /I "%COMMAND%"=="private" goto private

echo [错误] 未知命令：%COMMAND%
echo.
goto help

:menu
echo 当前仓库转闭源脚本
echo.
echo 目标仓库目录：%REPO_ROOT%
echo.
echo 请选择要执行的操作：
echo   1. 查询当前仓库可见性
echo   2. 把当前仓库转为 Private
echo   3. 查看帮助
echo   4. 退出
echo.
choice /C 1234 /N /M "请输入选项 1-4："
if errorlevel 4 exit /b 0
if errorlevel 3 goto help_pause
if errorlevel 2 goto private_interactive
if errorlevel 1 goto status_pause

:status_pause
call :status
echo.
pause
exit /b %errorlevel%

:private_interactive
set "INTERACTIVE_PRIVATE=1"
call :private
echo.
pause
exit /b %errorlevel%

:status
call :ensure_git_repo || exit /b 1
call :read_origin_repo || exit /b 1

echo [信息] 查询 GitHub 仓库可见性：%OWNER%/%REPO%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$repo='%OWNER%/%REPO%';" ^
  "$headers=@{ 'User-Agent'='Codex-Repo-Privacy-Script' };" ^
  "try {" ^
  "  $r=Invoke-RestMethod -Method Get -Uri \"https://api.github.com/repos/$repo\" -Headers $headers;" ^
  "  Write-Host ('仓库：' + $r.full_name);" ^
  "  Write-Host ('地址：' + $r.html_url);" ^
  "  Write-Host ('是否私有：' + $r.private);" ^
  "  Write-Host ('可见性：' + $r.visibility);" ^
  "} catch {" ^
  "  Write-Host '[错误] 查询失败。若仓库已经是私有，未认证访问可能会返回 404。';" ^
  "  Write-Host $_.Exception.Message;" ^
  "  exit 1;" ^
  "}"
exit /b %errorlevel%

:private
call :ensure_git_repo || exit /b 1
call :read_origin_repo || exit /b 1

set "TOKEN=%~2"
if "%TOKEN%"=="" set "TOKEN=%GITHUB_TOKEN%"
if "%TOKEN%"=="" set "TOKEN=%GH_TOKEN%"
if "%TOKEN%"=="" if "%INTERACTIVE_PRIVATE%"=="1" (
    echo [信息] 请输入 GitHub Token。
    echo [提示] Classic token 需要 repo 权限；Fine-grained token 需要目标仓库 Administration 读写权限。
    set /p "TOKEN=GitHub Token："
)

if "%TOKEN%"=="" (
    echo [错误] 请通过参数或环境变量提供 GitHub Token。
    echo.
    echo 参数方式：
    echo   %~nx0 private ghp_xxx
    echo.
    echo 环境变量方式：
    echo   set GITHUB_TOKEN=ghp_xxx
    echo   %~nx0 private
    echo.
    echo Token 权限建议：
    echo   Classic token：repo 权限
    echo   Fine-grained token：目标仓库 Administration 读写权限
    exit /b 1
)

echo [警告] 即将把 GitHub 仓库改为 Private：%OWNER%/%REPO%
echo [说明] 这只修改 origin 指向的 GitHub 仓库可见性，不会修改 upstream 原作者仓库。
echo.
choice /C YN /N /M "确认继续？输入 Y 继续，输入 N 取消："
if errorlevel 2 (
    echo [取消] 已取消修改。
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$repo='%OWNER%/%REPO%';" ^
  "$token='%TOKEN%';" ^
  "$headers=@{ 'User-Agent'='Codex-Repo-Privacy-Script'; 'Accept'='application/vnd.github+json'; 'Authorization'=('Bearer ' + $token); 'X-GitHub-Api-Version'='2022-11-28' };" ^
  "$body=@{ private=$true } ^| ConvertTo-Json;" ^
  "try {" ^
  "  $r=Invoke-RestMethod -Method Patch -Uri \"https://api.github.com/repos/$repo\" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body;" ^
  "  Write-Host ('[完成] 仓库已设置为 Private：' + $r.full_name);" ^
  "  Write-Host ('地址：' + $r.html_url);" ^
  "  Write-Host ('是否私有：' + $r.private);" ^
  "} catch {" ^
  "  Write-Host '[错误] 修改仓库可见性失败。';" ^
  "  if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { Write-Host ('HTTP 状态：' + [int]$_.Exception.Response.StatusCode) };" ^
  "  Write-Host $_.Exception.Message;" ^
  "  exit 1;" ^
  "}"
if errorlevel 1 exit /b 1

git remote get-url upstream >nul 2>nul
if not errorlevel 1 (
    git remote set-url --push upstream DISABLED >nul 2>nul
    echo [完成] 已禁用 upstream 的 push 地址，避免误推原作者仓库。
)

exit /b 0

:read_origin_repo
git remote get-url origin >nul 2>nul
if errorlevel 1 (
    echo [错误] 缺少 origin 远程仓库。
    exit /b 1
)

set "ORIGIN_URL="
for /f "delims=" %%i in ('git remote get-url origin') do set "ORIGIN_URL=%%i"

set "OWNER="
set "REPO="
set "REPO_PATH=%ORIGIN_URL%"
set "REPO_PATH=%REPO_PATH:https://github.com/=%"
set "REPO_PATH=%REPO_PATH:http://github.com/=%"
set "REPO_PATH=%REPO_PATH:git@github.com:=%"

if "%REPO_PATH%"=="%ORIGIN_URL%" (
    echo [错误] 当前脚本只支持 GitHub 仓库地址。
    echo [当前 origin] %ORIGIN_URL%
    exit /b 1
)

if "%REPO_PATH:~-4%"==".git" set "REPO_PATH=%REPO_PATH:~0,-4%"
if "%REPO_PATH:~-1%"=="/" set "REPO_PATH=%REPO_PATH:~0,-1%"

for /f "tokens=1,2 delims=/" %%a in ("%REPO_PATH%") do (
    set "OWNER=%%a"
    set "REPO=%%b"
)

if errorlevel 1 (
    echo [错误] 当前脚本只支持 GitHub 仓库地址。
    echo [当前 origin] %ORIGIN_URL%
    exit /b 1
)

if "%OWNER%"=="" (
    echo [错误] 解析 origin 仓库所有者失败。
    exit /b 1
)
if "%REPO%"=="" (
    echo [错误] 解析 origin 仓库名失败。
    exit /b 1
)

exit /b 0

:ensure_git_repo
git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    echo [错误] 当前目录不是 Git 仓库，请在项目根目录执行脚本。
    exit /b 1
)
exit /b 0

:help
echo 当前仓库转闭源脚本
echo.
echo 用法：
echo   %~nx0 status
echo   %~nx0 private [GitHubToken]
echo   %~nx0 help
echo.
echo 示例：
echo   %~nx0 status
echo   %~nx0 private ghp_xxx
echo   set GITHUB_TOKEN=ghp_xxx
echo   %~nx0 private
echo.
echo 说明：
echo   status  查询 origin 指向的 GitHub 仓库当前可见性。
echo   private 调用 GitHub API，把 origin 指向的仓库改成 Private。
echo   这个脚本不会影响 upstream 原作者仓库。
echo   脚本会把所在工具目录的上一级当作 Git 仓库根目录。
echo.
echo Token 权限建议：
echo   Classic token：repo 权限
echo   Fine-grained token：目标仓库 Administration 读写权限
exit /b 0

:help_pause
call :help
echo.
pause
exit /b 0
