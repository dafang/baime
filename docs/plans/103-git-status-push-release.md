# Plan: 检查 git 状态；push ；发布

## Context
baime 当前版本为 1.1.0，本地 main 领先 origin/main 5 个提交（包括 loop-backlog 功能改进和文档更新）。CHANGELOG.md 的 [Unreleased] 节记录了若干新变更。本任务需要：将 [Unreleased] 提升为新版本号，通过 pre-release 验证，执行 release 脚本完成版本提交、打 tag、push，并确认 GitHub Release 创建成功。

## Phase 1: 验证 git 状态
运行以下命令确认前置条件，并记录当前版本：
- `git status --porcelain | grep -v '^??'` → 应为空（无未提交的已追踪文件）
- `git rev-parse --abbrev-ref HEAD` → 应为 main
- `git log --oneline origin/main..HEAD` → 应有输出（有待推送提交）

### DoD
- [ ] `git status --porcelain | grep -v '^??' | diff - /dev/null`
- [ ] `git rev-parse --abbrev-ref HEAD | grep -q '^main$'`
- [ ] `git log --oneline origin/main..HEAD | grep -q '.'`

## Phase 2: 确定新版本号并更新 CHANGELOG
读取 CHANGELOG.md 的 `## [Unreleased]` 节内容，判断变更类型（新功能→minor bump，仅修复→patch bump，破坏性变更→major bump）。步骤：
1. 将 `## [Unreleased]` 重命名为 `## [X.Y.Z] - 2026-06-16`（X.Y.Z 为新版本号）
2. 在其上方新增空的 `## [Unreleased]` 节作占位
3. 将新版本号（格式 `vX.Y.Z`）写入 `docs/tasks/git-push-release-version.txt`，不含换行以外的多余内容

### DoD
- [ ] `grep -qP '## \[\d+\.\d+\.\d+\] - 2026-06-16' CHANGELOG.md`
- [ ] `grep -q '## \[Unreleased\]' CHANGELOG.md`
- [ ] `grep -qP '^v\d+\.\d+\.\d+$' docs/tasks/git-push-release-version.txt`

## Phase 3: 执行 pre-release 验证
使用 Phase 2 写入的版本号文件运行 pre-release 检查脚本，所有 7 项检查须全部通过：
```bash
bash scripts/release/pre-release-check.sh $(cat docs/tasks/git-push-release-version.txt)
```

### DoD
- [ ] `bash scripts/release/pre-release-check.sh $(cat docs/tasks/git-push-release-version.txt)`

## Phase 4: 执行 release 脚本
使用 Phase 2 写入的版本号运行 release 脚本（自动完成版本写入 manifest、commit、annotated tag、push main、push tag）：
```bash
bash scripts/release/release.sh $(cat docs/tasks/git-push-release-version.txt)
```

### DoD
- [ ] `git ls-remote --tags origin refs/tags/$(cat docs/tasks/git-push-release-version.txt) | grep -q '.'`
- [ ] `git log --oneline origin/main..HEAD | diff - /dev/null`

## Phase 5: 验证 GitHub Release
等待约 60 秒后验证 GitHub Actions release workflow 成功完成，GitHub Release 对象可见：
```bash
gh run list --repo yaleh/baime --workflow release.yml --limit 3
gh release view $(cat docs/tasks/git-push-release-version.txt) --repo yaleh/baime
```

### DoD
- [ ] `gh run list --repo yaleh/baime --workflow release.yml --limit 1 --json conclusion --jq '.[0].conclusion' | grep -q 'success'`
- [ ] `gh release view $(cat docs/tasks/git-push-release-version.txt) --repo yaleh/baime --json tagName --jq '.tagName' | grep -qP '^v\d+\.\d+\.\d+$'`

## Constraints
- 不手动执行 `git push`；让 release.sh 统一管理所有 push，保持 commit 与 tag 的原子性
- 不 force-push，不删除或重建已推送的 tag
- `jq` 须已安装（`command -v jq`）；若未安装，先执行 `sudo apt-get install -y jq`
- `docs/tasks/git-push-release-version.txt` 仅包含版本号（如 `v1.2.0`），不含其他内容

## Acceptance Gate
- [ ] `git log --oneline origin/main..HEAD | diff - /dev/null`
- [ ] `gh release view $(cat docs/tasks/git-push-release-version.txt) --repo yaleh/baime --json tagName --jq '.tagName' | grep -qP '^v\d+\.\d+\.\d+$'`
