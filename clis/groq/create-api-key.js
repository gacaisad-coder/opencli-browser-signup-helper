import { cli, Strategy } from '@jackwener/opencli/registry';
import { execFileSync } from 'node:child_process';

const SCRIPT = process.env.OPENCLI_GROQ_CREATE_API_KEY_SCRIPT || `${process.cwd()}/scripts/opencli-groq-create-api-key.sh`;

function normalize(value) {
  return String(value || '').trim();
}

function parseJson(text) {
  try {
    return JSON.parse(String(text || ''));
  } catch (err) {
    throw new Error(`failed to parse helper output as json: ${err.message}\n${String(text || '').slice(0, 500)}`);
  }
}

cli({
  site: 'groq',
  name: 'create-api-key',
  description: 'Use a Groq magic-link login URL, open API Keys, and create a key after manual Turnstile verification',
  domain: 'console.groq.com',
  strategy: Strategy.LOCAL,
  browser: false,
  args: [
    { name: 'login-url', type: 'string', default: '', description: 'Groq/Stytch magic-link login URL' },
    { name: 'name', type: 'string', default: 'groq-openclaw', description: 'display name for the new API key' },
    { name: 'wait-seconds', type: 'int', default: 120, description: 'how long to wait for manual Cloudflare Turnstile completion' },
    { name: 'poll-interval', type: 'int', default: 2, description: 'poll interval while waiting for Turnstile completion' },
  ],
  columns: ['key_name', 'status', 'detail', 'url'],
  func: async (_page, kwargs) => {
    const loginUrl = normalize(kwargs['login-url']);
    if (!loginUrl) {
      throw new Error('login-url is required');
    }

    const args = [
      '--login-url', loginUrl,
      '--name', normalize(kwargs.name) || 'groq-openclaw',
      '--wait-seconds', String(Number(kwargs['wait-seconds'] ?? 120) || 120),
      '--poll-interval', String(Number(kwargs['poll-interval'] ?? 2) || 2),
      '-f', 'json',
    ];

    let stdout = '';
    try {
      stdout = execFileSync(SCRIPT, args, {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (err) {
      const stderr = String(err?.stderr || '').trim();
      const stdoutText = String(err?.stdout || '').trim();
      const detail = stderr || stdoutText || err.message;
      throw new Error(`groq create-api-key helper failed: ${detail}`);
    }

    const rows = parseJson(stdout);
    if (!Array.isArray(rows)) {
      throw new Error('groq create-api-key helper did not return an array');
    }
    return rows.map((row) => ({
      key_name: row.key_name || '',
      status: row.status || '',
      detail: row.detail || '',
      url: row.url || '',
    }));
  },
});
