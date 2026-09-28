# 待轮换凭据（SECURITY-PENDING）

> 2026-09-29 立。**这些凭据曾以明文进入过版本控制，因此它们在 git 历史里仍可被读到。**
> **删文件不是修复 —— 只有去服务商后台"轮换/吊销"才是。**

| # | 凭据 | 曾出现位置 | 现状 | 你要做的 |
|---|---|---|---|---|
| 1 | **GitHub PAT**（`repo` 全权） | `skills/e-card-namecard/editor.html` 第 445 / 1921 行 | ✅ 已从文件清空 | 去 https://github.com/settings/tokens **删掉旧的那个**；如需再用就新建一个，**只放进「发布设置」（浏览器 localStorage）** |
| 2 | **UUMit api_key** | `skills/uumit-agent/memory/uumit-auth.json` | ✅ 已从 git 移出（文件留在磁盘，技能照常工作） | 去 UUMit 平台后台**吊销并重新生成**；新值由技能的 `auth.js` 自动写回同一文件（已 gitignore） |

## 为什么只是"移出"还不够

- git 的对象库是**只增**的：即使现在把文件删掉，`git log -p` / `git show` 依然能取回那串值。
- 因此**轮换是唯一真正的修复**；"移出 + gitignore"只是**止住继续扩散**。
- 本机是私有网络（5 台自有机器 + 自建镜像），**凭据没有出现在公开网上**（已核对公开仓 6 个文件全部干净）。

## 轮换完请做

1. 把本文件里对应那行改成 `✅ 已轮换（日期）`。
2. 跑 `bash scripts/check-credentials.sh <层根>` 确认 `CRED=OK`。
3. 跑 `bash scripts/check-integrity.sh <层根>` 确认 `INTEGRITY=PASS`。

> 如果希望**彻底**从历史里抹掉（需要全集群 force push，属破坏性操作），
> 请在轮换后单独决定 —— 而**即便抹掉历史，也仍然必须轮换**。
