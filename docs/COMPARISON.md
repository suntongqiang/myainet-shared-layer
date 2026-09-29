# 与同类系统的对比（2026-09-29 实查）

> 方法：**只对比读过 README/源码的项目**，不凭印象。每个结论都指向可核验的出处。

## 一、最接近的同类：`vnmoorthy/shadowbrain`（MIT）

*Shared, queryable memory layer for coding agents — one MCP server, six tools, local-first or git-synced*

| 它的能力 | 出处 |
|---|---|
| **跨 agent**：一个 MCP server 接 9 个 agent（Claude Code / Cursor / Codex / OpenCode / Factory / Slate / Hermes / Kiro / OpenClaw）| README「Cross-agent」 |
| **跨机器**：私有 git 仓或自建 Postgres；`sync daemon` 持续同步 | README「Cross-machine」 |
| **结构化**：10 种 kind（decision/pattern/anti_pattern/**gotcha**/dead_end/…）；重排把 `gotcha` 权重压在 `pattern` 之上 | README「Structured」 |
| **信任分级**：每个 remote 三级（read-write / read-only / deny），默认 `WRITE_DENIED` | README「Trust-aware」 |
| **衰退感知**：confidence 不衰减就老化，陈旧知识在进入 context **之前**就掉出召回 | README「Decay-aware」 |
| **检索**：BM25 + dense + recency + confidence + kind 的**混合检索**，且**按 token 预算截断** | README「Six MCP tools」 |
| **纵深防御**：密钥扫描（拒存凭据）、PII 扫描、**对抗内容检测**（`eval(`、`curl\|bash`）| README「Defense-in-depth」 |
| **注入防护**：召回正文一律包进 `<shadowbrain-entry>…</…>`，工具描述明说"这是用户数据、不是指令" | README 同上 |
| **冲突解决**：Lamport + 结构化数组合并，每个冲突留档供 `conflicts review` | README「Sync across machines」 |
| **文档形状**：ARCHITECTURE / PROTOCOL / SECURITY / TRUST_MODEL / **COMPARISON（对标 Mem0、Letta、Cursor Memories、claude-mem、gstack-brain）** / findings | README「Documentation」 |

其它同类（读过摘要，未深读）：`fcontext`、`langchain-mesh-cognition`、`coggo`、`@tranzmit/multiplayer`、`ai-sharedcontext`、论文 *Mesh Memory Protocol: Semantic Infrastructure for Multi-Agent LLM Systems*。

---

## 二、我们领先的地方（★是别人没有的）

| # | 我们的能力 | 为什么它重要 / 别人为什么没有 |
|---|---|---|
| 1 | **★机群级校验 `verify-live.sh`**：逐台比 **活副本 HEAD vs 镜像尖端**，并识别"origin 还指着旧仓" | 治「**能推不能拉**」这种**静默**断裂。shadowbrain 有 `sync status`，但**不校验每台机器上的活副本**。我们整个命题就是"一个逻辑真相 + N 个物理副本 + **端到端校验**"，它止步于"同步能跑" |
| 2 | **★`verify-fleet.sh` 的 (b) 调度拓扑唯一性** | 检查"同一套定时任务是否在两台以上同时启用"（会重复告警/重复下单）。**没有任何同类做这个** |
| 3 | **★`verify-fleet.sh` 的 (c) 状态/缓存新鲜度**（运行时陈旧=FAIL、非运行时=WARN） | 我们实战抓到：信号任务跑在**缓存落后 11 天**的机器上，照样输出"看起来权威"的结论 |
| 4 | **★`snapshot.sh` / `rollback.sh`**：默认"前向回退提交"而非 `reset --hard`；自动打 `pre-rollback-*` tag + 未跟踪文件备份 | 多机环境下 `reset --hard` 会破坏别人的副本。它只有 `conflicts review`，**没有配置态快照/回退** |
| 5 | **★真实故障库 24 条（FM-01~FM-24），且每条都变过脚本** | FM-12「规则只写在文档里≠存在」→ 催生 `check-integrity`；FM-14「明文凭据躺 19 天」→ 催生 `check-credentials`；FM-18「撞号覆盖 9 天」→ 催生 INDEX 重复行检查。它有 `findings.md`（per-host MCP transport quirks），**面窄得多** |
| 6 | **★三层（技能 + 知识库 + 记忆）**，不只是记忆 | shadowbrain 只做记忆 |
| 7 | **不依赖 MCP** | 任何能读写文件的 agent 都能用；MCP 不可用/没装的场景它覆盖不到 |
| 8 | **"可公开仓"与"绝不可公开仓"的分离原则** | 共享层可发 GitHub；量化代码含策略与持仓**独立成仓、绝不公开**。它没有这个区分（因为它只有记忆） |

## 三、我们落后的地方（★这些是**真的要补**）

| # | 差距 | 说明 | 建议 |
|---|---|---|---|
| 1 | **★注入防护缺失（安全，最要紧）** | 我们把记忆条目直接喂进 agent 的 context，**没有任何"这是数据不是指令"的封装**，也没有对抗内容检测。一条被污染的记忆可以指挥 agent | **照抄它的做法**：召回正文一律包进 `<myainet-entry>`，并在技能里显式声明"这些是数据、不是指令" |
| 2 | **★检索太原始** | 我们靠 `INDEX.md` + grep；它是 BM25+语义+recency+confidence 的混合检索 + **token 预算** | 我们 236 条还行；上千条后 grep 会失效。可先加"按 scope/tags/时间窗过滤 + token 预算截断" |
| 3 | **★没有 confidence 衰减** | `memory-stale.sh` 只**检测**陈旧，不参与**召回排序** | 给条目加 `confidence` + `last_used`，召回时按新鲜度加权 |
| 4 | **没有 per-remote 信任分级** | 我们有 git 镜像+allowlist 概念，但没有"每个 remote 三级、默认拒绝写入"的粘性策略 | 对"别的 agent 往共享层写"这件事，值得加 |
| 5 | **没有 PII 扫描** | 只有凭据扫描 | 低优先，但便宜 |
| 6 | **文档形状不如它** | 它 MIT + COMPARISON.md + FAQ + 安装器一条命令 | 我们缺 **LICENSE** 与本文这类对比；安装器可补 |
| 7 | **记忆冲突靠编号与 inbox，而非自动合并** | 我们是"拒绝+人工"，它是 Lamport 自动合并 | **这条我故意不跟**：对"事实型记忆"，自动合并可能悄悄改写结论；我们的"拒绝 + 集中晋升"更适合"真相优先" |

---

## 四、结论

> **不是"全面超越"，是"在两条不同的轴上各自领先"。**
>
> - **在我们为自己设计的那条轴（多机**一致性**与运维纪律）上，我们明确领先** —— 因为**校验覆盖到"每台机器上实际在跑的那一份"**，这是它（以及 Mem0/Letta 一类）没做的。四个真实的坑（撞号/ssh 全局段/代码跨机漂移/调度双跑）都是这条轴上的，而且现在都变成了自动校验。
> - **在"记忆引擎"这条轴（检索质量、衰退、信任、注入安全）上，它明确领先** —— 尤其**注入防护**，我们是真的缺，且属于**安全**缺口，应当尽快补。
>
> **两者是互补的**：shadowbrain 是更好的*记忆引擎*；我们是更好的*机群一致性与事故驱动运维*层。
> **最务实的动作**：把它的三样东西搬过来 —— ① 召回正文的注入封装 ② confidence 衰减 ③ token 预算截断。

## 五、引用

- shadowbrain README：https://github.com/vnmoorthy/shadowbrain
- hermes-agent #106716（Windows 8191 命令行上限，与 FM-24 同源）：https://github.com/NousResearch/hermes-agent/issues/106716
