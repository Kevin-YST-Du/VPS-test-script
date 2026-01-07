@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ==============================
:: Git 快捷助手（优化修复版）
:: ==============================

:: 设置 UTF-8 (若乱码请尝试改为 936 或在 CMD 属性设置字体为 Lucida Console/Consolas)
chcp 65001 >nul
title Git 管理助手 [优化版]
color 0b

:: ==========================================
:: 环境自检
:: ==========================================
where git >nul 2>&1
if errorlevel 1 (
    echo [严重错误] 未检测到 git，请先安装并添加到 PATH 环境变量。
    pause
    exit /b
)

:: 自动修复 core.quotepath (解决中文乱码)
for /f "delims=" %%Q in ('git config --get core.quotepath 2^>nul') do set "qp=%%Q"
if /i "!qp!"=="true" (
    git config --global core.quotepath false
    echo [系统] 已自动修复中文路径显示配置 (core.quotepath=false)
)

:: ==============================
:: 主循环入口
:: ==============================
:MENU
cls
call :SET_NOW
call :SHOW_REPO_INFO

echo.
echo ==========================================
echo        Git 管理助手 (%now_time%)
echo ==========================================
echo.
echo    [1] 拉取代码 (Pull)
echo    [2] 推送代码 (Push)
echo    [3] 查看状态 (Status)
echo    [0] 退出
echo.
echo ==========================================
set "choice="
set /p choice="请输入选项: "

if "%choice%"=="1" goto STEP_PULL
if "%choice%"=="2" goto STEP_PUSH
if "%choice%"=="3" goto STEP_STATUS
if "%choice%"=="0" exit
goto MENU

:: ==============================
:: 查看状态
:: ==============================
:STEP_STATUS
cls
echo.
echo --- 当前仓库状态 ---
echo.
git status
echo.
pause
goto MENU

:: ==============================
:: 拉取流程
:: ==============================
:STEP_PULL
cls
echo.
echo --- Pull 模式选择 ---
echo  [1] 普通拉取 (git pull)
echo  [2] Rebase 拉取 (推荐, 保持线性历史)
echo  [3] 自动 Stash -^> Pull -^> Pop (防冲突)
echo  [0] 返回
echo.
set "pull_mode="
set /p pull_mode="请选择: "

if "%pull_mode%"=="1" (
    echo. & echo --- 执行: git pull ---
    git pull
    pause & goto MENU
)
if "%pull_mode%"=="2" (
    echo. & echo --- 执行: git pull --rebase ---
    git pull --rebase
    pause & goto MENU
)
if "%pull_mode%"=="3" goto PULL_STASH
if "%pull_mode%"=="0" goto MENU
goto STEP_PULL

:PULL_STASH
cls
call :CHECK_CHANGES
if not defined has_change (
    echo [提示] 本地无改动，直接执行 pull...
    git pull
    pause & goto MENU
)

echo [提示] 检测到本地改动，准备执行 Stash...
git stash push -u -m "AutoStash_%date%_%time%"
if errorlevel 1 (
    echo [错误] Stash 失败，停止操作。
    pause & goto MENU
)

echo. & echo --- 执行 Pull ---
git pull
if errorlevel 1 (
    echo [错误] Pull 失败！您的改动仍在 Stash 列表中。
    echo 请手动执行: git stash pop 并解决冲突。
    pause & goto MENU
)

echo. & echo --- 恢复改动 (Pop) ---
git stash pop
pause & goto MENU

:: ==============================
:: 推送流程
:: ==============================
:STEP_PUSH
cls
call :CHECK_CHANGES
if not defined has_change (
    echo.
    echo [提示] 工作区干净，无文件需要提交。
    echo 正在检查是否需要推送到远端...
    goto PUSH_REMOTE_ONLY
)

echo.
echo --- 待提交文件 ---
git status --short
echo.
echo ==========================================
echo  [1] 批量提交 (所有改动)
echo  [2] 逐个提交 (选择性提交)
echo  [0] 返回
echo ==========================================
set "commit_mode="
set /p commit_mode="请选择: "

if "%commit_mode%"=="1" goto PUSH_BATCH
if "%commit_mode%"=="2" goto PUSH_SINGLE
if "%commit_mode%"=="0" goto MENU
goto STEP_PUSH

:: --- 批量提交 ---
:PUSH_BATCH
echo.
set "msg="
set /p msg="请输入提交备注 (回车默认: Auto Update): "
if "!msg!"=="" set "msg=Auto Update"

echo. & echo --- 添加并提交 ---
git add .
git commit -m "!msg!"
if errorlevel 1 (
    echo [错误] 提交失败。
    pause & goto MENU
)
goto PUSH_REMOTE_ONLY

:: --- 逐个提交 (修复闪退的核心部分) ---
:PUSH_SINGLE
cls
echo.
echo --- 逐个提交模式 ---
echo [提示] 输入 y 提交，n 跳过，q 退出提交阶段
echo.

:: 使用 tokens=1,* 解析状态和路径，避免空格问题
for /f "tokens=1,*" %%A in ('git status --porcelain') do (
    set "status_code=%%A"
    set "file_path=%%B"
    
    :: 去除路径可能自带的双引号 (针对带空格文件名)
    set "file_path=!file_path:"=!"
    
    :: 简单的重命名处理 (git status 输出: R  old -> new)
    :: 如果路径里包含 -> ，这行代码比较简陋，建议针对复杂情况只用批量提交
    echo.
    echo [文件] !file_path!  (状态: !status_code!)
    
    set "confirm="
    set /p confirm="是否提交? (y/n/q): "
    
    if /i "!confirm!"=="q" goto PUSH_REMOTE_ONLY
    if /i "!confirm!"=="y" (
        git add "!file_path!"
        
        set "s_msg="
        set /p s_msg="  备注 (回车默认: update): "
        if "!s_msg!"=="" set "s_msg=update: !file_path!"
        
        git commit -m "!s_msg!"
    )
)
echo.
echo [完成] 所有文件遍历完毕。
goto PUSH_REMOTE_ONLY

:: --- 推送至远端 ---
:PUSH_REMOTE_ONLY
echo.
echo ==========================================
echo  [1] 正常推送 (git push)
echo  [2] 强制推送 (Force with lease - 安全强推)
echo  [3] 强制推送 (Force - 危险!)
echo  [0] 取消推送，返回菜单
echo ==========================================
set "pmode="
set /p pmode="请选择: "

if "%pmode%"=="0" goto MENU

:: 自动获取当前分支名
for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD') do set "curr_branch=%%B"
:: 自动获取 upstream
for /f "delims=" %%U in ('git rev-parse --abbrev-ref --symbolic-full-name @{u} 2^>nul') do set "upstream=%%U"

set "push_args="
if not defined upstream (
    echo [提示] 当前分支无上游，将自动设置: -u origin !curr_branch!
    set "push_args=-u origin !curr_branch!"
)

if "%pmode%"=="1" (
    echo --- 正在推送 ---
    git push !push_args!
)
if "%pmode%"=="2" (
    echo --- 正在安全强推 ---
    git push --force-with-lease !push_args!
)
if "%pmode%"=="3" (
    echo.
    echo [警告] 危险操作！
    pause
    echo --- 正在强推 ---
    git push --force !push_args!
)

if errorlevel 1 (
    echo.
    echo [失败] 推送遇到错误，请检查网络或冲突。
) else (
    echo.
    echo [成功] 推送完成。
)
pause
goto MENU

:: ==============================
:: 工具函数区
:: ==============================
:SET_NOW
set "now_date=%date:~0,10%"
set "now_time=%time:~0,8%"
set "now_time=%now_time: =0%"
exit /b

:SHOW_REPO_INFO
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo [错误] 当前目录不是 Git 仓库！
    pause
    exit
)
for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD') do set "cur_br=%%B"
echo [信息] 仓库路径: %cd%
echo [信息] 当前分支: !cur_br!
exit /b

:CHECK_CHANGES
set "has_change="
for /f "delims=" %%S in ('git status --porcelain 2^>nul') do (
    set "has_change=1"
    goto :eof
)
exit /b