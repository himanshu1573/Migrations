const fs = require('fs');
let code = fs.readFileSync('sync.js', 'utf8');

const traceCode = `
            console.log('      [TRACE] Starting Interview Rounds');
            await syncInterviewRounds(pgPool, records, config);
            console.log('      [TRACE] Starting Screener Assignments');
            await syncScreenerAssignments(pgPool, records, config);
            console.log('      [TRACE] Starting Onboarding Events');
            await syncOnboardingEvents(pgPool, records, config);
            console.log('      [TRACE] Starting M2M');
            await syncManyToMany(pgPool, records, config);
            console.log('      [TRACE] Finished Post-processing');
`;

code = code.replace(
    /await syncInterviewRounds\(pgPool, records, config\);\n *await syncScreenerAssignments\(pgPool, records, config\);\n *await syncOnboardingEvents\(pgPool, records, config\);\n *await syncManyToMany\(pgPool, records, config\);/,
    traceCode
);

code = code.replace(/async function syncManyToMany[\s\S]*?async function runSync/m, 
`async function syncManyToMany(pgPool, records, config) {
    if (!config.manyToMany) return;

    for (const [airField, m2m] of Object.entries(config.manyToMany)) {
        let count = 0;
        console.log(\`      [TRACE] M2M loop for \${airField} with \${records.length} records\`);
        let recordIndex = 0;
        for (const record of records) {
            recordIndex++;
            try {
                const sourceId = await resolveFK(pgPool, config.supabaseTable, record.id);
                if (!sourceId) continue;

                const targetAirtableIds = record.fields[airField];
                if (!Array.isArray(targetAirtableIds) || targetAirtableIds.length === 0) continue;

                await pgPool.query(
                    \`DELETE FROM "\${m2m.junctionTable}" WHERE "\${m2m.sourceColumn}" = \$1\`,
                    [sourceId]
                );

                for (const targetAirtableId of targetAirtableIds) {
                    const targetId = await resolveFK(pgPool, m2m.targetTable, targetAirtableId);
                    if (!targetId) continue;

                    await pgPool.query(\`
                        INSERT INTO "\${m2m.junctionTable}" ("\${m2m.sourceColumn}", "\${m2m.targetColumn}")
                        VALUES (\$1, \$2) ON CONFLICT DO NOTHING
                    \`, [sourceId, targetId]);
                    count++;
                }
            } catch (err) {
                console.error(\`      [TRACE] Error in M2M record \${record.id}: \${err.message}\`);
            }
        }
        if (count > 0) console.log(\`      🔗 Synced \${count} \${airField} links\`);
    }
}

async function runSync`);

fs.writeFileSync('sync.js', code);
console.log('Patched with traces!');
