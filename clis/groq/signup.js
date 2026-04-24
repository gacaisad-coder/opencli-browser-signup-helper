import { cli, Strategy } from '@jackwener/opencli/registry';
import { execFileSync } from 'node:child_process';

const SCRIPT = process.env.OPENCLI_GROQ_SIGNUP_SCRIPT || `${process.cwd()}/scripts/opencli-groq-signup.sh`;

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
  name: 'signup',
  description: 'Start Groq email signup/login with the proven browser type/click path',
  domain: 'console.groq.com',
  strategy: Strategy.LOCAL,
  browser: false,
  args: [
    { name: 'email', type: 'string', default: '', description: 'explicit email address; when set, ignores --email-domain/--name-mode/--prefix' },
    { name: 'email-domain', type: 'string', default: '', description: 'email domain used when generating a random address, e.g. example.com' },
    { name: 'name-mode', type: 'string', default: 'random', description: 'email local-part mode; currently only random is supported' },
    { name: 'prefix', type: 'string', default: 'groq', description: 'prefix used for generated random email local-part' },
    { name: 'url', type: 'string', default: 'https://console.groq.com/home', description: 'Groq entry URL' },
    { name: 'wait-seconds', type: 'int', default: 2, description: 'seconds to wait after submit before checking result' },
  ],
  columns: ['email', 'source', 'status', 'detail', 'url'],
  func: async (_page, kwargs) => {
    const args = ['-f', 'json'];

    const email = normalize(kwargs.email);
    if (email) {
      args.push('--email', email);
    } else {
      const emailDomain = normalize(kwargs['email-domain']);
      if (!emailDomain) {
        throw new Error('email-domain is required when --email is not provided');
      }
      args.push('--email-domain', emailDomain);
      args.push('--name-mode', normalize(kwargs['name-mode']) || 'random');
      args.push('--prefix', normalize(kwargs.prefix) || 'groq');
    }

    const url = normalize(kwargs.url);
    if (url) args.push('--url', url);

    const waitSeconds = Number(kwargs['wait-seconds'] ?? 2);
    if (Number.isFinite(waitSeconds) && waitSeconds > 0) {
      args.push('--wait-seconds', String(waitSeconds));
    }

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
      throw new Error(`groq signup helper failed: ${detail}`);
    }

    const rows = parseJson(stdout);
    if (!Array.isArray(rows)) {
      throw new Error('groq signup helper did not return an array');
    }
    return rows.map((row) => ({
      email: row.email || '',
      source: row.source || '',
      status: row.status || '',
      detail: row.detail || '',
      url: row.url || '',
    }));
  },
});
