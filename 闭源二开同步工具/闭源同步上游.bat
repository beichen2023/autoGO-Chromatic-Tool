@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fI"
pushd "%REPO_ROOT%" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Cannot enter repo root: %REPO_ROOT%
    pause
    exit /b 1
)

set "COMMAND=%~1"

if "%COMMAND%"=="" goto menu
if /I "%COMMAND%"=="help" goto help
if /I "%COMMAND%"=="setup" goto setup
if /I "%COMMAND%"=="sync" goto sync

echo [ERROR] Unknown command: %COMMAND%
echo.
goto help

:menu
echo Upstream sync tool
echo.
echo Target repo root: %REPO_ROOT%
echo.
echo Select an action:
echo   1. Setup or update upstream
echo   2. Sync upstream into local branch
echo   3. Show help
echo   4. Exit
echo.
choice /C 1234 /N /M "Choose 1-4: "
if errorlevel 4 exit /b 0
if errorlevel 3 goto help_pause
if errorlevel 2 goto sync_interactive
if errorlevel 1 goto setup_interactive

:setup_interactive
set "INTERACTIVE_SETUP=1"
call :setup
set "RESULT=%errorlevel%"
echo.
pause
exit /b %RESULT%

:sync_interactive
set "INTERACTIVE_SYNC=1"
call :sync
set "RESULT=%errorlevel%"
echo.
pause
exit /b %RESULT%

:setup
call :ensure_git_repo || exit /b 1

set "UPSTREAM_URL=%~2"
if "%UPSTREAM_URL%"=="" if "%INTERACTIVE_SETUP%"=="1" (
    echo [INFO] Enter original upstream repo URL.
    echo Example: https://github.com/xiaozhang959/autoGO-Chromatic-Tool.git
    set /p "UPSTREAM_URL=Upstream URL: "
)
if "%UPSTREAM_URL%"=="" (
    echo [ERROR] Upstream repo URL is required.
    echo Example: this-script.bat setup https://github.com/xiaozhang959/autoGO-Chromatic-Tool.git
    exit /b 1
)

git remote get-url upstream >nul 2>nul
if errorlevel 1 (
    echo [INFO] Add upstream: %UPSTREAM_URL%
    git remote add upstream "%UPSTREAM_URL%"
) else (
    echo [INFO] Update upstream: %UPSTREAM_URL%
    git remote set-url upstream "%UPSTREAM_URL%"
)

if errorlevel 1 (
    echo [ERROR] Failed to set upstream.
    exit /b 1
)

git remote set-url --push upstream DISABLED >nul 2>nul

echo.
echo [OK] Upstream is configured. Upstream push URL is disabled.
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

if "%INTERACTIVE_SYNC%"=="1" (
    echo [INFO] Enter upstream branch. Leave empty to auto-detect master/main.
    set /p "UPSTREAM_BRANCH=Upstream branch: "
    echo [INFO] Enter local branch. Leave empty to use current branch.
    set /p "LOCAL_BRANCH=Local branch: "
    echo [INFO] Enter sync mode. Leave empty to use merge.
    set /p "SYNC_MODE=Sync mode merge/rebase: "
)

if "%SYNC_MODE%"=="" set "SYNC_MODE=merge"

if /I not "%SYNC_MODE%"=="merge" if /I not "%SYNC_MODE%"=="rebase" (
    echo [ERROR] Sync mode must be merge or rebase.
    echo Example: this-script.bat sync master master-mzh-20260606 merge
    exit /b 1
)

if "%LOCAL_BRANCH%"=="" (
    for /f "delims=" %%I in ('git branch --show-current') do set "LOCAL_BRANCH=%%I"
)

if "%LOCAL_BRANCH%"=="" (
    echo [ERROR] Cannot detect current branch. Please specify local branch.
    echo Example: this-script.bat sync master master-mzh-20260606
    exit /b 1
)

echo [INFO] Fetch upstream updates...
git fetch upstream --prune
if errorlevel 1 (
    echo [ERROR] Failed to fetch upstream. Check network or repo permission.
    exit /b 1
)

if "%UPSTREAM_BRANCH%"=="" call :detect_upstream_branch

if "%UPSTREAM_BRANCH%"=="" (
    echo [ERROR] Cannot detect upstream branch. Please specify it.
    echo Example: this-script.bat sync master
    echo Example: this-script.bat sync main
    exit /b 1
)

git rev-parse --verify --quiet "refs/remotes/upstream/%UPSTREAM_BRANCH%" >nul
if errorlevel 1 (
    echo [ERROR] upstream/%UPSTREAM_BRANCH% does not exist.
    echo [TIP] Run: git branch -r
    exit /b 1
)

git show-ref --verify --quiet "refs/heads/%LOCAL_BRANCH%"
if errorlevel 1 (
    echo [ERROR] Local branch does not exist: %LOCAL_BRANCH%
    echo [TIP] Run: git branch
    exit /b 1
)

echo [INFO] Checkout local branch: %LOCAL_BRANCH%
git checkout "%LOCAL_BRANCH%"
if errorlevel 1 (
    echo [ERROR] Failed to checkout branch.
    exit /b 1
)

if /I "%SYNC_MODE%"=="rebase" goto do_rebase
goto do_merge

:do_merge
echo [INFO] Merge upstream/%UPSTREAM_BRANCH% into %LOCAL_BRANCH%...
git merge --no-ff "upstream/%UPSTREAM_BRANCH%"
if errorlevel 1 (
    echo.
    echo [CONFLICT] Merge stopped because of conflicts.
    echo Resolve conflicts, then run:
    echo   git add conflict-files
    echo   git commit
    echo   git push origin %LOCAL_BRANCH%
    echo To abort:
    echo   git merge --abort
    exit /b 1
)
goto push_origin

:do_rebase
echo [INFO] Rebase %LOCAL_BRANCH% onto upstream/%UPSTREAM_BRANCH%...
git rebase "upstream/%UPSTREAM_BRANCH%"
if errorlevel 1 (
    echo.
    echo [CONFLICT] Rebase stopped because of conflicts.
    echo Resolve conflicts, then run:
    echo   git add conflict-files
    echo   git rebase --continue
    echo   git push --force-with-lease origin %LOCAL_BRANCH%
    echo To abort:
    echo   git rebase --abort
    exit /b 1
)
goto push_origin

:push_origin
echo [INFO] Push %LOCAL_BRANCH% to origin...
git push origin "%LOCAL_BRANCH%"
if errorlevel 1 (
    echo [ERROR] Push failed. Check origin permission or branch protection.
    exit /b 1
)

echo.
echo [OK] Synced upstream/%UPSTREAM_BRANCH% into %LOCAL_BRANCH% and pushed to origin.
exit /b 0

:detect_upstream_branch
set "UPSTREAM_HEAD="
for /f "delims=" %%I in ('git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2^>nul') do set "UPSTREAM_HEAD=%%I"
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
    echo [ERROR] Current target is not a Git repo. Put this tool folder under repo root.
    exit /b 1
)
exit /b 0

:ensure_remote
git remote get-url "%~1" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Missing remote: %~1
    if /I "%~1"=="upstream" echo [TIP] Run: this-script.bat setup original-repo-url
    exit /b 1
)
exit /b 0

:ensure_clean_worktree
for /f "delims=" %%I in ('git status --porcelain') do (
    echo [ERROR] Worktree is not clean. Commit or stash changes before sync.
    echo [TIP] Run: git status
    exit /b 1
)
exit /b 0

:help
echo Upstream sync tool
echo.
echo Usage:
echo   this-script.bat setup ^<original-repo-url^>
echo   this-script.bat sync [upstream-branch] [local-branch] [merge^|rebase]
echo   this-script.bat help
echo.
echo Examples:
echo   this-script.bat setup https://github.com/xiaozhang959/autoGO-Chromatic-Tool.git
echo   this-script.bat sync master
echo   this-script.bat sync master master-mzh-20260606
echo   this-script.bat sync master master-mzh-20260606 rebase
echo.
echo Notes:
echo   setup adds or updates upstream and disables upstream push URL.
echo   sync uses merge by default, then pushes local branch to origin.
echo   If local branch is omitted, current branch is used.
echo   The parent folder of this tool folder is used as the repo root.
exit /b 0

:help_pause
call :help
echo.
pause
exit /b 0
