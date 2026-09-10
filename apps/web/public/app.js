const $ = (s, root = document) => root.querySelector(s);
const esc = (value) =>
  String(value ?? '').replace(
    /[&<>"']/g,
    (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[
        c
      ],
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
  photo:
    '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',
};
const icon = (name) =>
  `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.closet}</svg>`;
let items = [],
  page = 'owning',
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
  localStorage.setItem('form-photo-drafts', JSON.stringify(drafts));
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
    throw new Error(
      data?.error?.message ||
        `Die Anfrage ist fehlgeschlagen (${response.status}).`,
    );
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
      ['owning', 'closet', 'Schrank'],
      ['wanting', 'heart', 'Wunschliste'],
      ['add', 'plus', 'Hinzufügen'],
      ['settings', 'settings', 'Einstellungen'],
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
  renderWardrobe();
}
function renderWardrobe() {
  const collection = items.filter((i) => i.state === page);
  const title =
    page === 'wanting'
      ? 'Auf deiner Liste.'
      : page === 'archived'
        ? 'Gut aufgehoben.'
        : 'Dein Kleiderschrank.';
  shell(`<div class="hero"><div><p class="eyebrow">${page === 'owning' ? 'Weniger suchen. Lieber tragen.' : page === 'wanting' ? 'Für irgendwann.' : 'Dein Archiv'}</p><h1>${title}</h1><p class="muted">${collection.length} ${collection.length === 1 ? 'Stück' : 'Stücke'}${page === 'owning' ? ', die zu dir gehören.' : ' gesammelt.'}</p></div><button class="round" id="add" aria-label="Kleidung hinzufügen">${icon('plus')}</button></div>
  <div class="search">${icon('search')}<input type="search" id="search" aria-label="Kleiderschrank durchsuchen" placeholder="Finde dein Lieblingsstück" value="${esc(query)}"></div>
  <div class="filters" aria-label="Kategorien">${[['all', 'Alle'], ...Object.entries(categories).filter(([c]) => collection.some((i) => i.metadata.category === c))].map(([c, label]) => `<button class="chip ${category === c ? 'active' : ''}" data-cat="${c}" aria-pressed="${category === c}">${label}</button>`).join('')}</div><div id="results"></div>`);
  $('#add').onclick = () => navigate('add');
  $('#search').oninput = (e) => {
    query = e.target.value;
    renderResults();
  };
  document.querySelectorAll('[data-cat]').forEach(
    (b) =>
      (b.onclick = () => {
        category = b.dataset.cat;
        document.querySelectorAll('[data-cat]').forEach((c) => {
          c.classList.toggle('active', c.dataset.cat === category);
          c.setAttribute('aria-pressed', String(c.dataset.cat === category));
        });
        renderResults();
      }),
  );
  renderResults();
}
function renderItemPhoto(item) {
  if (['queued', 'generating'].includes(item.status))
    return `<div class="photo"><div class="wardrobe-image-progress" role="status" aria-label="Katalogbild für ${esc(item.metadata.name)} wird erstellt"><span class="spinner"></span><span>Bild wird erstellt</span></div></div>`;
  return `<div class="photo"><img src="${preview(item)}" alt="${esc(item.metadata.name)}" loading="lazy" decoding="async"><img class="photo-source" data-source="${sourcePreview(item)}" alt="" aria-hidden="true" loading="lazy" decoding="async">${item.status === 'failed' ? '<span class="badge">Bild fehlgeschlagen</span>' : ''}</div>`;
}
function renderResults() {
  const list = items.filter(
    (i) =>
      i.state === page &&
      (category === 'all' || i.metadata.category === category) &&
      `${i.metadata.name} ${i.metadata.colors.join(' ')} ${i.metadata.notes || ''} ${categories[i.metadata.category]}`
        .toLocaleLowerCase()
        .includes(query.toLocaleLowerCase()),
  );
  $('#results').innerHTML = list.length
    ? `<div class="section-row"><span>${list.length} ${list.length === 1 ? 'Stück' : 'Stücke'}</span><span>Zuletzt hinzugefügt</span></div><div class="grid">${list.map((i) => `<button class="item" data-item="${i.id}">${renderItemPhoto(i)}<span class="item-name">${esc(i.metadata.name)}</span><span class="item-category">${categories[i.metadata.category]} · ${esc(i.metadata.colors.join(', '))}</span></button>`).join('')}</div>`
    : `<div class="empty">${icon('closet')}<h2>${query || category !== 'all' ? 'Noch nicht gefunden.' : 'Platz für deine Stücke.'}</h2><p>${query || category !== 'all' ? 'Versuche einen anderen Suchbegriff oder eine andere Kategorie.' : 'Fang mit ein paar Lieblingsstücken an. Ein Foto reicht, den Rest kannst du später ergänzen.'}</p>${!query && category === 'all' ? '<button class="primary" id="empty-add">Erstes Stück hinzufügen</button>' : ''}</div>`;
  document.querySelectorAll('[data-item]').forEach((b) => {
    b.onclick = () => openDetail(b.dataset.item);
    // Fade to the original upload on hover. Load it only on first hover to keep
    // the grid light, and drop the layer if the source photo is gone.
    const source = $('.photo-source', b);
    if (!source) return;
    source.onerror = () => source.remove();
    b.addEventListener(
      'mouseenter',
      () => {
        if (!source.src) source.src = source.dataset.source;
      },
      { once: true },
    );
  });
  if ($('#empty-add')) $('#empty-add').onclick = () => navigate('add');
}
async function refreshItems() {
  const data = await api('/wardrobe-items');
  items = data.wardrobeItems.sort((a, b) =>
    b.createdAt.localeCompare(a.createdAt),
  );
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
  if (
    colors.length < 1 ||
    colors.length > 6 ||
    colors.some((c) => c.length > 32)
  )
    throw new Error(
      'Bitte gib 1 bis 6 Farben mit jeweils maximal 32 Zeichen an.',
    );
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
// top of the sheet on every tick.
function showSheet(title, content, keepScroll = false) {
  detailId = null;
  const offset = $('#sheet').scrollTop;
  $('#sheet').innerHTML =
    `<div class="sheet-head"><h2 id="sheet-title">${esc(title)}</h2><button class="close" id="close-sheet" aria-label="Schließen">${icon('close')}</button></div><div class="sheet-body">${content}</div>`;
  $('#close-sheet').onclick = closeSheet;
  if (!$('#sheet').open) {
    $('#sheet').showModal();
    document.body.style.overflow = 'hidden';
  }
  $('#sheet').scrollTop = keepScroll ? offset : 0;
}
function closeSheet() {
  $('#sheet').close();
  detailId = null;
  document.body.style.overflow = '';
}
$('#sheet').addEventListener('close', () => {
  detailId = null;
  document.body.style.overflow = '';
});
async function assetUrl(id) {
  return (await api(`/assets/${id}/download`)).downloadUrl;
}
// The sheet has two states: 'view' shows the piece read-only, 'edit' shows only
// the metadata form. Both need the same detail payload and command handlers.
async function openDetail(id, mode = 'view', refresh = false) {
  if (!refresh)
    showSheet(
      mode === 'edit' ? 'Stück bearbeiten' : 'Dein Stück',
      '<div class="loading"><span class="spinner"></span> Wird geladen …</div>',
    );
  detailId = id;
  try {
    const detail = await api(`/wardrobe-items/${id}`);
    if (detailId !== id || !$('#sheet').open) return;
    const i = detail.wardrobeItem;
    const running = detail.generationAttempts.some((a) =>
      ['queued', 'processing'].includes(a.state),
    );
    const failed = detail.generationAttempts[0]?.state === 'failed';
    const primarySlide = running
      ? `<figure class="slide"><div class="wardrobe-image-progress" role="status" aria-label="Katalogbild für ${esc(i.metadata.name)} wird erstellt"><span class="spinner"></span><span>Bild wird erstellt</span></div></figure>`
      : `<figure class="slide"><img src="${preview(i)}" alt="${esc(i.metadata.name)}"></figure>`;
    const collections = {
      owning: 'Mein Schrank',
      wanting: 'Wunschliste',
      archived: 'Archiv',
    };
    // Leftmost is the plus tile, then the image in use, then the older ones
    // newest first, and the original photo closes the row on the right.
    const ordered = [...detail.shelfImageVersions].sort(
      (left, right) =>
        (right.id === i.currentShelfImageVersionId) -
        (left.id === i.currentShelfImageVersionId),
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
    <div class="rule"></div>${running ? '<div class="note generating"><p><span class="spinner"></span>Dein Bild wird erstellt. Du kannst weiter durch deinen Schrank stöbern.</p><button class="text-button" id="check-generation">Status aktualisieren</button></div>' : `<h3>Katalogbilder</h3><p class="muted">${failed ? 'Der letzte Versuch ist fehlgeschlagen. ' : ''}Ein neues Bild wird automatisch verwendet, ein älteres kannst du jederzeit wieder auswählen.</p><div class="versions"><button class="version add-version" id="generate" aria-label="Katalogbild erstellen …"><span class="version-frame">${icon('plus')}</span><span>Neues Bild …</span></button>${versionTiles}<button class="version source-version" id="source"><span class="version-frame"><img id="source-tile" src="${sourcePreview(i)}" alt="" aria-hidden="true"></span><span>Originalfoto ansehen</span></button></div>`}
    <div class="rule"></div><div class="stack"><button class="secondary" id="archive">${i.state === 'archived' ? 'Zurück in den Schrank' : 'Ins Archiv legen'}</button><button class="text-button" id="delete">Stück endgültig löschen …</button></div>`;
    showSheet(
      mode === 'edit' ? 'Stück bearbeiten' : 'Dein Stück',
      `<div class="gallery">${primarySlide}<figure class="slide worn"><img id="worn" src="${sourcePreview(i)}" alt="${esc(i.metadata.name)}, getragen"><figcaption>Originalfoto</figcaption></figure></div><p class="eyebrow">${categories[i.metadata.category]}</p><h2>${esc(i.metadata.name)}</h2><p class="muted item-colors">${esc(i.metadata.colors.join(' · '))}</p>${body}`,
      refresh,
    );
    detailId = id;
    // Drop the worn photo and the source tile when the original upload is gone.
    if ($('#worn'))
      $('#worn').onerror = () => $('#worn').closest('.slide').remove();
    if ($('#source-tile'))
      $('#source-tile').onerror = () => $('#source').remove();
    const command = () => ({
      expectedRecordVersion: i.recordVersion,
      idempotencyKey: key(),
    });
    if ($('#edit-details'))
      $('#edit-details').onclick = () => openDetail(id, 'edit');
    if ($('#cancel-edit')) $('#cancel-edit').onclick = () => openDetail(id);
    if ($('#edit-item'))
      $('#edit-item').onsubmit = async (e) => {
        e.preventDefault();
        const form = e.currentTarget;
        await action($('button[type=submit]', form), async () => {
          try {
            await api(
              `/wardrobe-items/${id}`,
              { ...readFields(form), ...command() },
              'PATCH',
            );
            await refreshItems();
            render();
            closeSheet();
            toast('Änderungen gespeichert');
          } catch (error) {
            formError(form, error);
          }
        });
      };
    if ($('#check-generation'))
      $('#check-generation').onclick = () => openDetail(id);
    if ($('#generate'))
      $('#generate').onclick = () => {
        showSheet(
          'Katalogbild erstellen',
          `<h2>Nur für dieses Stück.</h2><p>Das neue Katalogbild wird automatisch verwendet. Ein älteres Bild kannst du jederzeit wieder auswählen.</p><div class="note">Die Ausgabe kostet zusätzlich zum Eingabebild und Text. Abgerechnet wird nach tatsächlichem Verbrauch. In hoher Qualität liegt ein Bild nach aktueller Tarifrechnung bei etwa 12 US-Cent. Das ist eine Orientierung, kein garantierter Festpreis.</div><p class="muted" style="margin:16px 0">GPT Image 2 · High · ein neues Bild</p><button class="primary" id="confirm-generate">Ein kostenpflichtiges Bild anfordern</button><button class="text-button" id="cancel-generate">Abbrechen</button>`,
        );
        $('#cancel-generate').onclick = () => openDetail(id);
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
      $('#source').onclick = (e) =>
        action(e.currentTarget, async () => {
          const url = await assetUrl(detail.sourcePhoto.assetId);
          showSheet(
            'Originalfoto',
            `<div class="detail-photo"><img src="${esc(url)}" alt="Originalfoto"></div><button class="secondary" id="back-detail">Zurück zum Stück</button>`,
          );
          $('#back-detail').onclick = () => openDetail(id);
        });
    document.querySelectorAll('[data-asset]').forEach((img) =>
      assetUrl(img.dataset.asset)
        .then((url) => {
          if (img.isConnected) img.src = url;
        })
        .catch(() => {}),
    );
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
          toast(
            i.state === 'archived' ? 'Zurück im Schrank' : 'Im Archiv abgelegt',
          );
        });
    if ($('#delete'))
      $('#delete').onclick = () => {
        showSheet(
          'Stück löschen',
          `<h2>Endgültig löschen?</h2><p>„${esc(i.metadata.name)}“ und seine Katalogbilder werden gelöscht. Das lässt sich nicht rückgängig machen.</p><button class="danger" id="confirm-delete">Stück endgültig löschen</button><button class="text-button" id="cancel-delete">Behalten</button>`,
        );
        $('#cancel-delete').onclick = () => openDetail(id);
        $('#confirm-delete').onclick = (e) =>
          action(e.currentTarget, async () => {
            await api(`/wardrobe-items/${id}`, command(), 'DELETE');
            await refreshItems();
            render();
            closeSheet();
            toast('Stück gelöscht');
          });
      };
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
    const scale = Math.min(
      1,
      2400 / Math.max(image.naturalWidth, image.naturalHeight),
    );
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(image.naturalWidth * scale);
    canvas.height = Math.round(image.naturalHeight * scale);
    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) =>
      canvas.toBlob(resolve, 'image/jpeg', 0.92),
    );
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
      failure = new Error(
        detail || `Upload fehlgeschlagen (${response.status}).`,
      );
    } catch {
      failure = new Error('Upload-Verbindung unterbrochen.');
    }
    if (attempt === 0) await new Promise((resolve) => setTimeout(resolve, 300));
  }
  throw failure;
}
function renderAdd() {
  shell(
    `<p class="eyebrow">Stück für Stück</p><h1>${drafts.length ? 'Wähle deine Stücke.' : 'Foto rein.<br>Schrank fertig.'}</h1><p class="muted">Wir erkennen deine Kleidung, du wählst aus, was in den Schrank kommt.</p><div class="upload-area ${drafts.length ? 'compact-upload' : ''}">${drafts.length ? '' : `${icon('camera')}<h2>Alles auf ein Foto.</h2><p>Ein einzelnes Stück oder ein ganzes Outfit. Ein ruhiger Hintergrund hilft bei der Erkennung.</p>`}<div class="stack"><button class="primary" id="camera" ${importBusy ? 'disabled' : ''}>${icon('camera')} Foto aufnehmen</button><button class="secondary" id="library" ${importBusy ? 'disabled' : ''}>${icon('photo')} Fotos auswählen</button></div><input hidden type="file" id="camera-input" accept="image/*" capture="environment"><input hidden type="file" id="library-input" accept="image/*" multiple></div><p class="note">Analyse und Katalogbilder werden automatisch mit OpenAI erstellt und sind kostenpflichtig. Nach deiner Auswahl läuft alles im Hintergrund weiter.</p><div id="import-progress" role="status" aria-live="polite">${importBusy ? '<div class="loading"><span class="spinner"></span> Fotos werden hochgeladen …</div>' : ''}</div><div id="drafts"></div>`,
  );
  $('#camera').onclick = () => $('#camera-input').click();
  $('#library').onclick = () => $('#library-input').click();
  for (const id of ['camera-input', 'library-input'])
    $(`#${id}`).onchange = (e) => importPhotos([...e.target.files]);
  renderDrafts();
  for (const draft of drafts.filter((item) => item.phase === 'uploaded'))
    startDetection(draft);
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
    if ($('#import-progress'))
      $('#import-progress').innerHTML =
        `<div class="loading"><span class="spinner"></span> Foto ${n + 1} von ${files.length} …</div>`;
    try {
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
      drafts.push({
        id: key(),
        sourcePhotoId: completed.sourcePhoto.id,
        assetId: completed.asset.id,
        phase: 'uploaded',
      });
      persistDrafts();
      const draft = drafts.at(-1);
      if (draft) await startDetection(draft);
    } catch (error) {
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
  document.querySelectorAll('[data-draft-asset]').forEach((img) =>
    assetUrl(img.dataset.draftAsset)
      .then((url) => {
        if (img.isConnected) img.src = url;
      })
      .catch(() => {}),
  );
  document.querySelectorAll('[data-choice-preview]').forEach((canvas) => {
    const draft = drafts.find((item) => item.id === canvas.dataset.draft);
    const proposal = draft?.detections?.find(
      (item) => item.id === canvas.dataset.choicePreview,
    );
    if (!draft || !proposal) return;
    assetUrl(draft.assetId)
      .then((url) => drawDetectionPreview(canvas, url, proposal.boundingBox))
      .catch(() => {});
  });
  document.querySelectorAll('[data-toggle-piece]').forEach((button) => {
    button.onclick = () => {
      const draft = drafts.find((item) => item.id === button.dataset.draft);
      const proposal = draft?.detections?.find(
        (item) => item.id === button.dataset.togglePiece,
      );
      if (!proposal || draft.phase === 'importing') return;
      proposal.selected = !proposal.selected;
      persistDrafts();
      renderDrafts();
    };
  });
  document.querySelectorAll('[data-import-detected]').forEach((button) => {
    button.onclick = () => {
      const draft = drafts.find(
        (item) => item.id === button.dataset.importDetected,
      );
      if (draft) action(button, () => importDetected(draft));
    };
  });
  document.querySelectorAll('[data-manual-save]').forEach((form) => {
    form.onsubmit = (event) => {
      event.preventDefault();
      const draft = drafts.find((item) => item.id === form.dataset.manualSave);
      if (draft)
        action($('button[type=submit]', form), () =>
          importManual(draft, form),
        );
    };
  });
  document.querySelectorAll('[data-discard]').forEach(
    (b) =>
      (b.onclick = () => {
        drafts = drafts.filter((d) => d.id !== b.dataset.discard);
        persistDrafts();
        renderDrafts();
      }),
  );
}
function renderDetectionDraft(draft) {
  const discard = `<button class="close" data-discard="${draft.id}" aria-label="Foto verwerfen">${icon('close')}</button>`;
  if (draft.phase === 'manual') {
    return `<article class="draft" data-draft="${draft.id}"><div class="draft-head"><div><h3>Selbst hinzufügen</h3><p class="draft-status">${esc(draft.failure || 'Auf diesem Foto wurde kein Stück erkannt.')}</p></div>${discard}</div><img data-draft-asset="${draft.assetId}" alt="Hochgeladenes Foto"><form data-manual-save="${draft.id}">${fields(draft.metadata, 'owning')}<button class="primary" style="margin-top:18px" type="submit">Stück hinzufügen</button></form></article>`;
  }
  const detections = (draft.detections || []).filter((item) => !item.imported);
  const selected = detections.filter((item) => item.selected && !item.imported);
  const overlays = detections
    .map(
      (item, index) =>
        `<button class="detection-box ${item.selected ? 'selected' : ''}" data-draft="${draft.id}" data-toggle-piece="${item.id}" aria-label="${esc(item.name)} ${item.selected ? 'abwählen' : 'auswählen'}" aria-pressed="${item.selected}" style="left:${item.boundingBox.x / 10}%;top:${item.boundingBox.y / 10}%;width:${item.boundingBox.width / 10}%;height:${item.boundingBox.height / 10}%"><span>${index + 1}</span></button>`,
    )
    .join('');
  const choices = detections
    .map(
      (item, index) =>
        `<button class="detection-choice ${item.selected ? 'selected' : ''}" data-draft="${draft.id}" data-toggle-piece="${item.id}" aria-pressed="${item.selected}"><canvas class="choice-preview" data-draft="${draft.id}" data-choice-preview="${item.id}" width="112" height="112" aria-hidden="true"></canvas><span class="choice-copy"><strong>${esc(item.name)}</strong><small>${esc(categories[item.category])} · ${esc(item.colors.join(', '))}</small></span><span class="choice-number">${item.selected ? icon('check') : index + 1}</span></button>`,
    )
    .join('');
  const busy = ['uploaded', 'detecting'].includes(draft.phase);
  return `<article class="draft scan-card" data-draft="${draft.id}"><div class="draft-head"><div><h3>${busy ? 'Foto wird analysiert' : `${detections.length} ${detections.length === 1 ? 'Stück erkannt' : 'Stücke erkannt'}`}</h3><p class="draft-status">${busy ? 'Du kannst die App dabei geöffnet lassen oder später wiederkommen.' : 'Tippe auf die Rahmen, um deine Auswahl zu ändern.'}</p></div>${discard}</div><div class="detection-stage"><img data-draft-asset="${draft.assetId}" alt="Hochgeladenes Foto">${busy ? '<div class="scan-progress"><span class="spinner"></span><span>Kleidung wird erkannt …</span></div>' : overlays}</div>${busy ? '' : `<div class="detection-choices">${choices}</div><button class="primary" data-import-detected="${draft.id}" ${selected.length || draft.phase === 'importing' ? '' : 'disabled'}>${draft.phase === 'importing' ? '<span class="spinner"></span> Wird hinzugefügt …' : `${selected.length} ${selected.length === 1 ? 'Stück' : 'Stücke'} hinzufügen`}</button>`}</article>`;
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
  const scale = Math.min(
    canvas.width / sourceWidth,
    canvas.height / sourceHeight,
  );
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
function scheduleDetectionCheck(draft) {
  if (detectionPolls.has(draft.id)) return;
  detectionPolls.add(draft.id);
  setTimeout(async () => {
    detectionPolls.delete(draft.id);
    if (!drafts.some((item) => item.id === draft.id) || draft.phase !== 'detecting')
      return;
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
  const supported = data.detections.filter(
    (proposal) => proposal.category !== 'unsupported',
  );
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
  }));
  persistDrafts();
  renderDrafts();
  toast(
    `${supported.length} ${supported.length === 1 ? 'Stück erkannt' : 'Stücke erkannt'}.`,
  );
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
  const selected = draft.detections.filter(
    (proposal) => proposal.selected && !proposal.imported,
  );
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
        state: 'owning',
        idempotencyKey: proposal.itemKey,
      });
      await enqueueAutomaticImage(
        result.wardrobeItem.id,
        proposal.generationKey,
      );
      proposal.imported = true;
      persistDrafts();
    }
    drafts = drafts.filter((item) => item.id !== draft.id);
    persistDrafts();
    await refreshItems();
    if (drafts.length) renderAdd();
    else navigate('owning');
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
    else navigate('owning');
    toast('Dein Stück wird für den Schrank vorbereitet.');
  } catch (error) {
    draft.phase = 'manual';
    persistDrafts();
    formError(form, error);
  }
}
function renderSettings() {
  shell(
    `<p class="eyebrow">So, wie du es brauchst</p><h1>Ganz dein Ding.</h1><p class="muted">Dein privater Kleiderschrank auf stargate.</p><section class="panel"><h3>Auf deinem iPhone</h3><p>Öffne FORM in Safari. Tippe auf Teilen und dann auf „Zum Home-Bildschirm“. So öffnet sich dein Schrank wie eine App.</p><div class="setting-row">Zugang<span>Privat über Tailscale</span></div><div class="setting-row">Anmeldung<span>Kein Passwort nötig</span></div><div class="setting-row">Speicherort<span>Dein Server</span></div></section><section class="panel"><h3>Automatische Katalogbilder</h3><p>Beim Hinzufügen analysiert OpenAI dein Foto und erstellt für jedes ausgewählte Stück automatisch ein Katalogbild. Beides ist kostenpflichtig. Die Bildgenerierung läuft in sparsamer Qualität.</p><p>Weitere Katalogbilder startest du in der Detailansicht weiterhin einzeln. Dort siehst du auch die erfassten Kosten.</p><a class="text-button" href="https://developers.openai.com/api/docs/pricing" target="_blank" rel="noreferrer">Aktuelle OpenAI-Preise ↗</a></section><button class="secondary" id="open-archive">Archiv öffnen · ${items.filter((i) => i.state === 'archived').length} Stücke</button><section class="panel"><h3>Noch einmal von vorn</h3><p>Leert den gemeinsamen privaten Kleiderschrank auf allen deinen Geräten. Kleidung, Fotos und Bildverläufe werden dauerhaft gelöscht.</p><button class="danger" id="reset">Kleiderschrank leeren …</button></section><p class="muted" style="text-align:center;font-size:11px">FORM · Persönliche Web-Version</p>`,
  );
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
          await refreshItems();
          closeSheet();
          navigate('owning');
          toast('Dein Schrank ist wieder leer');
        } catch (error) {
          formError(form, error);
        }
      });
    };
  };
}
async function start() {
  const hash = location.hash.slice(1);
  if (['owning', 'wanting', 'add', 'settings', 'archived'].includes(hash))
    page = hash;
  try {
    await refreshItems();
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
  if (
    ['owning', 'wanting', 'add', 'settings', 'archived'].includes(next) &&
    next !== page
  ) {
    page = next;
    render();
  }
});
window.addEventListener('online', start);
window.addEventListener('offline', () =>
  toast('Verbindung unterbrochen. Prüfe Tailscale.'),
);
if ('serviceWorker' in navigator)
  navigator.serviceWorker.register('/sw.js').catch(() => {});
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
setInterval(refreshVersion, 60_000);
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
        if (['owning', 'wanting', 'archived'].includes(page)) renderResults();
        if (detailId && $('#check-generation'))
          await openDetail(detailId, 'view', true);
      }
    }
    if (page === 'add')
      for (const draft of drafts.filter((d) => d.phase === 'detecting')) {
        const result = await api(
          `/source-photos/${draft.sourcePhotoId}/detections`,
        );
        if (['succeeded', 'failed'].includes(result.attempt?.state))
          await checkDetection(draft);
      }
  } catch (error) {
    toast(error.message);
  } finally {
    checking = false;
  }
}, 10000);
