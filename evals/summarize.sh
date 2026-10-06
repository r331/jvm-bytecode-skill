#!/bin/bash
# Usage: summarize.sh <results.jsonl>
# Prints a Markdown summary: per task x mode pass rate and mean case pass
# fraction, then the skill-vs-baseline delta per task and overall.
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
/^\{/ {
  t = str($0, "task"); m = str($0, "mode")
  if (t == "" || m == "") next
  k = t SUBSEP m
  if (!(t in seen_t)) { seen_t[t] = 1; tasks[++nt] = t }
  if (!(m in seen_m)) { seen_m[m] = 1; modes[++nm] = m }
  n[k]++
  if (num($0, "pass") == "true") p[k]++
  ct = num($0, "cases_total") + 0; cp = num($0, "cases_passed") + 0
  frac[k] += (ct > 0 ? cp / ct : 0)
  dur[k] += num($0, "duration_s") + 0
  if (num($0, "pass") != "true") { r = str($0, "reason"); sub(":.*", "", r); fails[k, r]++; if (!((k, r) in fr)) { fr[k, r] = 1; reasons[k] = reasons[k] (reasons[k] == "" ? "" : "; ") r } }
  N[m]++; if (num($0, "pass") == "true") P[m]++; F[m] += (ct > 0 ? cp / ct : 0)
}
END {
  if (nt == 0) { print "No results."; exit }
  print "# Eval summary"
  print ""
  print "| task | mode | trials | pass rate | mean case pass | mean duration | failure reasons |"
  print "|---|---|---|---|---|---|---|"
  for (i = 1; i <= nt; i++) for (j = 1; j <= nm; j++) {
    k = tasks[i] SUBSEP modes[j]
    if (!(k in n)) continue
    printf "| %s | %s | %d | %s (%d/%d) | %s | %.0fs | %s |\n", tasks[i], modes[j], n[k], pct(p[k] / n[k]), p[k], n[k], pct(frac[k] / n[k]), dur[k] / n[k], reasons[k]
  }
  for (j = 1; j <= nm; j++) {
    m = modes[j]
    printf "| **all** | %s | %d | %s (%d/%d) | %s | | |\n", m, N[m], pct(P[m] / N[m]), P[m], N[m], pct(F[m] / N[m])
  }
  if (("skill" in seen_m) && ("baseline" in seen_m)) {
    print ""
    print "## Skill vs baseline"
    print ""
    print "| task | pass rate delta | case pass delta |"
    print "|---|---|---|"
    for (i = 1; i <= nt; i++) {
      ks = tasks[i] SUBSEP "skill"; kb = tasks[i] SUBSEP "baseline"
      if (!(ks in n) || !(kb in n)) continue
      printf "| %s | %s | %s |\n", tasks[i], sgn(p[ks] / n[ks] - p[kb] / n[kb]), sgn(frac[ks] / n[ks] - frac[kb] / n[kb])
    }
    printf "| **all** | %s | %s |\n", sgn(P["skill"] / N["skill"] - P["baseline"] / N["baseline"]), sgn(F["skill"] / N["skill"] - F["baseline"] / N["baseline"])
  }
}
' "$f"
