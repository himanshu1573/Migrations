-- 1. Create the backup table and copy all live data
CREATE TABLE backup_candidate_skill_map AS 
SELECT * FROM candidate_skill_map;

-- 2. Add Primary Key
ALTER TABLE backup_candidate_skill_map ADD PRIMARY KEY (id);

-- 3. Add Unique Constraint to match live table (unique pair of candidate and skill)
ALTER TABLE backup_candidate_skill_map 
ADD CONSTRAINT backup_csm_candidate_skill_unique UNIQUE (candidate_id, skill_id);

-- 4. Add Check Constraints to maintain data integrity in the backup
ALTER TABLE backup_candidate_skill_map 
ADD CONSTRAINT backup_csm_overall_rating_check CHECK (overall_rating >= 1 AND overall_rating <= 5);

ALTER TABLE backup_candidate_skill_map 
ADD CONSTRAINT backup_csm_pre_screening_ai_rating_check CHECK (pre_screening_ai_rating >= 0 AND pre_screening_ai_rating <= 5);

ALTER TABLE backup_candidate_skill_map 
ADD CONSTRAINT backup_csm_self_rating_check CHECK (self_rating >= 1 AND self_rating <= 10);

-- 5. Add performance indexes to match live references
CREATE INDEX idx_backup_csm_candidate_id ON backup_candidate_skill_map(candidate_id);

-- Optional: Traceability comment
COMMENT ON TABLE backup_candidate_skill_map IS 'Full Live Reference Backup created on 2026-04-03 before implementing opening_skill_question features';
