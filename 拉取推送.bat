@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ==========================================
:: Git 快捷管理助手 v3.2 (稳定修复版)
:: ==========================================

:: 设置 UTF-8 编码
chcp 65001 >nul
title Git 快捷助手 v3.2
color 0b

:: --- 环境自检 ---
where git >nul 2>&1
if errorlevel 1 (
    echo [严重错误] 未检测到 Git，请先安装并添加到 PATH。
    pause & exit /b
)

:: 自动修复中文路径乱码配置
git config --global core.quotepath false

:: ==============================
:: 主菜单循环
:: ==============================
:MENU
cls
call :GET_NOW
call :SHOW_REPO_INFO

echo.
echo    [1] 状态查询 (Status)
echo    [2] 拉取更新 (Pull / Rebase)
:: --- 下面这一行彻底移除了特殊符号 & 和 () ---
echo    [3] 提交推送 [Smart Commit + Push]  [更新!]
echo    [4] 一键同步 (Sync: Pull+Commit+Push)
echo    [5] 清理工具 (Clean Untracked)
echo    [0] 退出
echo.
echo ==========================================
set "choice="
set /p choice="请输入选项 (0-5): "

if "%choice%"=="1" goto STEP_STATUS
if "%choice%"=="2" goto STEP_PULL
if "%choice%"=="3" goto STEP_PUSH_MENU
if "%choice%"=="4" goto STEP_SYNC
if "%choice%"=="5" goto STEP_CLEAN
if "%choice%"=="0" exit
goto MENU

:: ==============================
:: 1. 查看状态
:: ==============================
:STEP_STATUS
cls
echo --- 当前工作区状态 ---
git status
echo.
echo --- 最近 5 条提交记录 ---
git log -n 5 --oneline --graph --decorate
echo.
pause
goto MENU

:: ==============================
:: 2. 拉取流程
:: ==============================
:STEP_PULL
cls
echo --- Pull 模式选择 ---
echo  [1] 普通拉取 (git pull)
echo  [2] 变基拉取 (git pull --rebase) - 推荐
echo  [3] 强力拉取 (Stash -> Pull -> Pop)
echo  [0] 返回
echo.
set "pull_mode="
set /p pull_mode="请选择: "

if "%pull_mode%"=="1" (
    echo 执行: git pull...
    git pull
    pause & goto MENU
)
if "%pull_mode%"=="2" (
    echo 执行: git pull --rebase...
    git pull --rebase
    pause & goto MENU
)
if "%pull_mode%"=="3" (
    echo [系统] 暂存本地改动...
    git stash push -u -m "AutoStash_%now_time%"
    echo [系统] 执行拉取...
    git pull
    echo [系统] 恢复本地改动...
    git stash pop
    pause & goto MENU
)
goto MENU

:: ==============================
:: 3. 提交推送主菜单
:: ==============================
:STEP_PUSH_MENU
cls
call :CHECK_CHANGES
if not defined has_change (
    echo [提示] 本地工作区无改动，直接进入推送阶段。
    goto PUSH_REMOTE_ONLY
)

echo --- 提交模式选择 ---
echo  [1] 打包提交 (所有文件使用同一个备注)
echo  [2] 逐个提交 (依次询问每个文件并写备注)
echo  [0] 返回
echo.
set "commit_mode="
set /p commit_mode="请选择模式: "

if "%commit_mode%"=="1" goto COMMIT_BULK
if "%commit_mode%"=="2" goto COMMIT_INDIVIDUAL
if "%commit_mode%"=="0" goto MENU
goto STEP_PUSH_MENU

:: --- 模式A: 打包提交 ---
:COMMIT_BULK
echo.
echo --- 待提交文件 ---
git status --short
echo.
set "msg="
set /p msg="请输入统一备注 (回车默认: update): "
if "!msg!"=="" set "msg=update %now_time%"

git add .
git commit -m "!msg!"
if errorlevel 1 (
    echo [错误] 提交失败。
    pause & goto MENU
)
goto PUSH_REMOTE_ONLY

:: --- 模式B: 逐个提交 ---
:COMMIT_INDIVIDUAL
cls
echo [进入逐个提交模式] 
echo 按 'y' 提交并写备注，按 'n' 跳过，按 'q' 停止。
echo ------------------------------------------------

:: 将状态输出到临时文件
git status --porcelain > "%temp%\git_status_temp.txt"

for /f "tokens=1,*" %%A in (%temp%\git_status_temp.txt) do (
    set "f_status=%%A"
    set "f_name=%%B"
    :: 去除文件名可能包含的双引号
    set "f_name=!f_name:"=!"
    
    call :PROCESS_SINGLE_FILE "!f_status!" "!f_name!"
    if defined EXIT_INDIVIDUAL_LOOP goto END_INDIVIDUAL_LOOP
)

:END_INDIVIDUAL_LOOP
del "%temp%\git_status_temp.txt"
set "EXIT_INDIVIDUAL_LOOP="
echo.
echo [逐个提交结束] 剩余未提交文件将保留在工作区。
goto PUSH_REMOTE_ONLY

:: --- 处理单个文件的子程序 ---
:PROCESS_SINGLE_FILE
set "p_status=%~1"
set "p_name=%~2"

echo.
echo 当前文件: [%p_status%] %p_name%
set "ans="
set /p ans="是否提交此文件? (y/n/q): "

if /i "!ans!"=="q" (
    set "EXIT_INDIVIDUAL_LOOP=1"
    exit /b
)

if /i "!ans!"=="y" (
    set "s_msg="
    set /p s_msg="请输入 [%p_name%] 的备注: "
    if "!s_msg!"=="" set "s_msg=Update %p_name%"
    
    git add "%p_name%"
    git commit -m "!s_msg!"
    echo [已提交]
) else (
    echo [已跳过]
)
exit /b

:: --- 推送阶段 (通用) ---
:PUSH_REMOTE_ONLY
echo.
echo --- 推送模式 ---
echo  [1] 标准推送 (git push)
echo  [2] 安全强推 (force-with-lease)
echo  [3] 强制推送 (force) - 谨慎!
echo  [0] 返回菜单
echo.
set "pmode="
set /p pmode="请选择: "

if "%pmode%"=="1" (
    git push
    goto PUSH_RESULT
)
if "%pmode%"=="2" set "P_CMD=--force-with-lease" & set "P_DESC=安全强推" & goto CONFIRM_FORCE
if "%pmode%"=="3" set "P_CMD=--force" & set "P_DESC=强制推送" & goto CONFIRM_FORCE
if "%pmode%"=="0" goto MENU
goto MENU

:CONFIRM_FORCE
cls
color 0c
echo ==========================================
echo            警 告：准备执行 !P_DESC!
echo ==========================================
echo  分支: !cur_br!
echo.
set /p c1="[确认 1/2] 确定强推? (y/n): "
if /i not "!c1!"=="y" ( color 0b & goto MENU )

set /p c2="[确认 2/2] 再次按 Y 确认执行: "
if /i not "!c2!"=="y" ( color 0b & goto MENU )

echo [执行中] git push !P_CMD! ...
git push !P_CMD!

:PUSH_RESULT
if %errorlevel% equ 0 (
    echo. & echo [成功] 操作已完成。
) else (
    echo. & echo [失败] 推送遇到错误，请检查冲突或网络。
)
color 0b
pause
goto MENU

:: ==============================
:: 4. 一键同步
:: ==============================
:STEP_SYNC
cls
echo [1/3] 正在拉取远程更新 (Rebase)...
git pull --rebase
echo.
echo [2/3] 正在自动提交本地改动...
call :CHECK_CHANGES
if defined has_change (
    git add .
    git commit -m "Quick Sync: %now_time%"
) else (
    echo (本地无改动，跳过提交)
)
echo.
echo [3/3] 正在推送到远端...
git push
if %errorlevel% equ 0 (
    echo. & echo [完成] 同步成功。
) else (
    echo. & echo [错误] 同步失败。
)
pause
goto MENU

:: ==============================
:: 5. 清理工具
:: ==============================
:STEP_CLEAN
cls
echo [警告] 这将永久删除所有未被 Git 追踪的文件和文件夹。
set /p c_confirm="确定清理吗? (y/n): "
if /i "%c_confirm!"=="y" (
    git clean -fd
    echo [完成] 清理完毕。
)
pause
goto MENU

:: ==============================
:: 工具函数区
:: ==============================

:GET_NOW
set "now_time=%time:~0,8%"
set "now_time=%now_time: =0%"
exit /b

:SHOW_REPO_INFO
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    color 0c & echo [错误] 当前目录不是 Git 仓库！ & pause & exit
)
for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD') do set "cur_br=%%B"
git fetch --prune >nul 2>&1
set "status_msg=已同步"
for /f "tokens=1,2" %%i in ('git rev-list --left-right --count HEAD...@{u} 2^>nul') do (
    set "status_msg=本地领先 %%i | 远程领先 %%j"
)
echo ==========================================
echo    位置: %cd%
echo    分支: !cur_br! (!status_msg!)
echo ==========================================
exit /b

:CHECK_CHANGES
set "has_change="
for /f "delims=" %%S in ('git status --porcelain 2^>nul') do (
    set "has_change=1"
    exit /b
)
exit /b