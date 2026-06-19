---
name: task-from-template
description: "Creates a Ready-status backlog task from a pre-approved template, bypassing the full review cycle. Performs a single LLM freshness check against recent git changes; if FRESH creates the task immediately, if STALE explains why and prompts the user to regenerate via task-to-backlog."
argument-hint: <template-slug>
allowed-tools: Read, Glob, Grep, Bash, Agent
contracts:
  - grep: "FRESH"
    target: self
  - grep: "STALE"
    target: self
  - grep: "templates"
    target: self
---

λ(slug) → taskFromTemplate(slug)

## Spec

Template :: {
  slug          : String,
  title         : String,
  lastUsed      : Date,
  applicableWhen: String,
  body          : String
}

data FreshnessVerdict = FRESH | STALE Reason

taskFromTemplate :: Slug → BacklogTask | Stopped
taskFromTemplate(slug) = {
  tmpl:    loadTemplate(repo, slug),
  changes: recentChanges(tmpl.lastUsed),
  verdict: freshnessCheck(tmpl, changes),
  if (verdict == STALE r): return Stopped,
  return:  createTask(tmpl)
}

-- freshnessCheck decision criteria: see reference/freshnessCheck-criteria.md
freshnessCheck :: (Template, Changes) → FreshnessVerdict
