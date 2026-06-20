const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ status: 'ok', service: 'smoke' }));
});

server.listen(3000, () => {
  console.log('smoke service running on port 3000');
});
