-- rec_id is unique within a run, not globally: a re-run of the same week carries the
-- same rec_ids under a new run_id. bet_grades follows with a composite reference.
-- (drizzle-kit emitted these statements out of order and without the old key's name;
-- ordered by hand. bet_grades is empty until grading ships, so NOT NULL is safe.)
ALTER TABLE "bet_grades" DROP CONSTRAINT "bet_grades_rec_id_recommendations_rec_id_fk";--> statement-breakpoint
ALTER TABLE "bet_grades" DROP CONSTRAINT "bet_grades_rec_id_grader_version_pk";--> statement-breakpoint
ALTER TABLE "recommendations" DROP CONSTRAINT "recommendations_pkey";--> statement-breakpoint
ALTER TABLE "recommendations" ADD CONSTRAINT "recommendations_run_id_rec_id_pk" PRIMARY KEY("run_id","rec_id");--> statement-breakpoint
ALTER TABLE "bet_grades" ADD COLUMN "run_id" text NOT NULL;--> statement-breakpoint
ALTER TABLE "bet_grades" ADD CONSTRAINT "bet_grades_run_id_rec_id_grader_version_pk" PRIMARY KEY("run_id","rec_id","grader_version");--> statement-breakpoint
ALTER TABLE "bet_grades" ADD CONSTRAINT "bet_grades_run_id_rec_id_recommendations_run_id_rec_id_fk" FOREIGN KEY ("run_id","rec_id") REFERENCES "public"."recommendations"("run_id","rec_id") ON DELETE no action ON UPDATE no action;
