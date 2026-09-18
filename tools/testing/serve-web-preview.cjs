// Read-only loopback preview. Build with ESEP_API_BASE pointing to a test API.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../build/web');
const mime = {'.html':'text/html', '.js':'application/javascript', '.json':'application/json', '.css':'text/css', '.wasm':'application/wasm', '.png':'image/png', '.svg':'image/svg+xml', '.woff2':'font/woff2'};
http.createServer((req, res) => {
  if (!['GET', 'HEAD'].includes(req.method)) {res.writeHead(405); return res.end();}
  let file;
  try {
    const url = new URL(req.url, 'http://127.0.0.1');
    file = path.resolve(root, '.' + decodeURIComponent(url.pathname));
    if (file !== root && !file.startsWith(root + path.sep)) {res.writeHead(403); return res.end();}
    if (fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
    const body = fs.readFileSync(file);
    res.writeHead(200, {'Content-Type':mime[path.extname(file)] || 'application/octet-stream', 'Cache-Control':'no-store'});
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch {res.writeHead(404); res.end('Not found');}
}).listen(38761, '127.0.0.1', () => console.log('Local preview: http://127.0.0.1:38761 (no deployment)'));
