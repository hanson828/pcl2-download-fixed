#Requires -Version 5.1
# =====================================================================
#  PCL2 下载功能解锁补丁 —— GUI 版源码
#
#  目标程序：Plain Craft Launcher 2  2.99.0.0 (Build 413)
#            原版 MD5 d6a946a007f8e84a8bfb0e239868f91a，5980160 字节
#
#  ── 为什么需要补丁 ──────────────────────────────────────────────────
#  2.99 的官方源码（Plain Craft Launcher 2\Pages\PageDownload\
#  PageDownloadInstall.xaml.vb 第 17 行）写的是：
#
#      If RestrictMcDownload Then
#          PageLoaderInit(LoadMinecraft, PanLoad, PanAllBack, Nothing,
#              New LoaderTask(Of String, DlClientListResult)("关闭下载",
#                  Sub() Throw New Exception("为遵守相关法律法规……")),
#              AddressOf LoadMinecraft_OnFinish)
#      Else
#          PageLoaderInit(..., Nothing, DlClientListLoader, ...)
#      End If
#
#  而 Modules\ModSecret.vb 第 18 行是
#      Public Const RestrictMcDownload As Boolean = True
#  它是编译期常量，所以 Else 分支被编译器整段删除，exe 里只剩那个
#  “一执行就抛异常”的假加载器。于是「下载 → 原版游戏」永远是加载失败。
#
#  ── 怎么补 ──────────────────────────────────────────────────────────
#  在 LoaderInit 里，把「构造假 LoaderTask」的那 48 字节 IL 整体换成
#  「ldsfld DlClientListLoader + 43 个 nop」：
#      ldsfld PCL.ModDownload::DlClientListLoader   (字段 token 0x0400040F)
#  字节数完全不变 → 方法体长度、RVA、元数据都不用动，也不改版本号，
#  所以 PCL 不会以为自己是旧版而重新自我更新。
#
#  注意：这 48 字节**不包含**前面那个 ldnull —— 它是 PageLoaderInit 的
#  第 4 个参数，一起吞掉会造成参数错位，运行时抛 InvalidProgramException。
#
#  补丁点：0x2C0DA（413 版）    长度 48 字节
#  原版：72 33 47 01 70 7E FB 09 00 04 2C 07 ... 73 8E 05 00 0A
#  补丁：7E 0F 04 00 04 00 00 ... 00（共 43 个 00）
#
#  ── 界面 ────────────────────────────────────────────────────────────
#  双击「PCL2补丁工具.vbs」启动（无黑框）；也可以直接
#      powershell -NoProfile -ExecutionPolicy Bypass -File 本文件
#
#  ── 日志 ────────────────────────────────────────────────────────────
#  每次运行都会在 %LOCALAPPDATA%\PCL2PatchTool\logs\ 下按天追加日志
#  （PCL2PatchTool-yyyyMMdd.log，UTF-8），界面日志框里的内容全部落盘，
#  另外记录启动环境、完整异常堆栈和每次操作结果。超过 2 MB 自动轮转成 .log.1。
#  想换目录：给 -LogDir 传参数。
# =====================================================================

param(
    [string]$PclPath = '',
    [string]$LogDir  = ''
)

$script:ToolVersion = '1.1.0'
$script:LogMaxBytes  = 2MB

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- 常量
# 原版里「假加载器」的精确 48 字节
$SigExact = [byte[]](
    0x72,0x33,0x47,0x01,0x70,                       # ldstr "关闭下载"
    0x7E,0xFB,0x09,0x00,0x04,                       # ldsfld <delegate cache>
    0x2C,0x07,                                      # brfalse.s
    0x7E,0xFB,0x09,0x00,0x04,
    0x2B,0x16,                                      # br.s
    0x7E,0xF9,0x09,0x00,0x04,
    0xFE,0x06, 0x67,0x14,0x00,0x06,                 # ldftn <抛异常的 lambda>
    0x73,0x8D,0x05,0x00,0x0A,                       # newobj Action
    0x25,0x80,0xFB,0x09,0x00,0x04,                  # dup / stsfld 缓存
    0x14,0x18,                                      # ldnull / ldc.i4.2
    0x73,0x8E,0x05,0x00,0x0A                        # newobj LoaderTask
)
# 同样的特征，但 Token 位置用 -1 通配，用于别人重编译过的版本兜底
$SigLoose = @(
    0x72,-1,-1,-1,0x70,  0x7E,-1,-1,-1,-1,  0x2C,0x07,
    0x7E,-1,-1,-1,-1,    0x2B,0x16,         0x7E,-1,-1,-1,-1,
    0xFE,0x06,           -1,-1,-1,-1,       0x73,-1,-1,-1,-1,
    0x25,0x80,-1,-1,-1,-1,  0x14,0x18,      0x73,-1,-1,-1,-1
)
# 替换内容：ldsfld DlClientListLoader + nop 填充
$Replacement = [byte[]](0x7E,0x0F,0x04,0x00,0x04) + [byte[]]::new($SigExact.Count - 5)

$KnownVersion = '2.99.0.0'
$KnownMd5     = 'd6a946a007f8e84a8bfb0e239868f91a'

$script:PclExe = ''

# ---------------------------------------------------------------- 日志
# 界面日志框 + 磁盘日志两条腿：界面给当下看，磁盘给事后查
$script:LogWriter = $null
$script:LogFile   = $null

function Initialize-Log([string]$Dir) {
    if (-not $Dir) { $Dir = Join-Path $env:LOCALAPPDATA 'PCL2PatchTool\logs' }
    try {
        if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
        $path = Join-Path $Dir ('PCL2PatchTool-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))

        # 单文件超过 2 MB 就轮转成 .1（只留一代，够排错又不占地方）
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Length -gt $script:LogMaxBytes)) {
            $rotated = "$path.1"
            if (Test-Path -LiteralPath $rotated) { Remove-Item -LiteralPath $rotated -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $path -Destination $rotated -Force -ErrorAction SilentlyContinue
        }

        # 追加模式 + UTF-8 BOM：文件在当前位置追加时不会再写 BOM
        $script:LogWriter = New-Object System.IO.StreamWriter(
            $path, $true, (New-Object System.Text.UTF8Encoding($true)))
        $script:LogWriter.AutoFlush = $true
        $script:LogFile = $path
    } catch {
        $script:LogWriter = $null
        $script:LogFile = $null
        return
    }

    # 启动环境，排错时最先看的就是这一段
    $osInfo = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $osText = if ($osInfo -and $osInfo.CurrentBuild) {
        # Win11 的注册表 ProductName 仍写着 Windows 10，按 build 号纠正
        $osName = $osInfo.ProductName
        if ([int]$osInfo.CurrentBuild -ge 22000 -and $osName -like 'Windows 10*') {
            $osName = $osName -replace '^Windows 10', 'Windows 11'
        }
        '{0} (build {1}.{2})' -f $osName, $osInfo.CurrentBuild, $osInfo.UBR
    } else { [Environment]::OSVersion.VersionString }

    $sep = '=' * 68
    foreach ($line in @(
        '', $sep,
        ('PCL2 补丁工具 v{0}    启动' -f $script:ToolVersion),
        ('时间      : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')),
        ('系统      : {0}  ({1})' -f $osText, [Environment]::MachineName),
        ('PowerShell: {0}' -f $PSVersionTable.PSVersion),
        ('工具路径  : {0}' -f $(if ($PSCommandPath) { $PSCommandPath } else { '(exe 内嵌脚本)' })),
        ('进程      : {0}' -f (Get-Process -Id $PID).Path),
        ('日志文件  : {0}' -f $script:LogFile),
        $sep
    )) { $script:LogWriter.WriteLine($line) }
}

function Write-LogFile([string]$line) {
    if (-not $script:LogWriter) { return }
    try { $script:LogWriter.WriteLine($line) } catch { $script:LogWriter = $null }
}

function Close-Log {
    if (-not $script:LogWriter) { return }
    try { $script:LogWriter.Flush(); $script:LogWriter.Dispose() } catch { }
    $script:LogWriter = $null
}

# ---------------------------------------------------------------- 工具函数
function Add-Log([string]$text) {
    $now = Get-Date
    Write-LogFile(('[{0}] {1}' -f $now.ToString('HH:mm:ss'), $text))
    if ($script:LogBox) {
        $script:LogBox.AppendText(('[{0}] {1}{2}' -f $now.ToString('HH:mm:ss'), $text, "`r`n"))
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# 异常：界面只显示一句话，磁盘里存完整堆栈
function Add-LogError([string]$prefix, $err) {
    Add-Log($prefix + $err.Exception.Message)
    if (-not $script:LogWriter) { return }
    Write-LogFile('    ' + $err.Exception.GetType().FullName + ': ' + $err.Exception.Message)
    if ($err.InvocationInfo -and $err.InvocationInfo.PositionMessage) {
        Write-LogFile('    位置: ' + ($err.InvocationInfo.PositionMessage -replace "`r?`n", ' '))
    }
    if ($err.ScriptStackTrace) {
        Write-LogFile('    堆栈: ' + ($err.ScriptStackTrace -replace "`r?`n", ' <== '))
    }
}

function Set-Status([string]$text, [string]$htmlColor) {
    $script:StatusLabel.Text = '状态：' + $text
    $script:StatusLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($htmlColor)
}

function Find-PclExe {
    param([string]$Hint)

    if ($Hint -and (Test-Path -LiteralPath $Hint)) { return (Resolve-Path -LiteralPath $Hint).Path }

    $candidates = @(
        'E:\Program Files\PCL2\Plain Craft Launcher 2.exe',
        'C:\Program Files\PCL2\Plain Craft Launcher 2.exe',
        'D:\Program Files\PCL2\Plain Craft Launcher 2.exe',
        'F:\Program Files\PCL2\Plain Craft Launcher 2.exe',
        'D:\PCL2\Plain Craft Launcher 2.exe',
        'E:\PCL2\Plain Craft Launcher 2.exe',
        "$env:USERPROFILE\Desktop\PCL2\Plain Craft Launcher 2.exe",
        "$env:USERPROFILE\Documents\PCL2\Plain Craft Launcher 2.exe"
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }

    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Free } | Select-Object -ExpandProperty Root)) {
        try {
            $hit = Get-ChildItem -LiteralPath $d -Filter 'Plain Craft Launcher 2.exe' -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($hit) { return $hit.FullName }
        } catch { }
    }
    return $null
}

function Find-Match {
    param([byte[]]$Bytes, [int[]]$Pattern)
    $n = $Pattern.Count
    $hits = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -le $Bytes.Length - $n; $i++) {
        if ($Bytes[$i] -ne $Pattern[0]) { continue }
        $ok = $true
        for ($j = 1; $j -lt $n; $j++) {
            $p = $Pattern[$j]
            if ($p -ge 0 -and $Bytes[$i + $j] -ne $p) { $ok = $false; break }
        }
        if ($ok) { $hits.Add($i); if ($hits.Count -gt 5) { break } }
    }
    return ,$hits.ToArray()
}

function Find-Patched {
    param([byte[]]$Bytes)
    for ($i = 0; $i -le $Bytes.Length - 48; $i++) {
        if ($Bytes[$i] -ne 0x7E -or $Bytes[$i+1] -ne 0x0F -or $Bytes[$i+2] -ne 0x04 -or
            $Bytes[$i+3] -ne 0x00 -or $Bytes[$i+4] -ne 0x04) { continue }
        $z = 0
        for ($k = 5; $k -lt 48; $k++) {
            if ($Bytes[$i + $k] -eq 0) { $z++ } else { break }
        }
        if ($z -ge 43) { return $i }
    }
    return -1
}

function Get-PclInfo {
    param([string]$Exe)
    $item = Get-Item -LiteralPath $Exe
    [pscustomobject]@{
        Path    = (Resolve-Path -LiteralPath $Exe).Path
        Version = $item.VersionInfo.FileVersion
        MD5     = (Get-FileHash -LiteralPath $Exe -Algorithm MD5).Hash.ToLower()
        Size    = $item.Length
        Backup  = "$Exe.bak"
    }
}

function Stop-PclIfRunning {
    param([string]$Exe)
    $procs = @(Get-Process -Name 'Plain Craft Launcher 2' -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch { }
        (-not $p) -or ($p -eq $Exe)
    })
    if ($procs.Count -eq 0) { return $true }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "PCL2 正在运行，必须先关闭它才能改动主程序。`r`n`r`n现在帮你关闭吗？",
        'PCL2 补丁工具', 'YesNo', 'Question')
    if ($r -ne 'Yes') { Add-Log '已取消（PCL2 仍在运行）'; return $false }
    $procs | Stop-Process -Force
    Start-Sleep -Seconds 2
    Add-Log '已关闭 PCL2'
    return $true
}

# ---------------------------------------------------------------- 三个动作
function Do-Check {
    if (-not (Test-Path -LiteralPath $script:PclExe)) { Add-Log '没有找到 PCL2 主程序'; Set-Status '找不到程序' '#C00000'; return }
    try {
        $info = Get-PclInfo $script:PclExe
        $bytes = [System.IO.File]::ReadAllBytes($script:PclExe)
        $at = Find-Patched $bytes
        $script:InfoLabel.Text = "版本 $($info.Version)   大小 $($info.Size)   MD5 $($info.MD5)"
        if ($at -ge 0) {
            Set-Status "已打补丁（0x$($at.ToString('X'))）" '#1E7D32'
            Add-Log "已打补丁，补丁点 0x$($at.ToString('X'))"
        } else {
            $hit = Find-Match $bytes $SigExact
            if ($hit.Count -eq 1) {
                Set-Status "未打补丁（补丁点 0x$($hit[0].ToString('X'))）" '#B26A00'
                Add-Log "未打补丁，可补丁点 0x$($hit[0].ToString('X'))"
            } else {
                Set-Status '未知（没有匹配到特征码）' '#C00000'
                Add-Log '没有匹配到特征码：可能是别的 PCL 版本，或文件已被改动'
            }
        }
    } catch {
        Set-Status '读取失败' '#C00000'
        Add-LogError('读取失败：', $_)
    }
}

function Do-Apply {
    if (-not (Test-Path -LiteralPath $script:PclExe)) { Add-Log '没有找到 PCL2 主程序'; return }
    if (-not (Stop-PclIfRunning $script:PclExe)) { return }

    $exe = $script:PclExe
    $info = Get-PclInfo $exe
    $bytes = [System.IO.File]::ReadAllBytes($exe)

    $at = Find-Patched $bytes
    if ($at -ge 0) {
        Add-Log "已经是打过补丁的状态（0x$($at.ToString('X'))），无需重复操作"
        Set-Status "已打补丁（0x$($at.ToString('X'))）" '#1E7D32'
        return
    }

    $hits = Find-Match $bytes $SigExact
    if ($hits.Count -ne 1) {
        $loose = Find-Match $bytes $SigLoose
        if ($loose.Count -eq 1) { $hits = $loose }
    }
    if ($hits.Count -eq 0) {
        Add-Log '没有找到可补丁的特征码（文件未改动）。可能 PCL 已自动更新到新版本'
        Set-Status '不支持该版本' '#C00000'
        [System.Windows.Forms.MessageBox]::Show(
            "这个 PCL2 找不到可补丁的特征码，文件没有改动。`r`n`r`n常见原因：PCL 自动更新到了新版本，`r`n或主程序被别的工具改过。`r`n`r`n本工具适配：2.99.0.0 (Build 413)",
            'PCL2 补丁工具', 'OK', 'Warning') | Out-Null
        return
    }
    if ($hits.Count -gt 1) {
        Add-Log "特征码出现 $($hits.Count) 处，无法安全确定位置，已中止"
        Set-Status '中止（特征码不唯一）' '#C00000'
        return
    }
    $sig = $hits[0]

    if ($info.MD5 -ne $KnownMd5) {
        Add-Log "提示：MD5 与已知的 $KnownVersion 不完全一致，但特征码唯一匹配，继续"
    }

    try {
        if (-not (Test-Path -LiteralPath $info.Backup)) {
            Copy-Item -LiteralPath $exe -Destination $info.Backup -Force
            Add-Log "已备份原文件 → $($info.Backup)"
        } else {
            Add-Log "已存在备份，保留不覆盖：$($info.Backup)"
        }

        for ($i = 0; $i -lt $Replacement.Length; $i++) { $bytes[$sig + $i] = $Replacement[$i] }
        [System.IO.File]::WriteAllBytes($exe, $bytes)

        $check = [System.IO.File]::ReadAllBytes($exe)
        $ok = $true
        for ($i = 0; $i -lt $Replacement.Length; $i++) {
            if ($check[$sig + $i] -ne $Replacement[$i]) { $ok = $false; break }
        }
        if ($ok) {
            $newMd5 = (Get-FileHash -LiteralPath $exe -Algorithm MD5).Hash.ToLower()
            Add-Log "补丁写入成功：0x$($sig.ToString('X'))，$($Replacement.Length) 字节，新 MD5 $newMd5"
            Set-Status "已打补丁（0x$($sig.ToString('X'))）" '#1E7D32'
            $script:InfoLabel.Text = "版本 $((Get-Item -LiteralPath $exe).VersionInfo.FileVersion)   大小 $($info.Size)   MD5 $newMd5"
            [System.Windows.Forms.MessageBox]::Show(
                "补丁成功！`r`n`r`n现在打开 PCL2 →「下载」→「原版游戏」，`r`n版本列表就回来了，选版本点「开始下载」即可。",
                'PCL2 补丁工具', 'OK', 'Information') | Out-Null
        } else {
            Add-Log '校验失败，正在回滚……'
            if (Test-Path -LiteralPath $info.Backup) { Copy-Item -LiteralPath $info.Backup -Destination $exe -Force }
            Add-Log '已回滚到备份'
            Set-Status '失败（已回滚）' '#C00000'
        }
    } catch {
        Add-LogError('出错：', $_)
        Set-Status '出错' '#C00000'
    }
}

function Do-Restore {
    if (-not (Test-Path -LiteralPath $script:PclExe)) { Add-Log '没有找到 PCL2 主程序'; return }
    $info = Get-PclInfo $script:PclExe
    if (-not (Test-Path -LiteralPath $info.Backup)) {
        Add-Log '没有备份文件 .bak，无法还原'
        [System.Windows.Forms.MessageBox]::Show('没有找到备份文件：' + "`r`n" + $info.Backup, 'PCL2 补丁工具', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not (Stop-PclIfRunning $script:PclExe)) { return }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "确定要从备份还原成原版吗？`r`n（补丁会被撤销，下载功能会再次不可用）",
        'PCL2 补丁工具', 'YesNo', 'Question')
    if ($r -ne 'Yes') { Add-Log '已取消还原'; return }
    try {
        Copy-Item -LiteralPath $info.Backup -Destination $script:PclExe -Force
        $md5 = (Get-FileHash -LiteralPath $script:PclExe -Algorithm MD5).Hash.ToLower()
        Add-Log "已从备份还原，MD5 $md5"
        Do-Check
    } catch {
        Add-LogError('还原失败：', $_)
    }
}

# ---------------------------------------------------------------- 界面
$form = New-Object System.Windows.Forms.Form
$form.Text = ('PCL2 下载解锁补丁 v{0}' -f $script:ToolVersion)
$form.ClientSize = New-Object System.Drawing.Size(640, 500)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 253)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'PCL2 下载功能解锁补丁'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
$title.SetBounds(20, 16, 600, 32)
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = '把 2.99 版被换成「抛异常」的假加载器改回 DlClientListLoader —— 48 字节 IL 手术，不改变版本号'
$sub.ForeColor = [System.Drawing.Color]::Gray
$sub.SetBounds(22, 50, 600, 20)
$form.Controls.Add($sub)

$gbPath = New-Object System.Windows.Forms.GroupBox
$gbPath.Text = 'PCL2 主程序'
$gbPath.SetBounds(20, 78, 600, 68)
$form.Controls.Add($gbPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.SetBounds(14, 28, 470, 26)
$gbPath.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '浏览…'
$btnBrowse.SetBounds(494, 27, 90, 28)
$gbPath.Controls.Add($btnBrowse)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = '状态：检查中…'
$script:StatusLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
$script:StatusLabel.SetBounds(24, 158, 590, 26)
$form.Controls.Add($script:StatusLabel)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = '打补丁'
$btnApply.SetBounds(24, 194, 130, 40)
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(25, 118, 210)
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.FlatStyle = 'Flat'
$btnApply.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnApply)

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = '刷新状态'
$btnCheck.SetBounds(162, 194, 110, 40)
$form.Controls.Add($btnCheck)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = '还原原版'
$btnRestore.SetBounds(280, 194, 110, 40)
$form.Controls.Add($btnRestore)

$btnLog = New-Object System.Windows.Forms.Button
$btnLog.Text = '打开日志'
$btnLog.SetBounds(398, 194, 110, 40)
$form.Controls.Add($btnLog)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = '退出'
$btnClose.SetBounds(516, 194, 100, 40)
$form.Controls.Add($btnClose)

$gbLog = New-Object System.Windows.Forms.GroupBox
$gbLog.Text = '日志'
$gbLog.SetBounds(20, 246, 600, 208)
$form.Controls.Add($gbLog)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Multiline = $true
$script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.BackColor = [System.Drawing.Color]::White
$script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:LogBox.SetBounds(12, 24, 576, 172)
$gbLog.Controls.Add($script:LogBox)

$script:InfoLabel = New-Object System.Windows.Forms.Label
$script:InfoLabel.Text = ''
$script:InfoLabel.ForeColor = [System.Drawing.Color]::Gray
$script:InfoLabel.SetBounds(22, 462, 600, 20)
$form.Controls.Add($script:InfoLabel)

# ---------------------------------------------------------------- 事件
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'PCL2 主程序 (Plain Craft Launcher 2.exe)|Plain Craft Launcher 2.exe|可执行文件 (*.exe)|*.exe'
    $dlg.Title = '选择 Plain Craft Launcher 2.exe'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:PclExe = $dlg.FileName
        $txtPath.Text = $script:PclExe
        Add-Log "已选择：$($script:PclExe)"
        Do-Check
    }
})

$btnCheck.Add_Click({ Do-Check })
$btnApply.Add_Click({ Do-Apply })
$btnRestore.Add_Click({ Do-Restore })
$btnClose.Add_Click({ $form.Close() })

# 打开日志：在资源管理器里定位到当天日志文件（选中，不是只开目录）
$btnLog.Add_Click({
    if (-not $script:LogFile -or -not (Test-Path -LiteralPath $script:LogFile)) {
        [System.Windows.Forms.MessageBox]::Show(
            "还没有生成日志文件，可能没有写入权限。`r`n`r`n默认目录：`r`n" +
                (Join-Path $env:LOCALAPPDATA 'PCL2PatchTool\logs'),
            'PCL2 补丁工具', 'OK', 'Warning') | Out-Null
        return
    }
    Add-Log "打开日志：$($script:LogFile)"
    Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $script:LogFile)
})

$form.Add_FormClosed({
    Add-Log '工具退出'
    Close-Log
})

$form.Add_Shown({
    Initialize-Log -Dir $LogDir
    if ($script:LogFile) {
        Add-Log "日志文件：$($script:LogFile)"
    } else {
        Add-Log '写日志失败（目录不可写？），只保留界面日志'
    }
    Add-Log '正在查找 PCL2 …'
    $found = Find-PclExe -Hint $PclPath
    if ($found) {
        $script:PclExe = $found
        $txtPath.Text = $found
        Add-Log "找到：$found"
        Do-Check
    } else {
        Add-Log '没有自动找到 PCL2，请点「浏览…」手动选择'
        Set-Status '请选择 PCL2 主程序' '#C00000'
    }
})

[void]$form.ShowDialog()
