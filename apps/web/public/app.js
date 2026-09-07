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
    '<circle cx="12" cy="12" r="3"/><path d="m9 3-1 3-3 1-2 3 2 3v4l3 2 3-1 3 1 3-2v-4l2-3-2-3-3-1-1-3Z"/>',
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
  toastTimer;
let drafts;
try {
  drafts = JSON.parse(localStorage.getItem('form-photo-drafts') || '[]');
} catch {
  drafts = [];
}
const persistDrafts = () =>
  localStorage.setItem('form-photo-drafts', JSON.stringify(drafts));
const preview = (item) =>
  `/v1/wardrobe-items/${encodeURIComponent(item.id)}/preview?v=${item.recordVersion}`;
const key = () => crypto.randomUUID();
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
    `<main class="shell"><header class="masthead"><span class="wordmark">FORM</span><span class="private"><span class="dot"></span> NUR FÜR DICH</span></header>${!navigator.onLine ? '<p class="offline">Du bist offline. Verbinde dich mit stargate, um deinen Kleiderschrank zu öffnen.</p>' : ''}${content}</main><nav class="nav" aria-label="Hauptnavigation">${[
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
    ? `<div class="section-row"><span>${list.length} ${list.length === 1 ? 'Stück' : 'Stücke'}</span><span>Zuletzt hinzugefügt</span></div><div class="grid">${list.map((i) => `<button class="item" data-item="${i.id}"><div class="photo"><img src="${preview(i)}" alt="${esc(i.metadata.name)}" loading="lazy" decoding="async">${['needs-review', 'queued', 'generating', 'failed'].includes(i.status) ? `<span class="badge">${{ 'needs-review': 'Bildentwurf ansehen', queued: 'Bild in Arbeit', generating: 'Bild in Arbeit', failed: 'Bild fehlgeschlagen' }[i.status]}</span>` : ''}</div><span class="item-name">${esc(i.metadata.name)}</span><span class="item-category">${categories[i.metadata.category]} · ${esc(i.metadata.colors.join(', '))}</span></button>`).join('')}</div>`
    : `<div class="empty">${icon('closet')}<h2>${query || category !== 'all' ? 'Noch nicht gefunden.' : 'Platz für deine Stücke.'}</h2><p>${query || category !== 'all' ? 'Versuche einen anderen Suchbegriff oder eine andere Kategorie.' : 'Fang mit ein paar Lieblingsstücken an. Ein Foto reicht, den Rest kannst du später ergänzen.'}</p>${!query && category === 'all' ? '<button class="primary" id="empty-add">Erstes Stück hinzufügen</button>' : ''}</div>`;
  document
    .querySelectorAll('[data-item]')
    .forEach((b) => (b.onclick = () => openDetail(b.dataset.item)));
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
function showSheet(title, content) {
  detailId = null;
  $('#sheet').innerHTML =
    `<div class="sheet-head"><h2 id="sheet-title">${esc(title)}</h2><button class="close" id="close-sheet" aria-label="Schließen">${icon('close')}</button></div><div class="sheet-body">${content}</div>`;
  $('#close-sheet').onclick = closeSheet;
  if (!$('#sheet').open) {
    $('#sheet').showModal();
    document.body.style.overflow = 'hidden';
  }
  $('#sheet').scrollTop = 0;
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
async function openDetail(id) {
  showSheet(
    'Dein Stück',
    '<div class="loading"><span class="spinner"></span> Wird geladen …</div>',
  );
  detailId = id;
  try {
    const detail = await api(`/wardrobe-items/${id}`);
    if (detailId !== id || !$('#sheet').open) return;
    const i = detail.wardrobeItem;
    const pending = detail.generationAttempts.find(
      (a) => a.state === 'needs-review',
    );
    const running = detail.generationAttempts.some((a) =>
      ['queued', 'processing'].includes(a.state),
    );
    const failed = detail.generationAttempts[0]?.state === 'failed';
    showSheet(
      'Dein Stück',
      `<div class="detail-photo"><img src="${preview(i)}" alt="${esc(i.metadata.name)}"></div><p class="eyebrow">${categories[i.metadata.category]}</p><h2>${esc(i.metadata.name)}</h2><form id="edit-item">${fields(i.metadata, i.state)}<button class="primary" style="margin-top:20px" type="submit">Änderungen speichern</button></form>
    <div class="rule"></div>${pending ? `<h3>Dein Bildentwurf</h3><p class="muted">Vergleiche den Entwurf mit deinem Foto. Du entscheidest, welches Bild im Schrank erscheint.</p><div class="detail-photo" style="margin-top:15px"><img id="candidate" alt="Neuer Bildentwurf"></div><p class="cost">${pending.costBreakdown && pending.costBreakdown.totalMicrounits > 10 ? `Erfasste Bildkosten: ${money(pending.costMicrounits)}` : 'Alter Kosteneintrag mit ungültigen Tarifen. Kein verlässlicher Preis.'}</p><div class="inline"><button class="secondary" id="reject">Verwerfen</button><button class="primary" id="keep">Bild verwenden</button></div>` : running ? '<div class="note"><span class="spinner"></span> Dein Bild wird erstellt. Du kannst weiter durch deinen Schrank stöbern.<button class="text-button" id="check-generation">Status aktualisieren</button></div>' : `<h3>Ein ruhigeres Katalogbild</h3><p class="muted">${failed ? 'Der letzte Versuch ist fehlgeschlagen. Dein Foto bleibt erhalten. ' : ''}Optional lässt du dein Stück einzeln aufbereiten. Der genaue Preis hängt von den verarbeiteten Bild- und Texttokens ab.</p><button class="secondary" id="generate" style="margin-top:15px">Katalogbild erstellen …</button>`}
    <button class="text-button" id="source">Originalfoto ansehen</button>${detail.shelfImageVersions.length ? `<div class="rule"></div><h3>Gespeicherte Bilder</h3><div class="versions">${detail.shelfImageVersions.map((v) => `<button class="version" data-version="${v.id}" ${v.id === i.currentShelfImageVersionId ? 'disabled' : ''}><img data-asset="${v.transparentAssetId}" alt="Gespeichertes Katalogbild"><span>${v.id === i.currentShelfImageVersionId ? 'Aktuelles Bild' : 'Dieses Bild verwenden'}</span></button>`).join('')}</div><button class="text-button" id="use-original">Originalfoto im Schrank verwenden</button>` : ''}<div class="rule"></div><div class="stack"><button class="secondary" id="archive">${i.state === 'archived' ? 'Zurück in den Schrank' : 'Ins Archiv legen'}</button><button class="text-button" id="delete">Stück endgültig löschen …</button></div>`,
    );
    detailId = id;
    const command = () => ({
      expectedRecordVersion: i.recordVersion,
      idempotencyKey: key(),
    });
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
    if (pending) {
      assetUrl(pending.transparentAssetId || pending.keyedAssetId)
        .then((url) => {
          if (detailId === id && $('#candidate')) $('#candidate').src = url;
        })
        .catch((e) => toast(e.message));
      for (const [button, endpoint] of [
        ['keep', 'shelf-image-versions/keep'],
        ['reject', 'generations/reject'],
      ])
        $(`#${button}`).onclick = (e) =>
          action(e.currentTarget, async () => {
            await api(`/wardrobe-items/${id}/${endpoint}`, {
              generationAttemptId: pending.id,
              ...command(),
            });
            await refreshItems();
            render();
            await openDetail(id);
          });
    }
    if ($('#check-generation'))
      $('#check-generation').onclick = () => openDetail(id);
    if ($('#generate'))
      $('#generate').onclick = () => {
        showSheet(
          'Katalogbild erstellen',
          `<h2>Nur für dieses Stück.</h2><p>Ein Bild in sparsamer Qualität mit 816 × 816 Pixeln. Es wird erst nach deiner Prüfung verwendet.</p><div class="note">Die Ausgabe kostet zusätzlich zum Eingabebild und Text. Abgerechnet wird nach tatsächlichem Verbrauch. Bisherige Bilder lagen nach aktueller Tarifrechnung bei etwa 1,1–1,9 US-Cent. Das ist eine Orientierung, kein garantierter Festpreis. Dein normales Foto kostet keine KI-Gebühr.</div><p class="muted" style="margin:16px 0">GPT Image 2 · Low · keine automatische Bildserie</p><button class="primary" id="confirm-generate">Ein kostenpflichtiges Bild anfordern</button><button class="text-button" id="cancel-generate">Bei meinem Foto bleiben</button>`,
        );
        $('#cancel-generate').onclick = () => openDetail(id);
        const generationKey = key();
        $('#confirm-generate').onclick = (e) =>
          action(e.currentTarget, async () => {
            await api('/generations', {
              wardrobeItemId: id,
              quality: 'low',
              size: '816x816',
              idempotencyKey: generationKey,
            });
            await refreshItems();
            render();
            await openDetail(id);
            toast('Dein Bild wird erstellt');
          });
      };
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
    if ($('#use-original'))
      $('#use-original').onclick = (e) =>
        action(e.currentTarget, async () => {
          await api(
            `/wardrobe-items/${id}`,
            { currentShelfImageVersionId: null, ...command() },
            'PATCH',
          );
          await refreshItems();
          render();
          await openDetail(id);
        });
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
    const scale = Math.min(
      1,
      1800 / Math.max(image.naturalWidth, image.naturalHeight),
    );
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(image.naturalWidth * scale);
    canvas.height = Math.round(image.naturalHeight * scale);
    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) =>
      canvas.toBlob(resolve, 'image/jpeg', 0.88),
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
function renderAdd() {
  shell(
    `<p class="eyebrow">Stück für Stück</p><h1>${drafts.length ? 'Deine neuen Stücke.' : 'Mach Platz für<br>deine Lieblinge.'}</h1><p class="muted">Fotografieren. Kurz benennen. Im Schrank haben.</p><div class="upload-area ${drafts.length ? 'compact-upload' : ''}">${drafts.length ? '' : `${icon('camera')}<h2>Ein Foto reicht.</h2><p>Am besten ein Kleidungsstück pro Foto, auf einem ruhigen Hintergrund.</p>`}<div class="stack"><button class="primary" id="camera" ${importBusy ? 'disabled' : ''}>${icon('camera')} Foto aufnehmen</button><button class="secondary" id="library" ${importBusy ? 'disabled' : ''}>${icon('photo')} Fotos auswählen</button></div><input hidden type="file" id="camera-input" accept="image/*" capture="environment"><input hidden type="file" id="library-input" accept="image/*" multiple></div><p class="note">Foto-Import ohne KI-Kosten. Du kannst mehrere Fotos auf einmal auswählen. Katalogbilder erstellst du später nur für die Stücke, bei denen du sie möchtest.</p><div id="import-progress" role="status" aria-live="polite">${importBusy ? '<div class="loading"><span class="spinner"></span> Fotos werden hochgeladen …</div>' : ''}</div><div id="drafts"></div>`,
  );
  $('#camera').onclick = () => $('#camera-input').click();
  $('#library').onclick = () => $('#library-input').click();
  for (const id of ['camera-input', 'library-input'])
    $(`#${id}`).onchange = (e) => importPhotos([...e.target.files]);
  renderDrafts();
}
async function importPhotos(files) {
  if (importBusy || !files.length) return;
  importBusy = true;
  renderAdd();
  let failed = 0;
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
      const response = await fetch(intent.uploadUrl, {
        method: 'PUT',
        headers: intent.headers,
        body: blob,
      });
      if (!response.ok)
        throw new Error(
          'Upload fehlgeschlagen. Bitte wähle das Foto noch einmal aus.',
        );
      const completed = await api('/source-photos/complete', {
        assetId: intent.assetId,
        idempotencyKey: key(),
      });
      drafts.push({
        id: key(),
        sourcePhotoId: completed.sourcePhoto.id,
        assetId: completed.asset.id,
        metadata: { name: '', category: 'top', colors: [], notes: null },
        state: 'owning',
      });
      persistDrafts();
      if ($('#drafts')) renderDrafts();
    } catch (error) {
      failed++;
      toast(`${files[n].name}: ${error.message}`);
    }
  }
  importBusy = false;
  if (page === 'add') renderAdd();
  toast(
    failed
      ? `${files.length - failed} hochgeladen, ${failed} fehlgeschlagen. Fehlende Fotos bitte erneut auswählen.`
      : `${files.length} ${files.length === 1 ? 'Foto bereit' : 'Fotos bereit'}. Ergänze die Namen.`,
  );
}
function renderDrafts() {
  if (!$('#drafts')) return;
  $('#drafts').innerHTML = drafts.length
    ? `<div class="section-row"><span>${drafts.length} ${drafts.length === 1 ? 'Foto bereit' : 'Fotos bereit'}</span><span>Entwürfe bleiben hier gespeichert</span></div>${drafts.map((d) => `<article class="draft" data-draft="${d.id}"><div class="draft-head"><h3>${d.detectionProposalId ? 'Erkanntes Stück' : 'Dein neues Stück'}</h3><button class="close" data-discard="${d.id}" aria-label="Entwurf verwerfen">${icon('close')}</button></div><img data-draft-asset="${d.assetId}" alt="Hochgeladenes Foto"><form data-save="${d.id}">${fields(d.metadata, d.state)}<button class="primary" style="margin-top:18px" type="submit">In den Schrank aufnehmen</button></form>${!d.detectionProposalId ? `<button class="text-button" data-detect="${d.id}">${d.detecting ? 'Erkennung prüfen' : 'Name und Farben automatisch erkennen …'}</button>` : ''}</article>`).join('')}`
    : '';
  document.querySelectorAll('[data-draft-asset]').forEach((img) =>
    assetUrl(img.dataset.draftAsset)
      .then((url) => {
        if (img.isConnected) img.src = url;
      })
      .catch(() => {}),
  );
  document.querySelectorAll('[data-save]').forEach((form) => {
    form.oninput = () => {
      const draft = drafts.find((d) => d.id === form.dataset.save);
      if (!draft) return;
      const f = new FormData(form);
      draft.metadata = {
        name: String(f.get('name')),
        category: String(f.get('category')),
        colors: String(f.get('colors')).split(', '),
        notes: String(f.get('notes')) || null,
      };
      draft.state = String(f.get('state'));
      persistDrafts();
    };
    form.onsubmit = (e) => {
      e.preventDefault();
      const d = drafts.find((d) => d.id === form.dataset.save);
      action($('button[type=submit]', form), async () => {
        try {
          const values = readFields(form);
          await api(
            d.detectionProposalId
              ? '/wardrobe-items'
              : '/wardrobe-items/from-photo',
            {
              ...(d.detectionProposalId
                ? { detectionProposalId: d.detectionProposalId }
                : { sourcePhotoId: d.sourcePhotoId }),
              ...values,
              idempotencyKey: d.id,
            },
          );
          drafts = drafts.filter((x) => x.id !== d.id);
          persistDrafts();
          await refreshItems();
          renderDrafts();
          toast('Im Schrank gespeichert');
        } catch (error) {
          formError(form, error);
        }
      });
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
  document.querySelectorAll('[data-detect]').forEach(
    (b) =>
      (b.onclick = () => {
        const d = drafts.find((x) => x.id === b.dataset.detect);
        if (d.detecting) return action(b, () => checkDetection(d));
        showSheet(
          'Kleidung erkennen',
          '<h2>Lass dir die Angaben vorschlagen.</h2><p>Die KI schlägt Namen, Kategorien und Farben vor. Du prüfst jedes Stück vor dem Speichern.</p><div class="note">Das Foto wird zur Analyse an OpenAI gesendet. Diese Erkennung ist kostenpflichtig. Es werden keine Katalogbilder erzeugt.</div><button class="primary" id="confirm-detect" style="margin-top:20px">Foto einmal analysieren</button>',
        );
        $('#confirm-detect').onclick = (e) =>
          action(e.currentTarget, async () => {
            d.detectionKey ||= key();
            persistDrafts();
            await api(`/source-photos/${d.sourcePhotoId}/detections`, {
              idempotencyKey: d.detectionKey,
            });
            d.detecting = true;
            persistDrafts();
            closeSheet();
            renderDrafts();
            toast('Die Erkennung läuft. Du kannst weitere Fotos erfassen.');
          });
      }),
  );
}
async function checkDetection(d) {
  const data = await api(`/source-photos/${d.sourcePhotoId}/detections`);
  if (!drafts.some((x) => x.id === d.id)) return;
  if (data.attempt?.state === 'failed') {
    d.detecting = false;
    delete d.detectionKey;
    persistDrafts();
    renderDrafts();
    throw new Error(
      'Die Erkennung ist fehlgeschlagen. Du kannst das Stück selbst benennen.',
    );
  }
  if (data.attempt?.state !== 'succeeded') {
    toast('Die Erkennung läuft noch.');
    return;
  }
  if (!data.detections.length) {
    d.detecting = false;
    persistDrafts();
    renderDrafts();
    toast('Keine Kleidung erkannt. Du kannst das Foto selbst benennen.');
    return;
  }
  drafts = drafts.filter((x) => x.id !== d.id);
  drafts.push(
    ...data.detections.map((proposal) => ({
      id: key(),
      sourcePhotoId: d.sourcePhotoId,
      assetId: d.assetId,
      detectionProposalId: proposal.id,
      metadata: {
        name: proposal.name,
        category:
          proposal.category === 'unsupported' ? 'top' : proposal.category,
        colors: proposal.colors,
        notes: null,
      },
      state: d.state,
    })),
  );
  persistDrafts();
  renderDrafts();
  toast(`${data.detections.length} Stücke erkannt. Bitte prüfe die Angaben.`);
}
function renderSettings() {
  shell(
    `<p class="eyebrow">So, wie du es brauchst</p><h1>Ganz dein Ding.</h1><p class="muted">Dein privater Kleiderschrank auf stargate.</p><section class="panel"><h3>Auf deinem iPhone</h3><p>Öffne FORM in Safari. Tippe auf Teilen und dann auf „Zum Home-Bildschirm“. So öffnet sich dein Schrank wie eine App.</p><div class="setting-row">Zugang<span>Privat über Tailscale</span></div><div class="setting-row">Anmeldung<span>Kein Passwort nötig</span></div><div class="setting-row">Speicherort<span>Dein Server</span></div></section><section class="panel"><h3>Du bestimmst die Bildkosten.</h3><p>Fotos hochladen, ordnen und bearbeiten kostet keine KI-Gebühren. Erkennung und Katalogbilder startest du einzeln, wenn du sie brauchst.</p><p>Bildgenerierung läuft in sparsamer Qualität. Verlässliche erfasste Kosten stehen beim jeweiligen neuen Bildentwurf. Alte Einträge hatten falsch konfigurierte Tarife.</p><a class="text-button" href="https://developers.openai.com/api/docs/pricing" target="_blank" rel="noreferrer">Aktuelle OpenAI-Preise ↗</a></section><button class="secondary" id="open-archive">Archiv öffnen · ${items.filter((i) => i.state === 'archived').length} Stücke</button><section class="panel"><h3>Noch einmal von vorn</h3><p>Leert den gemeinsamen privaten Kleiderschrank auf allen deinen Geräten. Kleidung, Fotos und Bildverläufe werden dauerhaft gelöscht.</p><button class="danger" id="reset">Kleiderschrank leeren …</button></section><p class="muted" style="text-align:center;font-size:11px">FORM · Persönliche Web-Version</p>`,
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
        if (detailId && $('#check-generation')) await openDetail(detailId);
      }
    }
    if (page === 'add')
      for (const draft of drafts.filter((d) => d.detecting)) {
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
