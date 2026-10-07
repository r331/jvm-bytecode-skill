#!/bin/bash
# Usage: summarize.sh <results.jsonl>
# Prints a Markdown summary: per task x mode pass rate and mean case pass
# fraction, then the skill-vs-baseline delta per task and overall.
# Agent error trials ("agent_error":true) are counted in their own column and
# excluded from pass rate, case pass, duration, and failure reasons. Lines
# without the agent_error or leak_suspect fields (older runs) count as false.
set -u
f="${1:?usage: summarize.sh <results.jsonl>}"

awk '
function str(line, key,   m) {
  if (match(line, "\"" key "\":\"[^\"]*\"")) {
    m = substr(line, RSTART, RLENGTH); sub("^\"" key "\":\"", "", m); sub("\"$", "", m); return m
  }
  return ""
}
function num(line, key,   m) {
  if (match(line, "\"" key "\":[-0-9.a-z]+")) {
    m = substr(line, RSTART, RLENGTH); sub("^\"" key "\":", "", m); return m
  }
  return ""
}
function pct(x) { return sprintf("%.0f%%", 100 * x) }
function sgn(x) { return (x > 0 ? "+" : "") sprintf("%.0f pp", 100 * x) }
function rate(a, b) { return b > 0 ? sprintf("%s (%d/%d)", pct(a / b), a, b) : "n/a (0/0)" }
function delta(a, b, c, d) { return (b > 0 && d > 0) ? sgn(a / b - c / d) : "n/a" }
/^\{/ {
  t = str($0, "task"); m = str($0, "mode")
  if (t == "" || m == "") next
  k = t SUBSEP m
  if (!(t in seen_t)) { seen_t[t] = 1; tasks[++nt] = t }
  if (!(m in seen_m)) { seen_m[m] = 1; modes[++nm] = m }
  n[k]++; N[m]++
  if (num($0, "leak_suspect") == "true") { lk[k]++; LK[m]++ }
  if (num($0, "agent_error") == "true") { ae[k]++; AE[m]++; AET++; next }
  g[k]++; G[m]++
  if (num($0, "pass") == "true") { p[k]++; P[m]++ }
  ct = num($0, "cases_total") + 0; cp = num($0, "cases_passed") + 0
  frac[k] += (ct > 0 ? cp / ct : 0); F[m] += (ct > 0 ? cp / ct : 0)
  dur[k] += num($0, "duration_s") + 0
  if (num($0, "pass") != "true") { r = str($0, "reason"); sub(":.*", "", r); if (!((k, r) in fr)) { fr[k, r] = 1; reasons[k] = reasons[k] (reasons[k] == "" ? "" : "; ") r } }
}
END {
  if (nt == 0) { print "No results."; exit }
  print "# Eval summary"
  print ""
  print "| task | mode | trials | agent errors | leak suspects | pass rate | mean case pass | mean duration | failure reasons |"
  print "|---|---|---|---|---|---|---|---|---|"
  for (i = 1; i <= nt; i++) for (j = 1; j <= nm; j++) {
    k = tasks[i] SUBSEP modes[j]
    if (!(k in n)) continue
    printf "| %s | %s | %d | %d | %d | %s | %s | %s | %s |\n", tasks[i], modes[j], n[k], ae[k], lk[k], rate(p[k], g[k]),
      (g[k] > 0 ? pct(frac[k] / g[k]) : "n/a"), (g[k] > 0 ? sprintf("%.0fs", dur[k] / g[k]) : "n/a"), reasons[k]
  }
  for (j = 1; j <= nm; j++) {
    m = modes[j]
    printf "| **all** | %s | %d | %d | %d | %s | %s | | |\n", m, N[m], AE[m], LK[m], rate(P[m], G[m]), (G[m] > 0 ? pct(F[m] / G[m]) : "n/a")
  }
  print ""
  printf "Agent errors (%d in total) are trials where the agent produced no files and exited non-zero, timed out, or logged an infrastructure error such as a credential, rate limit, or network failure.\n", AET
  print "They are excluded from the pass rate, mean case pass, mean duration, failure reasons, and the deltas below; the trials column includes them."
  print "Leak suspects are trials whose agent.log mentions the repository path, evals/tasks, solution/, or .claude/skills; check their transcripts."
  if (("skill" in seen_m) && ("baseline" in seen_m)) {
    print ""
    print "## Skill vs baseline"
    print ""
    print "| task | pass rate delta | case pass delta |"
    print "|---|---|---|"
    for (i = 1; i <= nt; i++) {
      ks = tasks[i] SUBSEP "skill"; kb = tasks[i] SUBSEP "baseline"
      if (!(ks in n) || !(kb in n)) continue
      printf "| %s | %s | %s |\n", tasks[i], delta(p[ks], g[ks], p[kb], g[kb]), delta(frac[ks], g[ks], frac[kb], g[kb])
    }
    printf "| **all** | %s | %s |\n", delta(P["skill"], G["skill"], P["baseline"], G["baseline"]), delta(F["skill"], G["skill"], F["baseline"], G["baseline"])
  }
}
' "$f"
