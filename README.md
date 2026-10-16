# KCSM systemd Watchdog 最小实验

**完全独立的仓库。** 模拟 KCSM（不包含真正的 corosync/pacemaker/qdevice 检测）。

## 四个关键文件

- `kcsm_demo.c`：C 进程，每秒发送 `WATCHDOG=1`；收到 SIGUSR1 后仍然存活，但不再发送通知。
- `kcsm_demo.service`：`WatchdogSec=6s` 和 `Restart=on-failure`。
- `test.sh`：在 Ubuntu systemd 主机上安装、运行、注入 Hang/Crash、检查重启并自动清理。
- `.github/workflows/watchdog-test.yml`：可手动触发的 GitHub Actions 工作流。

## 推荐运行方式：GitHub Actions

1. 在 GitHub 创建一个**新的**仓库，例如 `kcsm-systemd-watchdog-test`，勾选 `Add a README file`。
2. 在该仓库选择 **Code → Codespaces → Create codespace on main**。
3. 在 Codespaces 左侧 Explorer 中上传本 ZIP 到仓库根目录，在终端执行：

   ```bash
   python3 -m zipfile -e kcsm-watchdog-new-repo.zip .
   git add kcsm_demo.c kcsm_demo.service test.sh README.md .github/workflows/watchdog-test.yml
   git commit -m "Add systemd Watchdog minimal demo"
   git push origin main
   ```

   提醒：解压会覆盖仓库的默认 `README.md`，这是预期行为；全新仓库里没有其他项目文件。
4. 打开仓库的 **Actions** → **KCSM systemd Watchdog test** → **Run workflow**。
5. 点击该次运行 → `watchdog` Job → `Run Hang and Crash verification`，查找：

   ```text
   PASS: Hang -> Watchdog timeout -> restart
   PASS: Crash -> restart
   ========== ALL TESTS PASSED ==========
   ```

   工作流运行在 `ubuntu-24.04` 的 GitHub 托管 VM 上，要求 PID 1 是 systemd。不要改为 `ubuntu-slim` 或 `container:` Job。

## 程序/服务参数

- C 程序每秒完成一次“模拟监控”，然后发送 `WATCHDOG=1`。
- `Type=notify`，程序启动时先发送 `READY=1`。
- `WatchdogSec=6s`，停止健康通知超过阈值则由 systemd 触发故障处理。
- `Restart=on-failure`，模拟 Hang 和 SIGKILL 后尝试重启。

**这只是运行机制验证，不等于能自动检测 KCSM 任意局部线程 Hang。** 真正接入 KCSM 时，需要把 `WATCHDOG=1` 绑定到实际关键监控逻辑的正常推进。

## 本地 Linux VM 运行（可选）

适用于 PID 1 为 systemd 的 Ubuntu 24.04，执行 `bash test.sh`，会安装依赖、启动演示服务、注入故障和清理。

## 排错

- `PID 1 is not systemd`：不要在 Codespaces 外层开发容器直接执行 `test.sh`，请使用 GitHub Actions Job。
- Actions 没有 `Run workflow`：确认工作流位于默认 `main` 分支并且含 `workflow_dispatch`。
- `Watchdog is not enabled`：确认由 `systemctl` 启动服务且 `WatchdogSec` 有效。
- 失败时脚本自动输出最近的 `journalctl` 日志供排查。
