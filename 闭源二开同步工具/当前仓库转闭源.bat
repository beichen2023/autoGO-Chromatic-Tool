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
if /I "%COMMAND%"=="status" goto status
if /I "%COMMAND%"=="private" goto private

echo [ERROR] Unknown command: %COMMAND%
echo.
goto help

:menu
echo Repo privacy tool
echo.
echo Target repo root: %REPO_ROOT%
echo.
echo Select an action:
echo   1. Show repo visibility
echo   2. Set origin repo to Private
echo   3. Show help
echo   4. Exit
echo.
choice /C 1234 /N /M "Choose 1-4: "
if errorlevel 4 exit /b 0
if errorlevel 3 goto help_pause
if errorlevel 2 goto private_interactive
if errorlevel 1 goto status_pause

:status_pause
call :status
set "RESULT=%errorlevel%"
echo.
pause
exit /b %RESULT%

:private_interactive
set "INTERACTIVE_PRIVATE=1"
call :private
set "RESULT=%errorlevel%"
echo.
pause
exit /b %RESULT%

:status
call :ensure_git_repo || exit /b 1
call :read_origin_repo || exit /b 1

echo [INFO] Query GitHub repo visibility: %OWNER%/%REPO%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$repo='%OWNER%/%REPO%';" ^
  "$headers=@{ 'User-Agent'='Codex-Repo-Privacy-Script' };" ^
  "try {" ^
  "  $r=Invoke-RestMethod -Method Get -Uri \"https://api.github.com/repos/$repo\" -Headers $headers;" ^
  "  Write-Host ('repo=' + $r.full_name);" ^
  "  Write-Host ('url=' + $r.html_url);" ^
  "  Write-Host ('private=' + $r.private);" ^
  "  Write-Host ('visibility=' + $r.visibility);" ^
  "} catch {" ^
  "  Write-Host '[ERROR] Query failed. If the repo is already private, anonymous access may return 404.';" ^
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
    echo [INFO] Enter GitHub Token.
    echo [INFO] Classic token needs repo scope. Fine-grained token needs Administration read/write.
    set /p "TOKEN=GitHub Token: "
)

if "%TOKEN%"=="" (
    echo [ERROR] GitHub Token is required.
    echo.
    echo By argument:
    echo   this-script.bat private ghp_xxx
    echo.
    echo By environment variable:
    echo   set GITHUB_TOKEN=ghp_xxx
    echo   this-script.bat private
    echo.
    echo Required permission:
    echo   Classic token: repo scope
    echo   Fine-grained token: Administration read/write on target repo
    exit /b 1
)

echo [WARN] This will set GitHub repo to Private: %OWNER%/%REPO%
echo [INFO] This only changes the origin repo. It does not change upstream.
echo.
choice /C YN /N /M "Continue? Y/N: "
if errorlevel 2 (
    echo [CANCEL] No change was made.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$repo='%OWNER%/%REPO%';" ^
  "$token='%TOKEN%';" ^
  "$headers=@{ 'User-Agent'='Codex-Repo-Privacy-Script'; 'Accept'='application/vnd.github+json'; 'Authorization'=('Bearer ' + $token); 'X-GitHub-Api-Version'='2022-11-28' };" ^
  "$body='{""private"":true}';" ^
  "try {" ^
  "  $r=Invoke-RestMethod -Method Patch -Uri \"https://api.github.com/repos/$repo\" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body;" ^
  "  Write-Host ('[OK] Repo is now private: ' + $r.full_name);" ^
  "  Write-Host ('url=' + $r.html_url);" ^
  "  Write-Host ('private=' + $r.private);" ^
  "} catch {" ^
  "  Write-Host '[ERROR] Failed to change repo visibility.';" ^
  "  if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { Write-Host ('http_status=' + [int]$_.Exception.Response.StatusCode) };" ^
  "  Write-Host $_.Exception.Message;" ^
  "  exit 1;" ^
  "}"
if errorlevel 1 exit /b 1

git remote get-url upstream >nul 2>nul
if not errorlevel 1 (
    git remote set-url --push upstream DISABLED >nul 2>nul
    echo [OK] Disabled upstream push URL.
)

exit /b 0

:read_origin_repo
git remote get-url origin >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Missing origin remote.
    exit /b 1
)

set "ORIGIN_URL="
for /f "delims=" %%I in ('git remote get-url origin') do set "ORIGIN_URL=%%I"

set "OWNER="
set "REPO="
set "REPO_PATH=%ORIGIN_URL%"
set "REPO_PATH=%REPO_PATH:https://github.com/=%"
set "REPO_PATH=%REPO_PATH:http://github.com/=%"
set "REPO_PATH=%REPO_PATH:git@github.com:=%"

if "%REPO_PATH%"=="%ORIGIN_URL%" (
    echo [ERROR] Only GitHub origin URLs are supported.
    echo origin=%ORIGIN_URL%
    exit /b 1
)

if "%REPO_PATH:~-4%"==".git" set "REPO_PATH=%REPO_PATH:~0,-4%"
if "%REPO_PATH:~-1%"=="/" set "REPO_PATH=%REPO_PATH:~0,-1%"

for /f "tokens=1,2 delims=/" %%A in ("%REPO_PATH%") do (
    set "OWNER=%%A"
    set "REPO=%%B"
)

if "%OWNER%"=="" (
    echo [ERROR] Cannot parse origin owner.
    exit /b 1
)
if "%REPO%"=="" (
    echo [ERROR] Cannot parse origin repo.
    exit /b 1
)

exit /b 0

:ensure_git_repo
git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Current target is not a Git repo. Put this tool folder under repo root.
    exit /b 1
)
exit /b 0

:help
echo Repo privacy tool
echo.
echo Usage:
echo   this-script.bat status
echo   this-script.bat private [GitHubToken]
echo   this-script.bat help
echo.
echo Examples:
echo   this-script.bat status
echo   this-script.bat private ghp_xxx
echo   set GITHUB_TOKEN=ghp_xxx
echo   this-script.bat private
echo.
echo Notes:
echo   status  shows visibility of the GitHub repo pointed to by origin.
echo   private sets the GitHub repo pointed to by origin to Private.
echo   The upstream repo is not changed.
echo   The parent folder of this tool folder is used as the repo root.
echo.
echo Required permission:
echo   Classic token: repo scope
echo   Fine-grained token: Administration read/write on target repo
exit /b 0

:help_pause
call :help
echo.
pause
exit /b 0
