#!/usr/bin/env bash
# verify.sh — canary checks for thesisinstitute.org and its app subdomain.
#
# Checks the BARE production URLs a real browser actually requests — NO
# cache-busting query strings. Cache-busted (`?cb=`) requests hit a fresh edge
# cache key and can show correct content while the bare URL still serves a stale
# copy. That masking is exactly what hid the 2026-06 stale-old-app incident, so
# this script deliberately hits the same doors a browser does.
#
# Usage:  ./verify.sh [attempts] [scope]   attempts defaults to 1; scope is
#         all|apex|app|api (default all). Deploy scripts pass their OWN surface
#         so a coordinated multi-surface release can't deadlock one deploy on
#         another surface's pending canaries (2026-06-11 rollout lesson).
# Exit:   0 = every canary passed, 1 = at least one failed.

set -uo pipefail

ATTEMPTS="${1:-1}"
SCOPE="${2:-all}"
GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; NC=$'\033[0m'

status() { curl -sS -o /dev/null -w '%{http_code}' "$1"; }
status_follow() { curl -sSL -o /dev/null -w '%{http_code}' "$1"; }
location() { curl -sSI "$1" | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r'; }

pass() { printf "  ${GREEN}PASS${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; FAIL=1; }

checks_apex() {
  local code loc html

  # --- apex: must serve the fresh static institute landing ---
  code=$(status https://thesisinstitute.org/)
  html=$(curl -sS https://thesisinstitute.org/)
  [ "$code" = 200 ] && pass "apex /                      200" || fail "apex /                      $code (want 200)"
  grep -q "A sampling of forecasts" <<<"$html" \
    && pass "apex /  has institute content" \
    || fail "apex /  MISSING 'A sampling of forecasts' — stale old-app build?"
  grep -q 'href="/paper"' <<<"$html" \
    && fail "apex /  still links /paper — OLD APP nav is being served" \
    || pass "apex /  no /paper link (old-app marker absent)"

  # Withdrawn forecasts can return 200, so inspect content and run-record links.
  python3 "$(dirname "${BASH_SOURCE[0]}")/scripts/check_forecast_links.py" https://thesisinstitute.org/ \
    && pass "apex /  featured forecasts are published" \
    || fail "apex /  a featured forecast is missing or withdrawn"

  # --- apex /thesis -> 308 -> app/thesis ---
  code=$(status https://thesisinstitute.org/thesis)
  loc=$(location https://thesisinstitute.org/thesis)
  { [ "$code" = 308 ] && [[ "$loc" == *app.thesisinstitute.org/thesis* ]]; } \
    && pass "apex /thesis                308 -> app/thesis" \
    || fail "apex /thesis                $code -> $loc (want 308 -> app.thesisinstitute.org/thesis)"

  # --- apex /paper -> 404 (old Research route must be gone) ---
  code=$(status https://thesisinstitute.org/paper)
  [ "$code" = 404 ] && pass "apex /paper                 404" \
                    || fail "apex /paper                 $code (want 404; old app served 200)"

  # --- www -> redirect to apex ---
  code=$(status https://www.thesisinstitute.org/)
  loc=$(location https://www.thesisinstitute.org/)
  { [[ "$code" =~ ^30[78]$ ]] && [[ "$loc" == *thesisinstitute.org/* ]]; } \
    && pass "www                         $code -> apex" \
    || fail "www                         $code -> $loc (want 307/308 -> apex)"

}

checks_app() {
  local code loc html

  # --- app /forecasts: the institute's 'Forecasts' link target ---
  code=$(status_follow https://app.thesisinstitute.org/forecasts)
  html=$(curl -sSL https://app.thesisinstitute.org/forecasts)
  [ "$code" = 200 ] && pass "app /forecasts              200" \
                    || fail "app /forecasts              $code (want 200; stale build 308'd to apex -> 404)"
  grep -q 'href="/log"' <<<"$html" \
    && pass "app /forecasts has ledger nav (/log)" \
    || fail "app /forecasts MISSING /log nav — pre-ledger build?"

  # --- app cell pages stay embeddable (scorecard /plan iframes depend on this) ---
  framing=$(curl -sSI https://app.thesisinstitute.org/medicaid-call-wait-mar-2027-work-req-deadline-holds | grep -ci 'x-frame-options\|frame-ancestors' || true)
  [ "$framing" = 0 ] && pass "app cells embeddable (no framing headers)" \
                     || fail "app cells NOT embeddable — XFO/frame-ancestors present (breaks scorecard /plan embeds)"

  # --- app /about: the institute's 'About' link target ---
  code=$(status_follow https://app.thesisinstitute.org/about)
  [ "$code" = 200 ] && pass "app /about                  200" \
                    || fail "app /about                  $code (want 200)"

  # --- app /markets: legacy tree must 308 to /forecasts (consolidated 2026-06) ---
  code=$(status https://app.thesisinstitute.org/markets)
  loc=$(location https://app.thesisinstitute.org/markets)
  { [ "$code" = 308 ] && [[ "$loc" == */forecasts* ]]; } \
    && pass "app /markets                308 -> /forecasts" \
    || fail "app /markets                $code -> $loc (want 308 -> /forecasts; old build served a duplicate page)"

  # --- app /log + /log.json: the Thesis Log must serve (ledger build marker) ---
  code=$(status_follow https://app.thesisinstitute.org/log)
  [ "$code" = 200 ] && pass "app /log                    200" \
                    || fail "app /log                    $code (want 200)"
  schema=$(curl -sL https://app.thesisinstitute.org/log.json 2>/dev/null | head -c 400 | grep -o 'thesis_log_v3')
  [ "$schema" = "thesis_log_v3" ] && pass "app /log.json               schema thesis_log_v3" \
                                  || fail "app /log.json               missing thesis_log_v3 schema"

  # --- every surface the daily recorder (MaxGhenis/brier record-forecasts.yml)
  #     snapshots must serve its schema. /specs.json was retired 2026-06-30 and
  #     the recorder failed for two days before anyone noticed — this canary is
  #     what should have caught it. Keep this list in sync with the workflow.
  local surface url marker got
  for surface in "ledger.json policyengine_ledger_v1" \
                 "targets.json thesis_target_architecture_manifest_v2" \
                 "brier/reward.json brier_reward_export_v2"; do
    url="${surface%% *}"; marker="${surface##* }"
    got=$(curl -sL -m 30 "https://app.thesisinstitute.org/$url" 2>/dev/null | head -c 400 | grep -o "$marker")
    [ "$got" = "$marker" ] && pass "app /$url  schema $marker" \
                           || fail "app /$url  missing $marker — recorder surface broken/renamed"
  done

  # --- app root must SERVE the app, not redirect to the apex ---
  code=$(status https://app.thesisinstitute.org/)
  [ "$code" = 200 ] && pass "app /                       200 (serves app, not redirect)" \
                    || fail "app /                       $code (want 200; stale build redirected to apex)"

}

checks_api() {
  local code

  # --- api health ---
  code=$(status https://api.thesisinstitute.org/health)
  [ "$code" = 200 ] && pass "api /health                 200" \
                    || fail "api /health                 $code (want 200)"

  # --- api stream: must allow the app origin AND emit an event quickly.
  #     A stream that holds the connection open without sending is exactly the
  #     failure that pinned the app on 'connecting' (2026-06-09).
  local hdrs body acao
  hdrs=$(curl -sS -m 4 -D - -o /dev/null -H "Origin: https://app.thesisinstitute.org" \
    "https://api.thesisinstitute.org/forecasts/cpi-u-annual-2026/stream" 2>/dev/null)
  acao=$(awk 'tolower($1)=="access-control-allow-origin:"{print $2}' <<<"$hdrs" | tr -d '\r')
  [ "$acao" = "https://app.thesisinstitute.org" ] \
    && pass "api stream CORS             allows app origin" \
    || fail "api stream CORS             ACAO='$acao' (want https://app.thesisinstitute.org)"
  body=$(curl -sS -m 8 -H "Origin: https://app.thesisinstitute.org" \
    "https://api.thesisinstitute.org/forecasts/cpi-u-annual-2026/stream" 2>/dev/null | head -c 400)
  grep -q "^event:" <<<"$body" \
    && pass "api stream                  first event within 8s" \
    || fail "api stream                  NO event within 8s — hung/buffered stream"
}

run_checks() {
  FAIL=0
  case "$SCOPE" in
    apex) checks_apex ;;
    app)  checks_app ;;
    api)  checks_api ;;
    all)  checks_apex; checks_app; checks_api ;;
    *) echo "unknown scope: $SCOPE (want all|apex|app|api)"; return 1 ;;
  esac
  return $FAIL
}

echo "Thesis Institute canary checks — $(date '+%Y-%m-%d %H:%M:%S')"
for ((i = 1; i <= ATTEMPTS; i++)); do
  if run_checks; then
    echo "${GREEN}All canaries passed.${NC}"
    exit 0
  fi
  if [ "$i" -lt "$ATTEMPTS" ]; then
    echo "${DIM}  retry $i/$ATTEMPTS — waiting 6s for propagation…${NC}"
    sleep 6
  fi
done
echo "${RED}CANARY FAILURE — a surface is serving stale/incorrect content.${NC}"
echo "Fix: redeploy the affected project to PRODUCTION (a new deployment ID purges the"
echo "edge cache), then re-run. See README.md → 'If a canary fails'. Always check bare URLs."
exit 1
