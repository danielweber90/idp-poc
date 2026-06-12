const http = require('http');

const PORT = parseInt(process.env.PORT || '3000', 10);
const APP_NAME = '${{ values.name }}';

const server = http.createServer((req, res) => {
  if (req.url === '/health' || req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', app: APP_NAME }));
    return;
  }

  if (req.url === '/metrics') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end([
      '# HELP http_requests_total Total HTTP requests',
      '# TYPE http_requests_total counter',
      'http_requests_total{app="' + APP_NAME + '",status="200"} 1',
    ].join('\n'));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end('<!DOCTYPE html><html><head><title>' + APP_NAME + '</title></head><body>' +
    '<h1>' + APP_NAME + '</h1>' +
    '<p>Deployed via IDP PoC GitOps</p>' +
    '<ul>' +
    '<li>Runtime: ${{ values.runtime }}</li>' +
    '<li>Owner: ${{ values.owner }}</li>' +
    '<li>PostgreSQL: ${{ values.postgresql.enabled }}</li>' +
    '<li>Redis: ${{ values.redis.enabled }}</li>' +
    '<li>Object Storage: ${{ values.objectStorage.enabled }}</li>' +
    '</ul></body></html>');
});

server.listen(PORT, () => {
  console.log(APP_NAME + ' listening on port ' + PORT);
});
