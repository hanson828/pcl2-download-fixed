#Requires -Version 5.1
<#
    build/build-exe.ps1 —— 把 src/PCL2PatchGUI.ps1 打成单文件无控制台 exe

    用法（在仓库根目录、PowerShell 里）：
        powershell -NoProfile -ExecutionPolicy Bypass -File build\build-exe.ps1
        powershell -NoProfile -ExecutionPolicy Bypass -File build\build-exe.ps1 -OutputPath D:\x\PCL2补丁工具.exe

    依赖：ps2exe 1.0.18 —— 脚本会自己从 PowerShell Gallery 的 API 下 nupkg 解压，
          不走 Install-Module（PowerShellGet 1.0.0.1 上 Install-NuGetClientBinaries 会挂）。
    产物依赖本机 .NET Framework 4.x 的 csc 编译（Win10/Win11 自带）。

    注意：
      - -STA 必须显式给：非 STA 时「浏览…」的 OpenFileDialog 会报 OLE 单元线程错误。
      - -noConsole 才输出 winexe（无黑框）。
      - 产物容易被杀软/SmartScreen 启发式误报，分发时写清「右键属性 → 解除锁定」。
#>
param([string]$OutputPath = '')

$ErrorActionPreference = 'Stop'
$ps2exeVersion = '1.0.18'

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src\PCL2PatchGUI.ps1'
if (-not (Test-Path -LiteralPath $src)) { throw "找不到源码：$src" }
if (-not $OutputPath) { $OutputPath = Join-Path $root 'dist\PCL2补丁工具.exe' }

# ---- 准备 ps2exe 模块 -------------------------------------------------
$work = Join-Path $env:TEMP "ps2exe-$ps2exeVersion"
$manifest = Join-Path $work 'ps2exe.psd1'
if (-not (Test-Path -LiteralPath $manifest)) {
    Write-Host "下载 ps2exe $ps2exeVersion ..."
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $nupkg = Join-Path $work 'ps2exe.zip'      # nupkg 就是 zip，扩展名给 Expand-Archive 认
    Invoke-WebRequest -Uri "https://www.powershellgallery.com/api/v2/package/ps2exe/$ps2exeVersion" `
                      -OutFile $nupkg -UseBasicParsing
    Expand-Archive -LiteralPath $nupkg -DestinationPath $work -Force
}
if (-not (Test-Path -LiteralPath $manifest)) { throw "ps2exe 解压后找不到 $manifest" }
Import-Module $manifest -Force

# ---- 编译 -------------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }

Write-Host "编译：$src -> $OutputPath"
Invoke-PS2EXE -inputFile $src -outputFile $OutputPath -noConsole -STA -title 'PCL2 下载解锁补丁'

$item = Get-Item -LiteralPath $OutputPath
'完成：{0}（{1} 字节）' -f $item.FullName, $item.Length
