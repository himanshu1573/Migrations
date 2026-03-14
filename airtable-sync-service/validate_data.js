require('dotenv').config({ path: __dirname + '/.env.local' });
const { Pool } = require('pg');
const https = require('https');

const AIRTABLE_TOKEN = process.env.AIRTABLE_ACCESS_TOKEN;
const AIRTABLE_BASE = process.env.AIRTABLE_BASE_ID;
const DATABASE_URL = process.env.DATABASE_URL;

const pgPool = new Pool({ connectionString: DATABASE_URL });

async function fetchAirtableRecord(tableName, recordId) {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'api.airtable.com',
            path: `/v0/${AIRTABLE_BASE}/${encodeURIComponent(tableName)}/${recordId}`,
            headers: { 'Authorization': `Bearer ${AIRTABLE_TOKEN}` }
        };
        https.get(options, res => {
            let data = '';
            res.on('data', c => data += c);
            res.on('end', () => resolve(JSON.parse(data)));
            res.on('error', reject);
        });
    });
}

async function validateRandomVendorOpenings() {
    console.log('\n--- 1. Validating Vendor Openings (Many-to-Many) ---');
    // Get a vendor with openings mapped
    const res = await pgPool.query(`
        SELECT v.id, v.airtable_id, v.vendor_name, COUNT(vo.opening_id) as pg_count
        FROM vendor_master v
        JOIN vendor_openings vo ON vo.vendor_id = v.id
        GROUP BY v.id, v.airtable_id, v.vendor_name
        ORDER BY RANDOM() LIMIT 1
    `);
    if (res.rows.length === 0) return console.log('❌ No vendors with openings found in PG.');
    const vendor = res.rows[0];
    console.log(`🔹 Checking Vendor: ${vendor.vendor_name} (PG Openings count: ${vendor.pg_count})`);

    const airtableVendor = await fetchAirtableRecord('Vendor Master', vendor.airtable_id);
    const airtableOpenings = airtableVendor.fields['Openings'] || [];
    console.log(`🔹 Airtable Openings count: ${airtableOpenings.length}`);

    if (Number(vendor.pg_count) === airtableOpenings.length) {
        console.log('✅ Vendor Openings Match!');
    } else {
        console.log('❌ Mismatch in Vendor Openings!');
    }
}

async function validateRandomApplication() {
    console.log('\n--- 2. Validating Application (Screener Assignments) ---');
    const res = await pgPool.query(`
        SELECT a.id, a.airtable_id,
            (SELECT COUNT(*) FROM screener_assignments s WHERE s.application_id = a.id) as screener_count
        FROM applications_id a
        WHERE a.airtable_id IS NOT NULL
          AND EXISTS (SELECT 1 FROM screener_assignments s WHERE s.application_id = a.id)
        ORDER BY RANDOM() LIMIT 1
    `);
    if (res.rows.length === 0) return console.log('❌ No application found with screener assignments.');
    const app = res.rows[0];
    console.log(`🔹 Checking Application (PG Screeners: ${app.screener_count})`);

    const airApp = await fetchAirtableRecord('Applications_ID', app.airtable_id);

    let airScreenerCount = 0;
    if (airApp.fields['Screener']) airScreenerCount++;
    if (airApp.fields['Tech Screener']) airScreenerCount++;

    console.log(`🔹 Airtable equivalent Screeners: ${airScreenerCount}`);

    if (Number(app.screener_count) === airScreenerCount) {
        console.log('✅ Application Screener Data Matches!');
    } else {
        console.log('❌ Mismatch in Application Screener Data!');
    }
}

async function validateRandomOnboarding() {
    console.log('\n--- 3. Validating Selected Candidate (Onboarding Events) ---');
    const res = await pgPool.query(`
        SELECT s.id, s.airtable_id,
            (SELECT COUNT(*) FROM onboarding_events o WHERE o.selected_id = s.id) as event_count
        FROM selected_candidates s
        WHERE EXISTS (SELECT 1 FROM onboarding_events o WHERE o.selected_id = s.id)
        ORDER BY RANDOM() LIMIT 1
    `);
    if (res.rows.length === 0) return console.log('❌ No selected candidates with events found.');
    const sCand = res.rows[0];
    console.log(`🔹 Checking Selected Candidate (PG Events: ${sCand.event_count})`);

    const airCand = await fetchAirtableRecord('Selected Candidates', sCand.airtable_id);

    let airEventCount = 0;
    if (airCand.fields['Vendor onboarding date']) airEventCount++;
    if (airCand.fields['End Client onboarding']) airEventCount++;
    if (airCand.fields['BGV Trigger Date']) airEventCount++;
    if (airCand.fields['BGV Doc submission date']) airEventCount++;
    if (airCand.fields['SOW Signing Date']) airEventCount++;

    console.log(`🔹 Airtable mapped Events count: ${airEventCount}`);

    if (Number(sCand.event_count) === airEventCount) {
        console.log('✅ Onboarding Events Match!');
    } else {
        console.log('❌ Mismatch in Onboarding Events!');
    }
}

async function validateOpeningLocations() {
    console.log('\n--- 4. Validating Opening Locations (Many-to-Many) ---');
    const res = await pgPool.query(`
        SELECT o.id, o.airtable_id, o.job_title, COUNT(olo.locations_id) as pg_count
        FROM openings o
        JOIN openings_locations_openings olo ON olo.openings_id = o.id
        GROUP BY o.id, o.airtable_id, o.job_title
        ORDER BY RANDOM() LIMIT 1
    `);
    if (res.rows.length === 0) return console.log('❌ No openings with locations found.');
    const opening = res.rows[0];
    console.log(`🔹 Checking Opening: ${opening.job_title} (PG Location count: ${opening.pg_count})`);

    const airOpen = await fetchAirtableRecord('Openings', opening.airtable_id);
    const airLocs = airOpen.fields['Locations_Openings'] || [];
    console.log(`🔹 Airtable Location count: ${airLocs.length}`);

    if (Number(opening.pg_count) === airLocs.length) {
        console.log('✅ Opening Locations Match!\n');
    } else {
        console.log('❌ Mismatch in Opening Locations!\n');
    }
}

async function validateRandomCandidateProfile() {
    console.log('\n--- 5. Validating Candidate Profile (Vendor Link) ---');
    const res = await pgPool.query(`
        SELECT p.id, p.airtable_id, p.candidate_name, p.candidate_email, v.airtable_id as pg_vendor_airtable_id
        FROM profiles_database p
        JOIN vendor_master v ON v.id = p.vendors_id
        ORDER BY RANDOM() LIMIT 1
    `);
    if (res.rows.length === 0) return console.log('❌ No profiles found with a linked vendor.');
    const profile = res.rows[0];
    console.log(`🔹 Checking Profile: ${profile.candidate_name} (Email: ${profile.candidate_email})`);

    const airProfile = await fetchAirtableRecord('Profiles Database', profile.airtable_id);
    const airVendorIdArray = airProfile.fields['Vendors Id'] || [];
    const airVendorId = airVendorIdArray.length > 0 ? airVendorIdArray[0] : null;

    console.log(`🔹 PG mapped vendor airtable_id: ${profile.pg_vendor_airtable_id}`);
    console.log(`🔹 Airtable vendor link: ${airVendorId}`);

    if (profile.pg_vendor_airtable_id === airVendorId) {
        console.log('✅ Candidate Vendor Link Matches!');
    } else {
        console.log('❌ Mismatch in Candidate Vendor Link!');
    }
}

async function validateRandomScreening() {
    console.log('\n--- 6. Validating Screening (Candidate & App Links) ---');
    const res = await pgPool.query(`
        SELECT s.id, s.airtable_id, s.status, 
               p.airtable_id as pg_candidate_airtable_id,
               a.airtable_id as pg_app_airtable_id
        FROM screenings s
        JOIN profiles_database p ON p.id = s.candidate_id
        JOIN applications_id a ON a.id = s.application_id
        ORDER BY RANDOM() LIMIT 1
    `);
    if (res.rows.length === 0) return console.log('❌ No screenings found with loaded candidate/app links.');
    const scr = res.rows[0];
    console.log(`🔹 Checking Screening: ${scr.airtable_id} (Status: ${scr.status})`);

    const airScr = await fetchAirtableRecord('Screenings', scr.airtable_id);

    const airCandLink = (airScr.fields['Candidate ID'] || [])[0];
    const airAppLink = (airScr.fields['Application Id'] || [])[0];

    console.log(`🔹 PG   => Candidate: ${scr.pg_candidate_airtable_id}, App: ${scr.pg_app_airtable_id}`);
    console.log(`🔹 Airtable => Candidate: ${airCandLink}, App: ${airAppLink}`);

    if (scr.pg_candidate_airtable_id === airCandLink && scr.pg_app_airtable_id === airAppLink) {
        console.log('✅ Screening Linked Entities Match!');
    } else {
        console.log('❌ Mismatch in Screening Linked Entities!');
    }
}

async function runValidations() {
    try {
        await validateRandomVendorOpenings();
        await validateRandomApplication();
        await validateRandomOnboarding();
        await validateOpeningLocations();
        await validateRandomCandidateProfile();
        await validateRandomScreening();
    } catch (err) {
        console.error('Validation Script Error:', err);
    } finally {
        await pgPool.end();
    }
}

runValidations();
