# myainet-shared-layer

**A distributed shared memory + skills layer for a fleet of agent-driven machines.**
One logical source of truth (git commits) · N physical mirror replicas · end-to-end verification.

> 一套给「多台无人值守、由 AI agent 驱动」的机器共用的**记忆 + 技能共享层**方案。
> 本方案不是设计出来的 —— 是**踩坑踩出来的**。`docs/FAILURE-MODES.md` 里每一条都是真实事故。

## 它解决什么问题

多台机器、多个 agent 同时读写同一份「长期记忆 + 技能库」时，会遇到三类故障：

| 故障 | 症状 | 本方案的对策 |
|---|---|---|
| **静默分叉** | 各机 git origin 指向不同仓库 → **能推、拉不到**，没有任何报错 | 统一 origin + `verify-live.sh` 端到端逐台校验 |
| **编号撞号** | 两台机器各自分配 `mem-0212` → 同一个号两份不同内容 | `next-mem-id.sh` 跨全部镜像取号 + **per-agent inbox 写入通道** + pre-commit 守卫 |
| **半截迁移** | 建好了新镜像，却忘了改各机 origin | `verify-live.sh` 把"活副本是否真的更新"变成可检测事实 |

## 架构（一句话）

> **逻辑上一个真相（git commit hash），物理上多份副本（镜像仓）。
> 一致性不靠"放在一起"，靠「校验」和「纪律」。**

```
                        ┌──────────────────────────┐
                        │  逻辑真相 = git commit    │
                        └────────────┬─────────────┘
        ┌───────────────┬────────────┴────────────┬───────────────┐
        ▼               ▼                         ▼               ▼
   mirror A        mirror B                  mirror C        (热备，可随时顶)
        │               │                         │
        ▼               ▼                         ▼
   machine 1       machine 2                 machine 3      ← 各自从最近的镜像拉
   (工作副本)      (工作副本)                (工作副本)
        └────────── verify-live.sh 逐台校验 HEAD ──────────┘
```

## 组件

| 脚本 | 作用 |
|---|---|
| `scripts/shared-sync.sh` / `.ps1` | 多镜像同步：从首个可达镜像 fetch → **只 ff、绝不自动合并** → 推给所有可达镜像 |
| `scripts/verify-live.sh` | **★ 活副本端到端校验**：逐台 ssh 查 HEAD 与镜像 tip，不一致即报警并非零退出 |
| `scripts/next-mem-id.sh` | **★ 跨全部镜像**取已用最大编号，输出下一个空闲编号（禁止数本地 +1） |
| `scripts/check-integrity.sh` | 重复 id / INDEX 不一致 / 残留冲突标记 / frontmatter 缺失 扫描 |
| `scripts/inbox-submit.sh` | **★ 无冲突写入通道**：每个 agent 只写自己的 `<agent>-<时间戳>.md` |
| `scripts/promote-inbox.sh` | 中心化晋升：由唯一的 promoter 分配正式编号并落库 |
| `scripts/install-hooks.sh` + `hooks/pre-commit` | **★ 拒绝引入重复编号的提交** |

## 快速开始

```bash
git clone <this-repo> && cd myainet-shared-layer
bash scripts/check-integrity.sh /path/to/your/vault   # 先体检
bash scripts/next-mem-id.sh       /path/to/your/vault   # 下一个可用编号
bash scripts/install-hooks.sh     /path/to/your/vault   # 装 pre-commit 守卫
bash scripts/verify-live.sh                             # 校验各机是否真的同步
```

## 设计取舍（诚实说）

- **没有选 Obsidian Sync / Syncthing**：它们解决的是"文件怎么过去"，我们遇到的是"多个写者怎么不打架"。
  且 Syncthing 的冲突处理是生成 `.sync-conflict` 副本文件，对**需要合并的文本知识库**比 git 更糟。
- **没有选单点存储**：单点能消除"不一致"，但会换成"那一个地方挂了全网读写停"。我们选的是
  **一个逻辑真相 + 多物理副本**，并用校验兜住不一致。
- **没有选 CRDT**：对几 MB 的 Markdown、低频写入，CRDT 的复杂度收益不划算。

## 借用与致谢

本方案从下面两个项目**借了思想**（代码为独立实现）：

- [Noelune/unified-agent-memory](https://github.com/Noelune/unified-agent-memory) ——
  **per-agent 时间戳 inbox 作为唯一写入通道 + 中心化晋升**，用结构消除编号冲突（本方案 `inbox-submit.sh` / `promote-inbox.sh` 的思路来源）。
- [marcusquinn/aidevops](https://github.com/marcusquinn/aidevops) ——
  **pre-commit 拒绝重复 ID** 的守卫模式（本方案 `hooks/pre-commit` 的思路来源）。

## ☕ 赞赏

这套东西**不是设计出来的，是踩坑踩出来的** —— 故障库里的每一条都对应一次真实的排障，
包括「校验器把自己排除在外」「注释吞掉下一行代码」这类骗过了所有绿灯的事故。

如果它帮你省下了时间，可以请我喝杯咖啡：

| 微信赞赏码 | 支付宝 |
|:---:|:---:|
| <img src="docs/assets/wechat-reward.png" width="240" alt="微信赞赏码"> | <img src="docs/assets/alipay-reward.jpg" width="240" alt="支付宝收款码"> |

> 收款码只收不付；扫码后请自行核对收款方名称。

## License

MIT
