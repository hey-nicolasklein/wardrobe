import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { OpenAICatalogProvider } from '../../packages/service/src/catalog-provider.ts';
import { characterSheetModel } from '../../packages/service/src/inspiration.ts';
import { characterPrompt, refinementPrompt, characterSheetPromptVersion, characterSheetRefinePromptVersion, fitPrompt, fitPromptVersion, boardFitPrompt } from './prompts.mjs';

import { makePhotoBoard } from './photo-board.mjs';

const port = Number(process.env.LIKENESS_LAB_PORT || 4319);
const origin = `http://127.0.0.1:${port}`;
const downloads = join(homedir(), 'Downloads');
const output = resolve('.prototype-data/likeness-lab');
await mkdir(output, { recursive: true });
const listPhotos = async () => {
  const names = await readdir(downloads);
  return names.filter(n => /\.(jpg|jpeg|png|heic)$/i.test(n) && !n.startsWith('form-look-') &&
    !(/\.heic$/i.test(n) && names.some(other => other.replace(/\.(jpg|jpeg|png)$/i, '').toLowerCase() === n.replace(/\.heic$/i, '').toLowerCase() && /\.(jpg|jpeg|png)$/i.test(other))));
};
const provider = new OpenAICatalogProvider(process.env.OPENAI_API_KEY || '', process.env.OPENAI_API_BASE_URL);
const runs = new Map();
for (const name of await readdir(output)) {
  if (!name.endsWith('.json')) continue;
  const run = JSON.parse(await readFile(join(output, name), 'utf8'));
  if (run.status === 'running') { run.status = 'failed'; run.error = 'Server stopped during this run. Check provider usage before retrying.'; }
  runs.set(run.id, run);
}
let wardrobe = [];
try { wardrobe = JSON.parse(await readFile(join(output, 'wardrobe/items.json'), 'utf8')); } catch {}
function chosenItems(ids) {
  if (!Array.isArray(ids) || !ids.length || ids.length > 3 || new Set(ids).size !== ids.length) throw Error('Choose 1–3 clothing items.');
  return ids.map(id => { const item = wardrobe.find(i => i.id === id); if (!item) throw Error('Unknown clothing item.'); return item; });
}
let busy = false;
const save = run => writeFile(join(output, `${run.id}.json`), JSON.stringify(run, null, 2));
async function body(req) {
  const chunks = []; let length = 0;
  for await (const chunk of req) { length += chunk.length; if (length > 40 * 1024 * 1024) throw Error('Request exceeds 40 MB.'); chunks.push(chunk); }
  return JSON.parse(Buffer.concat(chunks).toString());
}
async function generate(run, references) {
  try {
    run.step = 'provider'; await save(run);
    const result = await provider.generateComposite({ references, prompt: run.prompt, model: characterSheetModel, quality: run.quality, size: run.size, signal: AbortSignal.timeout(Number(process.env.OPENAI_REQUEST_TIMEOUT_MS || 180000)) });
    run.step = 'save'; await save(run);
    await writeFile(join(output, `${run.id}.png`), result.pngBytes);
    Object.assign(run, { status: 'ready', step: 'review', requestId: result.requestId, usage: result.usage, image: `/output/${run.id}.png` });
  } catch (e) { Object.assign(run, { status: 'failed', error: e.message, category: e.category || 'local', failedStep: run.step }); }
  finally { run.finishedAt = new Date().toISOString(); await save(run); busy = false; }
}
createServer(async (req, res) => {
  const send = (status, data, type = 'application/json') => { res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); res.end(type === 'application/json' ? JSON.stringify(data) : data); };
  try {
    if (req.headers.host !== `127.0.0.1:${port}` && req.headers.host !== `localhost:${port}`) return send(403, { error: 'Local access only.' });
    if (req.method === 'POST' && req.headers.origin !== origin && req.headers.origin !== `http://localhost:${port}`) return send(403, { error: 'Origin rejected.' });
    const url = new URL(req.url, origin);
    const files = await listPhotos();
    if (req.method === 'GET' && url.pathname === '/') return send(200, await readFile(new URL('./index.html', import.meta.url)), 'text/html');
    if (req.method === 'GET' && url.pathname === '/prepare.js') {
      const source = await readFile(new URL('../../apps/web/public/app.js', import.meta.url), 'utf8');
      const start = source.indexOf('async function preparePhoto(file) {');
      const end = source.indexOf('\nasync function uploadPhoto', start);
      if (start < 0 || end < 0) throw Error('Cannot locate production photo preparation.');
      return send(200, source.slice(start, end), 'text/javascript');
    }
    if (req.method === 'GET' && url.pathname === '/api/state') return send(200, { files, wardrobe, runs: [...runs.values()].reverse(), busy, configured: Boolean(process.env.OPENAI_API_KEY), model: characterSheetModel, version: characterSheetPromptVersion });
    if (req.method === 'POST' && url.pathname === '/api/board') {
      const data = await body(req);
      if (!Array.isArray(data.references) || data.references.length < 1 || data.references.length > 8) throw Error('Choose 1–8 reference photos.');
      const bytes = data.references.map(ref => { if (!files.includes(ref.name) || typeof ref.base64 !== 'string') throw Error('Unknown photo.'); return Buffer.from(ref.base64, 'base64'); });
      const board = await makePhotoBoard(bytes);
      return send(200, { image: `data:image/png;base64,${board.toString('base64')}` });
    }
    if (req.method === 'POST' && url.pathname === '/api/prompt') {
      const data = await body(req);
      if (data.mode === 'fit') return send(200, { prompt: (data.identityLayout === 'board' ? boardFitPrompt : fitPrompt)(Number(data.photoCount) || 1, chosenItems(data.clothingIds), data.scene, data.note) });
      return send(200, { prompt: data.parent ? refinementPrompt(data.note || null, data.instruction || 'Correct the facial likeness using the real photos.') : characterPrompt(data.note || null) });
    }
    if (req.method === 'GET' && url.pathname.startsWith('/photo/')) {
      const name = decodeURIComponent(url.pathname.slice(7));
      if (!files.includes(name)) return send(404, { error: 'Unknown photo.' });
      return send(200, await readFile(join(downloads, name)), /png$/i.test(name) ? 'image/png' : /heic$/i.test(name) ? 'image/heic' : 'image/jpeg');
    }
    if (req.method === 'GET' && /^\/wardrobe\/[a-f0-9-]+\.png$/.test(url.pathname)) return send(200, await readFile(join(output, 'wardrobe', url.pathname.slice(10))), 'image/png');
    if (req.method === 'GET' && /^\/output\/[a-f0-9-]+(?:\.png|-ref-\d+\.jpg|-garment-\d+\.png|-board\.png)$/.test(url.pathname)) return send(200, await readFile(join(output, url.pathname.slice(8))), url.pathname.endsWith('.jpg') ? 'image/jpeg' : 'image/png');
    if (req.method === 'POST' && url.pathname === '/api/review') {
      const data = await body(req); const run = runs.get(data.id);
      if (!run || typeof data.review !== 'string' || data.review.length > 10000) return send(400, { error: 'Invalid review.' });
      run.review = data.review; await save(run); return send(200, run);
    }
    if (req.method === 'POST' && url.pathname === '/api/run') {
      if (busy) return send(409, { error: 'A generation is already running.' });
      if (!process.env.OPENAI_API_KEY) return send(400, { error: 'OPENAI_API_KEY is missing from the worker environment.' });
      const data = await body(req);
      const fit = data.mode === 'fit';
      const boardMode = fit && data.identityLayout === 'board';
      const clothing = fit ? chosenItems(data.clothingIds) : [];
      if (fit && data.parent) throw Error('Fit photos use original identity photos, not a parent sheet.');
      const parent = data.parent ? runs.get(data.parent) : null;
      if (data.parent && parent?.status !== 'ready') throw Error('Choose a completed parent sheet.');
      if (!Array.isArray(data.references) || data.references.length < 1 || data.references.length > (boardMode ? 8 : parent ? 3 : 4)) throw Error(boardMode ? 'Choose 1–8 photos for the board.' : 'Choose 1–4 photos, or 1–3 for refinement.');
      if (fit && (boardMode ? 1 : data.references.length) + clothing.length > 4) throw Error('Use at most four images total: identity photos plus clothing.');
      if (typeof data.prompt !== 'string' || !data.prompt.trim() || data.prompt.length > 15000) throw Error('A prompt of at most 15000 characters is required.');
      const references = [];
      if (parent) references.push(await readFile(join(output, `${parent.id}.png`)));
      const id = randomUUID();
      const evidence = [];
      for (const [i, ref] of data.references.entries()) {
        if (!files.includes(ref.name) || typeof ref.base64 !== 'string') throw Error('Unknown reference.');
        const bytes = Buffer.from(ref.base64, 'base64');
        if (bytes[0] !== 255 || bytes[1] !== 216 || bytes.length > 10 * 1024 * 1024) throw Error('Prepared reference must be a JPEG under 10 MB.');
        references.push(bytes);
        const name = `${id}-ref-${i}.jpg`;
        // Persist the exact model inputs once validation is complete.
        evidence.push({ name: ref.name, preparedFile: name, bytes: bytes.length, width: ref.width, height: ref.height, crop: ref.crop || null });
      }
      const originalReferences = [...references];
      const board = boardMode ? await makePhotoBoard(references) : null;
      if (board) references.splice(0, references.length, board);
      const identityCount = references.length;
      for (const item of clothing) references.push(await readFile(join(output, 'wardrobe', `${item.id}.png`)));
      const baseline = fit ? (boardMode ? boardFitPrompt : fitPrompt)(data.references.length, clothing, data.scene, data.note) : parent ? refinementPrompt(data.note || null, data.instruction || 'Correct the facial likeness using the real photos.') : characterPrompt(data.note || null);
      const run = { id, mode: fit ? 'fit' : 'sheet', identityLayout: boardMode ? 'board' : 'separate', board: boardMode ? `/output/${id}-board.png` : null, clothing: clothing.map((item, i) => ({...item, image: `/output/${id}-garment-${i}.png`})), scene: data.scene || '', label: String(data.label || 'Untitled comparison').slice(0, 100), createdAt: new Date().toISOString(), status: 'running', step: 'prepared', parent: parent?.id || null, prompt: data.prompt, baseline, variant: data.prompt !== baseline, note: data.note, instruction: data.instruction, model: characterSheetModel, quality: fit ? 'medium' : 'high', size: fit ? '1024x1280' : '864x1536', version: fit ? (boardMode ? 'photo-board-fit-v1' : fitPromptVersion) : parent ? characterSheetRefinePromptVersion : characterSheetPromptVersion, references: evidence };
      if (busy) return send(409, { error: 'A generation is already running.' });
      busy = true;
      try {
        for (const [i, ref] of evidence.entries()) await writeFile(join(output, ref.preparedFile), originalReferences[i + (parent ? 1 : 0)]);
        for (const [i] of clothing.entries()) await writeFile(join(output, `${id}-garment-${i}.png`), references[identityCount + i]);
        if (board) await writeFile(join(output, `${id}-board.png`), board);
        await save(run); runs.set(id, run); void generate(run, references);
      } catch (error) { busy = false; throw error; }
      return send(202, run);
    }
    send(404, { error: 'Not found.' });
  } catch (e) { send(400, { error: e.message }); }
}).listen(port, '127.0.0.1', () => console.log(`Likeness lab: ${origin}`));
