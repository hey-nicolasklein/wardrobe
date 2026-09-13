const $ = (s, root = document) => root.querySelector(s);
const esc = (value) =>
  String(value ?? '').replace(
    /[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c],
  );
const categories = {
  top: 'Oberteile',
  jacket: 'Jacken',
  pants: 'Hosen',
  skirt: 'Röcke',
  dress: 'Kleider',
  shoes: 'Schuhe',
  bag: 'Taschen',
  hat: 'Mützen & Hüte',
  scarf: 'Schals',
};
const icons = {
  closet: '<path d="M4 3h16v18H4zM12 3v18M9 11v2m6-2v2"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  heart:
    '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>',
  settings:
    '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  camera: '<path d="M3 7h4l2-3h6l2 3h4v14H3z"/><circle cx="12" cy="13" r="4"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
  arrow: '<path d="m14 6-6 6 6 6"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  top: '<path d="m8 4 4 3 4-3 4 4-3 3v9H7v-9L4 8z"/>',
  bottom: '<path d="M7 4h10l-1 16h-3l-1-8-1 8H8z"/>',
  shoes: '<path d="M4 15h7l3-5 2 4 4 2v4H4z"/>',
  accessory: '<path d="M6 8h12v12H6zM9 8V6a3 3 0 0 1 6 0v2"/>',
  photo:
    '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',
  feed: '<path d="M4 5h16v14H4z"/><path d="m4 15 4-4 3 3 3-4 6 6"/><circle cx="16" cy="9" r="1"/>',
  more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
};
const icon = (name) =>
  `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.closet}</svg>`;
const imageGenerationProgress = (name) =>
  `<div class="wardrobe-image-progress" role="status" aria-label="Katalogbild für ${esc(name)} wird erstellt"><span class="image-generation-loader" aria-hidden="true">${Array.from({ length: 9 }, (_, index) => `<i style="--tile:${index}"></i>`).join('')}</span><span>Bild wird erstellt</span></div>`;
const detectionCategoryTheme = (category) =>
  ['top', 'jacket', 'dress'].includes(category)
    ? 'top'
    : ['pants', 'skirt'].includes(category)
      ? 'bottom'
      : category === 'shoes'
        ? 'shoes'
        : 'accessory';
const detectionCategoryIcon = (category) => detectionCategoryTheme(category);
let items = [],
  looks = [],
  characterSheets = [],
  page = 'feed',
  stateFilter = 'all',
  category = 'all',
  query = '',
  detailId = null,
  importBusy = false,
  version = '',
  toastTimer;
const detectionPolls = new Set();
let drafts;
try {
  drafts = JSON.parse(localStorage.getItem('form-photo-drafts') || '[]');
} catch {
  drafts = [];
}
drafts = drafts.map((draft) => {
  if (draft.phase === 'importing')
    return { ...draft, phase: draft.detections ? 'ready' : 'manual' };
  if (draft.phase) return draft;
  if (draft.detectionProposalId) {
    return {
      ...draft,
      phase: 'ready',
      detections: [
        {
          id: draft.detectionProposalId,
          ...draft.metadata,
          boundingBox: { x: 0, y: 0, width: 1000, height: 1000 },
          selected: true,
          itemKey: draft.id,
          generationKey: null,
        },
      ],
    };
  }
  return { ...draft, phase: draft.detecting ? 'detecting' : 'uploaded' };
});
const persistDrafts = () =>
  localStorage.setItem(
    'form-photo-drafts',
    JSON.stringify(
      drafts
        .filter((draft) => draft.phase !== 'uploading')
        .map(({ localPreviewUrl: _localPreviewUrl, ...draft }) => draft),
    ),
  );
const revokeDraftPreview = (draft) => {
  if (draft.localPreviewUrl) URL.revokeObjectURL(draft.localPreviewUrl);
};
const preview = (item) =>
  `/v1/wardrobe-items/${encodeURIComponent(item.id)}/preview?v=${item.recordVersion}`;
// The full, uncropped source photo the piece was created from. Returns 404 once
// the original upload has been cleared, so consumers hide the image on error.
const sourcePreview = (item) => `${preview(item)}&variant=source`;
const key = () => {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};
const money = (micros) =>
  new Intl.NumberFormat('de-DE', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 3,
    maximumFractionDigits: 3,
  }).format(micros / 1e6);
// Images carrying `.fade` start transparent and fade in once they have pixels.
// Anything already in the browser cache reports `complete` synchronously and
// skips the transition, so a re-render never flashes a picture back in.
function wireFades(root) {
  root.querySelectorAll('img.fade:not(.loaded)').forEach((img) => {
    if (img.complete && img.naturalWidth) return img.classList.add('loaded');
    const show = () => img.classList.add('loaded');
    img.addEventListener('load', show, { once: true });
    img.addEventListener('error', show, { once: true });
  });
}
// Fades out the edge of a horizontally scrolling row that has more content
// behind it. The mask only softens the side you can still scroll towards, so a
// row that already fits stays crisp on both ends.
function wireScrollFade(row) {
  if (!row || row.classList.contains('scroll-fade')) return;
  row.classList.add('scroll-fade');
  const update = () => {
    row.classList.toggle('at-start', row.scrollLeft <= 1);
    row.classList.toggle('at-end', row.scrollLeft >= row.scrollWidth - row.clientWidth - 1);
  };
  row.addEventListener('scroll', update, { passive: true });
  // Tiles can still be sizing up when this runs, and the row is collected
  // together with its observer once the sheet or the page is replaced.
  new ResizeObserver(update).observe(row);
  update();
}
function toast(message) {
  const el = $('#toast');
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 4000);
}
async function api(path, body, method = 'POST') {
  let response;
  try {
    response = await fetch(`/v1${path}`, {
      method: body === undefined ? 'GET' : method,
      credentials: 'same-origin',
      headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new Error(
      'Keine Verbindung zu stargate. Prüfe WLAN oder Tailscale und versuche es erneut.',
    );
  }
  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (!response.ok)
    throw new Error(data?.error?.message || `Die Anfrage ist fehlgeschlagen (${response.status}).`);
  return data;
}
function formError(form, error) {
  let el = $('.error', form);
  if (!el) {
    el = document.createElement('p');
    el.className = 'error';
    el.setAttribute('role', 'alert');
    form.append(el);
  }
  el.textContent = error.message;
}
async function action(button, operation) {
  if (button.disabled) return;
  button.disabled = true;
  try {
    await operation();
  } catch (error) {
    toast(error.message);
  } finally {
    button.disabled = false;
  }
}
function shell(content) {
  $('#app').innerHTML =
    `<main class="shell"><header class="masthead"><span class="wordmark">FORM</span><span class="private"><span class="dot"></span> <span id="version">${esc(version)}</span></span></header>${!navigator.onLine ? '<p class="offline">Du bist offline. Verbinde dich mit stargate, um deinen Kleiderschrank zu öffnen.</p>' : ''}${content}</main><nav class="nav" aria-label="Hauptnavigation">${[
      ['feed', 'feed', 'Feed'],
      ['wardrobe', 'closet', 'Schrank'],
      ['settings', 'settings', 'Settings'],
    ]
      .map(
        ([id, i, label]) =>
          `<button data-nav="${id}" class="${page === id || (page === 'archived' && id === 'settings') ? 'active' : ''}" ${page === id ? 'aria-current="page"' : ''}>${icon(i)}<span>${label}</span></button>`,
      )
      .join('')}</nav>`;
  document
    .querySelectorAll('[data-nav]')
    .forEach((b) => (b.onclick = () => navigate(b.dataset.nav)));
}
function navigate(next) {
  page = next;
  category = 'all';
  query = '';
  location.hash = next;
  render();
  window.scrollTo(0, 0);
}
function render() {
  if (page === 'add') return renderAdd();
  if (page === 'settings') return renderSettings();
  if (page === 'feed') return renderFeed();
  renderWardrobe();
}
// Each collection keeps its results container alive while it is off screen, so
// coming back to a tab re-attaches images the browser has already decoded
// instead of building fresh <img> nodes for them.
const resultsByPage = new Map();
function renderWardrobe() {
  const archived = page === 'archived';
  const collection = items.filter((i) =>
    archived ? i.state === 'archived' : i.state !== 'archived',
  );
  shell(`<div class="hero"><div><p class="eyebrow">${archived ? 'Dein Archiv' : 'Weniger suchen. Lieber tragen.'}</p><h1>${archived ? 'Gut aufgehoben.' : 'Dein Schrank.'}</h1><p class="muted">${collection.length} ${collection.length === 1 ? 'Stück' : 'Stücke'} gesammelt.</p></div>${archived ? '' : `<button class="round" id="add" aria-label="Kleidung hinzufügen">${icon('plus')}</button>`}</div>
  <div class="search">${icon('search')}<input type="search" id="search" aria-label="Kleiderschrank durchsuchen" placeholder="Finde dein Lieblingsstück" value="${esc(query)}"></div>
  ${
    archived
      ? ''
      : `<div class="filters" aria-label="Status">${[
          ['all', 'Alle'],
          ['owning', 'Besitze ich'],
          ['wanting', 'Wünsche ich mir'],
        ]
          .map(
            ([value, label]) =>
              `<button class="chip ${stateFilter === value ? 'active' : ''}" data-state="${value}" aria-pressed="${stateFilter === value}">${label}</button>`,
          )
          .join('')}</div>`
  }<div class="filters" aria-label="Kategorien">${[['all', 'Alle'], ...Object.entries(categories).filter(([c]) => collection.some((i) => i.metadata.category === c))].map(([c, label]) => `<button class="chip ${category === c ? 'active' : ''}" data-cat="${c}" aria-pressed="${category === c}">${label}</button>`).join('')}</div><div id="results"></div>`);
  if ($('#add')) $('#add').onclick = () => navigate('add');
  document.querySelectorAll('[data-state]').forEach(
    (b) =>
      (b.onclick = () => {
        stateFilter = b.dataset.state;
        renderWardrobe();
      }),
  );
  $('#search').oninput = (e) => {
    query = e.target.value;
    applyFilter();
  };
  document.querySelectorAll('[data-cat]').forEach(
    (b) =>
      (b.onclick = () => {
        category = b.dataset.cat;
        document.querySelectorAll('[data-cat]').forEach((c) => {
          c.classList.toggle('active', c.dataset.cat === category);
          c.setAttribute('aria-pressed', String(c.dataset.cat === category));
        });
        applyFilter();
      }),
  );
  wireScrollFade($('.filters'));
  const cached = resultsByPage.get(page);
  if (cached) $('#results').replaceWith(cached);
  else resultsByPage.set(page, $('#results'));
  renderResults();
}
function renderItemPhoto(item) {
  if (['queued', 'generating'].includes(item.status))
    return `<div class="photo">${imageGenerationProgress(item.metadata.name)}</div>`;
  return `<div class="photo"><img class="fade" src="${preview(item)}" alt="${esc(item.metadata.name)}" loading="lazy" decoding="async"><img class="photo-source" data-source="${sourcePreview(item)}" alt="" aria-hidden="true" loading="lazy" decoding="async">${item.status === 'failed' ? '<span class="badge">Bild fehlgeschlagen</span>' : ''}</div>`;
}
// Everything a tile renders. A tile is rebuilt only when this changes, so
// polling and re-renders leave untouched pieces exactly as they are.
const tileSignature = (item) =>
  `${item.recordVersion}:${item.status}:${item.metadata.name}:${item.metadata.category}:${item.metadata.colors.join(',')}`;
// A stable tint per piece, derived from its id so it never moves when the grid
// is filtered or reordered.
const tint = (id) => {
  let sum = 0;
  for (const character of id) sum = (sum + character.charCodeAt(0)) % 3;
  return sum;
};
function buildTile(item) {
  const tile = document.createElement('button');
  tile.className = `item tint-${tint(item.id)}`;
  tile.dataset.item = item.id;
  tile.dataset.signature = tileSignature(item);
  tile.innerHTML = `${renderItemPhoto(item)}<span class="item-name">${esc(item.metadata.name)}</span><span class="item-category">${categories[item.metadata.category]} · ${esc(item.metadata.colors.join(', '))}</span>`;
  tile.onclick = () => openDetail(item.id);
  wireFades(tile);
  // Fade to the original upload on hover. Load it only on first hover to keep
  // the grid light, and drop the layer if the source photo is gone.
  const source = $('.photo-source', tile);
  if (source) {
    source.onerror = () => source.remove();
    tile.addEventListener(
      'mouseenter',
      () => {
        if (!source.src) source.src = source.dataset.source;
      },
      { once: true },
    );
  }
  return tile;
}
const matchesFilter = (item) =>
  (page === 'archived' || stateFilter === 'all' || item.state === stateFilter) &&
  (category === 'all' || item.metadata.category === category) &&
  `${item.metadata.name} ${item.metadata.colors.join(' ')} ${item.metadata.notes || ''} ${categories[item.metadata.category]}`
    .toLocaleLowerCase()
    .includes(query.toLocaleLowerCase());
// Reconciles the grid against the current collection, reusing the tile nodes it
// already has. Filtering never comes through here: it only toggles visibility,
// so a chip tap costs no image loading at all.
function renderResults() {
  const container = $('#results');
  if (!container) return;
  if (!$('.grid', container))
    container.innerHTML = `<div class="section-row"><span id="result-count"></span><span>Zuletzt hinzugefügt</span></div><div class="grid"></div><div class="empty" id="no-results" hidden></div>`;
  const grid = $('.grid', container);
  const existing = new Map([...grid.children].map((node) => [node.dataset.item, node]));
  const tiles = items
    .filter((i) => (page === 'archived' ? i.state === 'archived' : i.state !== 'archived'))
    .map((item) => {
      const node = existing.get(item.id);
      return node?.dataset.signature === tileSignature(item) ? node : buildTile(item);
    });
  grid.replaceChildren(...tiles);
  applyFilter();
}
function applyFilter() {
  const container = $('#results');
  const grid = container && $('.grid', container);
  const empty = container && $('#no-results', container);
  if (!grid || !empty) return;
  const byId = new Map(items.map((item) => [item.id, item]));
  let visible = 0;
  for (const tile of grid.children) {
    const item = byId.get(tile.dataset.item);
    const show = Boolean(item) && matchesFilter(item);
    tile.hidden = !show;
    if (show) visible++;
  }
  $('#result-count', container).textContent = `${visible} ${visible === 1 ? 'Stück' : 'Stücke'}`;
  $('.section-row', container).hidden = !visible;
  grid.hidden = !visible;
  empty.hidden = Boolean(visible);
  if (visible) return;
  const narrowed = Boolean(query) || category !== 'all';
  empty.innerHTML = `${icon('closet')}<h2>${narrowed ? 'Noch nicht gefunden.' : 'Platz für deine Stücke.'}</h2><p>${narrowed ? 'Versuche einen anderen Suchbegriff oder eine andere Kategorie.' : 'Fang mit ein paar Lieblingsstücken an. Ein Foto reicht, den Rest kannst du später ergänzen.'}</p>${narrowed ? '' : '<button class="primary" id="empty-add">Erstes Stück hinzufügen</button>'}`;
  if ($('#empty-add')) $('#empty-add').onclick = () => navigate('add');
}
async function refreshItems() {
  const data = await api('/wardrobe-items');
  items = data.wardrobeItems.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}
async function refreshInspiration() {
  const [lookData, sheetData] = await Promise.all([api('/looks'), api('/character-sheets')]);
  looks = lookData.looks;
  characterSheets = sheetData.characterSheets;
}
function renderFeed() {
  const activeSheet = characterSheets.find((sheet) => sheet.active && sheet.state === 'ready');
  shell(
    `<div class="hero"><div><p class="eyebrow">Deine Garderobe, in Bewegung</p><h1>Für heute.</h1><p class="muted">Neue Kombinationen aus deinen Stücken.</p></div><button class="round" id="add-look" aria-label="Look erstellen">${icon('plus')}</button></div><div class="look-feed" id="look-feed">${looks.length ? '' : `<div class="empty">${icon('feed')}<h2>Noch keine Looks.</h2><p>${activeSheet ? 'Lass FORM dein erstes Outfit zusammenstellen.' : 'Erstelle zuerst dein Character Sheet, damit Looks wirklich nach dir aussehen.'}</p><button class="primary" id="first-look">${activeSheet ? 'Ersten Look erstellen' : 'Character Sheet einrichten'}</button></div>`}</div>`,
  );
  if (looks.length) renderLookCards();
  $('#add-look').onclick = () => (activeSheet ? openLookComposer() : openCharacterSetup());
  if ($('#first-look'))
    $('#first-look').onclick = () => (activeSheet ? openLookComposer() : openCharacterSetup());
  wireLookCards();
}
// Keep complete cards, including their decoded images, while another page is
// open. A card is replaced only when its server representation changes.
const feedCards = new Map();
const lookCardSignature = (look) => JSON.stringify(look);
function renderLookCards() {
  const currentIds = new Set(looks.map((look) => look.id));
  for (const id of feedCards.keys()) if (!currentIds.has(id)) feedCards.delete(id);
  const cards = looks.map((look) => {
    const signature = lookCardSignature(look);
    const cached = feedCards.get(look.id);
    if (cached?.signature === signature) return cached.card;
    const template = document.createElement('template');
    template.innerHTML = renderLookCard(look);
    const card = template.content.firstElementChild;
    feedCards.set(look.id, { card, signature });
    return card;
  });
  $('#look-feed').replaceChildren(...cards);
}
/* Plätze am Körper der Person, als Prozent von der Bildmitte aus: x zählt gegen
   die Breite der Karte, y gegen ihre Höhe. Die Mitte bleibt frei, damit die
   Person zwischen ihren Stücken stehen bleibt. */
const lookAnchors = {
  chestLeft: [-27, -23],
  chestRight: [27, -23],
  waistLeft: [-33, 2],
  waistRight: [33, 2],
  legsRight: [27, 22],
  legsLeft: [-27, 22],
  head: [0, -40],
  feet: [0, 41],
};
/* Wunschplätze je Kategorie, vom besten zum nächstbesten. Die Reihenfolge der
   Vergabe entscheidet bei Streit, deshalb steht sie fest: von Kopf bis Fuß. */
const lookAnchorWishes = {
  hat: ['head', 'chestRight', 'chestLeft'],
  top: ['chestLeft', 'chestRight', 'waistLeft'],
  dress: ['chestLeft', 'chestRight', 'legsLeft'],
  jacket: ['chestRight', 'waistRight', 'chestLeft'],
  scarf: ['waistLeft', 'head', 'chestLeft'],
  pants: ['legsRight', 'legsLeft', 'waistRight'],
  skirt: ['legsRight', 'legsLeft', 'waistRight'],
  bag: ['waistRight', 'legsRight', 'waistLeft'],
  shoes: ['feet', 'legsLeft', 'legsRight'],
};
const lookPlacementOrder = Object.keys(lookAnchorWishes);
/* Verteilt die Stücke eines Looks um die Person. Jede Kategorie bekommt ihren
   Platz am Körper, ohne Oberteil rückt die Jacke auf dessen Stelle. Sind mehr
   Stücke da als Anker, landet der Rest auf einem weiten Ring – das kommt bei
   einem Outfit praktisch nicht vor, soll aber nicht stapeln.
   `--item-order` treibt den Versatz, die Stücke erscheinen also von oben nach
   unten. Viele Stücke werden kleiner, sonst überlappen die Nachbarplätze. */
function lookItemPositions(categories) {
  const free = new Set(Object.keys(lookAnchors));
  const wishesFor = (category) =>
    category === 'jacket' && !categories.includes('top')
      ? ['chestLeft', ...lookAnchorWishes.jacket]
      : lookAnchorWishes[category] || [];
  const size = categories.length > 6 ? 25 : categories.length > 4 ? 30 : 36;
  const styles = [];
  [...categories.keys()]
    .sort(
      (a, b) =>
        lookPlacementOrder.indexOf(categories[a]) - lookPlacementOrder.indexOf(categories[b]),
    )
    .forEach((index, rank) => {
      const anchor = wishesFor(categories[index]).find((name) => free.has(name)) || [...free][0];
      free.delete(anchor);
      const angle = (rank / categories.length) * Math.PI * 2;
      const [x, y] = lookAnchors[anchor] || [Math.cos(angle) * 38, Math.sin(angle) * 30];
      styles[index] =
        `--item-x:${x.toFixed(2)}%;--item-y:${y.toFixed(2)}%;--item-size:${size}%;--item-order:${rank};--item-count:${categories.length};`;
    });
  return styles;
}
function renderLookCard(look) {
  if (look.state === 'failed')
    return `<article class="look-card failed-look" data-look="${look.id}"><div><h2>Das Bild ist nicht entstanden.</h2><p>Der Versuch bleibt hier sichtbar. Du kannst ihn erneut starten.</p></div><button class="primary" data-retry-look="${look.id}">Erneut versuchen</button><button class="text-button" data-delete-look="${look.id}">Löschen …</button></article>`;
  if (look.state !== 'ready')
    return `<article class="look-card developing" data-look="${look.id}" role="status"><span class="spinner"></span><div><h2>Dein Look entwickelt sich.</h2><p>Du kannst FORM währenddessen weiter benutzen.</p></div></article>`;
  // Stücke, die der Schrank nicht (mehr) kennt, gelten als Oberteil: sie
  // bekommen so einen Platz am Körper statt in der Mitte zu landen.
  const worn = look.wardrobeItemIds.map(
    (id) => items.find((entry) => entry.id === id) || { id, recordVersion: 0 },
  );
  const positions = lookItemPositions(worn.map((item) => item.metadata?.category || 'top'));
  return `<article class="look-card ready-look" data-look="${look.id}"><button class="look-photo" data-toggle-look="${look.id}" aria-label="Getragene Stücke anzeigen" aria-pressed="false"><img class="fade" data-asset="${look.assetId}" alt="Generierter persönlicher Look" loading="lazy" decoding="async"></button><button class="look-more" data-look-menu="${look.id}" aria-label="Aktionen für Look">${icon('more')}</button><div class="look-items" data-look-items="${look.id}" hidden>${worn
    .map((item, index) => {
      const name = item.metadata?.name || 'Kleidungsstück';
      return `<button data-look-item="${item.id}" aria-label="${esc(name)} öffnen" style="${positions[index]}"><img src="${preview(item)}" alt="${esc(name)}"></button>`;
    })
    .join('')}</div></article>`;
}
/* Opens or closes the item overlay of a look card. The overlay stays in the DOM
   while the pieces fly back into the middle, so it is only hidden once the
   staggered exit has finished — otherwise invisible buttons would still be
   tappable. */
function toggleLookReveal(card, open) {
  const overlay = $('[data-look-items]', card);
  const toggle = $('[data-toggle-look]', card);
  clearTimeout(overlay.hideTimer);
  if (open) {
    overlay.hidden = false;
    // Erzwingt ein Layout, damit der Browser den zusammengeklappten Startzustand
    // kennt. Ohne das springen die Stücke ohne Übergang an ihren Platz.
    void overlay.offsetWidth;
  }
  card.classList.toggle('revealed', open);
  if (!open)
    overlay.hideTimer = setTimeout(() => {
      overlay.hidden = true;
    }, lookRevealDuration(overlay));
  toggle.setAttribute('aria-pressed', String(open));
  toggle.setAttribute(
    'aria-label',
    open ? 'Getragene Stücke ausblenden' : 'Getragene Stücke anzeigen',
  );
}
/* Total time the exit takes: the last item's stagger plus its own transition. */
function lookRevealDuration(overlay) {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return 0;
  return 340 + Math.max(overlay.children.length - 1, 0) * 45;
}
function wireLookCards() {
  document.querySelectorAll('.look-card img[data-asset]').forEach((img) => {
    if (!img.src) img.src = assetUrl(img.dataset.asset);
  });
  // Runs after the sources are set, so a look already in the cache reports
  // `complete` here and appears without a transition.
  wireFades($('#look-feed'));
  document.querySelectorAll('[data-toggle-look]').forEach(
    (button) =>
      (button.onclick = (event) => {
        event.stopPropagation();
        const card = button.closest('.look-card');
        toggleLookReveal(card, !card.classList.contains('revealed'));
      }),
  );
  document.querySelectorAll('[data-look-item]').forEach(
    (button) =>
      (button.onclick = (event) => {
        event.stopPropagation();
        openDetail(button.dataset.lookItem);
      }),
  );
  document.querySelectorAll('[data-retry-look]').forEach(
    (button) =>
      (button.onclick = () =>
        action(button, async () => {
          await api(`/looks/${button.dataset.retryLook}/retry`, {
            idempotencyKey: key(),
          });
          await refreshInspiration();
          renderFeed();
        })),
  );
  document
    .querySelectorAll('[data-delete-look]')
    .forEach((button) => (button.onclick = () => confirmDeleteLook(button.dataset.deleteLook)));
  document
    .querySelectorAll('[data-look-menu]')
    .forEach((button) => (button.onclick = () => openLookMenu(button.dataset.lookMenu)));
  document.querySelectorAll('.ready-look').forEach(
    (card) =>
      (card.onclick = (event) => {
        if (event.target === card && card.classList.contains('revealed'))
          toggleLookReveal(card, false);
      }),
  );
}
function openLookComposer(preselected = []) {
  const idempotencyKey = key();
  const eligible = items.filter(
    (item) => item.state !== 'archived' && item.currentShelfImageVersionId,
  );
  showSheet(
    'Look erstellen',
    `<h2>Was möchtest du tragen?</h2><p class="muted">Leer lassen für eine komplett geplante Überraschung. Stücke und Kategorien lassen sich kombinieren.</p><form id="look-composer"><fieldset><legend>Bestimmte Stücke</legend><div class="composer-items">${eligible.map((item) => `<label class="select-item"><input type="checkbox" name="item" value="${item.id}" ${preselected.includes(item.id) ? 'checked' : ''}><img src="${preview(item)}" alt=""><span>${esc(item.metadata.name)}</span></label>`).join('')}</div></fieldset><fieldset><legend>Kategorien</legend><div class="composer-categories">${Object.entries(
      categories,
    )
      .map(
        ([value, label]) =>
          `<label><input type="checkbox" name="category" value="${value}"> ${label}</label>`,
      )
      .join(
        '',
      )}</div></fieldset><button class="primary" type="submit">Überrasch mich</button></form>`,
  );
  $('#look-composer').onsubmit = (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    action($('button[type=submit]', form), async () => {
      const data = new FormData(form);
      const created = await api('/looks', {
        exactItemIds: data.getAll('item'),
        categories: data.getAll('category'),
        parentLookId: null,
        idempotencyKey,
      });
      await refreshInspiration();
      closeSheet();
      navigate('feed');
      requestAnimationFrame(() =>
        document
          .querySelector(`[data-look="${created.lookId}"]`)
          ?.scrollIntoView({ behavior: 'smooth', block: 'center' }),
      );
    });
  };
}
function openLookMenu(id) {
  const look = looks.find((entry) => entry.id === id);
  if (!look) return;
  showSheet(
    'Look',
    `<h2>Was möchtest du tun?</h2><div class="stack"><button class="secondary" id="vary-look">Variation erstellen</button><button class="secondary" id="look-details">Details ansehen</button><button class="secondary" id="download-look">Bild laden</button><button class="danger" id="remove-look">Look löschen …</button></div>`,
  );
  $('#vary-look').onclick = (event) =>
    action(event.currentTarget, async () => {
      await api('/looks', {
        exactItemIds: [],
        categories: [],
        parentLookId: id,
        idempotencyKey: key(),
      });
      await refreshInspiration();
      closeSheet();
      navigate('feed');
    });
  $('#look-details').onclick = () =>
    showSheet(
      'Look Details',
      `<dl class="facts"><div><dt>Konzept</dt><dd>${esc(look.concept ? `${look.concept.activity}, ${look.concept.scene}` : '–')}</dd></div><div><dt>Erstellt</dt><dd>${new Date(look.createdAt).toLocaleString('de-DE')}</dd></div><div><dt>Modell</dt><dd>${esc(look.model)} · ${look.quality} · ${look.size}</dd></div><div><dt>Character Sheet</dt><dd>${esc(look.characterSheetId)}</dd></div><div><dt>Stücke</dt><dd>${look.wardrobeItemIds.map((id) => esc(items.find((i) => i.id === id)?.metadata.name || id)).join(', ')}</dd></div></dl>`,
    );
  $('#download-look').onclick = () => {
    const anchor = document.createElement('a');
    anchor.href = assetUrl(look.assetId);
    anchor.download = `form-look-${look.id}.png`;
    anchor.click();
  };
  $('#remove-look').onclick = () => confirmDeleteLook(id);
}
function confirmDeleteLook(id) {
  showSheet(
    'Look löschen',
    `<h2>Wirklich dauerhaft löschen?</h2><p>Das Bild verschwindet aus deinem Feed. Bereits entstandene Kosten bleiben in der Statistik.</p><button class="danger" id="confirm-look-delete">Dauerhaft löschen</button><button class="text-button" id="cancel-look-delete">Abbrechen</button>`,
  );
  $('#cancel-look-delete').onclick = closeSheet;
  $('#confirm-look-delete').onclick = (event) =>
    action(event.currentTarget, async () => {
      await api(`/looks/${id}`, {}, 'DELETE');
      await refreshInspiration();
      closeSheet();
      renderFeed();
    });
}
function fields(
  metadata = { name: '', category: 'top', colors: [], notes: null },
  state = 'owning',
) {
  return `<label>Name<input name="name" required maxlength="80" value="${esc(metadata.name)}" placeholder="Zum Beispiel: Grünes Leinenhemd"></label><div class="inline"><label>Kategorie<select name="category">${Object.entries(
    categories,
  )
    .map(
      ([c, label]) =>
        `<option value="${c}" ${c === metadata.category ? 'selected' : ''}>${label}</option>`,
    )
    .join(
      '',
    )}</select></label><label>Gehört in<select name="state"><option value="owning" ${state === 'owning' ? 'selected' : ''}>Mein Schrank</option><option value="wanting" ${state === 'wanting' ? 'selected' : ''}>Wunschliste</option>${state === 'archived' ? '<option value="archived" selected>Archiv</option>' : ''}</select></label></div><label>Farben<input name="colors" required value="${esc(metadata.colors.join(', '))}" placeholder="Zum Beispiel: Grün, Weiß"></label><label>Notizen <span class="muted">optional</span><textarea name="notes" maxlength="2000" placeholder="Passform, Marke oder womit du es gern trägst">${esc(metadata.notes || '')}</textarea></label>`;
}
function readFields(form) {
  const f = new FormData(form);
  const colors = String(f.get('colors'))
    .split(',')
    .map((c) => c.trim())
    .filter(Boolean);
  if (colors.length < 1 || colors.length > 6 || colors.some((c) => c.length > 32))
    throw new Error('Bitte gib 1 bis 6 Farben mit jeweils maximal 32 Zeichen an.');
  return {
    metadata: {
      name: String(f.get('name')).trim(),
      category: String(f.get('category')),
      colors,
      notes: String(f.get('notes')).trim() || null,
    },
    state: String(f.get('state')),
  };
}
// `keepScroll` is for redrawing the sheet that is already on screen, e.g. while
// polling a running generation. Without it the reader gets thrown back to the
// top of the sheet on every tick. Pass a number to restore a specific offset,
// which is how the sheet returns to where it was after a confirmation covered it.
function showSheet(title, content, keepScroll = false) {
  detailId = null;
  const sheet = $('#sheet');
  const offset = typeof keepScroll === 'number' ? keepScroll : sheet.scrollTop;
  const heldFocus = sheet.contains(document.activeElement);
  sheet.innerHTML = `<div class="sheet-grip" aria-hidden="true"></div><div class="sheet-head"><h2 id="sheet-title" tabindex="-1">${esc(title)}</h2><button class="close" id="close-sheet" aria-label="Schließen">${icon('close')}</button></div><div class="sheet-body">${content}</div>`;
  $('#close-sheet').onclick = closeSheet;
  if (!sheet.open) {
    sheet.showModal();
    // `showModal` parks the focus on the first focusable child, which is the
    // close button, and it lights up its focus ring. The title is the better
    // landing point: it reads the sheet out and shows no ring.
    $('#sheet-title').focus({ preventScroll: true });
    setSheetChrome(true);
  } else if (heldFocus && !sheet.contains(document.activeElement)) {
    // Swapping the content dropped the focused element. Without this the focus
    // falls out of the open dialog onto the page behind it.
    $('#sheet-title').focus({ preventScroll: true });
  }
  const target = keepScroll === false ? 0 : offset;
  sheet.scrollTop = target;
  // The sheet can still be growing into its final height on this frame, which
  // would clamp the offset we just set.
  if (target) requestAnimationFrame(() => (sheet.scrollTop = target));
}
// Everything outside the dialog that reacts to it: the scrim over the page, the
// page scroll lock, and the colour iOS fills the status bar strip with.
const paper = '#f6f5f1';
const dimmedPaper = '#9fa39c';
function setSheetChrome(open) {
  $('#scrim').classList.toggle('show', open);
  document.body.classList.toggle('sheet-open', open);
  document.body.style.overflow = open ? 'hidden' : '';
  $('meta[name="theme-color"]').content = open ? dimmedPaper : paper;
}
function closeSheet() {
  $('#sheet').close();
  detailId = null;
  setSheetChrome(false);
}
$('#sheet').addEventListener('close', () => {
  detailId = null;
  setSheetChrome(false);
});
// Tapping the blurred area around the sheet closes it. A click on the backdrop
// is reported with the dialog itself as the target, so the coordinates decide:
// dead space inside the sheet must not close it.
$('#sheet').addEventListener('click', (event) => {
  const sheet = event.currentTarget;
  if (event.target !== sheet) return;
  const box = sheet.getBoundingClientRect();
  const inside =
    event.clientX >= box.left &&
    event.clientX <= box.right &&
    event.clientY >= box.top &&
    event.clientY <= box.bottom;
  if (!inside) closeSheet();
});
// Drag the sheet down to dismiss it. The drag only takes over when the content
// is already scrolled to the top or the finger started on the head, the gesture
// is locked to one axis on the first move, and the sideways-scrolling rows are
// excluded — so it never steals a scroll or a swipe from inside the sheet.
(function wireSheetDrag() {
  const sheet = $('#sheet');
  const threshold = 110;
  let startY = null;
  let startX = 0;
  let offset = 0;
  let axis = null;
  let dragging = false;
  const reset = () => {
    sheet.classList.remove('dragging');
    sheet.style.translate = '';
    startY = null;
    offset = 0;
    axis = null;
    dragging = false;
  };
  sheet.addEventListener(
    'touchstart',
    (event) => {
      reset();
      if (event.touches.length !== 1) return;
      const fromHead = event.target.closest?.('.sheet-head, .sheet-grip');
      // Rows that scroll sideways own their gesture completely. Without this a
      // swipe through the gallery nudges the whole sheet up and down.
      if (event.target.closest?.('.gallery, .versions')) return;
      if (sheet.scrollTop > 0 && !fromHead) return;
      startY = event.touches[0].clientY;
      startX = event.touches[0].clientX;
    },
    { passive: true },
  );
  sheet.addEventListener(
    'touchmove',
    (event) => {
      if (startY === null) return;
      const moveY = event.touches[0].clientY - startY;
      const moveX = event.touches[0].clientX - startX;
      // Decide once whether this is a vertical or a horizontal gesture, and
      // leave horizontal ones alone for the rest of the touch.
      if (axis === null) {
        if (Math.abs(moveX) < 8 && Math.abs(moveY) < 8) return;
        axis = Math.abs(moveX) > Math.abs(moveY) ? 'x' : 'y';
      }
      if (axis === 'x') return;
      offset = moveY;
      if (offset <= 0) {
        if (dragging) {
          sheet.classList.remove('dragging');
          sheet.style.translate = '';
          dragging = false;
        }
        return;
      }
      event.preventDefault();
      dragging = true;
      sheet.classList.add('dragging');
      sheet.style.translate = `0 ${offset}px`;
    },
    { passive: false },
  );
  const release = () => {
    if (!dragging) return reset();
    const shouldClose = offset > threshold;
    // Dropping `dragging` first hands the sheet back to the CSS transition, so
    // it either springs back or carries on into the closing animation.
    sheet.classList.remove('dragging');
    sheet.style.translate = '';
    if (shouldClose) closeSheet();
    startY = null;
    offset = 0;
    axis = null;
    dragging = false;
  };
  sheet.addEventListener('touchend', release);
  sheet.addEventListener('touchcancel', release);
})();
// The session reaches the content route directly, so an asset always has the
// same URL. Signed links used to mint a new one per call, which made every app
// launch re-download every look.
const assetUrl = (id) => `/v1/assets/${encodeURIComponent(id)}/content`;
// The payload behind the sheet currently on screen. Switching to the edit form
// or backing out of a confirmation changes nothing on the server, so those paths
// re-render from here instead of paying for a spinner and a refetch.
let detailCache = null;
// Whether a catalog image is being produced right now. The list and the detail
// payload report this differently, but both have to agree so that the gallery
// built for the placeholder survives into the loaded sheet.
const listRunning = (item) => ['queued', 'generating'].includes(item.status);
// What the picture row shows. Matching signatures mean the row on screen is
// still correct and can stay exactly as it is.
const gallerySignature = (item, running) => `${running}:${preview(item)}`;
// The picture row and the title block. Both the placeholder and the loaded sheet
// render this from the same strings, so the sheet only fills in underneath.
const galleryMarkup = (item, running) =>
  `<div class="gallery" id="detail-gallery" data-item="${item.id}" data-signature="${esc(gallerySignature(item, running))}">${
    running
      ? `<figure class="slide">${imageGenerationProgress(item.metadata.name)}</figure>`
      : `<figure class="slide"><img class="fade" src="${preview(item)}" alt="${esc(item.metadata.name)}"></figure>`
  }<figure class="slide worn"><img class="fade" id="worn" src="${sourcePreview(item)}" alt="${esc(item.metadata.name)}, getragen"><figcaption>Originalfoto</figcaption></figure></div><div id="detail-heading"><p class="eyebrow">${categories[item.metadata.category]}</p><h2>${esc(item.metadata.name)}</h2><p class="muted item-colors">${esc(item.metadata.colors.join(' · '))}</p></div>`;
// Stand-ins for the few parts that only the detail request knows: where the
// piece lives, its notes, and the saved catalog images.
const detailSkeleton = `<div role="status" aria-label="Details werden geladen"><dl class="facts"><div><dt>Gehört in</dt><dd><span class="skeleton skeleton-line" style="width:110px"></span></dd></div></dl><span class="skeleton skeleton-button"></span><span class="skeleton skeleton-button"></span><div class="rule"></div><h3>Katalogbilder</h3><p class="muted"><span class="skeleton skeleton-line" style="width:100%"></span><span class="skeleton skeleton-line" style="width:62%"></span></p><div class="versions">${'<span class="skeleton skeleton-version"></span>'.repeat(3)}</div><div class="rule"></div><span class="skeleton skeleton-button"></span></div>`;
// The sheet has two states: 'view' shows the piece read-only, 'edit' shows only
// the metadata form. Both need the same detail payload and command handlers.
// `cached` renders from `detailCache`, `refresh` redraws the sheet in place, and
// `scrollTop` restores an offset taken before a confirmation replaced the sheet.
async function openDetail(
  id,
  mode = 'view',
  { refresh = false, cached = false, scrollTop = null } = {},
) {
  if (cached && detailCache?.id === id)
    return renderDetail(id, detailCache.detail, mode, { refresh, scrollTop });
  if (!refresh) {
    // The grid already holds the picture, the name and the colours, so the sheet
    // opens with those in place and only skeletons what the request still owes.
    const known = mode === 'view' && items.find((item) => item.id === id);
    showSheet(
      mode === 'edit' ? 'Stück bearbeiten' : 'Dein Stück',
      known
        ? `${galleryMarkup(known, listRunning(known))}<div id="detail-body">${detailSkeleton}</div>`
        : '<div class="loading"><span class="spinner"></span> Wird geladen …</div>',
    );
    if (known) {
      wireFades($('#sheet'));
      if ($('#worn')) $('#worn').onerror = () => $('#worn').closest('.slide').remove();
    }
  }
  detailId = id;
  try {
    const detail = await api(`/wardrobe-items/${id}`);
    if (detailId !== id || !$('#sheet').open) return;
    detailCache = { id, detail };
    renderDetail(id, detail, mode, { refresh, scrollTop });
  } catch (error) {
    if ($('#sheet').open) {
      showSheet(
        'Nicht erreichbar',
        `<p class="error">${esc(error.message)}</p><button class="primary" id="retry-detail">Erneut versuchen</button>`,
      );
      $('#retry-detail').onclick = () => openDetail(id);
    }
  }
}
function renderDetail(id, detail, mode, { refresh = false, scrollTop = null }) {
  const i = detail.wardrobeItem;
  const running = detail.generationAttempts.some((a) => ['queued', 'processing'].includes(a.state));
  const failed = detail.generationAttempts[0]?.state === 'failed';
  const collections = {
    owning: 'Mein Schrank',
    wanting: 'Wunschliste',
    archived: 'Archiv',
  };
  // Leftmost is the plus tile, then the image in use, then the older ones
  // newest first, and the original photo closes the row on the right.
  const ordered = [...detail.shelfImageVersions].sort(
    (left, right) =>
      (right.id === i.currentShelfImageVersionId) - (left.id === i.currentShelfImageVersionId),
  );
  const versionTiles = ordered
    .map((v) => {
      const current = v.id === i.currentShelfImageVersionId;
      return `<button class="version${current ? ' current' : ''}" data-version="${v.id}" ${current ? 'disabled' : ''}><span class="version-frame"><img data-asset="${v.transparentAssetId}" alt="Gespeichertes Katalogbild">${v.quality === 'high' ? '<span class="version-tag">HQ</span>' : ''}</span><span>${current ? 'Aktuelles Bild' : 'Dieses Bild verwenden'}</span></button>`;
    })
    .join('');
  const body =
    mode === 'edit'
      ? `<form id="edit-item">${fields(i.metadata, i.state)}<button class="primary" style="margin-top:20px" type="submit">Änderungen speichern</button></form><button class="text-button" id="cancel-edit">Abbrechen</button>`
      : `<dl class="facts"><div><dt>Gehört in</dt><dd>${collections[i.state]}</dd></div>${i.metadata.notes ? `<div><dt>Notizen</dt><dd>${esc(i.metadata.notes)}</dd></div>` : ''}</dl><button class="secondary" id="edit-details">Details bearbeiten</button>
  <button class="primary" id="inspire-item" style="margin-top:10px">Inspiration erstellen</button>
  <div class="rule"></div>${running ? '<div class="note generating"><p><span class="spinner"></span>Dein Bild wird erstellt. Du kannst weiter durch deinen Schrank stöbern.</p><button class="text-button" id="check-generation">Status aktualisieren</button></div>' : `<h3>Katalogbilder</h3><p class="muted">${failed ? 'Der letzte Versuch ist fehlgeschlagen. ' : ''}Ein neues Bild wird automatisch verwendet, ein älteres kannst du jederzeit wieder auswählen.</p><div class="versions"><button class="version add-version" id="generate" aria-label="Katalogbild erstellen …"><span class="version-frame">${icon('plus')}</span><span>Neues Bild …</span></button>${versionTiles}<button class="version source-version" id="source"><span class="version-frame"><img id="source-tile" src="${sourcePreview(i)}" alt="" aria-hidden="true"></span><span>Originalfoto ansehen</span></button></div>`}
  <div class="rule"></div><div class="stack"><button class="secondary" id="archive">${i.state === 'archived' ? 'Zurück in den Schrank' : 'Ins Archiv legen'}</button><button class="text-button" id="delete">Stück endgültig löschen …</button></div>`;
  const title = mode === 'edit' ? 'Stück bearbeiten' : 'Dein Stück';
  // The gallery only depends on the pictures, not on the mode or the metadata
  // below it. Reusing it keeps the images on screen when the sheet toggles
  // into the edit form or when a poll redraws a running generation.
  const gallery = $('#detail-gallery');
  const reusable =
    gallery?.dataset.item === id && gallery.dataset.signature === gallerySignature(i, running);
  if (reusable) {
    $('#sheet-title').textContent = title;
    $('#detail-heading').innerHTML =
      `<p class="eyebrow">${categories[i.metadata.category]}</p><h2>${esc(i.metadata.name)}</h2><p class="muted item-colors">${esc(i.metadata.colors.join(' · '))}</p>`;
    $('#detail-body').innerHTML = body;
  } else {
    showSheet(
      title,
      `${galleryMarkup(i, running)}<div id="detail-body">${body}</div>`,
      scrollTop ?? refresh,
    );
  }
  wireFades($('#sheet'));
  wireScrollFade($('.versions'));
  detailId = id;
  // Drop the worn photo and the source tile when the original upload is gone.
  if ($('#worn')) $('#worn').onerror = () => $('#worn').closest('.slide').remove();
  if ($('#source-tile')) $('#source-tile').onerror = () => $('#source').remove();
  const command = () => ({
    expectedRecordVersion: i.recordVersion,
    idempotencyKey: key(),
  });
  if ($('#edit-details'))
    $('#edit-details').onclick = () => openDetail(id, 'edit', { cached: true });
  if ($('#inspire-item')) $('#inspire-item').onclick = () => openLookComposer([id]);
  if ($('#cancel-edit')) $('#cancel-edit').onclick = () => openDetail(id, 'view', { cached: true });
  if ($('#edit-item'))
    $('#edit-item').onsubmit = async (e) => {
      e.preventDefault();
      const form = e.currentTarget;
      await action($('button[type=submit]', form), async () => {
        try {
          await api(`/wardrobe-items/${id}`, { ...readFields(form), ...command() }, 'PATCH');
          await refreshItems();
          render();
          closeSheet();
          toast('Änderungen gespeichert');
        } catch (error) {
          formError(form, error);
        }
      });
    };
  if ($('#check-generation')) $('#check-generation').onclick = () => openDetail(id);
  if ($('#generate'))
    $('#generate').onclick = () => {
      // Backing out of the dialog must land where the reader left the sheet,
      // which is usually scrolled down at the catalog images.
      const offset = $('#sheet').scrollTop;
      showSheet(
        'Katalogbild erstellen',
        `<h2>Nur für dieses Stück.</h2><p>Das neue Katalogbild wird automatisch verwendet. Ein älteres Bild kannst du jederzeit wieder auswählen.</p><div class="note">Die Ausgabe kostet zusätzlich zum Eingabebild und Text. Abgerechnet wird nach tatsächlichem Verbrauch. In hoher Qualität liegt ein Bild nach den bisher erfassten Abrechnungen bei etwa 6 US-Cent. Das ist eine Orientierung, kein garantierter Festpreis.</div><p class="muted" style="margin:16px 0">GPT Image 2.5 Flare · High · ein neues Bild</p><button class="primary" id="confirm-generate">Ein kostenpflichtiges Bild anfordern</button><button class="text-button" id="cancel-generate">Abbrechen</button>`,
      );
      $('#cancel-generate').onclick = () =>
        openDetail(id, 'view', { cached: true, scrollTop: offset });
      const generationKey = key();
      $('#confirm-generate').onclick = (e) =>
        action(e.currentTarget, async () => {
          await api('/generations', {
            wardrobeItemId: id,
            quality: 'high',
            size: '816x816',
            autoKeep: true,
            idempotencyKey: generationKey,
          });
          await refreshItems();
          render();
          await openDetail(id);
          toast('Dein Bild wird erstellt');
        });
    };
  if ($('#source'))
    $('#source').onclick = () => {
      const offset = $('#sheet').scrollTop;
      showSheet(
        'Originalfoto',
        `<div class="detail-photo"><img class="fade" src="${esc(assetUrl(detail.sourcePhoto.assetId))}" alt="Originalfoto"></div><button class="secondary" id="back-detail">Zurück zum Stück</button>`,
      );
      wireFades($('#sheet'));
      $('#back-detail').onclick = () => openDetail(id, 'view', { cached: true, scrollTop: offset });
    };
  document
    .querySelectorAll('[data-asset]')
    .forEach((img) => (img.src = assetUrl(img.dataset.asset)));
  document.querySelectorAll('[data-version]').forEach(
    (b) =>
      (b.onclick = () =>
        action(b, async () => {
          await api(
            `/wardrobe-items/${id}/shelf-image-versions/${b.dataset.version}/restore`,
            command(),
          );
          await refreshItems();
          render();
          await openDetail(id);
        })),
  );
  if ($('#archive'))
    $('#archive').onclick = (e) =>
      action(e.currentTarget, async () => {
        await api(
          `/wardrobe-items/${id}`,
          {
            state: i.state === 'archived' ? 'owning' : 'archived',
            ...command(),
          },
          'PATCH',
        );
        await refreshItems();
        render();
        closeSheet();
        toast(i.state === 'archived' ? 'Zurück im Schrank' : 'Im Archiv abgelegt');
      });
  if ($('#delete'))
    $('#delete').onclick = () => {
      const offset = $('#sheet').scrollTop;
      showSheet(
        'Stück löschen',
        `<h2>Endgültig löschen?</h2><p>„${esc(i.metadata.name)}“ und seine Katalogbilder werden gelöscht. Das lässt sich nicht rückgängig machen.</p><button class="danger" id="confirm-delete">Stück endgültig löschen</button><button class="text-button" id="cancel-delete">Behalten</button>`,
      );
      $('#cancel-delete').onclick = () =>
        openDetail(id, 'view', { cached: true, scrollTop: offset });
      $('#confirm-delete').onclick = (e) =>
        action(e.currentTarget, async () => {
          await api(`/wardrobe-items/${id}`, command(), 'DELETE');
          await refreshItems();
          render();
          closeSheet();
          toast('Stück gelöscht');
        });
    };
}
async function preparePhoto(file) {
  if (file.size > 25 * 1024 * 1024)
    throw new Error('Das Foto ist zu groß. Bitte wähle ein Foto unter 25 MB.');
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    // The generation reference is a crop of this photo, so the long edge has to
    // carry enough pixels for fabric texture to survive into the model input.
    const scale = Math.min(1, 2400 / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(image.naturalWidth * scale);
    canvas.height = Math.round(image.naturalHeight * scale);
    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.92));
    if (!blob) throw new Error('Foto konnte nicht vorbereitet werden.');
    return blob;
  } catch {
    throw new Error(
      'Dieses Foto lässt sich hier nicht öffnen. Bitte verwende JPEG, PNG oder ein in Safari lesbares Foto.',
    );
  } finally {
    URL.revokeObjectURL(url);
  }
}
async function uploadPhoto(uploadUrl, headers, blob) {
  let failure;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await fetch(uploadUrl, {
        method: 'PUT',
        headers,
        body: blob,
      });
      if (response.ok) return;
      const detail = await response
        .json()
        .then((body) => body?.error?.message)
        .catch(() => null);
      failure = new Error(detail || `Upload fehlgeschlagen (${response.status}).`);
    } catch {
      failure = new Error('Upload-Verbindung unterbrochen.');
    }
    if (attempt === 0) await new Promise((resolve) => setTimeout(resolve, 300));
  }
  throw failure;
}
function renderAdd() {
  const hasActivity = drafts.length || importBusy;
  shell(
    `<p class="eyebrow">Stück für Stück</p><h1>${hasActivity ? 'Wähle deine Stücke.' : 'Foto rein.<br>Schrank fertig.'}</h1><p class="muted">Wir erkennen deine Kleidung, du wählst aus, was in den Schrank kommt.</p><div class="upload-area ${hasActivity ? 'compact-upload' : ''}">${hasActivity ? '' : `${icon('camera')}<h2>Alles auf ein Foto.</h2><p>Ein einzelnes Stück oder ein ganzes Outfit. Ein ruhiger Hintergrund hilft bei der Erkennung.</p>`}<div class="stack"><button class="primary" id="camera" ${importBusy ? 'disabled' : ''}>${icon('camera')} Foto aufnehmen</button><button class="secondary" id="library" ${importBusy ? 'disabled' : ''}>${icon('photo')} Fotos auswählen</button></div><input hidden type="file" id="camera-input" accept="image/*" capture="environment"><input hidden type="file" id="library-input" accept="image/*" multiple></div><p class="note">Analyse und Katalogbilder werden automatisch mit OpenAI erstellt und sind kostenpflichtig. Nach deiner Auswahl läuft alles im Hintergrund weiter.</p><div id="drafts"></div>`,
  );
  $('#camera').onclick = () => $('#camera-input').click();
  $('#library').onclick = () => $('#library-input').click();
  for (const id of ['camera-input', 'library-input'])
    $(`#${id}`).onchange = (e) => importPhotos([...e.target.files]);
  renderDrafts();
  for (const draft of drafts.filter((item) => item.phase === 'uploaded')) startDetection(draft);
  for (const draft of drafts.filter((item) => item.phase === 'detecting'))
    scheduleDetectionCheck(draft);
}
async function importPhotos(files) {
  if (importBusy || !files.length) return;
  importBusy = true;
  renderAdd();
  let failed = 0;
  const failures = [];
  for (let n = 0; n < files.length; n++) {
    let draft;
    try {
      draft = {
        id: key(),
        localPreviewUrl: URL.createObjectURL(files[n]),
        phase: 'uploading',
        state: 'owning',
      };
      drafts.push(draft);
      persistDrafts();
      if (page === 'add') renderDrafts();
      const blob = await preparePhoto(files[n]);
      const intent = await api('/source-photos/upload-intents', {
        fileName: 'wardrobe.jpg',
        contentType: 'image/jpeg',
        byteSize: blob.size,
      });
      await uploadPhoto(intent.uploadUrl, intent.headers, blob);
      const completed = await api('/source-photos/complete', {
        assetId: intent.assetId,
        idempotencyKey: key(),
      });
      Object.assign(draft, {
        sourcePhotoId: completed.sourcePhoto.id,
        assetId: completed.asset.id,
        phase: 'uploaded',
        state: 'owning',
      });
      persistDrafts();
      if (page === 'add') renderDrafts();
      await startDetection(draft);
    } catch (error) {
      if (draft) {
        revokeDraftPreview(draft);
        drafts = drafts.filter((item) => item.id !== draft.id);
        persistDrafts();
        if (page === 'add') renderDrafts();
      }
      failed++;
      failures.push(`${files[n].name}: ${error.message}`);
    }
  }
  importBusy = false;
  if (page === 'add') renderAdd();
  toast(
    failed
      ? `${files.length - failed} hochgeladen, ${failed} fehlgeschlagen. ${failures.join(' ')}`
      : `${files.length} ${files.length === 1 ? 'Foto wird analysiert' : 'Fotos werden analysiert'}.`,
  );
}
function renderDrafts() {
  if (!$('#drafts')) return;
  $('#drafts').innerHTML = drafts.length
    ? `<div class="section-row"><span>${drafts.length} ${drafts.length === 1 ? 'Foto' : 'Fotos'}</span><span>Bleiben auf diesem Gerät gespeichert</span></div>${drafts.map(renderDetectionDraft).join('')}`
    : '';
  document
    .querySelectorAll('[data-draft-asset]')
    .forEach(
      (img) => (img.src = img.dataset.draftPreview || assetUrl(img.dataset.draftAsset)),
    );
  document.querySelectorAll('[data-choice-preview]').forEach((canvas) => {
    const draft = drafts.find((item) => item.id === canvas.dataset.draft);
    const proposal = draft?.detections?.find((item) => item.id === canvas.dataset.choicePreview);
    if (!draft || !proposal) return;
    drawDetectionPreview(canvas, assetUrl(draft.assetId), proposal.boundingBox);
  });
  document.querySelectorAll('[data-toggle-piece]').forEach((button) => {
    button.onclick = () => {
      const draft = drafts.find((item) => item.id === button.dataset.draft);
      const proposal = draft?.detections?.find((item) => item.id === button.dataset.togglePiece);
      if (!proposal || draft.phase === 'importing') return;
      proposal.selected = !proposal.selected;
      persistDrafts();
      updateDetectionSelection(draft, proposal);
    };
  });
  document.querySelectorAll('[data-import-detected]').forEach((button) => {
    button.onclick = () => {
      const draft = drafts.find((item) => item.id === button.dataset.importDetected);
      if (draft) action(button, () => importDetected(draft));
    };
  });
  document.querySelectorAll('[data-batch-owning]').forEach((toggle) => {
    toggle.onchange = () => {
      const draft = drafts.find((item) => item.id === toggle.dataset.batchOwning);
      if (!draft) return;
      draft.state = toggle.checked ? 'owning' : 'wanting';
      for (const proposal of draft.detections || []) proposal.state = draft.state;
      persistDrafts();
      document
        .querySelectorAll(`[data-piece-owning][data-draft="${CSS.escape(draft.id)}"]`)
        .forEach((pieceToggle) => (pieceToggle.checked = toggle.checked));
    };
  });
  document.querySelectorAll('[data-piece-owning]').forEach((toggle) => {
    toggle.onchange = () => {
      const draft = drafts.find((item) => item.id === toggle.dataset.draft);
      const proposal = draft?.detections?.find((item) => item.id === toggle.dataset.pieceOwning);
      if (!proposal) return;
      proposal.state = toggle.checked ? 'owning' : 'wanting';
      persistDrafts();
    };
  });
  document.querySelectorAll('[data-manual-save]').forEach((form) => {
    form.onsubmit = (event) => {
      event.preventDefault();
      const draft = drafts.find((item) => item.id === form.dataset.manualSave);
      if (draft) action($('button[type=submit]', form), () => importManual(draft, form));
    };
  });
  document.querySelectorAll('[data-discard]').forEach(
    (b) =>
      (b.onclick = () => {
        const draft = drafts.find((item) => item.id === b.dataset.discard);
        if (draft) revokeDraftPreview(draft);
        drafts = drafts.filter((d) => d.id !== b.dataset.discard);
        persistDrafts();
        if (drafts.length) renderDrafts();
        else renderAdd();
      }),
  );
}
function renderDetectionDraft(draft) {
  const discard = `<button class="close" data-discard="${draft.id}" aria-label="Foto verwerfen">${icon('close')}</button>`;
  if (draft.phase === 'manual') {
    return `<article class="draft" data-draft="${draft.id}"><div class="draft-head"><div><h3>Selbst hinzufügen</h3><p class="draft-status">${esc(draft.failure || 'Auf diesem Foto wurde kein Stück erkannt.')}</p></div>${discard}</div><img data-draft-asset="${draft.assetId}" data-draft-preview="${esc(draft.localPreviewUrl || '')}" alt="Hochgeladenes Foto"><form data-manual-save="${draft.id}">${fields(draft.metadata, 'owning')}<button class="primary" style="margin-top:18px" type="submit">Stück hinzufügen</button></form></article>`;
  }
  const detections = (draft.detections || []).filter((item) => !item.imported);
  const selected = detections.filter((item) => item.selected && !item.imported);
  const overlays = detections
    .map(
      (item, index) =>
        `<button class="detection-box category-${detectionCategoryTheme(item.category)} ${item.selected ? 'selected' : ''}" data-draft="${draft.id}" data-toggle-piece="${item.id}" aria-label="${esc(item.name)} ${item.selected ? 'abwählen' : 'auswählen'}" aria-pressed="${item.selected}" style="left:${item.boundingBox.x / 10}%;top:${item.boundingBox.y / 10}%;width:${item.boundingBox.width / 10}%;height:${item.boundingBox.height / 10}%"><span class="detection-badge">${icon(detectionCategoryIcon(item.category))}</span></button>`,
    )
    .join('');
  const categoryGroups = [
    { label: 'Oberteile', icon: 'top', categories: ['top', 'jacket', 'dress'] },
    { label: 'Unterteile', icon: 'bottom', categories: ['pants', 'skirt'] },
    { label: 'Schuhe', icon: 'shoes', categories: ['shoes'] },
    { label: 'Accessoires', icon: 'accessory', categories: [] },
  ];
  const choices = categoryGroups
    .map((groupDefinition) => {
      const { label, icon: groupIcon, categories: groupCategories } = groupDefinition;
      const group = detections
        .map((item, index) => ({ item, index }))
        .filter(({ item }) =>
          groupCategories.length ? groupCategories.includes(item.category) : !['top', 'jacket', 'dress', 'pants', 'skirt', 'shoes'].includes(item.category),
        );
      if (!group.length) return '';
      return `<section class="detection-group category-${groupIcon}"><h4>${icon(groupIcon)}<span>${label}</span></h4>${group
        .map(
          ({ item, index }) =>
            `<div class="detection-choice-row category-${detectionCategoryTheme(item.category)} ${item.selected ? 'selected' : ''}"><button class="detection-choice ${item.selected ? 'selected' : ''}" data-draft="${draft.id}" data-toggle-piece="${item.id}" aria-pressed="${item.selected}"><canvas class="choice-preview" data-draft="${draft.id}" data-choice-preview="${item.id}" width="112" height="112" aria-hidden="true"></canvas><span class="choice-copy"><strong>${esc(item.name)}</strong><small>${esc(categories[item.category])} · ${esc(item.colors.join(', '))}</small></span><span class="choice-number">${item.selected ? icon('check') : index + 1}</span></button><label class="state-toggle"><span>Besitze ich</span><input type="checkbox" data-draft="${draft.id}" data-piece-owning="${item.id}" aria-label="${esc(item.name)} besitze ich" ${(item.state || draft.state || 'owning') === 'owning' ? 'checked' : ''}><span class="toggle-control" aria-hidden="true"></span></label></div>`,
        )
        .join('')}</section>`;
    })
    .join('');
  const busy = ['uploading', 'uploaded', 'detecting'].includes(draft.phase);
  const analyzing = draft.phase !== 'uploading';
  return `<article class="draft scan-card" data-draft="${draft.id}"><div class="draft-head"><div><h3>${busy ? analyzing ? 'Foto wird analysiert' : 'Foto wird hochgeladen' : `${detections.length} ${detections.length === 1 ? 'Stück erkannt' : 'Stücke erkannt'}`}</h3><p class="draft-status">${busy ? analyzing ? 'FORM sucht nach Kleidungsstücken auf deinem Foto.' : 'Dein Foto erscheint sofort, während es hochgeladen wird.' : 'Tippe auf die Rahmen, um deine Auswahl zu ändern.'}</p></div>${discard}</div><div class="detection-stage"><img data-draft-asset="${draft.assetId}" data-draft-preview="${esc(draft.localPreviewUrl || '')}" alt="Hochgeladenes Foto">${busy ? `<div class="scan-progress">${icon('search')}<span>${analyzing ? 'Kleidung wird erkannt …' : 'Foto wird hochgeladen …'}</span></div>` : overlays}</div>${busy ? '' : `<div class="batch-state"><span>Alle Stücke zunächst</span><small>Gilt für alle erkannten Stücke</small><label class="state-toggle"><span>Besitze ich</span><input type="checkbox" data-batch-owning="${draft.id}" aria-label="Alle Stücke besitze ich" ${(draft.state || 'owning') === 'owning' ? 'checked' : ''}><span class="toggle-control" aria-hidden="true"></span></label></div><div class="detection-choices">${choices}</div><button class="primary" data-import-detected="${draft.id}" ${selected.length || draft.phase === 'importing' ? '' : 'disabled'}>${draft.phase === 'importing' ? '<span class="spinner"></span> Wird hinzugefügt …' : `${selected.length} ${selected.length === 1 ? 'Stück' : 'Stücke'} hinzufügen`}</button>`}</article>`;
}
async function drawDetectionPreview(canvas, url, box) {
  const image = new Image();
  image.src = url;
  await image.decode();
  if (!canvas.isConnected) return;
  const sourceX = (box.x / 1000) * image.naturalWidth;
  const sourceY = (box.y / 1000) * image.naturalHeight;
  const sourceWidth = (box.width / 1000) * image.naturalWidth;
  const sourceHeight = (box.height / 1000) * image.naturalHeight;
  const scale = Math.max(canvas.width / sourceWidth, canvas.height / sourceHeight);
  const width = sourceWidth * scale;
  const height = sourceHeight * scale;
  const context = canvas.getContext('2d');
  context.fillStyle = '#eaece5';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(
    image,
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
    (canvas.width - width) / 2,
    (canvas.height - height) / 2,
    width,
    height,
  );
}
async function startDetection(draft) {
  if (!drafts.some((item) => item.id === draft.id)) return;
  draft.phase = 'detecting';
  draft.detectionKey ||= key();
  persistDrafts();
  renderDrafts();
  try {
    await api(`/source-photos/${draft.sourcePhotoId}/detections`, {
      idempotencyKey: draft.detectionKey,
    });
    scheduleDetectionCheck(draft);
  } catch (error) {
    useManualFallback(draft, error.message);
  }
}
function updateDetectionSelection(draft, proposal) {
  const selected = proposal.selected;
  const index = draft.detections.filter((item) => !item.imported).indexOf(proposal);
  document
    .querySelectorAll(
      `[data-draft="${CSS.escape(draft.id)}"][data-toggle-piece="${CSS.escape(proposal.id)}"]`,
    )
    .forEach((button) => {
      button.classList.toggle('selected', selected);
      button.closest('.detection-choice-row')?.classList.toggle('selected', selected);
      button.setAttribute('aria-pressed', selected);
      if (button.classList.contains('detection-box'))
        button.setAttribute('aria-label', `${proposal.name} ${selected ? 'abwählen' : 'auswählen'}`);
      const number = button.querySelector('.choice-number');
      if (number) number.innerHTML = selected ? icon('check') : index + 1;
    });
  const selectedCount = draft.detections.filter((item) => item.selected && !item.imported).length;
  const importButton = document.querySelector(
    `[data-import-detected="${CSS.escape(draft.id)}"]`,
  );
  if (importButton) {
    importButton.disabled = !selectedCount;
    importButton.textContent = `${selectedCount} ${selectedCount === 1 ? 'Stück' : 'Stücke'} hinzufügen`;
  }
}
function scheduleDetectionCheck(draft) {
  if (detectionPolls.has(draft.id)) return;
  detectionPolls.add(draft.id);
  setTimeout(async () => {
    detectionPolls.delete(draft.id);
    if (!drafts.some((item) => item.id === draft.id) || draft.phase !== 'detecting') return;
    try {
      await checkDetection(draft);
      if (draft.phase === 'detecting') scheduleDetectionCheck(draft);
    } catch (error) {
      toast(error.message);
      scheduleDetectionCheck(draft);
    }
  }, 2000);
}
function useManualFallback(draft, message) {
  if (!drafts.some((item) => item.id === draft.id)) return;
  draft.phase = 'manual';
  draft.failure = message;
  draft.metadata ||= { name: '', category: 'top', colors: [], notes: null };
  persistDrafts();
  renderDrafts();
}
async function checkDetection(draft) {
  const data = await api(`/source-photos/${draft.sourcePhotoId}/detections`);
  if (!drafts.some((item) => item.id === draft.id)) return;
  if (data.attempt?.state === 'failed') {
    return useManualFallback(
      draft,
      'Die automatische Erkennung ist fehlgeschlagen. Du kannst das Foto trotzdem verwenden.',
    );
  }
  if (data.attempt?.state !== 'succeeded') return;
  const supported = data.detections.filter((proposal) => proposal.category !== 'unsupported');
  if (!supported.length)
    return useManualFallback(
      draft,
      'Auf diesem Foto wurde kein unterstütztes Kleidungsstück erkannt.',
    );
  draft.phase = 'ready';
  draft.detections = supported.map((proposal) => ({
    ...proposal,
    selected: true,
    itemKey: key(),
    generationKey: key(),
    state: draft.state || 'owning',
  }));
  persistDrafts();
  renderDrafts();
  toast(`${supported.length} ${supported.length === 1 ? 'Stück erkannt' : 'Stücke erkannt'}.`);
}
async function enqueueAutomaticImage(wardrobeItemId, idempotencyKey) {
  await api('/generations', {
    wardrobeItemId,
    quality: 'high',
    size: '816x816',
    autoKeep: true,
    idempotencyKey,
  });
}
async function importDetected(draft) {
  const selected = draft.detections.filter((proposal) => proposal.selected && !proposal.imported);
  if (!selected.length) return;
  draft.phase = 'importing';
  persistDrafts();
  renderDrafts();
  try {
    for (const proposal of selected) {
      proposal.itemKey ||= key();
      proposal.generationKey ||= key();
      const result = await api('/wardrobe-items', {
        detectionProposalId: proposal.id,
        state: proposal.state || draft.state || 'owning',
        idempotencyKey: proposal.itemKey,
      });
      await enqueueAutomaticImage(result.wardrobeItem.id, proposal.generationKey);
      proposal.imported = true;
      persistDrafts();
    }
    revokeDraftPreview(draft);
    drafts = drafts.filter((item) => item.id !== draft.id);
    persistDrafts();
    await refreshItems();
    if (drafts.length) renderAdd();
    else navigate('wardrobe');
    toast(
      `${selected.length} ${selected.length === 1 ? 'Stück wird' : 'Stücke werden'} für deinen Schrank vorbereitet.`,
    );
  } catch (error) {
    draft.phase = 'ready';
    persistDrafts();
    renderDrafts();
    throw error;
  }
}
async function importManual(draft, form) {
  const values = readFields(form);
  draft.phase = 'importing';
  draft.itemKey ||= key();
  draft.generationKey ||= key();
  persistDrafts();
  try {
    const result = await api('/wardrobe-items/from-photo', {
      sourcePhotoId: draft.sourcePhotoId,
      ...values,
      idempotencyKey: draft.itemKey,
    });
    await enqueueAutomaticImage(result.wardrobeItem.id, draft.generationKey);
    drafts = drafts.filter((item) => item.id !== draft.id);
    persistDrafts();
    await refreshItems();
    if (drafts.length) renderAdd();
    else navigate('wardrobe');
    toast('Dein Stück wird für den Schrank vorbereitet.');
  } catch (error) {
    draft.phase = 'manual';
    persistDrafts();
    formError(form, error);
  }
}
function renderSettings() {
  shell(
    `<p class="eyebrow">So, wie du es brauchst</p><h1>Ganz dein Ding.</h1><p class="muted">Dein privater Kleiderschrank auf stargate.</p><section class="panel"><h3>Character Sheet</h3><p>Deine aktive Identitätsreferenz für persönliche Looks. Frühere Versionen bleiben erhalten.</p><div id="character-settings">${characterSettingsMarkup()}</div><button class="primary" id="new-character">Neues Character Sheet</button></section><section class="panel"><h3>Generierungskosten</h3><div id="cost-settings"><div class="loading"><span class="spinner"></span></div></div></section><section class="panel"><h3>Auf deinem iPhone</h3><p>Öffne FORM in Safari. Tippe auf Teilen und dann auf „Zum Home-Bildschirm“. So öffnet sich dein Schrank wie eine App.</p><div class="setting-row">Zugang<span>Privat über Tailscale</span></div><div class="setting-row">Anmeldung<span>Kein Passwort nötig</span></div><div class="setting-row">Speicherort<span>Dein Server</span></div></section><button class="secondary" id="open-archive">Archiv öffnen · ${items.filter((i) => i.state === 'archived').length} Stücke</button><section class="panel"><h3>Noch einmal von vorn</h3><p>Leert den gemeinsamen privaten Kleiderschrank auf allen deinen Geräten. Kleidung, Fotos, Looks und Character Sheets werden dauerhaft gelöscht.</p><button class="danger" id="reset">Kleiderschrank leeren …</button></section><p class="muted" style="text-align:center;font-size:11px">FORM · Persönliche Web-Version</p>`,
  );
  $('#new-character').onclick = openCharacterSetup;
  wireCharacterCards($('#character-settings'));
  if ($('#character-history')) $('#character-history').onclick = openCharacterHistory;
  loadSettingsData();
  $('#open-archive').onclick = () => navigate('archived');
  $('#reset').onclick = () => {
    showSheet(
      'Neu anfangen',
      '<h2>Alles zurück auf null?</h2><p>Alle Stücke, Fotos und Bildentwürfe in deinem privaten Kleiderschrank werden gelöscht. Auch auf deinen anderen Geräten.</p><form id="reset-form"><label>Tippe ALLES LÖSCHEN zur Bestätigung<input name="confirmation" autocomplete="off" required placeholder="ALLES LÖSCHEN"></label><button class="danger" type="submit" style="margin-top:20px">Alles endgültig löschen</button></form>',
    );
    $('#reset-form').onsubmit = (e) => {
      e.preventDefault();
      const form = e.currentTarget;
      if (new FormData(form).get('confirmation') !== 'ALLES LÖSCHEN')
        return formError(form, new Error('Bitte tippe genau ALLES LÖSCHEN.'));
      action($('button', form), async () => {
        try {
          await api('/personal/reset', { confirmation: 'ALLES LÖSCHEN' });
          drafts = [];
          persistDrafts();
          resultsByPage.clear();
          feedCards.clear();
          detailCache = null;
          await refreshItems();
          closeSheet();
          looks = [];
          characterSheets = [];
          navigate('feed');
          toast('Dein Schrank ist wieder leer');
        } catch (error) {
          formError(form, error);
        }
      });
    };
  };
}
function characterSettingsMarkup() {
  const current = currentCharacterSheet();
  const pending = characterSheets.find((sheet) => isCharacterPending(sheet));
  const past = characterSheets.filter((sheet) => sheet.id !== current?.id && sheet.id !== pending?.id);
  return current
    ? `${pending && pending.id !== current.id ? characterCurrentCard(pending, true) : ''}${characterCurrentCard(current)}${past.length ? `<button class="secondary" id="character-history">Frühere Versionen · ${past.length}</button>` : ''}`
    : '<p class="muted">Noch nicht eingerichtet.</p>';
}
async function loadSettingsData() {
  try {
    const [sheets, costData] = await Promise.all([
      api('/character-sheets'),
      api('/generation-costs'),
    ]);
    characterSheets = sheets.characterSheets;
    if (!$('#character-settings')) return;
    $('#character-settings').innerHTML = characterSettingsMarkup();
    $('#cost-settings').innerHTML =
      `<div class="setting-row">Looks gesamt<span>${money(costData.costs.lookTotalMicrounits)}</span></div><div class="setting-row">Ø pro fertigem Look<span>${money(costData.costs.averageSuccessfulLookMicrounits)}</span></div><div class="setting-row">Character Sheets<span>${money(costData.costs.characterSheetTotalMicrounits)}</span></div>`;
    wireCharacterCards($('#character-settings'));
    if ($('#character-history')) $('#character-history').onclick = openCharacterHistory;
  } catch (error) {
    if ($('#character-settings'))
      $('#character-settings').innerHTML = `<p class="error">${esc(error.message)}</p>`;
  }
}
const sheetDate = (sheet) => new Date(sheet.createdAt).toLocaleDateString('de-DE');
const characterStatus = (sheet) =>
  sheet.active
    ? 'Aktiv'
    : sheet.state === 'failed'
      ? 'Fehlgeschlagen'
      : sheet.state === 'ready'
        ? 'Gespeichert'
        : 'Wird erstellt …';
const isCharacterPending = (sheet) => !['ready', 'failed'].includes(sheet.state);
const characterThumbnail = (sheet) =>
  sheet.assetId
    ? `<span class="character-thumbnail"><img class="fade" data-asset="${sheet.assetId}" alt="Character Sheet vom ${sheetDate(sheet)}" decoding="async"></span>`
    : `<span class="character-thumbnail character-placeholder">${sheet.state === 'failed' ? icon('close') : '<span class="spinner"></span>'}</span>`;
function currentCharacterSheet() {
  return characterSheets.find((sheet) => sheet.active) ?? characterSheets[0] ?? null;
}
function characterCurrentCard(sheet, pending = false) {
  const referenceCount = sheet.referenceAssetIds.length;
  const title = pending ? 'Neues Character Sheet' : sheet.active ? 'Aktives Character Sheet' : 'Character Sheet';
  const subtitle = pending ? 'Wird erstellt' : `Seit ${sheetDate(sheet)}`;
  return `<button class="character-current ${sheet.active ? 'active' : ''} ${pending ? 'character-current-pending' : ''}" data-character="${sheet.id}" aria-label="Character Sheet vom ${sheetDate(sheet)} öffnen">${characterThumbnail(sheet)}<span class="character-current-copy"><strong>${title}</strong><small>${subtitle}</small><span class="character-current-meta"><span>${icon('photo')}${referenceCount} ${referenceCount === 1 ? 'Referenzfoto' : 'Referenzfotos'}</span>${sheet.refinementInstruction ? `<span>${icon('check')}Verfeinert</span>` : ''}</span></span></button>`;
}
function wireCharacterCards(root) {
  root.querySelectorAll('img[data-asset]').forEach((img) => (img.src = assetUrl(img.dataset.asset)));
  wireFades(root);
  root.querySelectorAll('[data-character]').forEach((button) => {
    button.onclick = () => openCharacterDetail(button.dataset.character);
  });
}
function openCharacterHistory() {
  const current = currentCharacterSheet();
  const pending = characterSheets.find((sheet) => isCharacterPending(sheet));
  const past = characterSheets.filter((sheet) => sheet.id !== current?.id && sheet.id !== pending?.id);
  showSheet(
    'Frühere Versionen',
    `<h2>Deine bisherigen Sheets.</h2><p>Wähle eine Version, um sie anzusehen, wieder zu aktivieren oder zu löschen.</p><div class="character-versions">${past.map((sheet) => `<button class="character-version" data-character="${sheet.id}" aria-label="Character Sheet vom ${sheetDate(sheet)} öffnen">${characterThumbnail(sheet)}<span class="character-version-copy"><strong>${characterStatus(sheet)}</strong><small>${sheetDate(sheet)}</small></span></button>`).join('')}</div>`,
  );
  wireCharacterCards($('#sheet'));
}
function openCharacterDetail(id) {
  const sheet = characterSheets.find((entry) => entry.id === id);
  if (!sheet) return;
  const status = characterStatus(sheet);
  showSheet(
    'Character Sheet',
    `${sheet.assetId ? `<figure class="character-detail"><img class="fade" data-asset="${sheet.assetId}" alt="Character Sheet in voller Ansicht" decoding="async"></figure>` : `<div class="character-detail character-placeholder">${sheet.state === 'failed' ? icon('close') : '<span class="spinner"></span>'}</div>`}<dl class="facts"><div><dt>Status</dt><dd>${status}</dd></div><div><dt>Erstellt</dt><dd>${new Date(sheet.createdAt).toLocaleString('de-DE')}</dd></div><div><dt>Referenzfotos</dt><dd>${sheet.referenceAssetIds.length}</dd></div><div><dt>Modell</dt><dd>${esc(sheet.model)} · ${sheet.quality} · ${sheet.size}</dd></div>${sheet.note ? `<div><dt>Hinweis</dt><dd>${esc(sheet.note)}</dd></div>` : ''}${sheet.refinementInstruction ? `<div><dt>Verfeinerung</dt><dd>${esc(sheet.refinementInstruction)}</dd></div>` : ''}${sheet.costMicrounits !== null ? `<div><dt>Kosten</dt><dd>${money(sheet.costMicrounits)}</dd></div>` : ''}${sheet.failureCategory ? `<div><dt>Fehler</dt><dd>${esc(sheet.failureCategory)}</dd></div>` : ''}</dl>${sheet.state === 'ready' && !sheet.active ? '<button class="primary" id="activate-character">Als aktiv verwenden</button>' : ''}${sheet.state === 'ready' && sheet.assetId ? '<button class="secondary" id="refine-character">Mit neuen Fotos verfeinern</button>' : ''}${!sheet.active && ['ready', 'failed'].includes(sheet.state) ? '<button class="text-button" id="remove-character">Character Sheet löschen …</button>' : ''}`,
  );
  const image = $('#sheet img[data-asset]');
  if (image) {
    image.src = assetUrl(image.dataset.asset);
    wireFades($('#sheet'));
  }
  if ($('#activate-character'))
    $('#activate-character').onclick = (event) =>
      action(event.currentTarget, async () => {
        await api(`/character-sheets/${id}/activate`, { idempotencyKey: key() });
        await refreshInspiration();
        closeSheet();
        renderSettings();
        toast('Character Sheet aktiviert.');
      });
  if ($('#refine-character')) $('#refine-character').onclick = () => openCharacterRefine(id);
  if ($('#remove-character'))
    $('#remove-character').onclick = () => {
      showSheet(
        'Character Sheet löschen',
        '<h2>Version dauerhaft entfernen?</h2><p>Sie verschwindet aus deinen Einstellungen und kann nicht wieder aktiviert werden. Bereits erzeugte Looks und historische Kosten bleiben erhalten.</p><button class="danger" id="confirm-character-removal">Dauerhaft löschen</button><button class="text-button" id="cancel-character-removal">Abbrechen</button>',
      );
      $('#cancel-character-removal').onclick = () => openCharacterDetail(id);
      $('#confirm-character-removal').onclick = (event) =>
        action(event.currentTarget, async () => {
          await api(`/character-sheets/${id}`, {}, 'DELETE');
          await refreshInspiration();
          closeSheet();
          renderSettings();
          toast('Character Sheet gelöscht.');
        });
    };
}
async function uploadReferenceFile(file) {
  const blob = await preparePhoto(file);
  const intent = await api('/source-photos/upload-intents', {
    fileName: 'character-reference.jpg',
    contentType: 'image/jpeg',
    byteSize: blob.size,
  });
  await uploadPhoto(intent.uploadUrl, intent.headers, blob);
  const completed = await api('/source-photos/complete', {
    assetId: intent.assetId,
    idempotencyKey: key(),
  });
  return completed.asset.id;
}
function openCharacterSetup() {
  showSheet(
    'Character Sheet',
    `<h2>So erkennt FORM dich.</h2><p>Wähle ein bis vier klare Fotos von Gesicht und Körper. Ein kurzer Hinweis kann stabile Details ergänzen.</p><form id="character-form"><label>Referenzfotos<input type="file" name="photos" accept="image/*" multiple required></label><div id="character-upload-progress"></div><label>Hinweis <span class="muted">optional</span><textarea name="note" maxlength="1000" placeholder="Zum Beispiel Körpergröße oder Haarfarbe"></textarea></label><button class="primary" type="submit">Character Sheet erstellen</button></form>`,
  );
  $('#character-form').onsubmit = (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const files = [...form.elements.photos.files];
    if (files.length < 1 || files.length > 4)
      return formError(form, new Error('Bitte wähle ein bis vier Fotos.'));
    action($('button[type=submit]', form), async () => {
      try {
        const referenceAssetIds = [];
        for (const [index, file] of files.entries()) {
          renderCharacterUploadProgress(form, files, index);
          referenceAssetIds.push(await uploadReferenceFile(file));
        }
        renderCharacterUploadProgress(form, files, files.length);
        await api('/character-sheets', {
          referenceAssetIds,
          note: new FormData(form).get('note').trim() || null,
          idempotencyKey: key(),
        });
        await refreshInspiration();
        closeSheet();
        navigate('settings');
        toast('Dein Character Sheet wird erstellt.');
      } catch (error) {
        formError(form, error);
      }
    });
  };
}
function renderCharacterUploadProgress(form, files, completed) {
  const progress = $('#character-upload-progress', form);
  if (!progress) return;
  progress.innerHTML = `<div class="character-upload-progress" role="status" aria-live="polite"><strong>${completed === files.length ? 'Character Sheet wird vorbereitet' : 'Fotos werden hochgeladen'}</strong>${files
    .map((file, index) => {
      const state = index < completed ? 'done' : index === completed ? 'uploading' : 'waiting';
      const label =
        state === 'done' ? 'Hochgeladen' : state === 'uploading' ? 'Wird hochgeladen …' : 'Wartet';
      return `<div class="character-upload-file ${state}"><span class="character-upload-state" aria-hidden="true">${state === 'done' ? icon('check') : ''}</span><span>${esc(file.name)}</span><small>${label}</small></div>`;
    })
    .join('')}</div>`;
}
// Refining keeps the current sheet active; the result has to be activated by hand.
function openCharacterRefine(id) {
  showSheet(
    'Verfeinern',
    `<h2>Was passt noch nicht?</h2><p>Diese Version bleibt erhalten. FORM zeichnet sie mit deinen neuen Fotos neu und ändert nur, was du beschreibst.</p><form id="refine-form"><label>Neue Fotos <span class="muted">ein bis drei</span><input type="file" name="photos" accept="image/*" multiple required></label><label>Was soll sich ändern?<textarea name="instruction" maxlength="1000" required placeholder="Zum Beispiel: Die Rückansicht zeigt die falsche Frisur"></textarea></label><button class="primary" type="submit">Verfeinerung erstellen</button></form>`,
  );
  $('#refine-form').onsubmit = (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const files = [...form.elements.photos.files];
    if (files.length < 1 || files.length > 3)
      return formError(form, new Error('Bitte wähle ein bis drei Fotos.'));
    action($('button[type=submit]', form), async () => {
      try {
        const referenceAssetIds = [];
        for (const file of files) referenceAssetIds.push(await uploadReferenceFile(file));
        await api(`/character-sheets/${id}/refine`, {
          referenceAssetIds,
          instruction: new FormData(form).get('instruction').trim(),
          idempotencyKey: key(),
        });
        await refreshInspiration();
        closeSheet();
        navigate('settings');
        toast('Die Verfeinerung wird erstellt.');
      } catch (error) {
        formError(form, error);
      }
    });
  };
}
async function start() {
  const rawHash = location.hash.slice(1);
  const hash = ['owning', 'wanting'].includes(rawHash) ? 'wardrobe' : rawHash;
  if (['feed', 'wardrobe', 'add', 'settings', 'archived'].includes(hash)) page = hash;
  try {
    await Promise.all([refreshItems(), refreshInspiration()]);
    render();
  } catch (error) {
    shell(
      `<div class="empty">${icon('closet')}<h2>Dein Schrank wartet.</h2><p>${esc(error.message)}</p><button class="primary" id="retry">Erneut verbinden</button></div>`,
    );
    $('#retry').onclick = start;
  }
}
window.addEventListener('hashchange', () => {
  const next = location.hash.slice(1);
  if (['feed', 'wardrobe', 'add', 'settings', 'archived'].includes(next) && next !== page) {
    page = next;
    render();
  }
});
window.addEventListener('online', start);
window.addEventListener('offline', () => toast('Verbindung unterbrochen. Prüfe Tailscale.'));
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
// Baked into the web image at deploy time. Reload an open PWA when a new shell arrives.
async function refreshVersion() {
  try {
    const response = await fetch('/version.json', { cache: 'no-store' });
    const data = response.ok ? await response.json() : null;
    if (!data?.version) return;
    if (version && version !== data.version) return location.reload();
    version = data.version;
    if ($('#version')) $('#version').textContent = version;
  } catch {}
}
refreshVersion();
setInterval(refreshVersion, 30_000);
// A PWA spends most of its life in the background, where the interval is
// throttled. Checking on the way back in is what makes a deploy land promptly.
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) refreshVersion();
});
start();

let checking = false;
setInterval(async () => {
  if (checking || document.hidden || !navigator.onLine) return;
  checking = true;
  try {
    if (items.some((i) => ['queued', 'generating'].includes(i.status))) {
      const previous = JSON.stringify(items);
      await refreshItems();
      if (previous !== JSON.stringify(items)) {
        if (['wardrobe', 'archived'].includes(page)) renderResults();
        if (detailId && $('#check-generation'))
          await openDetail(detailId, 'view', { refresh: true });
      }
    }
    if (
      looks.some((look) => !['ready', 'failed'].includes(look.state)) ||
      characterSheets.some((sheet) => !['ready', 'failed'].includes(sheet.state))
    ) {
      const previous = JSON.stringify([looks, characterSheets]);
      await refreshInspiration();
      if (previous !== JSON.stringify([looks, characterSheets])) {
        if (page === 'feed') renderFeed();
        if (page === 'settings') renderSettings();
      }
    }
    if (page === 'add')
      for (const draft of drafts.filter((d) => d.phase === 'detecting')) {
        const result = await api(`/source-photos/${draft.sourcePhotoId}/detections`);
        if (['succeeded', 'failed'].includes(result.attempt?.state)) await checkDetection(draft);
      }
  } catch (error) {
    toast(error.message);
  } finally {
    checking = false;
  }
}, 10000);
