---
name: myainet-shared-layer
description: 多台无人值守机器 + 多个 AI agent 共用的「共享记忆 / 技能库」层的架构与运维手册。当需要搭建或排障多机共享记忆、多镜像 git 同步、记忆编号冲突、活副本不同步（能推不能拉）、或要把这套方案搬去别的机器/上传 GitHub 时使用；也含与同类系统的双向对比。含真实故障库（FM-01~FM-27，27 条全部来自真实事故）、记忆写入协议、以及配套脚本（多镜像同步 / verify-live 活副本校验 / verify-fleet 机群四项校验（含任务返回码健康） / next-mem-id 编号分配 / 完整性检查 / inbox 无冲突写入与中心化晋升 / pre-commit 守卫）。触发词：共享层 / 共享记忆 / 多机同步 / 镜像仓 / 编号冲突 / 撞号 / 活副本 / verify-live / verify-fleet / 能推不能拉 / 调度拓扑 / 缓存末日。
---

# myainet-shared-layer · 多机共享记忆层

> 一套给「多台无人值守、由 AI agent 驱动」的机器共用的**记忆 + 技能共享层**方案。
> **不是设计出来的，是踩坑踩出来的** —— `docs/FAILURE-MODES.md` 里每条都是真实事故。

## 什么时候用本技能

- 要**搭建**多机共享记忆/技能层
- 多机同步出问题：**"某台机器好像没更新"**、**"能推不能拉"**、合并冲突
- **记忆编号撞号**（两台机器写了同一个 `mem-NNNN`）
- 要把这套方案**搬到别的机器集群**或**整理成开源项目**

## 核心心智模型（先记这句）

> **逻辑上一个真相（git commit hash），物理上多份副本（镜像仓）。
> 一致性不靠「放在同一个地方」，靠「校验」和「纪律」。**

两个方案都会坏：单点存储坏在**不可用**，多副本无校验坏在**不一致且不报错**。
本方案 = 多副本拿可用性 + 端到端校验拿一致性。

## 三条最容易被忽略的纪律

1. **迁移必须成对**：建新镜像的同时，**必须改所有消费方的 `git remote origin`**。
   只做一半 → **能推不能拉，且不报错**（FM-01，最危险的故障）。
2. **只跑同步不算同步**：同步后必须 `verify-live.sh` 逐台校验活副本 HEAD。
   `pushed_remote=2/3` 这种**单侧指标**会被误读成"同步好了"。
3. **禁止数本地最大值分配编号**：必须 `next-mem-id.sh` 跨镜像取号，
   或干脆走 inbox 通道由唯一 promoter 分配（FM-02）。

## 文件地图

| 路径 | 内容 |
|---|---|
| `docs/FAILURE-MODES.md` | **★ 真实故障库 FM-01~FM-10：症状 / 根因 / 对策 / 教训**（先读这个） |
| `docs/COMPARISON.md` | **★ 与同类系统的双向对比**（shadowbrain / Mem0 / Letta 一类）：我们领先在「机群一致性校验（verify-live/verify-fleet）」；**落后在「检索质量、confidence 衰减、★召回正文的注入防护」** —— 后三项是从同类学来的待补项 |
| `docs/ARCHITECTURE.md` | 架构与取舍（为什么不是单点 / Obsidian Sync / Syncthing / CRDT） |
| `docs/PROTOCOL.md` | 记忆写入协议：条目形态、编号纪律、冲突裁决、写入路径、校验 |
| `scripts/shared-sync.sh` / `.ps1` | 多镜像同步（fetch 首个可达 → 只 ff → 推所有可达） |
| `scripts/verify-live.sh` | **★ 活副本端到端校验**（逐台 ssh 查 HEAD，与镜像 tip 比对） |
| `scripts/verify-fleet.sh` | **★ 机群三项校验**：(a) 代码仓一致（HEAD/工作区/origin）(b) **调度拓扑唯一性**（同名交易任务不能两台同时启用）(c) **缓存末日**（运行时陈旧=FAIL/非运行时=WARN）。★一律比 commit 不比字节（三台 autocrlf=true，比字节必误报） |
| `scripts/next-mem-id.sh` | **★ 跨全部镜像**取下一个空闲编号 |
| `scripts/check-integrity.sh` | 重复 id / INDEX 不一致 / 残留冲突标记 / frontmatter 扫描 |
| `scripts/inbox-submit.sh` | **★ 无冲突写入通道**（per-agent 时间戳文件） |
| `scripts/promote-inbox.sh` | 中心化晋升：唯一 promoter 分配正式编号 |
| `scripts/install-hooks.sh` + `hooks/pre-commit` | **★ 拒绝引入重复编号 / 冲突标记 / 明文凭据的提交** |
| **`scripts/check-credentials.sh`** | **★ 明文凭据扫描**（GitHub/AWS/Slack/OpenAI/私钥/通用 token= 形态），命中即脱敏报警 |
| `scripts/memory-search.sh` | 检索 + **`<memory-data>` 注入防护**；支持 `--scope/--kind/--json` |
| `scripts/memory-stale.sh` | 陈旧记忆候选 → 可逆归档（**永不删除**） |
| **`scripts/snapshot.sh`** | **★ 打快照**：git tag + 逐文件 blob 哈希清单 + 各机活副本 HEAD（之后可回滚到它） |
| **`scripts/rollback.sh`** | **★ 回滚**：`--list/--check/--apply/--hard`。默认**前向回滚提交**（多机安全），回滚前自动留后路 |

## 典型操作

```bash
V=/path/to/vault

bash scripts/check-integrity.sh  $V      # 1. 体检（先跑这个）
bash scripts/next-mem-id.sh      $V      # 2. 下一个可用编号
bash scripts/inbox-submit.sh     $V "发现 X" --agent my-machine   # 3. 无冲突写入
bash scripts/promote-inbox.sh    $V --review   # 4. 出待晋升清单
bash scripts/promote-inbox.sh    $V --apply    # 5. 分配编号并落库
bash scripts/shared-sync.sh               # 6. 推给所有镜像
bash scripts/verify-live.sh               # 7. ★ 逐台确认真的同步了
bash scripts/install-hooks.sh    $V       # 8. 一次性：装 pre-commit 守卫

# 高风险操作前后
bash scripts/snapshot.sh         $V --name before-risky    # 打锚点
bash scripts/rollback.sh         $V --check before-risky   # 看会变什么
bash scripts/rollback.sh         $V --apply before-risky --yes   # 退回（前向提交，可同步）
```

## 排障速查

| 症状 | 先查 | 对应故障 |
|---|---|---|
| 某机内容不更新，但同步"成功" | `origin` 是否指向旧仓；`verify-live.sh` | FM-01 |
| 合并时一堆同号文件冲突 | 是否用本地最大值分配编号 | FM-02 |
| `git pull` 报 would be overwritten | 活副本有未提交改动 → 先 `stash -u` | FM-04 |
| 校验脚本全报不一致，但人工看是一致的 | 输出是否带 `\r`（Windows PowerShell） | FM-05 |
| 编号算出明显偏小的值 | 前导零被当八进制 → `10#` | FM-07 |
| 仓库里出现 `<<<<<<<` | `git add -A` 把冲突标记当已解决 | FM-08 |
| 某技能文件里有明文 Token | `check-credentials.sh <层根>` | FM-14 |
| 索引进有、文件不存在 | `check-integrity.sh` §4 双向比对 | FM-11 |
| 规则明明写了却还是复发 | 它只写在文档里 —— 变成脚本 | FM-12 |
| 同一份代码两台各跑各的 | `verify-fleet.sh` (a) 比 commit；查是否有人绕过了仓 | FM-20 |
| 文件"看起来正常"却语法错/配置失效 | 定界符被注释或编辑吃掉了（少 Host 行 / 吞 `}`）| FM-19 / FM-21 |
| 任务状态 Ready、日志在长，但没产出 | 读日志内容 + 核产物；`Ready` ≠ 跑成功 | FM-22 |
| 校验全绿但故障还在 | **故障长在你没校验的地方** —— 覆盖面要跟着"实际在跑的东西"走 | FM-23 |
| 同一个问题两台机器两个答案 | `verify-fleet.sh` (c) 比缓存末日 | FM-23 |

## 设计边界（诚实说）

- **Obsidian 是"给人开的窗"**（双链/图谱/搜索），**不是同步的桥**。本方案把它当可选的可读层。
- **不选 Syncthing/Obsidian Sync**：它们解决"文件怎么过去"，不解决"多写者怎么不打架"。
- **不选 CRDT**：对几 MB Markdown、低频写入，复杂度收益不划算。
- 规则**必须可执行**：没有脚本能判定的规则，最后都会变成"文档里写了但没人执行"。

## 致谢（借了思想，代码独立实现）

- [Noelune/unified-agent-memory](https://github.com/Noelune/unified-agent-memory)：per-agent 时间戳 inbox 作唯一写入通道 + 中心化晋升
- [marcusquinn/aidevops](https://github.com/marcusquinn/aidevops)：pre-commit 拒绝重复 ID 的守卫模式
