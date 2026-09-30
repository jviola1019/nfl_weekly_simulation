-- Invariants the database enforces (spec §3 "Invariants enforced in the database").

-- Audit P2: a recommendation is a bet exactly when it carries a stake.
ALTER TABLE "recommendations"
  ADD CONSTRAINT "recommendations_tier_stake_ck" CHECK (("tier" = 'bet') = ("stake_pct" > 0));
--> statement-breakpoint
ALTER TABLE "recommendations"
  ADD CONSTRAINT "recommendations_tier_ck" CHECK ("tier" IN ('bet', 'lean', 'pass'));
--> statement-breakpoint
ALTER TABLE "model_runs"
  ADD CONSTRAINT "model_runs_status_ck" CHECK ("status" IN ('published', 'qa_failed', 'superseded'));
--> statement-breakpoint
ALTER TABLE "backtest_runs"
  ADD CONSTRAINT "backtest_runs_status_ck" CHECK ("status" IN ('complete', 'void'));
--> statement-breakpoint
ALTER TABLE "evidence_ledger"
  ADD CONSTRAINT "evidence_ledger_status_ck" CHECK ("status" IN ('validated', 'reproducible', 'unvalidated', 'withdrawn'));
--> statement-breakpoint
ALTER TABLE "venues"
  ADD CONSTRAINT "venues_kind_ck" CHECK ("kind" IN ('sportsbook', 'exchange', 'consensus'));
--> statement-breakpoint

-- Append-only evidence: UPDATE and DELETE raise. A re-grade is a new grader_version,
-- a re-run is a new bt_run_id, a re-captured price is a new snapshot.
CREATE OR REPLACE FUNCTION forbid_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'table % is append-only (% refused)', TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'restrict_violation';
END;
$$ LANGUAGE plpgsql;
--> statement-breakpoint
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['odds_snapshots', 'source_fetches', 'closing_lines', 'eval_windows',
                           'backtest_runs', 'backtest_metrics', 'calibration_bins', 'promotion_gates',
                           'clv_picks', 'bet_grades']
  LOOP
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION forbid_mutation()',
                   t || '_append_only', t);
  END LOOP;
END;
$$;
