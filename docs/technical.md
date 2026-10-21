# 定位这 48 字节的过程

以 PCL2 `2.99.0.0` (Build 413)、原版 MD5 `d6a946a007f8e84a8bfb0e239868f91a` 为例。
目标是**从源码出发找位置**，而不是在 exe 里瞎猜字节。

## 1. 先确认是哪道门

跑 PCL2，看 `PCL\PCL\Log*.txt`：

```
加载线程 关闭下载 出错：为遵守相关法律法规……
   在 PCL.PageDownloadInstall._Closure$__…
```

⇒ 就是 `LoaderInit` 里那一个点，不是别的地方在拦。

## 2. 拿到官方源码（关键，别靠猜 IL）

源码在 GitHub `Meloong-Git/PCL`，tag 就是版本号（如 `2.99.0.0`）：

- `Plain Craft Launcher 2/Pages/PageDownload/PageDownloadInstall.xaml.vb`
- `Plain Craft Launcher 2/Modules/ModSecret.vb`

`codeload.github.com` 在部分地区常被墙，可用镜像：

```
https://ghfast.top/https://github.com/Meloong-Git/PCL/archive/refs/tags/2.99.0.0.zip
```

读到的结论：

```vb
' PageDownloadInstall.xaml.vb
If RestrictMcDownload Then
    New LoaderTask(Of String, DlClientListResult)("关闭下载", Sub() Throw New Exception("…"))
Else
    DlClientListLoader
End If

' ModSecret.vb
Public Const RestrictMcDownload As Boolean = True
```

`Const` 是编译期常量 ⇒ `Else` 分支和整合包的真实实现**根本没编进 exe**。

## 3. 在 exe 里定位

PCL2 是未混淆的 VB.NET，用 `dnfile` + `dncil` 就能读（无需专门反编译器）：

```bash
uv run --with dnfile --with dncil python3 locate.py "Plain Craft Launcher 2.exe"
```

步骤：

1. 扫整张 `ldstr` 表，命中「为遵守相关法律法规」的字符串 → 找到引用它的方法。
   同样的字符串会出现在 3 个地方：
   - `FormMain.ShowUpdateLog`（只是文本）
   - `ModModpack.ModpackInstall`（方法体被削成只剩提示）
   - 一个 tiny lambda（真正的 `Throw`）
   - 以及 `PageDownloadInstall.LoaderInit` 里的构造点
2. 要改的是 **`LoaderInit` 里构造假 LoaderTask 的那一段**，不是整个调用。
3. 2.99 的 IL 形态：

```
... get_PanAllBack            ; 第 3 个参数
    ldnull                    ; 第 4 个参数（不要动）
    ldstr "关闭下载"
    ldsfld <delegate cache>
    brfalse.s / br.s
    ldftn <throw-lambda>
    newobj Action
    dup ; stsfld <cache>
    ldnull ; ldc.i4.2
    newobj LoaderTask         ; ← 到这儿结束，共 48 字节
    ldarg.0 ; ldftn finish
    newobj Action
    ldnull ; ldc.i4.1
    call PageLoaderInit(7 参)
```

4. 按名字从 Field 表取 `DlClientListLoader` 的 token（0x0400040F），并确认它的类型是
   `LoaderTask`2<string, DlClientListResult>` —— 必须与 `PageLoaderInit` 第 5 个形参一致，
   传 `LoaderCombo` 之类不兼容类型会在运行时炸。
5. 写回：`7E 0F 04 00 04`（`ldsfld`）＋ 43 个 `00`（`nop`）。

## 4. 两个容易翻车的点

**`ldnull` 不属于这 48 字节。** 它是 `PageLoaderInit` 的第 4 个参数；一起吞掉会让栈/参数错位，
症状是 `System.InvalidProgramException`（"公共语言运行时检测到无效的程序"），在 `LoaderInit` 抛出。

**dncil 的指令 offset 含方法体头。** fat 头首指令 offset 是 `0x0c`，
文件偏移 = `body_start + ilOffset`，别直接拿 `ilOffset` 当文件偏移。

**宽松通配模式会命中 3 处。** 所以工具先精确匹配、要求唯一命中；宽泛模式只在精确模式
落空时兜底，且同样要求唯一。

## 5. 验证（改完必须真跑）

- 拷贝到别处跑不行：PCL 从 `%TEMP%` 启动会弹「意料外的等待弹窗：我知道了」后退出 —— 必须在原目录改。
- 启动后日志里 `关闭下载` 不再报错，`DlClientList Mojang … Finished` 照常出现。
- 界面点顶部「下载」→ 应出现「最新版本 26.3 / 26.4-snapshot」+ 正式版/预览版/远古版/愚人节版。
- 点某版本 → 版本名输入框 + Forge/NeoForge/Fabric/OptiFine 卡片 +「开始下载」；
  点下去后台日志出现 `[ModNet] … resources.download.minecraft.net` 与
  `versions\<ver>\<ver>.json`。

## 6. 适配到别的版本

`src/PCL2PatchGUI.ps1` 顶部常量区是唯一要改的地方：

| 变量 | 作用 |
|---|---|
| `$SigExact` | 目标版本里那 48 字节的精确内容（含 token） |
| `$SigLoose` | 同形状但 token 位用 `-1` 通配的兜底特征 |
| `$Replacement` | 替换内容，第 5 字节起补 `nop`，长度必须与 `$SigExact` 相同 |
| `$KnownVersion` / `$KnownMd5` | 用于「文件与预期不一致」的提示 |
