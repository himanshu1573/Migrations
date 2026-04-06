-- ============================================================================
-- OPENING ASSESSMENT SCHEMA
-- ============================================================================

-- 1. OPENING_ASSESSMENT_SESSION
-- Purpose: Track assessment sessions for a specific job opening per candidate
CREATE TABLE IF NOT EXISTS opening_assessment_session (
  id TEXT PRIMARY KEY,
  opening_id INTEGER NOT NULL, -- Logical link to openings.opening_id (matches skill_map pattern)
  candidate_id TEXT NOT NULL, -- Logical link to naukri_candidates.unique_candidate_id
  status TEXT DEFAULT 'not_started' 
    CHECK (status IN ('not_started', 'in_progress', 'paused', 'completed', 'abandoned')),
  start_time TIMESTAMP WITH TIME ZONE,
  end_time TIMESTAMP WITH TIME ZONE,
  total_score REAL,
  passed BOOLEAN,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_oas_opening_id ON opening_assessment_session(opening_id);
CREATE INDEX idx_oas_candidate_id ON opening_assessment_session(candidate_id);
CREATE INDEX idx_oas_status ON opening_assessment_session(status);


-- 2. OPENING_ASSESSMENT_ANSWER
-- Purpose: Store candidate answers specific to an opening assessment
CREATE TABLE IF NOT EXISTS opening_assessment_answer (
  id BIGSERIAL PRIMARY KEY,
  session_id TEXT NOT NULL,
  opening_skill_question_id BIGINT NOT NULL,  -- Link to opening_skill_question
  question_id BIGINT NOT NULL,
  selected_answer_id BIGINT,
  answer_text TEXT,
  is_correct BOOLEAN,
  time_spent_seconds INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT opening_assessment_answer_session_fkey 
    FOREIGN KEY (session_id) REFERENCES opening_assessment_session(id) ON DELETE CASCADE,
  CONSTRAINT opening_assessment_answer_osq_fkey 
    FOREIGN KEY (opening_skill_question_id) REFERENCES opening_skill_question(id) ON DELETE CASCADE,
  CONSTRAINT opening_assessment_answer_question_fkey 
    FOREIGN KEY (question_id) REFERENCES skill_question(id) ON DELETE CASCADE
);

CREATE INDEX idx_oaa_session_id ON opening_assessment_answer(session_id);
CREATE INDEX idx_oaa_osq_id ON opening_assessment_answer(opening_skill_question_id);


-- 3. OPENING_ASSESSMENT_RESULT
-- Purpose: Store final assessment results for job opening
CREATE TABLE IF NOT EXISTS opening_assessment_result (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  opening_id INTEGER NOT NULL,
  candidate_id TEXT NOT NULL,
  skill_map_id BIGINT NOT NULL,
  skill_id BIGINT NOT NULL,
  
  -- Metrics
  total_questions_assigned INTEGER,
  total_questions_answered INTEGER,
  correct_answers INTEGER,
  score_percentage REAL,
  passed BOOLEAN,
  skill_rating_1_to_5 INTEGER,
  
  -- By difficulty
  easy_score REAL,
  moderate_score REAL,
  difficult_score REAL,
  
  -- Timing
  total_time_seconds INTEGER,
  start_time TIMESTAMP WITH TIME ZONE,
  end_time TIMESTAMP WITH TIME ZONE,
  
  -- Status
  reviewed BOOLEAN DEFAULT false,
  reviewer_notes TEXT,
  final_recommendation TEXT 
    CHECK (final_recommendation IN ('proceed', 'hold', 'reject')),
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT opening_assessment_result_session_fkey 
    FOREIGN KEY (session_id) REFERENCES opening_assessment_session(id) ON DELETE CASCADE,
  CONSTRAINT opening_assessment_result_skill_map_fkey 
    FOREIGN KEY (skill_map_id) REFERENCES skill_map(id) ON DELETE CASCADE,
  CONSTRAINT opening_assessment_result_skill_fkey 
    FOREIGN KEY (skill_id) REFERENCES skill_master(id) ON DELETE CASCADE
);

CREATE INDEX idx_oar_opening_id ON opening_assessment_result(opening_id);
CREATE INDEX idx_oar_candidate_id ON opening_assessment_result(candidate_id);
CREATE INDEX idx_oar_skill_map_id ON opening_assessment_result(skill_map_id);
CREATE INDEX idx_oar_session_id ON opening_assessment_result(session_id);
