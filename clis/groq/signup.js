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
  access: 'write',
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
    { name: 'session', type: 'string', default: 'groq-signup', description: 'opencli browser session name' },
  ],
  columns: ['email', 'source', 'status', 'detail', 'url'],
  func: async (kwargs) => {
    const args = ['-f', 'json'];

    const get = (kebab, fallback = '') => kwargs[kebab] ?? kwargs[kebab.replace(/-([a-z])/g, (_, c) => c.toUpperCase())] ?? fallback;

    const email = normalize(get('email'));
    if (email) {
      args.push('--email', email);
    } else {
      const emailDomain = normalize(get('email-domain'));
      if (!emailDomain) {
        throw new Error('email-domain is required when --email is not provided');
      }
      args.push('--email-domain', emailDomain);
      args.push('--name-mode', normalize(get('name-mode', 'random')) || 'random');
      args.push('--prefix', normalize(get('prefix', 'groq')) || 'groq');
    }

    const url = normalize(get('url'));
    if (url) args.push('--url', url);

    const waitSeconds = Number(get('wait-seconds', 2));
    if (Number.isFinite(waitSeconds) && waitSeconds > 0) {
      args.push('--wait-seconds', String(waitSeconds));
    }

    const session = normalize(get('session', 'groq-signup'));
    if (session) args.push('--session', session);

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
