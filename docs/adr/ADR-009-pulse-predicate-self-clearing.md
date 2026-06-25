---
adr: "009"
title: "电平触发脉冲的谓词必须自清除：避免空闲会话被陈旧事件无限唤醒"
status: Accepted
date: 2026-06-25
applies-to: ["plugin/scripts/basic-daemon.js", "scripts/daemon-routing.test.js", "plugin/skills/loop-backlog/**"]
enforcement: static
stage: [check]
lint: |
  # 电平触发 pulse 每个间隔都会复发所有匹配谓词的 id；因此每个被 pulse 复发的通道，
  # 其谓词必须"自清除"——actionable 条件一旦解决就停止匹配。守住已知的非平凡通道:
  # child-done 必须 gated 在父 epic 处于 "Epic: Awaiting Children"。
  daemon="plugin/scripts/basic-daemon.js"
  test -f "$daemon" || { echo "ADR-009: missing $daemon"; exit 1; }
  grep -q "EPIC_AWAITING_CHILDREN_STATUS" "$daemon" \
    || { echo "ADR-009: child-done gate constant missing in daemon"; exit 1; }
  grep -q "pmeta.status === EPIC_AWAITING_CHILDREN_STATUS" "$daemon" \
    || { echo "ADR-009: child-done predicate not gated on parent epic Awaiting Children"; exit 1; }
  # 冷启动重放策略：Monitor 必须从日志 EOF 起，不重放历史。
  skill="plugin/skills/loop-backlog/SKILL.md"
  grep -q 'OFFSET="\$LOG_SIZE"' "$skill" \
    || { echo "ADR-009: cold-start Monitor must start at log EOF (OFFSET=LOG_SIZE)"; exit 1; }
  # 回归覆盖必须存在。
  grep -q "child-done suppressed" scripts/daemon-routing.test.js \
    || { echo "ADR-009: missing child-done suppression regression test"; exit 1; }
---

## Context

unified B″ daemon（`basic-daemon.js`）用两套机制把任务看板状态转成事件:

- **边沿触发** `timer`（0.5s）：靠 `notified` Set 去重,状态首次进入谓词集时只发一次。
- **电平触发 pulse** `pulseTimer`（60s,TASK-197 引入）：**无条件**把当前所有匹配谓词的 id
  全部复发一遍,无视 `notified`。目的是 `/clear` 后让空闲 session 能 re-attach——
  "当前还 actionable 的待办"被周期性重申,新 session 总能接上。

pulse 的正确性依赖一个**隐性前提**:被复发的谓词是"自清除"的——actionable 条件一旦
被处理掉,谓词就不再匹配,复发自然停止。五个通道里四个满足:

| 通道 | 谓词清除条件 | 自清除? |
|---|---|---|
| basic-ready | 任务被 claim 离开 Ready | ✅ |
| epic-ready | epic 离开 Ready → Decomposing | ✅ |
| proposal/plan-approved | worker 删除 `.ftb-awaiting-*` marker | ✅ |
| **child-done(原实现)** | `Basic: Done` + 有 `parent_task_id` —— **永久终态** | ❌ |

`child-done` 原谓词只看子任务自己:`Basic: Done` 且有 parent。子任务一旦完成就**永远**
满足,即使父 epic 早已 `Epic: Done`、无可调和。于是 pulse 每 60s 把这批 `child-done`
全部复发,worker 每次 `onChildDone` 正确返回 Idle,但每轮烧一个完整 model round-trip,
**永不停止**。这是一个跨项目复现的故障(baime 与 archguard 两个看板都观察到)。

第二个相关故障在消费端:冷启动时 worker 用 `tail -c +${OFFSET}` 从旧 checkpoint 重放
历史事件,而 dispatch 路径**没有廉价预过滤**——对每个重放行都 `backlog task view` + 查
parent 逐文件调查。一批已 settled 的历史 `child-done` 因此让冷启动空转数分钟
(实测一次 3m34s 才 arm Monitor)。

两个故障同源:**电平复发 + 不自清除的谓词,叠加无预过滤的重放**,使"已解决的事件"
反复把空闲会话唤醒。

## Decision

**凡是被电平触发 pulse 复发的通道,其谓词必须自清除:actionable 条件一旦解决就停止
匹配。新增或修改 daemon 通道时,这是 review 与 check 阶段的硬约束。** 配套确立冷启动
的重放策略,使"陈旧历史不被反复调查"。

### 1. child-done 谓词 gated 在父 epic 的可动状态

`onChildDone` 只在父 epic == `Epic: Awaiting Children` 时做事,其余一律 Idle。让 daemon
谓词与 worker 的实际可动条件对齐:

```js
function isChildDone(filepath, tasksDir) {
  const meta = readTaskMeta(filepath);
  if (!meta) return false;
  if (!(meta.hasKindBasic && !meta.hasKindEpic
        && meta.status === BASIC_DONE_STATUS && !!meta.parent_task_id)) return false;
  const parentPath = findTaskFileById(tasksDir, meta.parent_task_id);
  const pmeta = parentPath ? readTaskMeta(parentPath) : null;
  return !!pmeta && pmeta.hasKindEpic && pmeta.status === EPIC_AWAITING_CHILDREN_STATUS;
}
```

父 epic 一旦推进到 Evaluating/Done(或不存在)→ 谓词转 false → pulse 停止复发。
仍保留 child-done 在 pulse 内:当 epic 真在等子任务、且 session 被 `/clear` 过时,pulse
是"确保 epic 最终被 evaluate"的安全网,且天然有界(子任务做完即停)。

### 2. 冷启动从日志 EOF 起,不重放历史

`daemonBootstrap` 的空闲路径将 Monitor 的起点 `OFFSET` 取为当前日志 EOF
(`OFFSET="$LOG_SIZE"`),**只让 arm 之后新到达的事件走完整 dispatch**。这之所以安全,
正是因为五个通道现在**全部**电平触发 + 自清除:

- 真正还 actionable 的状态,pulse 在 ≤60s 内重新浮现;
- `Basic: Ready` 在 arm Monitor *之前*已被 `claimBatch()` 同步认领,不依赖重放;
- 已 settled 的历史(parent 终态、已 reconcile)根本不被重放,零调查。

`.loop-checkpoint` 退化为只写不读的 bookkeeping(供 operator 检视),不再 seed OFFSET。

### 3. 静态 check 守护(本 ADR 的 lint)

按 ADR-008 schema,本 ADR 标 `enforcement: static`,lint 守住已知非平凡实例:
daemon 的 child-done gate 常量与谓词、冷启动 EOF 策略、以及 `daemon-routing.test.js`
的 suppression 回归用例三者齐备。通用原则(任意未来通道都需自清除)无法纯 grep,
由本 Decision 文本在 review 阶段约束 —— 与 ADR-008 的分层路由一致。

## Consequences

- archguard/baime 看板上"父 epic 已 Done 的 child-done 每 60s 弹一次"消失;空闲会话
  真正静默。
- 冷启动不再逐文件调查历史事件:Monitor 从 EOF 起,arm 近即时;epic-lane 事件在
  detach 窗口内变 actionable 时,冷启动后最多 60s 由 pulse 触达(人工 gated lane,可接受)。
- 新增 daemon 通道时必须同时回答"这个谓词如何自清除";否则会复现本类无限唤醒。
- `daemon-version` v9 → v10;`daemon-routing.test.js` 内联谓词镜像新 gate 并加 5e/5f
  两条 suppression 回归;现有调用经默认参数 `tasksDir = path.dirname(filepath)` 兼容。
- 代价:epic-lane 在 detach 窗口的事件冷启动后 ≤60s 才被 pulse 触达,换取零陈旧调查
  与即时 arm。

## Alternatives Considered

- **保留 OFFSET 历史重放,在 dispatch 前加 cap-marker/parent-终态廉价 shell 短路**:
  可行且延迟更低,但需在消费端每个事件类型各写一份预过滤,代码面更大、易漏。被否,
  采用"发射端自清除 + 冷启动 EOF"这对更小且无遗漏风险的组合。
- **把 child-done 移出 pulse(仅边沿触发)**:被否。会丢掉"epic 等子任务期间 session 被
  `/clear`、最后一个子任务已 Done 却未 reconcile"的安全网,epic 将永久卡在
  Awaiting Children。
- **冷启动把 OFFSET 推到 EOF,但不修 child-done 谓词**:被否。只治消费端,daemon 仍把
  stale child-done 写进日志,任何重放/pulse 仍会复活它;两端必须一起改。
- **缩短/关闭 pulse 间隔**:被否。pulse 是 `/clear` 后 re-attach 的核心机制,关掉会破坏
  空闲恢复;根因是谓词不自清除,不是 pulse 本身。
