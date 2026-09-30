CREATE TABLE "auth_throttle" (
	"key" text PRIMARY KEY NOT NULL,
	"failures" integer DEFAULT 0 NOT NULL,
	"window_start" timestamp with time zone NOT NULL,
	"locked_until" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "backtest_metrics" (
	"bt_run_id" text NOT NULL,
	"split" text NOT NULL,
	"phase" text NOT NULL,
	"candidate" text NOT NULL,
	"n" integer NOT NULL,
	"brier" double precision NOT NULL,
	"logloss" double precision NOT NULL,
	"accuracy" double precision NOT NULL,
	"ece" double precision NOT NULL,
	"slope" double precision NOT NULL,
	"slope_lo" double precision NOT NULL,
	"slope_hi" double precision NOT NULL,
	"skill" double precision NOT NULL,
	"skill_lo" double precision NOT NULL,
	"skill_hi" double precision NOT NULL,
	"dm_p_better_bh" double precision,
	CONSTRAINT "backtest_metrics_bt_run_id_split_phase_candidate_pk" PRIMARY KEY("bt_run_id","split","phase","candidate")
);
--> statement-breakpoint
CREATE TABLE "backtest_runs" (
	"bt_run_id" text PRIMARY KEY NOT NULL,
	"window_id" text NOT NULL,
	"run_id" text NOT NULL,
	"status" text NOT NULL,
	"result_sha256" text NOT NULL,
	"code_git_sha" text NOT NULL,
	"generated_utc" timestamp with time zone NOT NULL,
	"controls" jsonb NOT NULL,
	"clv_summary" jsonb
);
--> statement-breakpoint
CREATE TABLE "bet_grades" (
	"rec_id" text NOT NULL,
	"grader_version" text NOT NULL,
	"outcome" text NOT NULL,
	"clv_bps" double precision,
	"units" double precision,
	CONSTRAINT "bet_grades_rec_id_grader_version_pk" PRIMARY KEY("rec_id","grader_version")
);
--> statement-breakpoint
CREATE TABLE "bundle_ingests" (
	"bundle_sha256" text PRIMARY KEY NOT NULL,
	"cycle_id" text NOT NULL,
	"kind" text NOT NULL,
	"run_id" text NOT NULL,
	"status" text NOT NULL,
	"ingested_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "calibration_bins" (
	"bt_run_id" text NOT NULL,
	"split" text NOT NULL,
	"candidate" text NOT NULL,
	"bin" integer NOT NULL,
	"p_mean" double precision NOT NULL,
	"y_mean" double precision NOT NULL,
	"n" integer NOT NULL,
	CONSTRAINT "calibration_bins_bt_run_id_split_candidate_bin_pk" PRIMARY KEY("bt_run_id","split","candidate","bin")
);
--> statement-breakpoint
CREATE TABLE "closing_lines" (
	"game_id" text NOT NULL,
	"market_id" text NOT NULL,
	"venue_id" text NOT NULL,
	"player_key" text DEFAULT '' NOT NULL,
	"side" text NOT NULL,
	"snapshot_id" integer NOT NULL,
	"close_gap_min" double precision,
	"rule_version" text NOT NULL,
	CONSTRAINT "closing_lines_game_id_market_id_venue_id_player_key_side_pk" PRIMARY KEY("game_id","market_id","venue_id","player_key","side")
);
--> statement-breakpoint
CREATE TABLE "clv_picks" (
	"bt_run_id" text NOT NULL,
	"candidate" text NOT NULL,
	"game_id" text NOT NULL,
	"side" text NOT NULL,
	"clv_bps" double precision NOT NULL,
	"units" double precision NOT NULL,
	CONSTRAINT "clv_picks_bt_run_id_candidate_game_id_pk" PRIMARY KEY("bt_run_id","candidate","game_id")
);
--> statement-breakpoint
CREATE TABLE "eval_windows" (
	"window_id" text PRIMARY KEY NOT NULL,
	"folds" jsonb NOT NULL,
	"protocol_sha256" text NOT NULL,
	"frozen_at_utc" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "evidence_ledger" (
	"claim_id" text PRIMARY KEY NOT NULL,
	"claim" text NOT NULL,
	"status" text NOT NULL,
	"reason" text NOT NULL,
	"evidence_path" text NOT NULL,
	"supersedes" text
);
--> statement-breakpoint
CREATE TABLE "game_predictions" (
	"run_id" text NOT NULL,
	"game_id" text NOT NULL,
	"candidate" text NOT NULL,
	"p_home_raw" double precision,
	"p_home_final" double precision,
	"p_home_mkt_novig" double precision,
	"margin_q50" double precision,
	"total_q50" double precision,
	CONSTRAINT "game_predictions_run_id_game_id_candidate_pk" PRIMARY KEY("run_id","game_id","candidate")
);
--> statement-breakpoint
CREATE TABLE "games" (
	"game_id" text PRIMARY KEY NOT NULL,
	"season" integer NOT NULL,
	"week" integer NOT NULL,
	"game_type" text DEFAULT 'REG' NOT NULL,
	"home_team_id" text NOT NULL,
	"away_team_id" text NOT NULL,
	"kickoff_utc" timestamp with time zone NOT NULL,
	"roof" text,
	"neutral" boolean DEFAULT false NOT NULL,
	"home_score" integer,
	"away_score" integer
);
--> statement-breakpoint
CREATE TABLE "markets" (
	"market_id" text PRIMARY KEY NOT NULL,
	"scope" text NOT NULL,
	"outcome_kind" text NOT NULL,
	"grading_rule" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "model_runs" (
	"run_id" text PRIMARY KEY NOT NULL,
	"kind" text NOT NULL,
	"cycle_id" text NOT NULL,
	"season" integer,
	"week" integer,
	"model_label" text NOT NULL,
	"code_git_sha" text NOT NULL,
	"code_dirty" boolean NOT NULL,
	"config_hash" text NOT NULL,
	"config" jsonb NOT NULL,
	"seed" integer,
	"n_sims" integer,
	"bundle_sha256" text NOT NULL,
	"generated_utc" timestamp with time zone NOT NULL,
	"data_asof_utc" timestamp with time zone NOT NULL,
	"qa_ok" boolean NOT NULL,
	"qa_failures" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"status" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "odds_snapshots" (
	"snapshot_id" bigserial PRIMARY KEY NOT NULL,
	"fetch_id" integer,
	"game_id" text NOT NULL,
	"market_id" text NOT NULL,
	"venue_id" text NOT NULL,
	"player_id" text,
	"side" text NOT NULL,
	"line" numeric,
	"price_american" integer,
	"bid" numeric,
	"ask" numeric,
	"last" numeric,
	"volume" numeric,
	"captured_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "player_aliases" (
	"source" text NOT NULL,
	"alias" text NOT NULL,
	"player_id" text NOT NULL,
	CONSTRAINT "player_aliases_source_alias_pk" PRIMARY KEY("source","alias")
);
--> statement-breakpoint
CREATE TABLE "player_game_stats" (
	"game_id" text NOT NULL,
	"player_id" text NOT NULL,
	"stat" text NOT NULL,
	"value" double precision NOT NULL,
	CONSTRAINT "player_game_stats_game_id_player_id_stat_pk" PRIMARY KEY("game_id","player_id","stat")
);
--> statement-breakpoint
CREATE TABLE "players" (
	"player_id" text PRIMARY KEY NOT NULL,
	"full_name" text NOT NULL,
	"position" text
);
--> statement-breakpoint
CREATE TABLE "promotion_gates" (
	"bt_run_id" text NOT NULL,
	"candidate" text NOT NULL,
	"g1" boolean NOT NULL,
	"g2" boolean NOT NULL,
	"g3" boolean NOT NULL,
	"g4" boolean NOT NULL,
	"brier_status" text NOT NULL,
	"betting_value_status" text NOT NULL,
	CONSTRAINT "promotion_gates_bt_run_id_candidate_pk" PRIMARY KEY("bt_run_id","candidate")
);
--> statement-breakpoint
CREATE TABLE "prop_line_probs" (
	"run_id" text NOT NULL,
	"player_id" text NOT NULL,
	"market_id" text NOT NULL,
	"line" numeric NOT NULL,
	"p_over" double precision NOT NULL,
	"p_push" double precision DEFAULT 0 NOT NULL,
	CONSTRAINT "prop_line_probs_run_id_player_id_market_id_line_pk" PRIMARY KEY("run_id","player_id","market_id","line")
);
--> statement-breakpoint
CREATE TABLE "prop_projections" (
	"run_id" text NOT NULL,
	"game_id" text NOT NULL,
	"player_id" text NOT NULL,
	"market_id" text NOT NULL,
	"dist_family" text NOT NULL,
	"dist_params" jsonb NOT NULL,
	CONSTRAINT "prop_projections_run_id_game_id_player_id_market_id_pk" PRIMARY KEY("run_id","game_id","player_id","market_id")
);
--> statement-breakpoint
CREATE TABLE "publish_pointers" (
	"pointer" text PRIMARY KEY NOT NULL,
	"run_id" text NOT NULL,
	"updated_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "recommendations" (
	"rec_id" text PRIMARY KEY NOT NULL,
	"run_id" text NOT NULL,
	"snapshot_id" integer,
	"game_id" text NOT NULL,
	"candidate" text NOT NULL,
	"side" text NOT NULL,
	"price_american" integer,
	"p_model" double precision NOT NULL,
	"p_mkt_novig" double precision,
	"ev" double precision,
	"stake_pct" double precision NOT NULL,
	"tier" text NOT NULL,
	"pass_reason" text
);
--> statement-breakpoint
CREATE TABLE "roster_weeks" (
	"player_id" text NOT NULL,
	"team_id" text NOT NULL,
	"season" integer NOT NULL,
	"week" integer NOT NULL,
	"status" text,
	CONSTRAINT "roster_weeks_player_id_season_week_pk" PRIMARY KEY("player_id","season","week")
);
--> statement-breakpoint
CREATE TABLE "score_distributions" (
	"run_id" text NOT NULL,
	"game_id" text NOT NULL,
	"kind" text NOT NULL,
	"bins" jsonb NOT NULL,
	CONSTRAINT "score_distributions_run_id_game_id_kind_pk" PRIMARY KEY("run_id","game_id","kind")
);
--> statement-breakpoint
CREATE TABLE "source_fetches" (
	"fetch_id" bigserial PRIMARY KEY NOT NULL,
	"source" text NOT NULL,
	"endpoint_redacted" text NOT NULL,
	"http_status" integer NOT NULL,
	"fetched_at" timestamp with time zone NOT NULL,
	"raw_sha256" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "source_status" (
	"run_id" text NOT NULL,
	"source" text NOT NULL,
	"status" text NOT NULL,
	"last_success_utc" timestamp with time zone,
	"detail" text,
	CONSTRAINT "source_status_run_id_source_pk" PRIMARY KEY("run_id","source")
);
--> statement-breakpoint
CREATE TABLE "td_events" (
	"game_id" text NOT NULL,
	"seq" integer NOT NULL,
	"player_id" text,
	"team_id" text,
	CONSTRAINT "td_events_game_id_seq_pk" PRIMARY KEY("game_id","seq")
);
--> statement-breakpoint
CREATE TABLE "team_aliases" (
	"source" text NOT NULL,
	"alias" text NOT NULL,
	"team_id" text NOT NULL,
	CONSTRAINT "team_aliases_source_alias_pk" PRIMARY KEY("source","alias")
);
--> statement-breakpoint
CREATE TABLE "teams" (
	"team_id" text PRIMARY KEY NOT NULL,
	"full_name" text NOT NULL,
	"division" text,
	"tz" text
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" text PRIMARY KEY NOT NULL,
	"email" text NOT NULL,
	"password_hash" text NOT NULL,
	"session_version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "venues" (
	"venue_id" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"kind" text NOT NULL
);
--> statement-breakpoint
ALTER TABLE "backtest_metrics" ADD CONSTRAINT "backtest_metrics_bt_run_id_backtest_runs_bt_run_id_fk" FOREIGN KEY ("bt_run_id") REFERENCES "public"."backtest_runs"("bt_run_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "backtest_runs" ADD CONSTRAINT "backtest_runs_window_id_eval_windows_window_id_fk" FOREIGN KEY ("window_id") REFERENCES "public"."eval_windows"("window_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "backtest_runs" ADD CONSTRAINT "backtest_runs_run_id_model_runs_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."model_runs"("run_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bet_grades" ADD CONSTRAINT "bet_grades_rec_id_recommendations_rec_id_fk" FOREIGN KEY ("rec_id") REFERENCES "public"."recommendations"("rec_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "calibration_bins" ADD CONSTRAINT "calibration_bins_bt_run_id_backtest_runs_bt_run_id_fk" FOREIGN KEY ("bt_run_id") REFERENCES "public"."backtest_runs"("bt_run_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "closing_lines" ADD CONSTRAINT "closing_lines_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "closing_lines" ADD CONSTRAINT "closing_lines_market_id_markets_market_id_fk" FOREIGN KEY ("market_id") REFERENCES "public"."markets"("market_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "closing_lines" ADD CONSTRAINT "closing_lines_venue_id_venues_venue_id_fk" FOREIGN KEY ("venue_id") REFERENCES "public"."venues"("venue_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "closing_lines" ADD CONSTRAINT "closing_lines_snapshot_id_odds_snapshots_snapshot_id_fk" FOREIGN KEY ("snapshot_id") REFERENCES "public"."odds_snapshots"("snapshot_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clv_picks" ADD CONSTRAINT "clv_picks_bt_run_id_backtest_runs_bt_run_id_fk" FOREIGN KEY ("bt_run_id") REFERENCES "public"."backtest_runs"("bt_run_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "clv_picks" ADD CONSTRAINT "clv_picks_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "game_predictions" ADD CONSTRAINT "game_predictions_run_id_model_runs_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."model_runs"("run_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "game_predictions" ADD CONSTRAINT "game_predictions_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "games" ADD CONSTRAINT "games_home_team_id_teams_team_id_fk" FOREIGN KEY ("home_team_id") REFERENCES "public"."teams"("team_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "games" ADD CONSTRAINT "games_away_team_id_teams_team_id_fk" FOREIGN KEY ("away_team_id") REFERENCES "public"."teams"("team_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "odds_snapshots" ADD CONSTRAINT "odds_snapshots_fetch_id_source_fetches_fetch_id_fk" FOREIGN KEY ("fetch_id") REFERENCES "public"."source_fetches"("fetch_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "odds_snapshots" ADD CONSTRAINT "odds_snapshots_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "odds_snapshots" ADD CONSTRAINT "odds_snapshots_market_id_markets_market_id_fk" FOREIGN KEY ("market_id") REFERENCES "public"."markets"("market_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "odds_snapshots" ADD CONSTRAINT "odds_snapshots_venue_id_venues_venue_id_fk" FOREIGN KEY ("venue_id") REFERENCES "public"."venues"("venue_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "odds_snapshots" ADD CONSTRAINT "odds_snapshots_player_id_players_player_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("player_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "player_aliases" ADD CONSTRAINT "player_aliases_player_id_players_player_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("player_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "player_game_stats" ADD CONSTRAINT "player_game_stats_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "player_game_stats" ADD CONSTRAINT "player_game_stats_player_id_players_player_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("player_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "promotion_gates" ADD CONSTRAINT "promotion_gates_bt_run_id_backtest_runs_bt_run_id_fk" FOREIGN KEY ("bt_run_id") REFERENCES "public"."backtest_runs"("bt_run_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prop_line_probs" ADD CONSTRAINT "prop_line_probs_run_id_model_runs_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."model_runs"("run_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prop_line_probs" ADD CONSTRAINT "prop_line_probs_player_id_players_player_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("player_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prop_line_probs" ADD CONSTRAINT "prop_line_probs_market_id_markets_market_id_fk" FOREIGN KEY ("market_id") REFERENCES "public"."markets"("market_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prop_projections" ADD CONSTRAINT "prop_projections_run_id_model_runs_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."model_runs"("run_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prop_projections" ADD CONSTRAINT "prop_projections_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prop_projections" ADD CONSTRAINT "prop_projections_player_id_players_player_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("player_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prop_projections" ADD CONSTRAINT "prop_projections_market_id_markets_market_id_fk" FOREIGN KEY ("market_id") REFERENCES "public"."markets"("market_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "publish_pointers" ADD CONSTRAINT "publish_pointers_run_id_model_runs_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."model_runs"("run_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recommendations" ADD CONSTRAINT "recommendations_run_id_model_runs_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."model_runs"("run_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recommendations" ADD CONSTRAINT "recommendations_snapshot_id_odds_snapshots_snapshot_id_fk" FOREIGN KEY ("snapshot_id") REFERENCES "public"."odds_snapshots"("snapshot_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recommendations" ADD CONSTRAINT "recommendations_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "roster_weeks" ADD CONSTRAINT "roster_weeks_player_id_players_player_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("player_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "roster_weeks" ADD CONSTRAINT "roster_weeks_team_id_teams_team_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("team_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "score_distributions" ADD CONSTRAINT "score_distributions_run_id_model_runs_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."model_runs"("run_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "score_distributions" ADD CONSTRAINT "score_distributions_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "source_status" ADD CONSTRAINT "source_status_run_id_model_runs_run_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."model_runs"("run_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "td_events" ADD CONSTRAINT "td_events_game_id_games_game_id_fk" FOREIGN KEY ("game_id") REFERENCES "public"."games"("game_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "td_events" ADD CONSTRAINT "td_events_player_id_players_player_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("player_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "td_events" ADD CONSTRAINT "td_events_team_id_teams_team_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("team_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "team_aliases" ADD CONSTRAINT "team_aliases_team_id_teams_team_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("team_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "games_season_week_idx" ON "games" USING btree ("season","week");--> statement-breakpoint
CREATE UNIQUE INDEX "model_runs_bundle_sha_uk" ON "model_runs" USING btree ("bundle_sha256");--> statement-breakpoint
CREATE INDEX "odds_game_market_idx" ON "odds_snapshots" USING btree ("game_id","market_id","venue_id","captured_at");