# deploy.sh 交互式选择 cron 执行周期 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `deploy.sh install` 时交互式选择 cron 执行周期（预设菜单 + 自定义兜底），默认 `*/10 0-23 * * *`。

**Architecture:** 在 deploy.sh 新增三个职责清晰的函数——`cron_expr_valid`（纯校验）、`_cron_menu_pick`（菜单选择逻辑，从 stdin 读输入）、`input_cron_schedule`（tty 检测后调度：交互则弹菜单，非交互则用默认）。`config_wizard` 增加一步调用它；`create_cron_job` 用所得 `SELECTED_CRON_EXPR` 替代硬编码。周期不写入 config.json。

**Tech Stack:** Bash（`#!/bin/bash`，需数组支持），Markdown（README）。零外部依赖——不引入 bats，测试用纯 bash「sed 提取函数 + 断言」。

## Global Constraints

- **平台**：部署目标 Linux（Python 3.7+）；开发机为 Windows，bash 函数级测试通过 Bash 工具（Git Bash）执行。完整 install 端到端需在 Linux 手动验证。
- **依赖**：零外部依赖。测试不得引入 bats/shellcheck 之外的工具；校验仅用 `grep`/`awk`/`sed`/`[`。
- **config.json 不存 cron 周期**（方案 B）：周期只在 install 时决定、写进 crontab。
- **文案**：中文，与现有 `print_info`/`print_warning` 风格一致。
- **分支**：当前在 `main`。执行前先开特性分支：`git checkout -b feat/cron-schedule-prompt`（除非用户另有指示）。
- **不得实际触发智谱 API**：验证时跳过 `test_run` 或用无效 key，避免消耗 Coding Plan 额度。

## File Structure

| 文件 | 责任 | 改动 |
|------|------|------|
| `deploy.sh` | 部署脚本 | 新增 3 个函数；改 `config_wizard`、`create_cron_job`；更新文案 |
| `README.md` | 文档 | 删管道方式、更新默认周期描述 |
| `docs/superpowers/plans/2026-07-26-deploy-cron-schedule-prompt.md` | 本计划 | （本文件） |

无新文件（除计划文档本身）。函数全部内联在 deploy.sh，与现有风格一致（现有 `input_api_key` 等都是内联函数）。

---

### Task 1: 新增 `cron_expr_valid` 纯校验函数

**Files:**
- Modify: `deploy.sh`（在 `input_api_key` 函数定义之前，约第 179 行 `# 交互式输入 API Key` 注释上方插入）
- Test: 临时脚本，通过 Bash 工具运行（不落盘或落盘到 `/tmp`）

**Interfaces:**
- Consumes: 无
- Produces: `cron_expr_valid(expr) -> 0`（合法）`| 1`（非法）。合法 = 去首尾空格后恰好 5 段、每段仅含 `0-9 * / - ,`。

- [ ] **Step 1: 写失败测试**

把以下内容存为 `tests/test_cron_valid.sh`（执行后可删，仅本次验证用）：

```bash
#!/bin/bash
# 提取被测函数（不 source 整个脚本，避免顶层副作用）
eval "$(sed -n '/^cron_expr_valid()/,/^}/p' deploy.sh)"

pass=0; fail=0
ok()   { if cron_expr_valid "$1"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL(应合法): $1"; fi; }
bad()  { if cron_expr_valid "$1"; then fail=$((fail+1)); echo "FAIL(应非法): $1"; else pass=$((pass+1)); fi; }

ok "*/10 0-23 * * *"
ok "*/30 9-18 * * 1-5"
ok "0 9,12,15,18 * * 1-5"
ok "* * * * *"
ok "0 0 1 * 1-5"
bad "* * *"                       # 3 段
bad "*/10 0-23 * * 1-5 extra"     # 6 段
bad "abc def ghi jkl mno"         # 非法字符
bad "*/10 0-23 * *"               # 4 段
bad ""                            # 空

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd "C:\Users\cd\Documents\projects\zai_refresh" && bash tests/test_cron_valid.sh`
Expected: 提取为空/函数未定义，全部 FAIL，退出码非 0。

- [ ] **Step 3: 实现函数**

在 `deploy.sh` 第 179 行 `# 交互式输入 API Key（隐藏输入）` 上方插入：

```bash
# 校验 cron 表达式：去首尾空格后恰好 5 段，每段仅含 0-9 * / - ,
# 返回 0=合法，1=非法
cron_expr_valid() {
    local expr="$1"
    local trimmed
    trimmed="$(printf '%s' "$expr" | sed 's/^ *//;s/ *$//')"
    local field_count
    field_count=$(printf '%s' "$trimmed" | awk '{print NF}')
    [ "$field_count" -eq 5 ] || return 1
    local i seg
    for i in 1 2 3 4 5; do
        seg=$(printf '%s' "$trimmed" | awk -v n="$i" '{print $n}')
        printf '%s' "$seg" | grep -qE '^[0-9*/,-]+$' || return 1
    done
    return 0
}

```

- [ ] **Step 4: 运行测试，确认通过**

Run: `bash tests/test_cron_valid.sh`
Expected: `pass=9 fail=0`，退出码 0。

- [ ] **Step 5: 语法检查**

Run: `bash -n deploy.sh`
Expected: 无输出，退出码 0。

- [ ] **Step 6: Commit**

```bash
git add deploy.sh
git commit -m "feat(deploy): add cron_expr_valid validator"
```

（`tests/test_cron_valid.sh` 是临时验证脚本，不入库；Task 5 统一清理。）

---

### Task 2: 新增 `_cron_menu_pick` 与 `input_cron_schedule`

**Files:**
- Modify: `deploy.sh`（紧接 Task 1 的 `cron_expr_valid` 之后插入两个函数）
- Test: `tests/test_cron_menu.sh`

**Interfaces:**
- Consumes: `cron_expr_valid`（Task 1）；`print_warning`/`print_info`（已在 deploy.sh 顶部定义）
- Produces:
  - `_cron_menu_pick`：从 stdin 读用户选择，设全局 `SELECTED_CRON_EXPR` 并 `return 0`；输入非法序号则循环重试。
  - `input_cron_schedule`：`[ ! -t 0 ]` 时设 `SELECTED_CRON_EXPR="*/10 0-23 * * *"` 直接返回；否则调用 `_cron_menu_pick`。

- [ ] **Step 1: 写失败测试**

存为 `tests/test_cron_menu.sh`：

```bash
#!/bin/bash
# 提取被测函数 + 为依赖打桩
eval "$(sed -n '/^cron_expr_valid()/,/^}/p' deploy.sh)"
# print_warning/print_info 桩（_cron_menu_pick 依赖）
print_warning() { :; }
print_info()    { :; }
eval "$(sed -n '/^_cron_menu_pick()/,/^}/p' deploy.sh)"

pass=0; fail=0
# 用例：输入 → 期望 SELECTED_CRON_EXPR
case_check() {
    local input="$1" expected="$2"
    SELECTED_CRON_EXPR=""
    printf '%s\n' "$input" | _cron_menu_pick >/dev/null 2>&1
    if [ "$SELECTED_CRON_EXPR" = "$expected" ]; then pass=$((pass+1));
    else fail=$((fail+1)); echo "FAIL input='$input' got='$SELECTED_CRON_EXPR' want='$expected'"; fi
}

case_check "1"      "*/10 0-23 * * *"     # 预设1
case_check ""       "*/10 0-23 * * *"     # 回车默认
case_check "2"      "*/30 0-23 * * *"
case_check "3"      "*/10 0-23 * * 1-5"
case_check "4"      "*/30 9-18 * * 1-5"
case_check $'5\n*/15 * * * *' "*/15 * * * *"          # 自定义合法
case_check $'9\n1' "*/10 0-23 * * *"                   # 非法序号后回默认
case_check $'5\nbad bad bad\n*/10 0-23 * * *' "*/10 0-23 * * *"  # 自定义非法后合法

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `bash tests/test_cron_menu.sh`
Expected: 函数未定义，全部 FAIL。

- [ ] **Step 3: 实现两个函数**

紧接 Task 1 的 `cron_expr_valid` 之后插入：

```bash
# 菜单选择逻辑：从 stdin 读输入，设全局 SELECTED_CRON_EXPR
# 非法序号/非法表达式则循环重试。仅处理交互选择，不做 tty 检测。
_cron_menu_pick() {
    local presets_expr=(
        "*/10 0-23 * * *"
        "*/30 0-23 * * *"
        "*/10 0-23 * * 1-5"
        "*/30 9-18 * * 1-5"
    )
    local presets_desc=(
        "每天 0:00-23:59，每10分钟（默认）"
        "每天 0:00-23:59，每30分钟"
        "工作日 0:00-23:59，每10分钟"
        "工作日 9-18点，每30分钟"
    )

    while true; do
        echo ""
        echo "请选择 cron 执行周期："
        local idx
        for idx in 0 1 2 3; do
            printf "  %d) %s   %s\n" "$((idx+1))" "${presets_desc[$idx]}" "${presets_expr[$idx]}"
        done
        echo "  5) 自定义（手动输入 cron 表达式）"
        echo -n "请输入序号 [1]: "
        local choice
        read -r choice || true
        [ -z "$choice" ] && choice=1

        case "$choice" in
            1|2|3|4)
                SELECTED_CRON_EXPR="${presets_expr[$((choice-1))]}"
                return 0
                ;;
            5)
                while true; do
                    echo "请输入 cron 表达式（5 段：分 时 日 月 周），如 */10 0-23 * * *："
                    echo -n "cron: "
                    local custom
                    read -r custom || true
                    if cron_expr_valid "$custom"; then
                        SELECTED_CRON_EXPR="$custom"
                        return 0
                    fi
                    print_warning "格式不合法（需 5 段，仅含 0-9 * / - ,），请重新输入"
                done
                ;;
            *)
                print_warning "无效序号，请输入 1-5"
                ;;
        esac
    done
}

# 交互式选择 cron 执行周期，结果写入全局 SELECTED_CRON_EXPR
# 非交互/管道模式（stdin 非 tty）：直接用默认，不弹菜单
input_cron_schedule() {
    if [ ! -t 0 ]; then
        SELECTED_CRON_EXPR="*/10 0-23 * * *"
        return
    fi
    _cron_menu_pick
}

```

- [ ] **Step 4: 运行测试，确认通过**

Run: `bash tests/test_cron_menu.sh`
Expected: `pass=8 fail=0`。

- [ ] **Step 5: 语法检查**

Run: `bash -n deploy.sh`
Expected: 无输出，退出码 0。

- [ ] **Step 6: Commit**

```bash
git add deploy.sh
git commit -m "feat(deploy): add interactive cron schedule picker"
```

（`tests/test_cron_menu.sh` 是临时验证脚本，不入库；Task 5 统一清理。）

---

### Task 3: 串接到 `config_wizard` 与 `create_cron_job`，更新文案

**Files:**
- Modify: `deploy.sh:247`（步骤编号）、`deploy.sh:248-249` 之后（调用）、`deploy.sh:272`（摘要文案）、`deploy.sh:299`（创建提示）、`deploy.sh:302`（cron_expr 赋值）、`deploy.sh:326`（完成文案）

**Interfaces:**
- Consumes: `input_cron_schedule` / 全局 `SELECTED_CRON_EXPR`（Task 2）
- Produces: install 流程在配 API Key 后多一步选周期；`create_cron_job` 用所选周期。

- [ ] **Step 1: 修改 `config_wizard` 步骤编号与调用**

把 `deploy.sh:247` 的：
```bash
    # 输入 API Key
    print_info "步骤 1/1: 配置 API Key"
    input_api_key
    api_key="$RETURN_VALUE"
```
改为：
```bash
    # 输入 API Key
    print_info "步骤 1/2: 配置 API Key"
    input_api_key
    api_key="$RETURN_VALUE"

    # 选择 cron 执行周期
    print_info "步骤 2/2: 选择执行周期"
    input_cron_schedule
```

- [ ] **Step 2: 更新配置摘要文案（`deploy.sh:272`）**

把：
```bash
    print_info "执行时间:       9:00-18:00，每10分钟（可在 crontab 中修改）"
```
改为：
```bash
    print_info "执行周期:       $SELECTED_CRON_EXPR（可在 crontab 中修改）"
```

- [ ] **Step 3: 修改 `create_cron_job` 的 cron_expr 赋值（`deploy.sh:299-302`）**

把：
```bash
    print_info "默认配置：工作日 9:00-18:00，每10分钟执行一次"

    # 创建 cron 任务：周一到周五，9-18点，每10分钟执行
    local cron_expr="*/10 9-18 * * 1-5"
```
改为：
```bash
    print_info "执行周期: $SELECTED_CRON_EXPR"

    # 使用安装时选择的执行周期（兜底默认全天每10分钟）
    local cron_expr="${SELECTED_CRON_EXPR:-*/10 0-23 * * *}"
```

- [ ] **Step 4: 更新完成文案（`deploy.sh:326`）**

把：
```bash
    print_info "定时规则: 工作日 9:00-18:00，每10分钟执行"
```
改为：
```bash
    print_info "定时规则: $cron_expr"
```

- [ ] **Step 5: 语法检查**

Run: `bash -n deploy.sh`
Expected: 无输出，退出码 0。

- [ ] **Step 6: 确认旧文案无残留**

Run: `grep -n "9:00-18:00，每10分钟\|9-18点，每10分钟\|步骤 1/1" deploy.sh`
Expected: 无输出（或仅剩注释，若有则清理）。

- [ ] **Step 7: Commit**

```bash
git add deploy.sh
git commit -m "feat(deploy): wire schedule picker into install; update copy"
```

---

### Task 4: 更新 README

**Files:**
- Modify: `README.md:17-44`（快速开始）、`README.md:69-85`（定时任务配置）

**Interfaces:** 无代码接口；仅文档。

- [ ] **Step 1: 删除管道方式、突出直接执行**

把 `README.md:17-37` 的「### Linux 一键安装（推荐）」整段（方式1 + 方式2 + 注意）替换为：

```markdown
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
```

- [ ] **Step 2: 更新定时任务配置段（`README.md:69-85`）**

把 `### 定时任务配置` 下：
```markdown
默认 cron 任务：工作日 9:00-18:00，每 10 分钟执行一次

如需修改执行时间，使用 `crontab -e` 编辑：
```
改为：
```markdown
默认 cron 任务：每天 0:00-23:59，每 10 分钟执行一次（`*/10 0-23 * * *`）。安装时可从预设中交互选择，或输入自定义表达式。

如需事后修改执行时间，使用 `crontab -e` 编辑：
```
并把该段示例列表里出现的 `*/10 9-18 * * 1-5`（若作为「默认」出现）相应调整，示例表达式本身可保留。

- [ ] **Step 3: 确认旧默认描述无残留**

Run: `grep -n "工作日 9:00-18:00，每10分钟\|默认：工作日 9:00-18:00" README.md`
Expected: 无输出。

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: recommend direct execution; update default cron schedule"
```

---

### Task 5: 全量验证与清理

**Files:**
- Remove: `tests/test_cron_valid.sh`、`tests/test_cron_menu.sh`（临时验证脚本，验证完可删；若希望保留作回归则移入 `tests/` 并在 README 提及——默认删除，符合「零外部依赖」精神）

- [ ] **Step 1: 重跑全部函数级测试**

Run: `bash tests/test_cron_valid.sh && bash tests/test_cron_menu.sh`
Expected: 两个脚本均 `fail=0`、退出码 0。

- [ ] **Step 2: 全脚本语法检查**

Run: `bash -n deploy.sh`
Expected: 无输出，退出码 0。

- [ ] **Step 3: 端到端干跑（Linux 环境，手动）**

在 Linux 测试机/容器：
- 交互：`./deploy.sh install`，依次验证：菜单显示、回车默认、选 2/3/4 各自正确、选 5 输入合法/非法表达式、最终 `crontab -l` 含所选表达式。
- 非交互：`./deploy.sh install < /dev/null`（设 `ZHIPU_API_KEY`）应直接用默认 `*/10 0-23 * * *`，不卡在读输入。
- 注意：`test_run` 会调用智谱 API；如不想消耗额度，用无效 key 让其在额度查询阶段安全失败即可（不影响 cron 逻辑验证）。

- [ ] **Step 4: 清理临时测试脚本**

```bash
rm -f tests/test_cron_valid.sh tests/test_cron_menu.sh
rmdir tests 2>/dev/null || true
```

（测试脚本未入库，本地删除即可，无需 git 操作。）

- [ ] **Step 5: 交付确认**

确认：`deploy.sh` 语法正确、函数级测试全过、README 无旧描述残留、所有提交在特性分支上。
