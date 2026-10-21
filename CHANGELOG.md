# 更新记录

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
