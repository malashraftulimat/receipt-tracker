#!/usr/bin/env node
/**
 * Zero-dependency static server for the Flutter web build.
 *
 *   node scripts/serve_web.js            # http://localhost:8080
 *   node scripts/serve_web.js 3000       # custom port
 *
 * Binds 0.0.0.0 so a phone on the same Wi-Fi can open
 * http://<your-LAN-IP>:<port>/ .
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const port = Number(process.argv[2] || process.env.PORT || 8080);
const root = path.resolve(__dirname, '..', 'build', 'web');

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.wasm': 'application/wasm',
  '.map': 'application/json; charset=utf-8',
  '.bin': 'application/octet-stream',
  '.txt': 'text/plain; charset=utf-8',
};

if (!fs.existsSync(path.join(root, 'index.html'))) {
  console.error('build/web not found. Run: flutter build web --release');
  process.exit(1);
}

const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  let file = path.join(root, urlPath);
  if (!file.startsWith(root)) {
    res.writeHead(403).end('forbidden');
    return;
  }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) {
    file = path.join(file, 'index.html');
  }
  if (!fs.existsSync(file)) {
    // Hash-based routing means this is rarely needed, but SPA fallback is cheap.
    file = path.join(root, 'index.html');
  }
  const ext = path.extname(file).toLowerCase();
  res.writeHead(200, {
    'Content-Type': types[ext] || 'application/octet-stream',
    'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=3600',
  });
  fs.createReadStream(file).pipe(res);
});

server.listen(port, '0.0.0.0', () => {
  const nets = os.networkInterfaces();
  const lan = Object.values(nets)
    .flat()
    .filter((n) => n && n.family === 'IPv4' && !n.internal)
    .map((n) => n.address);
  console.log(`Website:   http://localhost:${port}/`);
  for (const ip of lan) console.log(`On phone:  http://${ip}:${port}/  (same Wi-Fi)`);
  console.log('Press Ctrl+C to stop.');
});
