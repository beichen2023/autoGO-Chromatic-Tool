@echo off
chcp 65001 >nul
setlocal

set "COMMAND=%~1"

if "%COMMAND%"=="" goto help
if /I "%COMMAND%"=="help" goto help
if /I "%COMMAND%"=="setup" goto setup
if /I "%COMMAND%"=="sync" goto sync

echo [错误] 未知命令：%COMMAND%
echo.
goto help

:setup
call :ensure_git_repo || exit /b 1

set "UPSTREAM_URL=%~2"
if "%UPSTREAM_URL%"=="" (
    echo [错误] 请提供原作者仓库地址。
    echo 示例：%~nx0 setup https://github.com/xiaozhang959/autoGO-Chromatic-Tool.git
    exit /b 1
)

git remote get-url upstream >nul 2>nul
if errorlevel 1 (
    echo [信息] 添加 upstream：%UPSTREAM_URL%
    git remote add upstream "%UPSTREAM_URL%"
) else (
    echo [信息] 更新 upstream：%UPSTREAM_URL%
    git remote set-url upstream "%UPSTREAM_URL%"
)

if errorlevel 1 (
    echo [错误] upstream 设置失败。
    exit /b 1
)

git remote set-url --push upstream DISABLED >nul 2>nul

echo.
echo [完成] upstream 已配置，push 地址已禁用，避免误推原作者仓库。
git remote -v
exit /b 0

:sync
call :ensure_git_repo || exit /b 1
call :ensure_remote origin || exit /b 1
call :ensure_remote upstream || exit /b 1
call :ensure_clean_worktree || exit /b 1

set "UPSTREAM_BRANCH=%~2"
set "LOCAL_BRANCH=%~3"
set "SYNC_MODE=%~4"

if "%SYNC_MODE%"=="" set "SYNC_MODE=merge"

if /I not "%SYNC_MODE%"=="merge" if /I not "%SYNC_MODE%"=="rebase" (
    echo [错误] 同步模式只能是 merge 或 rebase。
    echo 示例：%~nx0 sync master master-mzh-20260606 merge
    exit /b 1
)

if "%LOCAL_BRANCH%"=="" (
    for /f "delims=" %%i in ('git branch --show-current') do set "LOCAL_BRANCH=%%i"
)

if "%LOCAL_BRANCH%"=="" (
    echo [错误] 无法识别当前分支，请手动指定本地分支。
    echo 示例：%~nx0 sync master master-mzh-20260606
    exit /b 1
)

echo [信息] 获取 upstream 最新更新...
git fetch upstream --prune
if errorlevel 1 (
    echo [错误] 拉取 upstream 失败，请检查网络或仓库权限。
    exit /b 1
)

if "%UPSTREAM_BRANCH%"=="" call :detect_upstream_branch

if "%UPSTREAM_BRANCH%"=="" (
    echo [错误] 无法自动识别上游分支，请手动指定。
    echo 示例：%~nx0 sync master
    echo 示例：%~nx0 sync main
    exit /b 1
)

git rev-parse --verify --quiet "refs/remotes/upstream/%UPSTREAM_BRANCH%" >nul
if errorlevel 1 (
    echo [错误] upstream/%UPSTREAM_BRANCH% 不存在。
    echo [提示] 可以先执行 git branch -r 查看远程分支。
    exit /b 1
)

git show-ref --verify --quiet "refs/heads/%LOCAL_BRANCH%"
if errorlevel 1 (
    echo [错误] 本地分支 %LOCAL_BRANCH% 不存在。
    echo [提示] 可以先执行 git branch 查看本地分支。
    exit /b 1
)

echo [信息] 切换到本地分支：%LOCAL_BRANCH%
git checkout "%LOCAL_BRANCH%"
if errorlevel 1 (
    echo [错误] 切换分支失败。
    exit /b 1
)

if /I "%SYNC_MODE%"=="rebase" goto do_rebase
goto do_merge

:do_merge
echo [信息] 合并 upstream/%UPSTREAM_BRANCH% 到 %LOCAL_BRANCH%...
git merge --no-ff "upstream/%UPSTREAM_BRANCH%"
if errorlevel 1 (
    echo.
    echo [冲突] 合并过程中出现冲突，脚本已停止。
    echo [处理] 解决冲突后执行：
    echo        git add 冲突文件
    echo        git commit
    echo        git push origin %LOCAL_BRANCH%
    echo [放弃] 如果不想继续本次同步，执行：
    echo        git merge --abort
    exit /b 1
)
goto push_origin

:do_rebase
echo [信息] 变基 %LOCAL_BRANCH% 到 upstream/%UPSTREAM_BRANCH%...
git rebase "upstream/%UPSTREAM_BRANCH%"
if errorlevel 1 (
    echo.
    echo [冲突] rebase 过程中出现冲突，脚本已停止。
    echo [处理] 解决冲突后执行：
    echo        git add 冲突文件
    echo        git rebase --continue
    echo        git push --force-with-lease origin %LOCAL_BRANCH%
    echo [放弃] 如果不想继续本次同步，执行：
    echo        git rebase --abort
    exit /b 1
)
goto push_origin

:push_origin
echo [信息] 推送 %LOCAL_BRANCH% 到 origin...
git push origin "%LOCAL_BRANCH%"
if errorlevel 1 (
    echo [错误] 推送失败，请检查 origin 权限或远程分支保护规则。
    exit /b 1
)

echo.
echo [完成] 已同步 upstream/%UPSTREAM_BRANCH% 到 %LOCAL_BRANCH%，并推送到 origin。
exit /b 0

:detect_upstream_branch
set "UPSTREAM_HEAD="
for /f "delims=" %%i in ('git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2^>nul') do set "UPSTREAM_HEAD=%%i"
if not "%UPSTREAM_HEAD%"=="" call set "UPSTREAM_BRANCH=%%UPSTREAM_HEAD:upstream/=%%"

if not "%UPSTREAM_BRANCH%"=="" exit /b 0

git show-ref --verify --quiet refs/remotes/upstream/master
if not errorlevel 1 (
    set "UPSTREAM_BRANCH=master"
    exit /b 0
)

git show-ref --verify --quiet refs/remotes/upstream/main
if not errorlevel 1 (
    set "UPSTREAM_BRANCH=main"
    exit /b 0
)

exit /b 0

:ensure_git_repo
git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    echo [错误] 当前目录不是 Git 仓库，请在项目根目录执行脚本。
    exit /b 1
)
exit /b 0

:ensure_remote
git remote get-url "%~1" >nul 2>nul
if errorlevel 1 (
    echo [错误] 缺少远程仓库：%~1
    if /I "%~1"=="upstream" echo [提示] 请先执行：%~nx0 setup 原作者仓库地址
    exit /b 1
)
exit /b 0

:ensure_clean_worktree
for /f "delims=" %%i in ('git status --porcelain') do (
    echo [错误] 工作区不干净，请先提交或暂存当前改动后再同步。
    echo [提示] 可执行 git status 查看详情。
    exit /b 1
)
exit /b 0

:help
echo 闭源二开同步上游脚本
echo.
echo 用法：
echo   %~nx0 setup ^<原作者仓库地址^>
echo   %~nx0 sync [上游分支] [本地分支] [merge^|rebase]
echo   %~nx0 help
echo.
echo 示例：
echo   %~nx0 setup https://github.com/xiaozhang959/autoGO-Chromatic-Tool.git
echo   %~nx0 sync master
echo   %~nx0 sync master master-mzh-20260606
echo   %~nx0 sync master master-mzh-20260606 rebase
echo.
echo 说明：
echo   setup 会添加或更新 upstream，并禁用 upstream 的 push 地址。
echo   sync 默认使用 merge，把 upstream/上游分支 同步到本地分支并推送 origin。
echo   不传本地分支时，默认使用当前分支。
exit /b 0
