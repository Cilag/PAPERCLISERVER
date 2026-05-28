#!/usr/bin/env node
// post-issue.js <descFile> <title> <assigneeAgentId> [status] [priority]
// Posts an issue to the local Paperclip API for company "Guigui Lab".
const fs = require('fs');
const http = require('http');

const [descFile, title, assignee, status = 'todo', priority = 'high'] = process.argv.slice(2);
const CID = 'f7e677f1-a742-4876-a930-b6ac9c0ff13c';
const description = fs.readFileSync(descFile, 'utf8');
const payload = JSON.stringify({ title, description, assigneeAgentId: assignee, status, priority });

const req = http.request({
  host: '127.0.0.1', port: 3100, method: 'POST',
  path: `/api/companies/${CID}/issues`,
  headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
}, (res) => {
  let body = '';
  res.on('data', (c) => (body += c));
  res.on('end', () => {
    try {
      const i = JSON.parse(body);
      console.log(`created: ${i.identifier} | status=${i.status} | assignee=${i.assigneeAgentId ? i.assigneeAgentId.slice(0, 8) : 'none'} | id=${i.id}`);
    } catch (e) {
      console.error(`HTTP ${res.statusCode}: ${body.slice(0, 300)}`);
      process.exit(1);
    }
  });
});
req.on('error', (e) => { console.error('request error:', e.message); process.exit(1); });
req.write(payload);
req.end();
