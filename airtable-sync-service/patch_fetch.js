const fs = require('fs');
let code = fs.readFileSync('sync.js', 'utf8');

// Replace fetchAirtableSync with a more robust one
code = code.replace(/async function fetchAirtableSync[\s\S]*?function transformValue/m, `async function fetchAirtableSync(tableName, lastSync) {
    return new Promise((resolve, reject) => {
        const encodedTable = encodeURIComponent(tableName);
        let allRecords = [];
        let totalFetched = 0;

        const fetchPage = (currentOffset) => {
            let urlPath = \`/v0/\${AIRTABLE_BASE}/\${encodedTable}?pageSize=100\`;
            if (currentOffset) urlPath += \`&offset=\${currentOffset}\`;

            if (lastSync && !process.argv.includes('--full')) {
                urlPath += \`&filterByFormula=\${encodeURIComponent(\`IS_AFTER(LAST_MODIFIED_TIME(), "\${lastSync}")\`)}\`;
            }

            const options = {
                hostname: 'api.airtable.com',
                path: urlPath,
                headers: { 'Authorization': \`Bearer \${AIRTABLE_TOKEN}\` },
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
                            return reject(new Error(\`Airtable Error: \${parsed.error.message}\`));
                        }
                        
                        if (parsed.records) {
                            allRecords.push(...parsed.records);
                            totalFetched += parsed.records.length;
                            process.stdout.write(\`\\r      ⏳ Fetched \${totalFetched} airtable records...\`);
                        }
                        
                        if (parsed.offset) {
                            setTimeout(() => fetchPage(parsed.offset), 250);
                        } else {
                            process.stdout.write('\\n');
                            resolve(allRecords);
                        }
                    } catch (e) { 
                        return reject(new Error(\`Parse error: \${e.message} | Data: \${data.substring(0,100)}\`)); 
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

function transformValue`);

fs.writeFileSync('sync.js', code);
console.log('Patched fetch hook.');
