import { cli, Strategy } from '@jackwener/opencli/registry';
import { execFileSync } from 'node:child_process';

const SCRIPT = process.env.OPENCLI_GROQ_LOGOUT_SCRIPT || `${process.cwd()}/scripts/opencli-groq-logout.sh`;

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
  name: 'logout',
  description: 'Log out the currently authenticated Groq browser session',
  domain: 'console.groq.com',
  strategy: Strategy.LOCAL,
  browser: false,
  args: [
    { name: 'url', type: 'string', default: 'https://console.groq.com/home', description: 'Groq entry URL' },
  ],
  columns: ['status', 'detail', 'url'],
  func: async (_page, kwargs) => {
    const args = ['-f', 'json'];

    const url = normalize(kwargs.url);
    if (url) args.push('--url', url);

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
      throw new Error(`groq logout helper failed: ${detail}`);
    }

    const rows = parseJson(stdout);
    if (!Array.isArray(rows)) {
      throw new Error('groq logout helper did not return an array');
    }
    return rows.map((row) => ({
      status: row.status || '',
      detail: row.detail || '',
      url: row.url || '',
    }));
  },
});
