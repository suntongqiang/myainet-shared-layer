# 凭据吊销操作单（照着点就行）

> 为什么必须做：这两个密钥**曾经明文进过版本控制**，所以 git 历史里还留着。
> **改文件没用，只有去后台把它"作废"才真正安全。**
> 好消息：**它们没有出现在公开网上**（已核对公开仓 6 个文件全部干净），只是在我们 5 台自有机器之间流转过。

---

## 要吊销的两样东西

| # | 东西 | 怎么认它 |
|---|---|---|
| 1 | **GitHub 令牌**（个人访问令牌，权限=能读写你所有仓库） | 以 `ghp_` 开头，**结尾是 `icqpD`** |
| 2 | **UUMit 密钥** | 以 `Lvykme` 开头，共 64 个字符 |

---

## 第一步：吊销 GitHub 旧令牌

1. 手机或电脑浏览器打开 👉 **https://github.com/settings/tokens**
2. **先确认右上角头像是 `suntongqiang`**（别在别的账号里删）
3. 页面标题是 **Tokens (classic)**，下面是一个列表
4. 找那个结尾 `icqpD` 的 → 点它右边的 **Delete** → 弹窗里点确认
   - 名字记不清也没关系：**把列表里的都删掉**，都不影响我们（第 3 步给了不依赖令牌的方案）
5. 点页面上方 **Fine-grained tokens** 标签，如果里面也有，一并 Delete

> 删完列表变空是**正常的**，不用慌。

## 第二步：吊销 UUMit 密钥

1. 打开 👉 **https://m.uumit.com** 并登录
2. 找这些入口之一：**个人中心 / 账号设置 / 安全设置 / API 密钥 / 授权管理 / 开放平台**
3. 找到以 `Lvykme` 开头的那串 → **吊销 / 删除 / 重置**
4. 如果平台没有单独的吊销按钮，就点 **重新授权 / 重新绑定** —— 新密钥会自动覆盖旧的

## 第三步（可选，但推荐）：让我以后不用令牌也能发布

把下面这段公钥加到账号里，以后往 GitHub 推送就**不需要任何令牌**了：

1. 打开 👉 **https://github.com/settings/keys**
2. 点 **New SSH key**
3. **Title** 填：`cunchu-myainet`
4. **Key type** 选：`Authentication Key`
5. **Key** 框里粘贴这整整一行：

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILY/T/gmurjvjvCJQ/BqUGtrNaWI8e1tlszqudcsAEAsw administrator@cunchu
```

6. 点 **Add SSH key**

> 这一步只是"方便"，不做也不影响安全。

---

## 做完之后告诉我，我会

1. **拿那个旧令牌再打一次 GitHub** —— 应该返回 `401`（= 真的失效了，这是我的验证方式）
2. 把 `SECURITY-PENDING.md` 里对应行改成 **✅ 已轮换（日期）**
3. 跑一遍 `check-integrity.sh` 确认 `INTEGRITY=PASS`

## 只想做最少？

**只做第一步（GitHub）** 就够了 —— 它权限最大（能读写你所有仓库）。
UUMit 那个可以晚点再弄。

---

## 备用：GitHub 的"个人访问令牌"页面找不到怎么办

- 直达链接：**https://github.com/settings/tokens**
- 路径：右上角头像 → **Settings** → 左侧最下 **Developer settings** → **Personal access tokens** → **Tokens (classic)**
- 如果你看到的是"没有任何令牌"，说明**已经删过了**，那就直接做第三步。
