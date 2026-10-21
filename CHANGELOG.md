# 更新记录

## v1.1.0 — 2026-10-21

**新增日志功能。**

- 每次运行追加写磁盘日志：`%LOCALAPPDATA%\PCL2PatchTool\logs\PCL2PatchTool-yyyyMMdd.log`（UTF-8 带 BOM，按天分文件）
- 界面日志框的每行都落盘，另加启动环境（版本 / 系统 build / PowerShell 版本 / 进程路径）、异常类型 + 位置 + 完整堆栈、退出时间
- 单文件超过 2 MB 自动轮转为 `.log.1`（保留一代）
- 新增「打开日志」按钮：在资源管理器里选中当天日志
- 新增 `-LogDir` 参数，可改日志目录；目录不可写时退化为只显示界面日志，不影响主流程
- 异常改为走 `Add-LogError`：界面上仍是一句话，磁盘里留完整堆栈
- 窗口标题与 exe 版本号现在带版本（`v1.1.0`）；exe 由 `build-exe.ps1 -version` 写入 FileVersion

## v1.0.0 — 2026-10-21

首个公开版本。

- 适配 PCL2 `2.99.0.0` (Build 413)，原版 MD5 `d6a946a007f8e84a8bfb0e239868f91a`
- 补丁点 `0x2C0DA`：48 字节 `newobj LoaderTask(抛异常 lambda)` → `ldsfld DlClientListLoader` + 43 × `nop`
- GUI（`src/PCL2PatchGUI.ps1` + `src/PCL2补丁工具.vbs`）：打补丁 / 刷新状态 / 还原原版
- 安全措施：精确特征 + 唯一命中断言、首次自动 `.bak` 备份、写盘回读校验、失败自动回滚、判重
- 命令行参数 `$PclPath`：直接指定目标 exe，跳过自动查找
- `build/build-exe.ps1`：ps2exe 1.0.18 打单文件无控制台 exe（`-noConsole -STA`）
- 文档：`docs/technical.md`（dnfile + dncil 定位过程、`ldnull` 参数陷阱、验证步骤）、`docs/代码说明.md`

已知限制：

- 不修「整合包下载」（该实现被编译期常量裁掉，exe 里不存在）
- PCL2 自动更新到新版本后会覆盖主程序，补丁失效，需要重新适配 token
