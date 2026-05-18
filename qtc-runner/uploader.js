/**
 * uploader.js  —  Uploads test results + attachments back to Salesforce.
 *
 * Responsibilities:
 *   1. Create Test_Result__c child records (one per Playwright test case).
 *   2. Upload screenshots and video as ContentVersion records linked to
 *      the Test_Run__c record via ContentDocumentLink.
 *   3. Patch the Test_Run__c record with final status, counts, and log.
 */

'use strict';

const fs         = require('fs');
const path       = require('path');
const https      = require('https');
const http       = require('http');
const { URL }    = require('url');
const { getSfCredentials } = require('./auth');

// ─── REST helpers ────────────────────────────────────────────────────────────

async function sfRequest(method, path, body) {
    const { instanceUrl, accessToken } = getSfCredentials();
    const url = new URL(path, instanceUrl);

    return new Promise((resolve, reject) => {
        const bodyStr  = body ? JSON.stringify(body) : null;
        const options  = {
            hostname : url.hostname,
            path     : url.pathname + url.search,
            method,
            headers  : {
                Authorization  : `Bearer ${accessToken}`,
                'Content-Type' : 'application/json',
                ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {}),
            },
        };
        const proto = url.protocol === 'https:' ? https : http;
        const req = proto.request(options, res => {
            let data = '';
            res.on('data', chunk => { data += chunk; });
            res.on('end', () => {
                try {
                    const parsed = data ? JSON.parse(data) : null;
                    if (res.statusCode >= 400) {
                        reject(new Error(
                            `SF API ${method} ${path} → ${res.statusCode}: ${data}`
                        ));
                    } else {
                        resolve(parsed);
                    }
                } catch (e) {
                    reject(new Error(`JSON parse error: ${e.message} — body: ${data}`));
                }
            });
        });
        req.on('error', reject);
        if (bodyStr) req.write(bodyStr);
        req.end();
    });
}

// ─── Upload binary file as ContentVersion ────────────────────────────────────

/**
 * Uploads a local file to Salesforce Files (ContentVersion) and links it
 * to a parent record via ContentDocumentLink.
 *
 * @param {string} filePath     - Absolute path to the file on disk
 * @param {string} title        - File title shown in Salesforce
 * @param {string} parentId     - Salesforce record Id to link the file to
 * @returns {string}            - ContentDocumentId
 */
async function uploadFile(filePath, title, parentId) {
    if (!fs.existsSync(filePath)) {
        console.warn(`[uploader] File not found, skipping: ${filePath}`);
        return null;
    }

    const { instanceUrl, accessToken } = getSfCredentials();
    const fileBuffer  = fs.readFileSync(filePath);
    const base64Data  = fileBuffer.toString('base64');
    const ext         = path.extname(filePath).slice(1).toLowerCase();
    const mimeType    = ext === 'png'  ? 'image/png'
                      : ext === 'webm' ? 'video/webm'
                      : ext === 'mp4'  ? 'video/mp4'
                      : 'application/octet-stream';

    // ContentVersion insert via multipart/form-data
    const boundary = `----QtcBoundary${Date.now()}`;
    const metaJson = JSON.stringify({
        Title         : title,
        PathOnClient  : path.basename(filePath),
        VersionData   : base64Data,
        IsMajorVersion: true,
    });

    const cv = await sfRequest(
        'POST',
        `/services/data/v62.0/sobjects/ContentVersion`,
        {
            Title         : title,
            PathOnClient  : path.basename(filePath),
            VersionData   : base64Data,
            IsMajorVersion: true,
        }
    );

    if (!cv || !cv.id) {
        throw new Error(`ContentVersion insert failed: ${JSON.stringify(cv)}`);
    }

    // Retrieve ContentDocumentId
    const query = `/services/data/v62.0/query?q=${encodeURIComponent(
        `SELECT ContentDocumentId FROM ContentVersion WHERE Id = '${cv.id}'`
    )}`;
    const queryRes  = await sfRequest('GET', query);
    const docId     = queryRes.records[0].ContentDocumentId;

    // Link to parent record
    await sfRequest('POST', '/services/data/v62.0/sobjects/ContentDocumentLink', {
        ContentDocumentId : docId,
        LinkedEntityId    : parentId,
        ShareType         : 'V',
        Visibility        : 'AllUsers',
    });

    console.log(`[uploader] Uploaded "${title}" → ContentDocument ${docId}`);
    return docId;
}

// ─── Insert Test_Result__c records ───────────────────────────────────────────

/**
 * @param {string} testRunId
 * @param {Array<{
 *   title: string, status: string, durationMs: number,
 *   suiteName: string, errorMessage: string, retryCount: number
 * }>} tests
 */
async function insertTestResults(testRunId, tests) {
    for (const t of tests) {
        const record = {
            Test_Run__c   : testRunId,
            Name          : t.title.slice(0, 80),
            Test_Name__c  : t.title,
            Suite_Name__c : t.suiteName || '',
            Status__c     : t.status,   // PASSED | FAILED | SKIPPED
            Duration_Ms__c: t.durationMs || 0,
            Retry_Count__c: t.retryCount || 0,
        };
        if (t.errorMessage) record.Error_Message__c = t.errorMessage.slice(0, 32000);

        await sfRequest('POST', '/services/data/v62.0/sobjects/Test_Result__c', record);
    }
    console.log(`[uploader] Inserted ${tests.length} Test_Result__c records`);
}

// ─── Patch the Test_Run__c record ────────────────────────────────────────────

/**
 * @param {string} testRunId
 * @param {{
 *   status: string, passed: number, failed: number, durationMs: number,
 *   errorMessage: string, logOutput: string, completedAt: string
 * }} fields
 */
async function patchTestRun(testRunId, fields) {
    const body = {
        Status__c       : fields.status,
        Tests_Passed__c : fields.passed    || 0,
        Tests_Failed__c : fields.failed    || 0,
        Duration_Ms__c  : fields.durationMs || 0,
        Completed_At__c : fields.completedAt || new Date().toISOString(),
    };
    if (fields.errorMessage) {
        body.Error_Message__c = fields.errorMessage.slice(0, 32000);
    }
    if (fields.logOutput) {
        body.Log_Output__c = fields.logOutput.slice(0, 131000);
    }
    if (fields.richResults) {
        // Salesforce Long Text Area max = 131072 chars
        const richStr = typeof fields.richResults === 'string'
            ? fields.richResults
            : JSON.stringify(fields.richResults);
        body.Rich_Results__c = richStr.slice(0, 131072);
    }

    await sfRequest('PATCH', `/services/data/v62.0/sobjects/Test_Run__c/${testRunId}`, body);
    console.log(`[uploader] Patched Test_Run__c ${testRunId} → ${fields.status}`);
}

module.exports = { uploadFile, insertTestResults, patchTestRun };
