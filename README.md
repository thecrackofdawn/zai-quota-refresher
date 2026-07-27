# 智谱 API 自动刷新工具

自动监控智谱 API 使用额度，当额度为 0 时自动触发刷新请求，启动 5 小时滚动恢复。

## 功能特性

- ✅ 自动监控 API 使用额度
- ✅ 额度为 0 时自动发送刷新请求
- ✅ 基于 cron 定时任务，轻量可靠
- ✅ 无需 root 权限，普通用户即可运行
- ✅ 一键部署，简单配置
- ✅ 日志自动滚动（单文件最大 1MB，保留 2 个备份）
- ✅ 零外部依赖，仅使用 Python 标准库

## 快速开始

### Linux 一键安装

**下载后执行（交互式）**

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/thecrackofdawn/zai-quota-refresher/main/deploy.sh -o deploy.sh

# 执行安装
chmod +x deploy.sh
./deploy.sh install
```

安装过程中会：
- 从 GitHub 拉取代码到 `~/.zai-quota-refresher`
- 交互式配置 API Key
- **交互式选择 cron 执行周期**（默认每天 0:00-23:59，每10分钟）
- 测试执行一次验证配置

### Windows 使用

```bash
# 1. 复制 config.default.json 为 config.json 并填入 API Key
# 2. 运行程序（无需安装依赖，仅使用 Python 标准库）
python quota_refresher.py
```

## 配置说明

配置文件 `config.json`：

```json
{
  "api_key": "你的智谱API_KEY",
  "log_file": "quota_refresher.log"
}
```

### 配置参数

- `api_key`: 智谱 API Key（必需）
- `log_file`: 日志文件路径（可选，默认为 `quota_refresher.log`）

### 定时任务配置

默认 cron 任务：每天 0:00-23:59，每 10 分钟执行一次（`*/10 0-23 * * *`）。安装时可从预设中交互选择，或输入自定义表达式。

如需事后修改执行时间，使用 `crontab -e` 编辑：

```bash
# 编辑定时任务
crontab -e

# 常用时间表达式示例：
*/30 * * * *           # 每30分钟（全天）
0 */2 * * *            # 每2小时（全天）
*/30 9-18 * * 1-5      # 工作日9-18点，每30分钟
*/10 9-18 * * *        # 每天9-18点，每10分钟
0 9,12,15,18 * * 1-5  # 工作日特定时间点
```

## 常用命令

```bash
./deploy.sh status    # 查看定时任务状态
./deploy.sh logs      # 查看实时日志
./deploy.sh config    # 编辑配置文件
./deploy.sh update    # 更新代码
./deploy.sh remove    # 移除定时任务
```

### Cron 相关命令

```bash
crontab -l             # 查看当前用户的定时任务
crontab -e             # 编辑定时任务
tail -f cron.log        # 查看 cron 执行日志
```

## 项目结构

```
~/.zai-quota-refresher/
├── quota_refresher.py       # 主程序
├── config.json              # 配置文件
├── config.default.json      # 默认配置模板
└── deploy.sh                # 部署脚本

日志文件（与源码同目录）：
├── quota_refresher.log      # 程序执行日志
└── cron.log                 # cron 调度日志
```

## 工作原理

1. Cron 定时任务按配置的时间间隔调用 Python 脚本
2. Python 脚本查询当前 API 额度使用情况
3. 当额度为 0（不在 5 小时恢复窗口内）时，发送 "hi" 请求触发恢复
4. 所有操作记录到日志文件

## 安全建议

1. **权限保护**：配置文件位于用户目录，自动受用户权限保护
2. **环境变量**：安装时可使用 `ZHIPU_API_KEY` 环境变量提供密钥
3. **定期检查**：使用 `./deploy.sh status` 和 `./deploy.sh logs` 监控运行状态

## 系统要求

- Linux：Ubuntu 16.04+, Debian 8+, CentOS 7+, RHEL 7+
- Python 3.7+（仅使用标准库，无外部依赖）
- 不需要 sudo 权限

## 依赖

**零外部依赖** - 仅使用 Python 标准库：
- `urllib` - HTTP 请求
- `json` - JSON 处理
- `logging` - 日志记录
- `time` & `datetime` - 时间处理

## 优势

相比 systemd 服务方案：

1. **更轻量**：无需常驻进程，按需执行
2. **更简单**：不需要理解 systemd 配置
3. **更标准**：使用 Unix 标准的 cron 工具
4. **更安全**：无需 root 权限，普通用户即可运行
5. **更灵活**：直接使用标准 cron 表达式
6. **更易调试**：日志文件直接可读

## 许可证

MIT License
