const fs = require('fs');
let code = fs.readFileSync('sync.js', 'utf8');

// 1. Replace Client with Pool
code = code.replace("const { Client } = require('pg');", "const { Pool } = require('pg');");
code = code.replace("const pgClient = new Client({ connectionString: DATABASE_URL });\n    await pgClient.connect();", 
                    "const pgPool = new Pool({ connectionString: DATABASE_URL, max: 20 });");
// Change all pgClient to pgPool in runSync
code = code.replace(/pgClient/g, "pgPool");
// Don't call .end() if it's Client, but Pool needs .end() which is the same
// 2. Rewrite upsertBatch to be concurrent
const newUpsertBatch = `async function upsertBatch(pool, tableName, rows) {
    if (rows.length === 0) return 0;
    const batchSize = 100;
    let count = 0;

    for (let i = 0; i < rows.length; i += batchSize) {
        process.stdout.write(\`\\r      ⏳ Upserting batch \${i} to \${i + batchSize}...\`);
        const batch = rows.slice(i, i + batchSize);
        const columns = Object.keys(batch[0]);
        const updateCols = columns.filter(c => c !== 'airtable_id' && c !== 'id');
        const setClause = updateCols.map(c => \`"\${c}" = EXCLUDED."\${c}"\`).join(', ');

        const promises = batch.map(async (row) => {
            const values = columns.map(c => row[c]);
            const placeholders = values.map((_, idx) => \`\$\${idx + 1}\`).join(', ');
            const query = \`
                INSERT INTO "\${tableName}" (\${columns.map(c => \`"\${c}"\`).join(', ')})
                VALUES (\${placeholders})
                ON CONFLICT (airtable_id) DO UPDATE SET \${setClause}
                RETURNING id
            \`;
            try {
                const res = await pool.query(query, values);
                row._internal_id = res.rows[0].id;
                count++;
            } catch (err) {
                console.error(\`\\n   ❌ Failed row \${row.airtable_id}: \${err.message}\`);
            }
        });
        await Promise.all(promises);
    }
    process.stdout.write('\\n');
    return count;
}`;
code = code.replace(/async function upsertBatch[\s\S]*?return count;\n}/, newUpsertBatch);

fs.writeFileSync('sync.js', code);
console.log('Patched to use Pool and concurrent batch queries.');
