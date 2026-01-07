@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ==========================================
:: Git 快捷管理助手 v2.6 (增强异步体验版)
:: ==========================================

:: 设置 UTF-8 编码
chcp 65001 >nul
title Git 快捷助手 v2.6
color 0b

:: --- 环境自检 ---
where git >nul 2>&1
if errorlevel 1 (
    echo [严重错误] 未检测到 Git，请先安装并添加到 PATH。
    pause & exit /b
)

:: 基础配置优化
git config --global core.quotepath false
:: 减少冗余的提示（可选）
set "GIT_TERMINAL_PROMPT=1"

:: ==============================
:: 主菜单循环
:: ==============================
:MENU
cls
call :GET_NOW
call :SHOW_REPO_INFO

echo.
echo    [1] 状态查询 (Status)           [4] 一键同步 (Sync)
echo    [2] 拉取更新 (Pull/Rebase)      [5] 清理工具 (Clean)
echo    [3] 提交推送 (Commit+Push)      [0] 退出程序
echo.
echo ------------------------------------------
set "choice="
set /p choice="请输入选项 (0-5): "

if "%choice%"=="1" goto STEP_STATUS
if "%choice%"=="2" goto STEP_PULL
if "%choice%"=="3" goto STEP_PUSH
if "%choice%"=="4" goto STEP_SYNC
if "%choice%"=="5" goto STEP_CLEAN
if "%choice%"=="0" exit
goto MENU

:: ==============================
:: 1. 查看状态
:: ==============================
:STEP_STATUS
cls
echo [当前状态] 正在获取详细信息...
echo ------------------------------------------
git status
echo.
echo [提交历史] 最近 5 条记录:
git log -n 5 --oneline --graph --decorate
echo.
pause
goto MENU

:: ==============================
:: 2. 拉取流程
:: ==============================
:STEP_PULL
cls
echo [拉取更新] 请选择模式:
echo ------------------------------------------
echo  [1] 标准拉取 (git pull)
echo  [2] 变基拉取 (git pull --rebase) - 保持线形历史
echo  [3] 智能覆盖 (Stash -> Pull -> Pop) - 解决本地冲突
echo  [0] 返回菜单
echo.
set "pull_mode="
set /p pull_mode="请选择: "

if "%pull_mode%"=="1" (
    git pull
) else if "%pull_mode%"=="2" (
    git pull --rebase
) else if "%pull_mode%"=="3" (
    echo [系统] 正在暂存本地未提交修改...
    git stash push -u -m "AutoStash_%now_time%"
    echo [系统] 执行拉取...
    git pull
    echo [系统] 正在尝试回退暂存...
    git stash pop
) else (
    goto MENU
)
pause
goto MENU

:: ==============================
:: 3. 推送流程
:: ==============================
:STEP_PUSH
cls
call :CHECK_CHANGES
if not defined has_change (
    echo [提示] 本地工作区干净，检查是否有待推送的 Commit...
    goto PUSH_REMOTE_ONLY
)

echo [提交改动]
git status --short
echo.
set "msg="
set /p msg="请输入 Commit 信息 (直接回车: update): "
if "!msg!"=="" set "msg=update %now_time%"

git add .
git commit -m "!msg!"
if errorlevel 1 (
    echo [错误] Commit 失败，请检查是否有冲突。
    pause & goto MENU
)

:PUSH_REMOTE_ONLY
echo.
echo [推送模式]
echo  [1] 标准推送 (git push)
echo  [2] 安全强推 (force-with-lease)
echo  [3] 暴力强推 (force)
echo  [0] 返回
echo.
set "pmode="
set /p pmode="请选择: "

if "%pmode%"=="1" (
    git push
    goto PUSH_RESULT
)
if "%pmode%"=="2" set "P_CMD=--force-with-lease" & set "P_DESC=安全强推" & goto CONFIRM_FORCE
if "%pmode%"=="3" set "P_CMD=--force" & set "P_DESC=强制推送" & goto CONFIRM_FORCE
goto MENU

:CONFIRM_FORCE
cls
color 0c
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo           警告：准备执行 !P_DESC!
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo  目标分支: !cur_br!
echo.
set /p c1="[二次确认 1/2] 确定执行吗? (y/n): "
if /i not "!c1!"=="y" ( color 0b & goto MENU )

set /p c2="[二次确认 2/2] 请再次按 Y 确认: "
if /i not "!c2!"=="y" ( color 0b & goto MENU )

echo [执行中] git push !P_CMD! ...
git push !P_CMD!

:PUSH_RESULT
if %errorlevel% equ 0 (
    echo. & echo [成功] 远端同步已完成。
) else (
    echo. & echo [失败] 推送失败，可能是远端有更新，请先拉取。
)
color 0b
pause
goto MENU

:: ==============================
:: 4. 一键同步 (Pull + Commit + Push)
:: ==============================
:STEP_SYNC
cls
echo [1/3] 同步远端代码 (Rebase)...
git pull --rebase
if errorlevel 1 (
    echo [中止] 拉取过程出现冲突，请手动处理后再执行。
    pause & goto MENU
)

echo [2/3] 处理本地改动...
call :CHECK_CHANGES
if defined has_change (
    git add .
    git commit -m "Auto-Sync: %now_time%"
) else (
    echo [提示] 本地无改动，跳过提交。
)

echo [3/3] 推送至服务器...
git push
if %errorlevel% equ 0 (
    echo. & echo [完成] 全流程同步成功！
) else (
    echo. & echo [失败] 推送环节出现错误。
)
pause
goto MENU

:: ==============================
:: 5. 清理工具
:: ==============================
:STEP_CLEAN
cls
echo [清理模式]
echo  [1] 仅预览 (Dry Run)
echo  [2] 确定清理 (删除所有未追踪文件/目录)
echo  [0] 返回
echo.
set /p c_type="请选择: "
if "%c_type%"=="1" (
    git clean -fdn
) else if "%c_type%"=="2" (
    git clean -fd
    echo [完成] 清理完毕。
)
pause
goto MENU

:: ==============================
:: 工具函数区
:: ==============================

:GET_NOW
set "now_time=%date:~0,10% %time:~0,8%"
exit /b

:SHOW_REPO_INFO
:: 检查 Git 环境
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    color 0c
    echo ==========================================
    echo    错误: 当前路径非 Git 仓库或无法访问
    echo    路径: %cd%
    echo ==========================================
    pause & exit
)

:: 获取分支名
for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD') do set "cur_br=%%B"

:: 检查与远程的差异 (异步模拟：快速检查本地缓存的远程状态)
set "status_msg=待检测"
for /f "tokens=1,2" %%i in ('git rev-list --left-right --count HEAD...@{u} 2^>nul') do (
    set "status_msg=本地领先 %%i | 远程领先 %%j"
)
if "!status_msg!"=="待检测" set "status_msg=未关联远程分支"

echo ==========================================
echo    仓库: %cd%
echo    分支: !cur_br! [ !status_msg! ]
echo ==========================================
exit /b

:CHECK_CHANGES
set "has_change="
for /f "delims=" %%S in ('git status --porcelain 2^>nul') do (
    set "has_change=1"
    exit /b
)
exit /b
