/** Single seam between this POC and the authenticated Codex CLI. */
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

const CODEX_BIN = process.env.CODEX_BIN ?? 'codex';

export async function runCodex(prompt: string, images: string[], cwd: string): Promise<string> {
  const scratch = await mkdtemp(path.join(tmpdir(), 'form-codex-'));
  const lastMessage = path.join(scratch, 'last-message.txt');
  const args = ['exec', '--json', '--skip-git-repo-check'];
  if (images.length) args.push('-i', images.join(','));
  args.push('-C', cwd, '-s', 'workspace-write', '-o', lastMessage, '-');

  const child = spawn(CODEX_BIN, args, { stdio: ['pipe', 'ignore', 'pipe'], env: process.env });
  child.stdin.end(prompt);
  let stderr = '';
  child.stderr.on('data', (chunk: Buffer) => {
    stderr = (stderr + chunk.toString('utf8')).slice(-20_000);
  });

  const code = await new Promise<number>((resolve, reject) => {
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error('Codex image generation timed out'));
    }, 15 * 60 * 1000);
    child.on('error', reject);
    child.on('close', (value) => {
      clearTimeout(timer);
      resolve(value ?? 1);
    });
  });

  const message = await readFile(lastMessage, 'utf8').catch(() => '');
  await rm(scratch, { recursive: true, force: true });
  if (code !== 0) throw new Error(stderr.trim().split('\n').slice(-6).join('\n') || `Codex exited with ${code}`);
  return message.trim();
}
