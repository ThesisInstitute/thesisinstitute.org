# The Thesis Institute — landing site

Static landing for **thesisinstitute.org** (the org). The forecasting app is a
separate Next.js project served at **app.thesisinstitute.org** (Vercel project
`thesis-forecasts`, built from `site/` in [MaxGhenis/brier](https://github.com/MaxGhenis/brier)).

The Chronicle record app used to live here as `ledger/`; on 2026-08-30 it moved
to its own repo,
[ThesisInstitute/chronicle.institute](https://github.com/ThesisInstitute/chronicle.institute),
with its history. Nothing about `chronicle.institute` is built from this repo
any more.

## Domains

| URL | Serves | Project |
|-----|--------|---------|
| `thesisinstitute.org` | this static landing | `thesis-institute` |
| `www.thesisinstitute.org` | → 307 → apex | `thesis-institute` |
| `thesisinstitute.org/thesis` | → 308 → app `/thesis` | `thesis-institute` (`vercel.json`) |
| `app.thesisinstitute.org` | the forecasting app | `thesis-forecasts` (brier repo `site/`) |
| `api.thesisinstitute.org` | API | `thesis-api` (brier repo `forecast-api/`) |
| `farness.ai`, `brieralmanac.org` | legacy → app | redirects |
| `chronicle.institute` | the record app — **[ThesisInstitute/chronicle.institute](https://github.com/ThesisInstitute/chronicle.institute)**, not this repo | `chronicle` |
| `ledger.thesisinstitute.org` | → `chronicle.institute` | `chronicle` |

Vercel team: `policy-engine`.

## Deploy = git push to main (since 2026-07-02)

All three projects are **git-integrated**: pushing `main` deploys production.

- Landing: push to [MaxGhenis/thesis-institute](https://github.com/MaxGhenis/thesis-institute) `main`.
- App: push to [MaxGhenis/brier](https://github.com/MaxGhenis/brier) `main`
  (project `thesis-forecasts`, root directory `site/`).
- API: same repo (project `thesis-api`, root directory `forecast-api/`).

Both monorepo projects skip builds when their root directory didn't change
(`git diff --quiet HEAD^ HEAD -- .`), so daily `records/` commits don't
redeploy anything. Commits with `[skip ci]` skip Vercel too.

**Do not CLI-deploy.** `vercel --prod` from any checkout still captures the
production alias and bypasses review, tests, and the commit history — the
cause of both 2026-06 incidents. The old `deploy*.sh` scripts remain only as
break-glass for when GitHub or the git integration is down, and refuse to run
without `THESIS_BREAK_GLASS=1`.

## Verify / monitor

```bash
./verify.sh         # one pass; exit 0 = healthy, 1 = a surface is wrong
```

`verify.sh` checks the **bare** production URLs a browser requests (never
`?cb=` cache-busters — they mask stale edge copies), including every JSON
surface the daily recorder in MaxGhenis/brier snapshots
(`log.json`, `ledger.json`, `targets.json`, `brier/reward.json`). Keep that
list in sync with `.github/workflows/record-forecasts.yml` there.

A launchd agent (`org.thesisinstitute.canary`) runs `monitor.sh` daily and
raises a macOS notification plus an email alert via `gog` (and logs to
`.canary.log`) if any canary fails.

## Worktrees must never link to production

Rule kept from the 2026-06-08 incident: never `vercel link` a worktree to a
production project; delete any `site/.vercel/` directory found in a worktree.
Git integration makes push-to-main the only sanctioned deploy path, but a
lingering link plus a raw `vercel --prod` can still capture the alias.

## The 2026-06 incidents (why the guardrails exist)

`thesisinstitute.org` served a **stale old-app build** for hours (2026-06-05),
and `app.thesisinstitute.org` regressed for two days (2026-06-08) when an
agent worktree with a `.vercel` link ran raw `vercel --prod` from a stale
base. Root causes and lessons:

1. **Stale edge cache.** Cached HTML with a long TTL survives a project
   switch; only a **fresh production deploy** (new deployment ID) purges it.
2. **Alias capture.** Any CLI production deploy captures the alias, whatever
   checkout it came from. Git integration removes that class: production only
   builds from merged `main`.
3. **Verification masked the bug.** `?cb=` cache-busters hit a fresh edge key
   and looked healthy while bare URLs served the stale copy. Always verify
   bare URLs.

### If a canary fails

Push a fix (or an empty commit) to the affected repo's `main` — the git
deploy is the redeploy. Then re-run `./verify.sh`. Break-glass only:
`THESIS_BREAK_GLASS=1 ./deploy.sh` (or `deploy-app.sh` / `deploy-api.sh`).

## License

Code in this repository is released under the [MIT License](LICENSE). Original text and figures are released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) with attribution to Thesis Institute. Third-party data and materials keep their own terms.
