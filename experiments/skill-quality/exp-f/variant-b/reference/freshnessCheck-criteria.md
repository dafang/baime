# freshnessCheck Decision Criteria

## Step 4: freshness check (single LLM call via Task agent)

Spawn a Task agent with the following prompt (substitute literal values for all
`<VARIABLE>` placeholders):

> You are performing a freshness check on a task template.
>
> **Template slug**: `<SLUG>`
> **Last used**: `<TMPL_LAST_USED>`
> **Applicable when**: `<TMPL_APPLICABLE_WHEN>`
> **Today's date**: `<TODAY>`
>
> **Template body**:
> ```
> <TMPL_BODY>
> ```
>
> **Git changes since last use** (`git log --oneline --since=<TMPL_LAST_USED>`):
> ```
> <GIT_CHANGES>
> ```
>
> Decide whether the template is still valid for its stated purpose.
> Consider:
> - Do the Phase steps and DoD commands still match the current project structure?
> - Have any scripts or tools that the template **directly invokes** (e.g. in Phase bash
>   blocks or DoD commands) been renamed or removed? Check only what the executor runs,
>   not what those scripts do internally.
> - Do the git changes suggest the overall workflow has fundamentally changed?
>
> **Important**: do NOT check files that are only mentioned in descriptive text, or files
> that a script modifies internally. Only the script/tool entry points matter.
>
> Your output MUST begin with exactly one of:
> - `FRESH` — template is still valid; no changes required
> - `STALE:<one-line reason>` — template needs updating
>
> After the first line, you may write a brief explanation (optional).

## Key decision rules

- Changes to documentation, CHANGELOG, or README → `FRESH` (do not affect template validity)
- Changes to scripts/tools **directly invoked** by the template → `STALE`
- Changes to workflow steps the template depends on → `STALE`
- Changes completely outside the template's `applicableWhen` domain → `FRESH`
- Architectural changes that make the template's approach obsolete → `STALE`
