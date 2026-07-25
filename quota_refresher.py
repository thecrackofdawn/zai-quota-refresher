#!/usr/bin/env python3
"""
智谱 GLM Coding Plan 自动刷新工具
自动监控额度使用情况，当额度为0时触发刷新
支持自定义刷新时间段配置
仅使用 Python 标准库，无外部依赖
"""
import urllib.request
import urllib.error
import json
import time
import os
import sys
import logging
from logging.handlers import RotatingFileHandler
from datetime import datetime
import subprocess

# 配置文件路径
CONFIG_FILE = "config.json"
DEFAULT_CONFIG_FILE = "config.default.json"

# API 端点
QUOTA_URL = "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
# 注意：必须使用 Coding 套餐专属端点（含 /coding/），否则请求会走标准 API 的独立计费通道，
# 不消耗、也不激活 Coding Plan 的套餐额度（表现为“请求成功但远程额度仍为 0”）。
# 官方说明：https://docs.bigmodel.cn/cn/coding-plan/faq
CHAT_API_URL = "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions"

# 日志配置
MAX_LOG_SIZE = 1 * 1024 * 1024  # 1MB
BACKUP_COUNT = 2  # 保留2个滚动文件


def load_config():
    """加载配置文件"""
    # 优先从环境变量读取 API Key
    env_api_key = os.getenv("ZHIPU_API_KEY")

    # 检查配置文件是否存在
    if not os.path.exists(CONFIG_FILE):
        print(f"配置文件 {CONFIG_FILE} 不存在，请先创建配置文件")
        print("可以参考 config.default.json 创建 config.json")
        sys.exit(1)

    with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
        config = json.load(f)

    # 如果环境变量中有 API Key，优先使用
    if env_api_key:
        config['api_key'] = env_api_key

    # 获取脚本所在目录
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # 处理日志文件路径：如果是相对路径，则放在脚本所在目录
    log_file = config.get('log_file', 'quota_refresher.log')
    if not os.path.isabs(log_file):
        # 相对路径：与脚本放在同一目录
        config['log_file'] = os.path.join(script_dir, log_file)

    return config


def setup_logger(log_file):
    """配置日志滚动处理器"""
    # 创建日志目录（如果不存在）
    log_dir = os.path.dirname(log_file)
    if log_dir and not os.path.exists(log_dir):
        os.makedirs(log_dir, exist_ok=True)

    # 创建 logger
    logger = logging.getLogger('zai_quota_refresher')
    logger.setLevel(logging.INFO)

    # 清除已有的处理器
    if logger.handlers:
        logger.handlers.clear()

    # 创建滚动文件处理器
    file_handler = RotatingFileHandler(
        log_file,
        maxBytes=MAX_LOG_SIZE,
        backupCount=BACKUP_COUNT,
        encoding='utf-8'
    )
    file_handler.setLevel(logging.INFO)

    # 创建控制台处理器
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)

    # 创建格式化器
    formatter = logging.Formatter('[%(asctime)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
    file_handler.setFormatter(formatter)
    console_handler.setFormatter(formatter)

    # 添加处理器
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)

    return logger


def log_message(message, log_file):
    """记录日志到文件和终端（使用滚动日志）"""
    # 使用全局 logger 或创建新的
    logger = logging.getLogger('zai_quota_refresher')

    # 如果 logger 未配置，先配置
    if not logger.handlers:
        logger = setup_logger(log_file)

    logger.info(message)


def make_http_request(url, headers, data=None, method="GET"):
    """使用标准库发送 HTTP 请求"""
    try:
        if data:
            # POST 请求
            json_data = json.dumps(data).encode('utf-8')
            req = urllib.request.Request(
                url,
                data=json_data,
                headers=headers,
                method='POST'
            )
        else:
            # GET 请求
            req = urllib.request.Request(url, headers=headers, method='GET')

        # 设置超时
        with urllib.request.urlopen(req, timeout=10) as response:
            response_data = response.read().decode('utf-8')
            return json.loads(response_data), response.status, None

    except urllib.error.HTTPError as e:
        error_data = e.read().decode('utf-8') if e.fp else ''
        return None, e.code, error_data
    except urllib.error.URLError as e:
        return None, None, str(e)
    except Exception as e:
        return None, None, str(e)


def check_quota(api_key, log_file):
    """查询当前使用额度"""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    data, status_code, error = make_http_request(QUOTA_URL, headers)

    if error:
        if status_code:
            log_message(f"查询失败，状态码：{status_code}，响应：{error}", log_file)
        else:
            log_message(f"请求异常：{error}", log_file)
        return None

    if data:
        log_message(f"额度查询成功: {json.dumps(data, ensure_ascii=False)}", log_file)

        # 解析 TOKENS_LIMIT 的使用百分比
        if "data" in data and "limits" in data["data"]:
            limits = data["data"]["limits"]

            # 查找 TOKENS_LIMIT
            for limit in limits:
                if limit.get("type") == "TOKENS_LIMIT":
                    percentage = limit.get("percentage", 0)

                    # percentage 为 0 表示不在5小时窗口期内，需要触发刷新
                    # percentage > 0 表示已经在窗口期内，正在使用中
                    if percentage == 0:
                        log_message(f"TOKENS_LIMIT 使用率: {percentage}%，不在窗口期内", log_file)
                        return 0
                    else:
                        log_message(f"TOKENS_LIMIT 使用率: {percentage}%，已在5小时窗口期内", log_file)
                        return percentage  # 返回使用百分比

            log_message("未找到 TOKENS_LIMIT 数据", log_file)

    return None


def verify_window_activated(api_key, log_file):
    """刷新后回查额度，判断 TOKENS_LIMIT 的 5 小时窗口是否已进入活跃状态。

    返回 True=已激活，False=未激活，None=无法判断（查询失败）。
    活跃标志：percentage>0，或响应中已出现 nextResetTime（刚激活时 usage 统计可能有延迟，
    但窗口的重置时间会立即出现）。
    """
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    data, status_code, error = make_http_request(QUOTA_URL, headers)
    if error or not isinstance(data, dict):
        return None

    for limit in data.get("data", {}).get("limits", []):
        if limit.get("type") == "TOKENS_LIMIT":
            percentage = limit.get("percentage", 0)
            has_reset = "nextResetTime" in limit
            log_message(
                f"验证额度：TOKENS_LIMIT percentage={percentage}%，"
                f"nextResetTime={'有' if has_reset else '无'}",
                log_file,
            )
            return percentage > 0 or has_reset
    return None


def trigger_refresh(api_key, log_file):
    """触发刷新 - 通过 Coding 套餐端点发送 hi 请求以激活 5 小时滚动窗口。"""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    data = {
        "model": "glm-4.7",
        "messages": [
            {"role": "user", "content": "hi"}
        ]
    }

    response_data, status_code, error = make_http_request(
        CHAT_API_URL,
        headers,
        data=data,
        method="POST"
    )

    if error:
        log_message(f"❌ 刷新请求失败，状态码：{status_code}，响应：{error}", log_file)
        return False

    # 记录真实响应便于排查：HTTP 200 不代表请求真正走了套餐通道
    resp_brief = json.dumps(response_data, ensure_ascii=False)
    if len(resp_brief) > 200:
        resp_brief = resp_brief[:200] + "..."
    log_message(f"刷新请求返回，状态码：{status_code}，响应：{resp_brief}", log_file)

    # 服务端有时以 200 返回错误结构，需检查 error 字段
    if isinstance(response_data, dict) and response_data.get("error"):
        log_message(f"❌ 服务端返回错误：{response_data.get('error')}", log_file)
        return False

    # 回查额度，确认 5 小时窗口确实已被激活（而非仅“请求发出成功”）
    time.sleep(3)
    activated = verify_window_activated(api_key, log_file)
    if activated is True:
        log_message("✅ 刷新成功，5 小时滚动窗口已激活", log_file)
    elif activated is False:
        log_message("⚠️ 刷新请求已发送，但额度尚未反映窗口激活"
                    "（后台统计可能有延迟，建议稍后到用量页确认）", log_file)
    else:
        log_message("⚠️ 刷新请求已发送，但无法回查额度确认结果", log_file)
    return True


def check_and_refresh(config):
    """检查额度并在需要时触发刷新"""
    log_message("开始检查额度...", config['log_file'])

    percentage = check_quota(config['api_key'], config['log_file'])

    if percentage is None:
        log_message("无法获取额度信息，跳过本次检查", config['log_file'])
        return

    if percentage == 0:
        log_message("⚠️  TOKENS_LIMIT 使用率为 0%，不在5小时窗口期内，准备触发刷新...", config['log_file'])
        trigger_refresh(config['api_key'], config['log_file'])
    else:
        log_message(f"✅ TOKENS_LIMIT 使用率: {percentage}%，已在5小时窗口期内，无需刷新", config['log_file'])


def print_config(config):
    """打印当前配置"""
    log_message("=" * 60, config['log_file'])
    log_message("智谱 GLM Coding Plan 自动刷新工具已启动", config['log_file'])
    log_message(f"检查间隔: {config['check_interval_minutes']} 分钟", config['log_file'])

    start_h = config['refresh_time_range']['start']['hour']
    start_m = config['refresh_time_range']['start']['minute']
    end_h = config['refresh_time_range']['end']['hour']
    end_m = config['refresh_time_range']['end']['minute']

    log_message(f"刷新策略时间段: {start_h:02d}:{start_m:02d} - {end_h:02d}:{end_m:02d}",
               config['log_file'])
    log_message("=" * 60, config['log_file'])


def main():
    """主函数 - 单次执行模式，由 cron 调用"""
    # 加载配置
    config = load_config()

    # 配置日志
    logger = setup_logger(config['log_file'])

    log_message("执行定时检查...", config['log_file'])

    # 执行检查和刷新
    check_and_refresh(config)

    log_message("检查完成", config['log_file'])


if __name__ == "__main__":
    main()
