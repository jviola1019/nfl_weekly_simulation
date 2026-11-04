#!/usr/bin/env bash
# Runs golden-master.yml's Record step, as written in the workflow, against a fake Rscript that fails a set number
# of times, and checks the step's exit code and the number of attempts. Usage: bash gm_retry_test.sh <workflow.yml>
set -u
WF=$1
W=$(mktemp -d)
Rscript -e 'w <- yaml::read_yaml(commandArgs(TRUE)[1]); s <- Filter(function(x) identical(x$name, "Record"), w$jobs$record$steps)[[1]]; cat(s$run)' "$WF" \
  | sed -e 's/\${{ matrix.dir }}/testdir/g' -e 's/\${{ matrix.commit }}/abc1234/g' > "$W/step.sh"
mkdir -p "$W/bin"
cat > "$W/bin/Rscript" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$COUNT"
[ "$n" -gt "$FAILS" ]
EOF
chmod +x "$W/bin/Rscript"
status=0
check() {  # fails, expected exit, expected attempts
  rm -f "$W/count"
  out=$(COUNT="$W/count" FAILS=$1 RUNNER_TEMP="$W" GM_WEEK=15 GM_SEASON=2024 PATH="$W/bin:$PATH" \
        bash --noprofile --norc -eo pipefail -c "sleep() { :; }; $(cat "$W/step.sh")" 2>&1); rc=$?
  tries=$(cat "$W/count")
  if [ "$rc" -eq "$2" ] && [ "$tries" -eq "$3" ]; then r=PASS; else r=FAIL; status=1; fi
  echo "$r: $1 failure(s) -> exit $rc after $tries attempt(s) (want exit $2 after $3)"
  printf '%s\n' "$out" | grep '::warning::' | sed 's/^/      /'
}
check 0 0 1
check 2 0 3
check 3 1 3
rm -rf "$W"
exit $status
