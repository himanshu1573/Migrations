/**
 * ============================================================
 *  Airtable 🔄 Supabase Incremental Sync Script (v2 — Post-Migration)
 * ============================================================
 *
 *  Updated for the normalized schema:
 *   • No more temp_ columns — FK resolution is inline
 *   • Screener/tech_screener → screener_assignments table
 *   • Onboarding milestones → onboarding_events table
 *   • vendors_id remains the canonical vendor link on profiles_database
 *   • Locations on openings → openings_locations_openings junction
 *
 *  Usage: node sync.js [--full]
 */

require('dotenv').config();
const { Pool } = require('pg');
const https = require('https');
const fs = require('fs');
const path = require('path');

// ── Configuration ─────────────────────────────────────────────
const AIRTABLE_TOKEN = process.env.AIRTABLE_ACCESS_TOKEN;
const AIRTABLE_BASE = process.env.AIRTABLE_BASE_ID;
const DATABASE_URL = process.env.DATABASE_URL;
const STATE_FILE = path.join(__dirname, 'sync_state.json');

// ── Table Sync Config ─────────────────────────────────────────
// fieldMap: { 'Airtable Field Name': 'pg_column_name' }
// linkFields: { 'Airtable Link Field': { col: 'pg_fk_column', target: 'target_table' } }
//   → resolved inline by looking up airtable_id in the target table
// extraFields: fields fetched from Airtable but handled in post-processing (not upserted directly)
// manyToMany: { 'Airtable Field': { junction, sourceCol, targetCol, targetTable } }

const SYNC_CONFIG = [
    {
        airtableName: 'Client Master',
        supabaseTable: 'client_master',
        fieldMap: {
            'Client Name': 'client_name', 'Client Industry': 'client_industry',
            'Contact Email': 'contact_email', 'Contact Phone': 'contact_phone',
            'SPOC': 'spoc', 'Client Requirements': 'client_requirements',
            'Location': 'location', 'Requirements Type': 'requirements_type',
            'LinkedIn Url': 'linkedin_url', 'Client ID': 'client_id',
        },
        linkFields: {},
    },
    {
        airtableName: 'Locations',
        supabaseTable: 'locations',
        fieldMap: { 'Name': 'name' },
        linkFields: {},
    },
    {
        airtableName: 'Client Department',
        supabaseTable: 'client_department',
        fieldMap: {
            'Department Name': 'department_name', 'Department ID': 'department_id',
            'Primary PoC': 'primary_poc', 'Primary PoC Phone Number': 'primary_poc_phone_number',
            'Primary PoC Role': 'primary_poc_role', 'Secondary PoC': 'secondary_poc',
            'Secondary PoC Phone Number': 'secondary_poc_phone_number',
            'Secondary PoC Role': 'secondary_poc_role',
            'Primary PoC Email ID': 'primary_poc_email_id',
            'Secondary PoC Email ID': 'secondary_poc_email_id',
            'document type': 'document_type',
            'Phone Screening Questionnaire': 'phone_screening_questionnaire',
        },
        linkFields: {
            'Client Name': { col: 'client_name_id', target: 'client_master' },
        },
    },
    {
        airtableName: 'Vendor Master',
        supabaseTable: 'vendor_master',
        fieldMap: {
            'Vendor Name': 'vendor_name', 'Vendor Address': 'vendor_address',
            'Vendor Registration Date': 'vendor_registration_date',
            'Vendor Profiles': 'vendor_profiles', 'Resource Location': 'resource_location',
            'LinkedIn Url': 'linkedin_url', 'Vendor Status': 'vendor_status',
            'Vendor ID Number': 'vendor_id_number', 'Revenue Model': 'revenue_model',
            'Vendor PoC': 'vendor_poc', 'PoC Contact Number': 'poc_contact_number',
            'PoC Mail ID': 'poc_mail_id', 'Additional PoC Mail IDs': 'additional_poc_mail_ids',
            'Password': 'password', 'Vendor Type': 'vendor_type',
            'Master PID Document': 'master_pid_document', 'Status': 'status',
        },
        linkFields: {},
        manyToMany: {
            'Openings': {
                junctionTable: 'vendor_openings',
                sourceColumn: 'vendor_id',
                targetColumn: 'opening_id',
                targetTable: 'openings',
            },
        },
    },
    {
        airtableName: 'Screeners Profile',
        supabaseTable: 'screeners_profile',
        fieldMap: {
            'Name': 'name', 'Number': 'number', 'Status': 'status',
        },
        linkFields: {},
    },
    {
        airtableName: 'Users',
        supabaseTable: 'users',
        fieldMap: {
            'Username': 'username', 'Password': 'password', 'Type': 'type',
            'Screener Link': 'screener_link', 'Name(Manual entry)': 'namemanual_entry',
            'PID Authorization?': 'pid_authorization',
        },
        linkFields: {},
    },
    {
        airtableName: 'Openings',
        supabaseTable: 'openings',
        fieldMap: {
            'Job Title': 'job_title', 'Opening ID': 'opening_id',
            'Experience Level': 'experience_level',
            'Number of open position': 'number_of_open_position',
            'Job Description': 'job_description', 'Status': 'status',
            'Client Billing': 'client_billing', 'Duration (months)': 'duration_months',
            'Date Opened': 'date_opened', 'Onboarding process notes': 'onboarding_process_notes',
            'Comments': 'comments', 'BLine ID': 'bline_id',
            'CTC LPA Limit (e.g. 14)': 'ctc_lpa_limit_eg_14',
            'Is exclusive?': 'is_exclusive', 'Max Vendor Budget': 'max_vendor_budget',
            'Job Group': 'job_group', 'Job Id': 'job_id',
            'Interview slots': 'interview_slots', 'Questionnaire': 'questionnaire',
            'Master PID Document': 'master_pid_document',
            'Recruitment Target CTC': 'recruitment_target_ctc',
            'Naukri Folder': 'naukri_folder',
            'Maximum Joining Period (days)': 'maximum_joining_period_days',
            'Maximum Notice Period Allowed': 'maximum_notice_period_allowed',
            'Candidate Type': 'candidate_type',
            'Partner Recruitment Fees (% of Annual CTC)': 'partner_recruitment_fees_of_annual_ctc',
            'Coding Q1': 'coding_q1', 'Coding Q2': 'coding_q2',
            'Skill Coding Q1': 'skill_coding_q1', 'Skill Coding Q2': 'skill_coding_q2',
            'JD for Prompt': 'jd_for_prompt', 'Screeners Profile': 'screeners_profile',
            'Job Visibility': 'job_visibility', 'Job Bench Type': 'job_bench_type',
            'Advisory': 'advisory',
        },
        linkFields: {
            'Client Department': { col: 'client_department_id', target: 'client_department' },
            'Client': { col: 'client_id', target: 'client_master' },
        },
        manyToMany: {
            'Locations_Openings': {
                junctionTable: 'openings_locations_openings',
                sourceColumn: 'openings_id',
                targetColumn: 'locations_id',
                targetTable: 'locations',
            },
        },
    },
    {
        airtableName: 'Profiles Database',
        supabaseTable: 'profiles_database',
        fieldMap: {
            'Candidate ID': 'candidate_id', 'Creation Date': 'creation_date',
            'Skill': 'skill', 'Candidate Name': 'candidate_name',
            'CV Link': 'cv_link', 'Candidate Contact': 'candidate_contact',
            'Candidate Email': 'candidate_email', 'Current Company': 'current_company',
            'Notice Period': 'notice_period', 'Current Location': 'current_location',
            'Preferred Location': 'preferred_location', 'CTC Lpa': 'ctc_lpa',
            'ECTC Lpa': 'ectc_lpa', 'Candidate Cost': 'candidate_cost',
            'Bench Type': 'bench_type', 'Govt ID': 'govt_id',
            'Communication Rating': 'communication_rating',
            'Confidence Rating': 'confidence_rating',
            'Tech Self Rating': 'tech_self_rating', 'Comments': 'comments',
            'Last Working Day': 'last_working_day', 'Candidate Type': 'candidate_type',
            'Screening Report': 'screening_report', 'Career Gap': 'career_gap',
            'Edited CV': 'edited_cv', 'Edited PSR': 'edited_psr',
            'lyncogs': 'lyncogs', 'lyncogs_summary': 'lyncogs_summary',
            'Is Resigned': 'is_resigned', 'Candidate Document': 'candidate_document',
            'Type of ID': 'type_of_id', 'Recruitment Notes': 'recruitment_notes',
            'Is Draft': 'is_draft',
        },
        linkFields: {
            'Vendors Id': { col: 'vendors_id', target: 'vendor_master' },
            'Location Id': { col: 'location_id', target: 'locations' },
        },
    },
    {
        airtableName: 'Applications_ID',
        supabaseTable: 'applications_id',
        fieldMap: {
            'Status': 'status',
            'Internal Screening Time and Date': 'internal_screening_time_and_date',
            'Status Remarks': 'status_remarks', 'Next Task': 'next_task',
            'Link Post Interview Questionnaire': 'link_post_interview_questionnaire',
            'Status Post Interview Questionnaire': 'status_post_interview_questionnaire',
            'Screening - Fathom Links': 'screening_fathom_links',
            'Other Offers': 'other_offers', 'Screening Report Link': 'screening_report_link',
            "Candidate's preferred slot": 'candidates_preferred_slot',
            'Experience Level - Candidate': 'experience_level_candidate',
            'Clients Interview Feedback': 'clients_interview_feedback',
            'Followup Email Status': 'followup_email_status',
            'Send Mail': 'send_mail', 'Form filled by': 'form_filled_by',
            'LWD': 'lwd', 'Follow Up Date': 'follow_up_date',
            'Update AirTable': 'update_airtable',
            'Pre L1 Transcript': 'pre_l1_transcript',
            'Post screening report': 'post_screening_report',
            'Screening Clear Date': 'screening_clear_date',
            'Revised CTC LPA': 'revised_ctc_lpa',
            'VS remarks': 'vs_remarks', 'Send to client?': 'send_to_client',
            'Tech Screening': 'tech_screening', 'Cluely Report': 'cluely_report',
            'Backup Candidate': 'backup_candidate', 'Tracker remarks': 'tracker_remarks',
            'CV Sent to Client Date': 'cv_sent_to_client_date',
            'CV Sent to Client Date Last Updated': 'cv_sent_to_client_date_last_updated',
            'Name as per the Aadhar': 'name_as_per_the_aadhar',
            'Backup option 1': 'backup_option_1', 'Vendor of Option 1': 'vendor_of_option_1',
            'Backup Option 2': 'backup_option_2', 'Vendor of Option 2': 'vendor_of_option_2',
            'id type submitted': 'id_type_submitted', 'Transcript': 'transcript',
            'Morning Followup Status': 'morning_followup_status',
            'Panel Type': 'panel_type',
            'Scheduling Coordination Started?': 'scheduling_coordination_started',
            'Interview Coordination': 'interview_coordination',
            'Candidate Followup': 'candidate_followup',
            'Offboarding?': 'offboarding', 'Offboarding Status': 'offboarding_status',
            'Opening Vendor Summary': 'opening_vendor_summary',
            'Clients feedback status': 'clients_feedback_status',
        },
        linkFields: {
            'Vendor ID': { col: 'vendor_id', target: 'vendor_master' },
            'Openings ID': { col: 'openings_id', target: 'openings' },
            'Candidate Id(Profile Database)': { col: 'profiles_database_id', target: 'profiles_database' },
            'PID taken by': { col: 'pid_taken_by_id', target: 'users' },
        },
        // These Airtable fields are fetched but handled in post-processing
        extraFields: [
            'Client L1 Screening Date and Time', 'Client L2 Screening Date and TIme',
            'Client L3 Screening Date and Time', 'Pre L1 Date and Time',
            'Client L1 Meeting Link', 'Client L2 Meeting Link',
            'Client L3 Meeting Link', 'Internal Meeting Link',
            'Screener', 'Tech Screener',
        ],
    },
    {
        airtableName: 'Screenings',
        supabaseTable: 'screenings',
        fieldMap: {
            'Candidate Name': 'candidate_name', 'DATE': 'date',
            'Meeting Link': 'meeting_link', 'Skill': 'skill', 'CV Link': 'cv_link',
            'Organizer Email': 'organizer_email',
            'Event Created Time': 'event_created_time',
            'Screener assigned': 'screener_assigned',
            'Created Email': 'created_email', 'Event Id': 'event_id',
            'Status': 'status', 'Comments': 'comments',
            'AI Interview Link': 'ai_interview_link', 'SlotKey': 'slotkey',
            'Admin Interview Link': 'admin_interview_link',
            'test date ': 'test_date',
            'Screener Evaluation Report': 'screener_evaluation_report',
            'Answer of Coding Q1': 'answer_of_coding_q1',
            'Answer of Coding Q2': 'answer_of_coding_q2',
        },
        linkFields: {
            'Candidate ID': { col: 'candidate_id', target: 'profiles_database' },
            'Vendor Id': { col: 'vendor_id', target: 'vendor_master' },
            'Application Id': { col: 'application_id', target: 'applications_id' },
        },
    },
    {
        airtableName: 'Selected Candidates',
        supabaseTable: 'selected_candidates',
        fieldMap: {
            'Status': 'status', 'Selection Date': 'selection_date',
            'Overall Status': 'overall_status', 'PF Status': 'pf_status',
            'PF doc remarks': 'pf_doc_remarks',
            'University docs check': 'university_docs_check',
            'University docs remarks': 'university_docs_remarks',
            'Finalised CTC (e.g. 12,00,000)': 'finalised_ctc_eg_1200000',
            'Is this FTE?': 'is_this_fte', 'Invoice raised?': 'invoice_raised',
            'CRC Confirmation Date': 'crc_confirmation_date',
            'Offboarding?': 'offboarding', 'Offboarding Status': 'offboarding_status',
        },
        linkFields: {
            'Candidate from Applications': { col: 'candidate_from_applications_id', target: 'applications_id' },
            'Whose Bench?': { col: 'whose_bench_id', target: 'vendor_master' },
        },
        // These fields are fetched but handled in post-processing (→ onboarding_events)
        extraFields: [
            'Vendor onboarding date', 'Xpo onboarding status',
            'Synechron onboarding date', 'Synechron onboarding status',
            'BGV Trigger Date', 'BGV Status',
            'End Client onboarding', 'End Client onboarding status',
            'BGV Doc submission date', 'SOW Signing Date',
        ],
    },
];

// ── Helpers ───────────────────────────────────────────────────

function getSyncState() {
    if (fs.existsSync(STATE_FILE)) {
        return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    }
    return { last_sync: null };
}

function saveSyncState(lastSync) {
    fs.writeFileSync(STATE_FILE, JSON.stringify({ last_sync: lastSync }, null, 2));
}

async function fetchAirtableSync(tableName, lastSync) {
    return new Promise((resolve, reject) => {
        const encodedTable = encodeURIComponent(tableName);
        let allRecords = [];
        let totalFetched = 0;

        const fetchPage = (currentOffset) => {
            let urlPath = `/v0/${AIRTABLE_BASE}/${encodedTable}?pageSize=100`;
            if (currentOffset) urlPath += `&offset=${currentOffset}`;

            if (lastSync && !process.argv.includes('--full')) {
                urlPath += `&filterByFormula=${encodeURIComponent(`IS_AFTER(LAST_MODIFIED_TIME(), "${lastSync}")`)}`;
            }

            const options = {
                hostname: 'api.airtable.com',
                path: urlPath,
                headers: { 'Authorization': `Bearer ${AIRTABLE_TOKEN}` },
                timeout: 30000, // 30s timeout
            };

            const req = https.get(options, (res) => {
                // If it's a 429, wait and retry
                if (res.statusCode === 429) {
                    console.log('      ⚠️ Rate limited. Retrying in 5s...');
                    setTimeout(() => fetchPage(currentOffset), 5000);
                    res.resume();
                    return;
                }

                let data = '';
                res.on('data', c => data += c);
                res.on('end', () => {
                    try {
                        const parsed = JSON.parse(data);
                        if (parsed.error) {
                            if (parsed.error.type === 'MODEL_RATE_LIMIT_EXCEEDED') {
                                console.log('      ⚠️ Rate limited. Retrying in 5s...');
                                setTimeout(() => fetchPage(currentOffset), 5000);
                                return;
                            }
                            return reject(new Error(`Airtable Error: ${parsed.error.message}`));
                        }

                        if (parsed.records) {
                            allRecords.push(...parsed.records);
                            totalFetched += parsed.records.length;
                            process.stdout.write(`\r      ⏳ Fetched ${totalFetched} airtable records...`);
                        }

                        if (parsed.offset) {
                            setTimeout(() => fetchPage(parsed.offset), 250);
                        } else {
                            process.stdout.write('\n');
                            resolve(allRecords);
                        }
                    } catch (e) {
                        return reject(new Error(`Parse error: ${e.message} | Data: ${data.substring(0, 100)}`));
                    }
                });
            });

            req.on('timeout', () => {
                req.destroy();
                console.log('      ⚠️ Request timed out. Retrying...');
                setTimeout(() => fetchPage(currentOffset), 1000);
            });

            req.on('error', (e) => {
                if (e.code === 'ECONNRESET') {
                    console.log('      ⚠️ Connection reset. Retrying...');
                    setTimeout(() => fetchPage(currentOffset), 1000);
                } else {
                    reject(e);
                }
            });

            req.end();
        };

        fetchPage(null);
    });
}

function transformValue(value) {
    if (value === null || value === undefined) return null;
    if (typeof value === 'object' && !Array.isArray(value)) return JSON.stringify(value);
    if (Array.isArray(value)) {
        if (value.length === 0) return null;
        // Airtable linked record IDs — take first one (handled by linkFields)
        if (typeof value[0] === 'string' && value[0].startsWith('rec')) return value[0];
        // PG array literal for text[] columns (e.g., job_group)
        return `{${value.map(v => `"${String(v).replace(/"/g, '\\"')}"`).join(',')}}`;
    }
    const dateStr = String(value);
    const dateMatch = dateStr.match(/\d{4}-\d{2}-\d{2}/);
    if (dateMatch && dateStr.length < 25) return dateMatch[0];
    return value;
}

/**
 * Resolves an Airtable record ID to a Supabase UUID by looking up the target table.
 * Uses an in-memory cache to avoid repeated DB queries.
 */
const _fkCache = {};
async function resolveFK(pgPool, targetTable, airtableId) {
    if (!airtableId) return null;
    const key = `${targetTable}:${airtableId}`;
    if (_fkCache[key] !== undefined) return _fkCache[key];
    try {
        const res = await pgPool.query(
            `SELECT id FROM "${targetTable}" WHERE airtable_id = $1 LIMIT 1`,
            [airtableId]
        );
        const id = res.rows.length > 0 ? res.rows[0].id : null;
        _fkCache[key] = id;
        return id;
    } catch {
        return null;
    }
}

async function upsertBatch(pool, tableName, rows) {
    if (rows.length === 0) return 0;
    const batchSize = 100;
    let count = 0;

    for (let i = 0; i < rows.length; i += batchSize) {
        process.stdout.write(`\r      ⏳ Upserting batch ${i} to ${i + batchSize}...`);
        const batch = rows.slice(i, i + batchSize);
        const columns = Object.keys(batch[0]);
        const updateCols = columns.filter(c => c !== 'airtable_id' && c !== 'id');
        const setClause = updateCols.map(c => `"${c}" = EXCLUDED."${c}"`).join(', ');

        const conflictClause = updateCols.length > 0
            ? `ON CONFLICT (airtable_id) DO UPDATE SET ${setClause}`
            : `ON CONFLICT (airtable_id) DO NOTHING`;

        const values = [];
        const placeholdersRow = [];
        let paramIdx = 1;

        for (const row of batch) {
            const rowPlaceholders = [];
            for (const col of columns) {
                values.push(row[col]);
                rowPlaceholders.push(`$${paramIdx++}`);
            }
            placeholdersRow.push(`(${rowPlaceholders.join(', ')})`);
        }

        const query = `
            INSERT INTO "${tableName}" (${columns.map(c => `"${c}"`).join(', ')})
            VALUES ${placeholdersRow.join(', ')}
            ${conflictClause}
            RETURNING airtable_id, id
        `;

        try {
            const res = await pool.query(query, values);
            const idMap = {};
            if (res.rows) {
                for (const r of res.rows) {
                    idMap[r.airtable_id] = r.id;
                    _fkCache[`${tableName}:${r.airtable_id}`] = r.id;
                }
            }
            for (const row of batch) {
                if (idMap[row.airtable_id]) row._internal_id = idMap[row.airtable_id];
                count++;
            }
        } catch (err) {
            console.error(`\n   ❌ Failed batch ${i}: ${err.message}`);
        }
    }
    process.stdout.write('\n');
    return count;
}

// ── Post-processing: screener_assignments ─────────────────────

async function syncScreenerAssignments(pgPool, records, config) {
    if (config.supabaseTable !== 'applications_id') return;

    const roles = [
        { airField: 'Screener', role: 'screener' },
        { airField: 'Tech Screener', role: 'tech_screener' },
    ];

    let count = 0;
    const insertData = [];

    for (const record of records) {
        const appId = await resolveFK(pgPool, 'applications_id', record.id);
        if (!appId) continue;

        for (const r of roles) {
            const links = record.fields[r.airField];
            const screenerAirtableId = Array.isArray(links) && links.length > 0 ? links[0] : null;
            if (!screenerAirtableId) continue;

            const screenerId = await resolveFK(pgPool, 'screeners_profile', screenerAirtableId);
            if (!screenerId) continue;

            insertData.push([screenerId, appId, r.role]);
        }
    }

    if (insertData.length > 0) {
        const batchSize = 1000;
        for (let i = 0; i < insertData.length; i += batchSize) {
            const chunk = insertData.slice(i, i + batchSize);
            const values = [];
            const placeholders = [];
            let paramIdx = 1;

            for (const row of chunk) {
                values.push(row[0], row[1], row[2]);
                placeholders.push(`($${paramIdx++}, $${paramIdx++}, $${paramIdx++})`);
            }

            try {
                await pgPool.query(`
                    INSERT INTO screener_assignments (screener_id, application_id, role)
                    VALUES ${placeholders.join(', ')}
                    ON CONFLICT (screener_id, application_id, role) DO NOTHING
                `, values);
                count += chunk.length;
            } catch (err) {
                console.error(`      [TRACE] Assignments Bulk Error: ${err.message}`);
            }
        }
    }

    if (count > 0) console.log(`      👤 Synced ${count} screener assignments`);
}

// ── Post-processing: onboarding_events ────────────────────────

async function syncOnboardingEvents(pgPool, records, config) {
    if (config.supabaseTable !== 'selected_candidates') return;

    const eventDefs = [
        { airDate: 'Vendor onboarding date', airStatus: 'Xpo onboarding status', eventType: 'vendor_onboarding' },
        { airDate: 'End Client onboarding', airStatus: 'End Client onboarding status', eventType: 'end_client_onboarding' },
        { airDate: 'BGV Trigger Date', airStatus: 'BGV Status', eventType: 'bgv' },
        { airDate: 'BGV Doc submission date', airStatus: null, eventType: 'bgv_doc_submission' },
        { airDate: 'SOW Signing Date', airStatus: null, eventType: 'sow_signing' },
    ];

    let count = 0;
    const insertData = [];

    for (const record of records) {
        const selId = await resolveFK(pgPool, 'selected_candidates', record.id);
        if (!selId) continue;

        for (const ed of eventDefs) {
            const eventDate = record.fields[ed.airDate];
            if (!eventDate) continue;

            const status = ed.airStatus ? (record.fields[ed.airStatus] || null) : null;
            insertData.push([selId, ed.eventType, eventDate, status]);
        }
    }

    if (insertData.length > 0) {
        const batchSize = 1000;
        for (let i = 0; i < insertData.length; i += batchSize) {
            const chunk = insertData.slice(i, i + batchSize);
            const values = [];
            const placeholders = [];
            let paramIdx = 1;

            for (const row of chunk) {
                values.push(row[0], row[1], row[2], row[3]);
                placeholders.push(`($${paramIdx++}, $${paramIdx++}, $${paramIdx++}, $${paramIdx++})`);
            }

            try {
                await pgPool.query(`
                    INSERT INTO onboarding_events (selected_id, event_type, event_date, status)
                    VALUES ${placeholders.join(', ')}
                    ON CONFLICT DO NOTHING
                `, values);
                count += chunk.length;
            } catch (err) {
                console.error(`      [TRACE] Onboarding Bulk Error: ${err.message}`);
            }
        }
    }

    if (count > 0) console.log(`      📋 Synced ${count} onboarding events`);
}

// ── Post-processing: Many-to-Many ─────────────────────────────

async function syncManyToMany(pgPool, records, config) {
    if (!config.manyToMany) return;

    for (const [airField, m2m] of Object.entries(config.manyToMany)) {
        let count = 0;
        console.log(`      [TRACE] M2M bulk-sync for ${airField} with ${records.length} records`);

        const sourceIds = [];
        const insertPairs = [];

        for (const record of records) {
            const targetAirtableIds = record.fields[airField];
            if (!Array.isArray(targetAirtableIds) || targetAirtableIds.length === 0) continue;

            const sourceId = await resolveFK(pgPool, config.supabaseTable, record.id);
            if (!sourceId) continue;
            sourceIds.push(sourceId);

            for (const targetAirtableId of targetAirtableIds) {
                const targetId = await resolveFK(pgPool, m2m.targetTable, targetAirtableId);
                if (targetId) insertPairs.push({ source: sourceId, target: targetId });
            }
        }

        if (sourceIds.length === 0) continue;

        try {
            await pgPool.query(
                `DELETE FROM "${m2m.junctionTable}" WHERE "${m2m.sourceColumn}" = ANY($1::uuid[])`,
                [sourceIds]
            );

            if (insertPairs.length > 0) {
                const batchSize = 1000;
                for (let i = 0; i < insertPairs.length; i += batchSize) {
                    const chunk = insertPairs.slice(i, i + batchSize);
                    const values = [];
                    const placeholders = [];
                    let paramIdx = 1;

                    for (const pair of chunk) {
                        values.push(pair.source, pair.target);
                        placeholders.push(`($${paramIdx++}, $${paramIdx++})`);
                    }

                    await pgPool.query(`
                        INSERT INTO "${m2m.junctionTable}" ("${m2m.sourceColumn}", "${m2m.targetColumn}")
                        VALUES ${placeholders.join(', ')}
                        ON CONFLICT DO NOTHING
                    `, values);
                    count += chunk.length;
                }
            }
        } catch (err) {
            console.error(`      [TRACE] M2M Bulk Error: ${err.message}`);
        }

        if (count > 0) console.log(`      🔗 Synced ${count} ${airField} links`);
    }
}

async function runSync() {
    const pgPool = new Pool({ connectionString: DATABASE_URL, max: 5 });

    const state = getSyncState();
    const startTime = new Date().toISOString();

    console.log(`\n🔄 Starting Sync [Last Sync: ${state.last_sync || 'Never'}]`);
    console.log(''.padEnd(50, '-'));

    let totalUpdated = 0;

    for (const config of SYNC_CONFIG) {
        try {
            console.log(`📋 ${config.airtableName}...`);
            const records = await fetchAirtableSync(config.airtableName, state.last_sync);

            if (records.length === 0) {
                console.log('   ✅ Up to date (0 changes)');
                continue;
            }

            // ── Build rows for upsert ──
            const rows = records.map(r => {
                const row = { airtable_id: r.id };

                // Direct field mappings
                for (const [airName, supName] of Object.entries(config.fieldMap)) {
                    row[supName] = transformValue(r.fields[airName]);
                }

                // Link field mappings are stored as airtable_id text temporarily
                // We'll resolve them inline after building all rows
                return row;
            });

            // ── Resolve link fields inline ──
            for (let i = 0; i < rows.length; i++) {
                const record = records[i];
                const row = rows[i];
                for (const [airName, linkDef] of Object.entries(config.linkFields)) {
                    const links = record.fields[airName];
                    const airtableId = Array.isArray(links) && links.length > 0 ? links[0] : null;
                    row[linkDef.col] = await resolveFK(pgPool, linkDef.target, airtableId);
                }
            }

            const updated = await upsertBatch(pgPool, config.supabaseTable, rows);
            console.log(`   ✅ Synced ${updated} records`);
            totalUpdated += updated;

            // ── Post-processing ──

            console.log('      [TRACE] Starting Screener Assignments');
            await syncScreenerAssignments(pgPool, records, config);
            console.log('      [TRACE] Starting Onboarding Events');
            await syncOnboardingEvents(pgPool, records, config);
            console.log('      [TRACE] Starting M2M');
            await syncManyToMany(pgPool, records, config);
            console.log('      [TRACE] Finished Post-processing');


        } catch (err) {
            console.error(`   ❌ Error: ${err.message}`);
        }
    }

    saveSyncState(startTime);
    console.log(''.padEnd(50, '-'));
    console.log(`🎉 Sync Finished. Total records updated: ${totalUpdated}\n`);

    await pgPool.end();
}

runSync();
