# 记忆写入协议

> 目标：**多台机器、多个 agent 并发写，仍然无冲突、可裁决、可追溯。**

## 1. 条目的形态

一条长期记忆 = 一个 Markdown 文件（`memory/mem-NNNN.md`），YAML frontmatter + 正文。

```yaml
---
id: mem-0228            # 必填，与文件名一致
created: 2026-09-28
updated: 2026-09-28T21:00:00+08:00   # 必填；冲突裁决靠它
kind: fact              # fact | decision | finding | state
owner: dsh-mobile       # 谁写的（机器/实例实名）
scope: 项目:股票量化     # 归属域；同一 scope 只应有一个 owner 有权分号
tags: [因子, 回测]
status: active          # active | superseded | archived
confidence: high        # high | medium | low
supersedes: []          # 本条目取代了谁
superseded_by:          # 被谁取代
---
## 内容
...
```

`INDEX.md` 是登记表：一行一条，便于全量浏览与机器检索。

## 2. ★编号分配纪律（治撞号）

**禁止**用「数本地 `INDEX.md` 最大值 +1」分配 —— 这是撞号的根因（见 FM-02）。

**必须**先跑分配器：

```bash
bash scripts/next-mem-id.sh /path/to/vault     # 输出 NEXT=mem-NNNN
```

它跨**所有可达镜像 + 本地**取已用最大编号，返回下一个空闲编号。

- 若某镜像不可达，仍以可达镜像最大值为准，并在当日流水里记一行"有镜像不可达，编号可能不完整"。
- **更稳的做法**：不要自己分号 —— 走 inbox 通道，由唯一 promoter 分配（见 §4）。

## 3. ★冲突裁决算法（机器可判定）

同一 `scope` 下、指向同一件事的多条：

1. 只看 `status: active` 的；
2. 取其中 `updated` **最大**的那条为准；
3. 落败的条目：`status` 改为 `superseded`，并填 `superseded_by: <胜者id>`；
4. **不删除任何条目** —— 保留完整演变历史；
5. 若两条都是 `high` confidence 且语义**直接矛盾** → 记为**未决冲突**，交人来裁定，**不要自己拍**。

> 这套规则的价值在于**机器可判定** —— 否则"冲突"就变成需要人逐条看的地狱。

## 4. 写入路径（结构上消除冲突）

```
agent ──► inbox/<agent>-<时间戳>.md      ← 唯一写入通道
                │
                ▼
         唯一 promoter（例如每晚定时任务）
                │  跑 --review 出待晋升清单 → 人工/AI 审核 → --apply 分配 mem-NNNN
                ▼
         canonical：memory/mem-NNNN.md + 更新 INDEX.md
```

- **写**：`bash scripts/inbox-submit.sh <vault> "内容" --agent <你>` —— 文件名含 agent 与时间戳，**不可能撞**。
- **晋升**：`bash scripts/promote-inbox.sh <vault> --review` / `--apply`。
- **promoter 必须是唯一的**。多台机器各自跑 promoter = 撞号又回来了。

## 5. 同步与校验纪律

每次同步后**必须**跑校验：

```bash
bash scripts/shared-sync.sh      # 同步
bash scripts/verify-live.sh      # ★ 逐台确认活副本 HEAD == 镜像 tip
bash scripts/check-integrity.sh  # ★ 重复 id / INDEX 一致性 / 残留冲突标记
```

**只跑同步不跑校验 = 只有一半。** `verify-live.sh` 退出非零就是有机器没同步上。

## 6. pre-commit 守卫

```bash
bash scripts/install-hooks.sh /path/to/vault
```

装上后，任何**引入重复编号**（或残留冲突标记）的提交会被**直接拒绝** —— 让错误在它发生的那一步就停住。

## 7. 规则的可执行性

> **文档不是约束，可执行的校验才是约束。**

写进本文档的每条规则，都应该有对应的脚本能**自动判定**它是否被遵守。
没有脚本的规则，最后都会变成 FM-10（"文档里写了但没人执行"）。


---

## 8. ★禁止明文凭据（2026-09-28 立，依据 FM-14）

共享层里的任何文件（技能、脚本、配置、模板）**不得出现明文密钥**。
包括但不限于：GitHub Token、云厂商 AK/SK、Slack/OpenAI Key、私钥、数据库口令。

**硬规则**：
- ❌ 不要把密钥写进"默认值/预填值"图省事 —— 那是最常见的泄露路径。
- ✅ 需要凭据时：走**环境变量**、**用户级凭据文件（0600）**，或**让用户在界面里填一次并存到浏览器**。
- ✅ 提交前由 `hooks/pre-commit` 自动拦截；体检时 `check-integrity.sh` §6 会扫。
- ⚠️ **一旦某个密钥进过版本控制，唯一正确的修复是"轮换"** —— 删文件不解决问题，历史里还在。
