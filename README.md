# PCL2 下载解锁补丁 / PCL2 Download Unlock Patch

把 **Plain Craft Launcher 2 (PCL2) 2.99.0.0 (Build 413)** 里那个「一执行就抛异常」的假下载加载器，
用 **48 字节 IL 补丁**换回真正的 `DlClientListLoader`。

文件大小不变、版本号不变、随时可以一键还原。

> **直接下载**：[`PCL2PatchTool-v1.1.0.exe`](https://github.com/hanson828/pcl2-download-fixed/releases/latest) —— 单文件 GUI（57856 字节，SHA-256 `41b67aaa…927af1`），免安装，双击即用。不想跑 exe 就用下面的脚本版。


- Windows PowerShell 5.1 + WinForms，单个 `.ps1`，不依赖任何第三方模块
- 提供 GUI（打补丁 / 刷新状态 / 还原原版）和命令行参数
- 首次打补丁自动备份成 `.bak`，写完回读校验，失败自动回滚

---

## 背景：下载功能为什么会坏

PCL2 2.99 的官方源码
`Plain Craft Launcher 2/Pages/PageDownload/PageDownloadInstall.xaml.vb` 里是这样写的：

```vb
If RestrictMcDownload Then
    PageLoaderInit(LoadMinecraft, PanLoad, PanAllBack, Nothing,
        New LoaderTask(Of String, DlClientListResult)("关闭下载",
            Sub() Throw New Exception("为遵守相关法律法规……")),
        AddressOf LoadMinecraft_OnFinish)
Else
    PageLoaderInit(LoadMinecraft, PanLoad, PanAllBack, Nothing,
        DlClientListLoader, AddressOf LoadMinecraft_OnFinish)
End If
```

而 `Modules/ModSecret.vb` 里是：

```vb
Public Const RestrictMcDownload As Boolean = True
```

`Const` 是**编译期常量**，所以 `Else` 分支被编译器整段删除 —— 发出来的 exe 里只剩那个假加载器，
「下载 → 原版游戏」永远是加载失败。

## 补丁做了什么

在 `PageDownloadInstall.LoaderInit` 里，把「构造假 LoaderTask」的那 48 字节整体换成

```
ldsfld  PCL.ModDownload::DlClientListLoader     ; 7E 0F 04 00 04
nop × 43                                        ; 00 00 ...
```

字节数完全不变，方法体长度 / RVA / 元数据 / 版本号全都不用动 —— 所以 PCL 不会以为自己
是旧版而重新自我更新。

补丁点（413 版）：`0x2C0DA`，长度 48 字节：

| 区域 | 内容 |
|---|---|
| 原版 | `72 33 47 01 70` `7E FB 09 00 04` `2C 07` `7E FB 09 00 04` `2B 16` `7E F9 09 00 04` `FE 06 67 14 00 06` `73 8D 05 00 0A` `25 80 FB 09 00 04` `14 18` `73 8E 05 00 0A` |
| 补丁后 | `7E 0F 04 00 04` + 43 × `00` |

**注意**：这 48 字节**不包含**它前面那个 `ldnull`（`14`）—— 那是 `PageLoaderInit` 的第 4 个参数，
把它一起吞掉会造成参数错位，运行时抛 `InvalidProgramException`。

更细的定位过程（用 `dnfile` + `dncil` 反汇编、按名字拿字段 token）见 [docs/technical.md](docs/technical.md)。

## 适用范围

| | |
|---|---|
| 适配版本 | PCL2 `2.99.0.0` (Build 413) |
| 原版 MD5 | `d6a946a007f8e84a8bfb0e239868f91a`（5980160 字节） |
| 补丁后 MD5 | `617e6924888fa988495b5349109b1e6f` |
| 系统 | Windows + 自带 Windows PowerShell 5.1 / .NET Framework 4.x |

**不适用**：本补丁不修「整合包下载」。2.99 里 `ModpackInstall()` 的真实实现同样被
`Const` 裁掉了，exe 里根本没这段代码，改字节救不回来。

**会失效**：PCL2 自动更新到新版本后会覆盖主程序，补丁消失，需要按 docs 里的方法重新定位适配。
本工具在这种情况下会明确提示「没有找到可补丁的特征码」，不会乱改文件。

## 用法

### 方式一：启动器（无黑框）

```
src\PCL2补丁工具.vbs      ← 双击
```

`vbs` 用 `wscript` 以隐藏窗口调起同目录的 `PCL2PatchGUI.ps1`。

### 方式二：直接跑脚本

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src\PCL2PatchGUI.ps1
```

可以带一个参数，跳过自动查找：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src\PCL2PatchGUI.ps1 "D:\PCL2\Plain Craft Launcher 2.exe"
```

### 方式三：自己编一个单文件 exe

见 [build/build-exe.ps1](build/build-exe.ps1)（ps2exe 打包，`-noConsole -STA`）。

### 界面按钮

- **打补丁** —— 备份（仅首次）→ 写入 48 字节 → 回读校验 → 成功弹窗；校验失败自动回滚
- **刷新状态** —— 显示「已打补丁 / 未打补丁 / 未知」，附版本、大小、MD5（只读，不改文件）
- **还原原版** —— 从 `.bak` 还原（二次确认）
- **打开日志** —— 在资源管理器里定位到当天日志文件

PCL2 正在运行时工具会先问要不要帮你关掉 —— 主程序被占用时无法写入。

## 日志

每次运行都会写磁盘日志，路径：

```
%LOCALAPPDATA%\PCL2PatchTool\logs\PCL2PatchTool-yyyyMMdd.log
```

- 界面日志框里的每一行都会落盘，**另加**界面看不到的内容：启动环境（版本 / 系统 build / PowerShell 版本 / 进程路径）、异常的类型 + 位置 + 完整堆栈、退出时间
- 每天一个文件、UTF-8（带 BOM，记事本直接开）、追加写入，每次运行用一行 `====` 和启动信息分隔
- 单文件超过 2 MB 自动轮转成 `.log.1`（只留一代）
- 换目录：`powershell -File src\PCL2PatchGUI.ps1 -LogDir D:\logs`；目录不可写时只保留界面日志，不会因此崩溃

排错时的用法：出问题先点「打开日志」，把当天那个文件末尾的一次运行块发出来，比截图有用。

## 安全设计

| 措施 | 说明 |
|---|---|
| 精确特征码 | 默认用含 token 的精确 48 字节，命中数 ≠ 1 就中止 |
| 通配兜底 | 精确特征没命中时，才用 token 位通配的宽松特征，且同样要求唯一命中 |
| 唯一性检查 | 宽松模式在同一 exe 里会命中 3 处，所以绝不「看到就改」 |
| 判重 | 已经是 `7E 0F 04 00 04` + ≥43 个 `00` 就提示「已打补丁」，不重复写 |
| 备份 | 首次打补丁时复制为 `.bak`；已存在 `.bak` 时保留不覆盖（防止把补丁态当原版备份） |
| 回读校验 | 写盘后重新读取比对，不一致立即用 `.bak` 回滚 |
| MD5 提示 | 与已知版本 MD5 不同但特征码唯一时，只提示、不拒绝 |

## 常见问题

**打完补丁下载还是不行？**
先看 PCL 日志里是否还有 `关闭下载 出错`。如果补丁点又变回了原版字节，基本是 PCL 自更新覆盖了主程序 ——
`刷新状态` 会显示「未打补丁」。

**Windows 提示"已保护你的电脑" / 杀软报毒？**
脚本打包成 exe（PS2EXE）容易被启发式误报。右键 exe → 属性 → 勾选「解除锁定」→ 确定；
或者直接跑 `.ps1` 版本，不经过 exe。

**提示"没有找到可补丁的特征码"？**
说明主程序不是 2.99.0.0 (Build 413)，或者被别的工具改过。文件没有被改动 —— 换对应版本的
token 重新适配即可（见 docs/technical.md）。

**能对抗 PCL 的自动更新吗？**
不能。补丁只在当前 exe 里，服务器发新版本、PCL 复制自身更新后就会失效。这是设计使然 ——
打补丁不改版本号，所以同版本内不会反复触发更新。

## 免责声明

- 本项目是**本地二进制研究与教学示例**：演示如何定位一个 WPF/VB.NET 程序里的特定调用并做等长 IL 替换。
- 它**不包含**、**不提供**、**不分发**任何游戏本体或 Mojang 的下载内容；补丁效果只是让 PCL2 自己原有的下载逻辑重新可达。
- PCL2 的版权归原作者（LTCatt / 龙腾猫跃）所有；Minecraft 归 Mojang / Microsoft 所有。
- 请只修改**你自己拥有并有权修改**的副本，并自行确认你所在地区的法律法规允许你这么做。
  部分地区对游戏下载有合规要求 —— 若不适用，请勿使用。
- 使用本工具的风险（包括主程序损坏、更新失效、账号或合规风险）由使用者自行承担。

## 许可

本项目代码以 [MIT License](LICENSE) 发布。

## English

Minimal 48-byte IL patch for Plain Craft Launcher 2 `2.99.0.0` (Build 413). The official build
compiles `If RestrictMcDownload ... Else DlClientListLoader ... End If` with `RestrictMcDownload`
as a compile-time `Const = True`, so the real download loader is absent from the binary and
"Download → Vanilla" always fails.

The tool patches `PageDownloadInstall.LoaderInit` at `0x2C0DA`, replacing the 48-byte
`newobj LoaderTask(throwing lambda)` sequence with `ldsfld PCL.ModDownload::DlClientListLoader`
followed by 43 `nop`s. Same byte length → no size, RVA or version change. Backup, read-back
verification and automatic rollback are built in.

For local research/educational use on copies you own. Not affiliated with PCL2 or Mojang.
You are responsible for compliance with your local laws.
