require('./stub.js');
const fs = require('fs');
const src = fs.readFileSync('out.js', 'utf8');
// expose the top-level vars/functions for testing
const ctxWrap = new Function(src + '\n; return { get: (n) => eval(n), call: (n, ...a) => eval(n)(...a), set: (n, v) => eval(n + " = v") };');
const api = ctxWrap();
module.exports = api;
