require('dotenv').config();
const cron = require('node-cron');
const { spawn } = require('child_process');

console.log('🚀 Airtable to Supabase Sync Service Started');
console.log('⏰ Scheduled to run every 5 minutes');

// Schedule: Every 5 minutes (*/5 * * * *)
cron.schedule('*/5 * * * *', () => {
    console.log(`\n[${new Date().toISOString()}] Starting scheduled sync...`);

    const sync = spawn('node', ['sync.js']);

    sync.stdout.on('data', (data) => {
        process.stdout.write(data);
    });

    sync.stderr.on('data', (data) => {
        process.stderr.write(`❌ Error: ${data}`);
    });

    sync.on('close', (code) => {
        console.log(`[${new Date().toISOString()}] Sync process finished with code ${code}`);
    });
});

// Run immediately on startup
console.log('🏃 Running initial sync...');
const initialSync = spawn('node', ['sync.js']);
initialSync.stdout.on('data', (data) => process.stdout.write(data));
initialSync.on('close', () => console.log('✅ Initial sync complete. Waiting for schedule...'));
