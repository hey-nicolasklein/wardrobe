import {
  ArrowLeft,
  Bookmark,
  Camera,
  Check,
  ChevronRight,
  ImagePlus,
  Images,
  Link2,
  LoaderCircle,
  Plus,
  RotateCcw,
  Shirt,
  Sparkles,
  ThumbsDown,
  ThumbsUp,
  WandSparkles,
  X,
  UserRound,
} from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { generateTryOn, importProduct, recommendItems } from './api';
import { createId } from './id';
import ProfileSettings from './ProfileSettings';
import { loadFittingDraft, loadFittingProfile, saveFittingDraft, saveFittingProfile } from './profileStorage';
import type { Category, FittingProfile, GeneratedLookSettings, ImageGenerationQuality, Look, LookSuggestion, WardrobeItem } from './types';

type Tab = 'looks' | 'wanting' | 'owning';

const categories: Category[] = ['Tops', 'Bottoms', 'Outerwear', 'Shoes', 'Accessories'];

const seedItems: WardrobeItem[] = [
  { id: 'linen-shirt', name: 'Relaxed linen shirt', brand: 'ARKET', category: 'Tops', source: 'wardrobe', origin: 'manual', image: 'https://images.unsplash.com/photo-1598033129183-c4f50c736f10?auto=format&fit=crop&w=700&q=85' },
  { id: 'denim', name: 'Wide leg denim', brand: 'Weekday', category: 'Bottoms', source: 'wardrobe', origin: 'manual', image: 'https://images.unsplash.com/photo-1542272604-787c3835535d?auto=format&fit=crop&w=700&q=85' },
  { id: 'sneakers', name: 'Retro runner', brand: 'New Balance', category: 'Shoes', source: 'wardrobe', origin: 'manual', image: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=700&q=85' },
  { id: 'sweater', name: 'Merino crew neck', brand: 'Uniqlo', category: 'Tops', source: 'wardrobe', origin: 'manual', image: 'https://images.unsplash.com/photo-1620799140408-edc6dcb6d633?auto=format&fit=crop&w=700&q=85' },
  { id: 'trench', name: 'Cotton trench coat', brand: 'COS', category: 'Outerwear', source: 'wishlist', origin: 'shop', image: 'https://images.unsplash.com/photo-1544022613-e87ca75a784a?auto=format&fit=crop&w=700&q=85' },
  { id: 'bag', name: 'Soft leather tote', brand: 'Massimo Dutti', category: 'Accessories', source: 'wishlist', origin: 'shop', image: 'https://images.unsplash.com/photo-1584917865442-de89df76afd3?auto=format&fit=crop&w=700&q=85' },
  { id: 'trousers', name: 'Pleated wool trousers', brand: 'Selected', category: 'Bottoms', source: 'wishlist', origin: 'shop', image: 'https://images.unsplash.com/photo-1506629082955-511b1aa562c8?auto=format&fit=crop&w=700&q=85' },
];

function readImage(file?: File): Promise<string> {
  if (!file) return Promise.reject(new Error('Choose a photo'));
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export default function App() {
  const [tab, setTab] = useState<Tab>('looks');
  const [items, setItems] = useState(seedItems);
  const [looks, setLooks] = useState<Look[]>([]);
  const [profile, setProfile] = useState<FittingProfile | null>(null);
  const [profileReady, setProfileReady] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(() => new URLSearchParams(window.location.search).has('settings'));
  const [detailId, setDetailId] = useState<string | null>(null);
  const [addItemSource, setAddItemSource] = useState<'wardrobe' | 'wishlist' | null>(null);
  const [snapOpen, setSnapOpen] = useState(false);
  const [generateOpen, setGenerateOpen] = useState(false);
  const [analysingId, setAnalysingId] = useState<string | null>(null);
  const [retryingId, setRetryingId] = useState<string | null>(null);
  const [toast, setToast] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    const recoveryFile = new URLSearchParams(window.location.search).get('recoverProfile');
    const validRecoveryFile = recoveryFile && /^[a-f0-9-]{36}\.png$/i.test(recoveryFile) ? recoveryFile : null;
    void Promise.all([
      loadFittingProfile(),
      validRecoveryFile ? loadFittingDraft() : Promise.resolve(null),
    ])
      .then(async ([stored, draft]) => {
        let next = stored;
        if (!next && validRecoveryFile && draft && draft.photos.length >= 2) {
          next = {
            name: draft.name.trim() || 'Me',
            image: `/api/generated/${validRecoveryFile}`,
            referencePhotos: draft.photos,
            notes: draft.notes,
            messages: [{
              id: createId(),
              role: 'assistant',
              text: 'Recovered the fitting profile that finished before the browser closed the request.',
            }],
            updatedAt: 'Just now',
          };
          await Promise.all([
            saveFittingProfile(next),
            saveFittingDraft({ ...draft, editingSources: false, savedAt: new Date().toISOString() }),
          ]);
        }
        if (active) setProfile(next);
      })
      .catch(() => { if (active) setError('FORM could not restore your fitting profile from this browser.'); })
      .finally(() => { if (active) setProfileReady(true); });
    return () => { active = false; };
  }, []);

  const changeProfile = (next: FittingProfile | null) => {
    setProfile(next);
    void saveFittingProfile(next).catch(() => setError('Your fitting profile changed, but this browser could not save it for the next reload.'));
  };

  const showToast = (message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(''), 2600);
  };

  const changeTab = (next: Tab) => {
    setDetailId(null);
    setSettingsOpen(false);
    setTab(next);
  };

  const analyse = async (look: Look) => {
    setAnalysingId(look.id);
    setError('');
    try {
      const linked = look.itemIds.map((id) => items.find((item) => item.id === id)).filter(Boolean) as WardrobeItem[];
      const result = await recommendItems(look.image, linked);
      setLooks((current) => current.map((value) => value.id === look.id ? { ...value, suggestions: result.suggestions } : value));
      showToast(result.suggestions.length ? 'Suggestions ready for your verdict' : 'No confident suggestions for this look');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not analyse this look');
    } finally {
      setAnalysingId(null);
    }
  };

  const rateSuggestion = (look: Look, suggestion: LookSuggestion, accepted: boolean) => {
    let newItemId: string | null = null;
    if (accepted) {
      newItemId = `suggested-${suggestion.id}`;
      setItems((current) => current.some((item) => item.id === newItemId) ? current : [...current, {
        id: newItemId!, name: suggestion.name, brand: 'AI suggestion', category: suggestion.category,
        source: 'wishlist', origin: 'suggested',
      }]);
    }
    setLooks((current) => current.map((value) => value.id === look.id ? {
      ...value,
      itemIds: newItemId ? [...value.itemIds, newItemId] : value.itemIds,
      suggestions: value.suggestions.map((entry) => entry.id === suggestion.id ? { ...entry, status: accepted ? 'accepted' : 'rejected' } : entry),
    } : value));
    showToast(accepted ? 'Saved to Wanting and linked to this look' : 'Marked not useful');
  };

  const retryLook = async (look: Look) => {
    if (!look.generation) return;
    setRetryingId(look.id);
    setError('');
    try {
      const result = await generateTryOn(look.generation);
      setLooks((current) => [{
        id: createId(), title: 'New generated look', image: result.image, itemIds: look.itemIds,
        note: look.generation!.note, createdAt: 'Just now', kind: 'generated', suggestions: [], generation: look.generation,
      }, ...current]);
      showToast('Generated a new variation with the same settings');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not retry this look');
    } finally {
      setRetryingId(null);
    }
  };

  const detail = detailId ? items.find((item) => item.id === detailId) : null;

  return (
    <div className="app-shell">
      <header className="app-header">
        <button className="brand" onClick={() => changeTab('looks')}><span>F</span>ORM</button>
        <button className={`header-avatar ${profile ? '' : 'empty'}`} aria-label="Open settings" onClick={() => { setDetailId(null); setSettingsOpen(true); }}>{profile ? <img src={profile.image} alt="" /> : <UserRound size={18} />}</button>
      </header>

      {error ? <div className="notice error"><span>{error}</span><button onClick={() => setError('')}><X size={16} /></button></div> : null}
      {toast ? <div className="notice success"><Check size={16} />{toast}</div> : null}

      {settingsOpen ? (
        profileReady
          ? <ProfileSettings profile={profile} onBack={() => setSettingsOpen(false)} onChange={changeProfile} onToast={showToast} />
          : <main className="page profile-loading"><LoaderCircle className="spin" /><span>Restoring your fitting profile…</span></main>
      ) : detail ? (
        <ItemDetail item={detail} looks={looks.filter((look) => look.itemIds.includes(detail.id))} onBack={() => setDetailId(null)} onMove={() => {
          setItems((current) => current.map((item) => item.id === detail.id ? { ...item, source: item.source === 'wardrobe' ? 'wishlist' : 'wardrobe' } : item));
          setDetailId(null);
          showToast(detail.source === 'wardrobe' ? 'Moved to Wanting' : 'Moved to Owning');
        }} />
      ) : tab === 'looks' ? (
        <LooksTab
          looks={looks}
          items={items}
          analysingId={analysingId}
          retryingId={retryingId}
          onAnalyse={analyse}
          onRate={rateSuggestion}
          onOpenItem={setDetailId}
          onSnap={() => setSnapOpen(true)}
          onGenerate={() => profile ? setGenerateOpen(true) : setSettingsOpen(true)}
          onRetry={retryLook}
          hasProfile={Boolean(profile)}
          onCreateProfile={() => setSettingsOpen(true)}
        />
      ) : (
        <ItemsTab
          mode={tab}
          items={items.filter((item) => item.source === (tab === 'owning' ? 'wardrobe' : 'wishlist'))}
          looks={looks}
          onOpen={setDetailId}
          onAdd={() => setAddItemSource(tab === 'owning' ? 'wardrobe' : 'wishlist')}
        />
      )}

      {!settingsOpen ? <nav className="bottom-tabs">
        <TabButton active={tab === 'looks'} icon={Images} label="Looks" onClick={() => changeTab('looks')} />
        <TabButton active={tab === 'wanting'} icon={Bookmark} label="Wanting" onClick={() => changeTab('wanting')} />
        <TabButton active={tab === 'owning'} icon={Shirt} label="Owning" onClick={() => changeTab('owning')} />
      </nav> : null}

      {snapOpen ? <SnapSheet owned={items.filter((item) => item.source === 'wardrobe')} onClose={() => setSnapOpen(false)} onSave={(look) => { setLooks((current) => [look, ...current]); setSnapOpen(false); showToast('Snap added to Looks'); }} /> : null}
      {generateOpen && profile ? <GenerateSheet characterImage={profile.image} items={items.filter((item) => item.image)} onClose={() => setGenerateOpen(false)} onSave={(look) => { setLooks((current) => [look, ...current]); setGenerateOpen(false); showToast('Generated look added'); }} onError={setError} /> : null}
      {addItemSource ? <AddItemSheet source={addItemSource} onClose={() => setAddItemSource(null)} onSave={(item) => { setItems((current) => [item, ...current]); setAddItemSource(null); showToast(`Added to ${item.source === 'wardrobe' ? 'Owning' : 'Wanting'}`); }} /> : null}
    </div>
  );
}

function TabButton({ active, icon: Icon, label, onClick }: { active: boolean; icon: typeof Images; label: string; onClick: () => void }) {
  return <button className={active ? 'active' : ''} onClick={onClick}><Icon size={21} /><span>{label}</span></button>;
}

function LooksTab({ looks, items, analysingId, retryingId, onAnalyse, onRate, onOpenItem, onSnap, onGenerate, onRetry, hasProfile, onCreateProfile }: {
  looks: Look[]; items: WardrobeItem[]; analysingId: string | null;
  retryingId: string | null;
  onAnalyse: (look: Look) => void; onRate: (look: Look, suggestion: LookSuggestion, accepted: boolean) => void;
  onOpenItem: (id: string) => void; onSnap: () => void; onGenerate: () => void; onRetry: (look: Look) => void; hasProfile: boolean; onCreateProfile: () => void;
}) {
  const decisions = looks.flatMap((look) => look.suggestions).filter((suggestion) => suggestion.status !== 'pending');
  const accepted = decisions.filter((suggestion) => suggestion.status === 'accepted').length;
  return (
    <main className="page looks-page-simple">
      <div className="page-header">
        <div><span className="kicker">Your visual diary</span><h1>Looks</h1></div>
        <div className="look-actions"><button onClick={onSnap}><Camera size={18} /><span>Add snap</span></button><button className="primary" onClick={onGenerate}><WandSparkles size={18} /><span>Generate</span></button></div>
      </div>
      {decisions.length ? <div className="experiment-score"><Sparkles size={15} /><span><strong>{accepted}/{decisions.length}</strong> AI suggestions useful so far</span></div> : null}
      {!looks.length ? <section className="looks-empty"><div><Sparkles size={24} /></div><span className="kicker">Nothing generated for you</span><h2>{hasProfile ? 'Build your first look' : 'Start with your fitting profile'}</h2><p>{hasProfile ? 'Choose clothing from Owning or Wanting and see it on your reusable profile.' : 'Add 2–5 photos in Settings so generated looks use your face, build, and proportions.'}</p><button onClick={hasProfile ? onGenerate : onCreateProfile}>{hasProfile ? <WandSparkles size={18} /> : <UserRound size={18} />}{hasProfile ? 'Generate first look' : 'Create fitting profile'}</button><button className="empty-secondary" onClick={onSnap}><Camera size={17} /> Or add a real outfit snap</button></section> : null}
      <div className="look-feed">
        {looks.map((look) => {
          const linked = look.itemIds.map((id) => items.find((item) => item.id === id)).filter(Boolean) as WardrobeItem[];
          const pending = look.suggestions.filter((suggestion) => suggestion.status === 'pending');
          return (
            <article className="feed-look" key={look.id}>
              <div className="feed-photo"><img src={look.image} alt={look.title} /><span>{look.kind === 'snap' ? <><Camera size={12} /> SNAP</> : <><Sparkles size={12} /> GENERATED</>}</span></div>
              <div className="feed-copy"><div className="feed-meta"><span>{look.createdAt}</span><h2>{look.title}</h2><p>{look.note}</p></div>
                {look.kind === 'generated' && look.generation ? <button className="retry-look" disabled={retryingId === look.id} onClick={() => onRetry(look)}>{retryingId === look.id ? <LoaderCircle className="spin" size={15} /> : <RotateCcw size={15} />}{retryingId === look.id ? 'Generating variation…' : 'Retry same settings · High quality'}</button> : null}
                <div className="linked-list"><h3>Items in this look <span>{linked.length}</span></h3>{linked.map((item) => <LinkedItem item={item} onClick={() => onOpenItem(item.id)} key={item.id} />)}</div>
                <section className="recommendations">
                  <div className="recommendation-head"><div><Sparkles size={15} /><h3>Try with this look</h3><span>Experimental</span></div>{!pending.length ? <button disabled={analysingId === look.id} onClick={() => onAnalyse(look)}>{analysingId === look.id ? <LoaderCircle className="spin" size={15} /> : <Sparkles size={15} />}{analysingId === look.id ? 'Thinking…' : look.suggestions.length ? 'Try again' : 'Get suggestions'}</button> : null}</div>
                  {pending.length ? <div className="suggestion-list">{pending.map((suggestion) => <div className="suggestion" key={suggestion.id}><div><span>{suggestion.category} · {Math.round(suggestion.confidence * 100)}% confidence</span><strong>{suggestion.name}</strong><p>{suggestion.reason}</p></div><div className="suggestion-vote"><span>Useful?</span><button aria-label="Not useful" onClick={() => onRate(look, suggestion, false)}><ThumbsDown size={16} /></button><button aria-label="Useful, save to wanting" onClick={() => onRate(look, suggestion, true)}><ThumbsUp size={16} /></button></div></div>)}</div> : <p className="recommendation-empty">AI can suggest complementary pieces from the photo. Accepting saves one to Wanting; rejecting helps us measure usefulness.</p>}
                </section>
              </div>
            </article>
          );
        })}
      </div>
    </main>
  );
}

function LinkedItem({ item, onClick }: { item: WardrobeItem; onClick: () => void }) {
  return <button className="linked-item" onClick={onClick}><ItemThumb item={item} /><div><span>{item.source === 'wardrobe' ? 'OWNING' : 'WANTING'} · {item.category}</span><strong>{item.name}</strong><small>{item.brand}</small></div><ChevronRight size={18} /></button>;
}

function ItemsTab({ mode, items, looks, onOpen, onAdd }: { mode: 'wanting' | 'owning'; items: WardrobeItem[]; looks: Look[]; onOpen: (id: string) => void; onAdd: () => void }) {
  return <main className="page items-page"><div className="page-header"><div><span className="kicker">{mode === 'owning' ? 'Your wardrobe' : 'Your shortlist'}</span><h1>{mode === 'owning' ? 'Owning' : 'Wanting'}</h1><p>{items.length} items</p></div><button className="round-add" onClick={onAdd}><Plus /></button></div><div className="item-index">{items.map((item) => { const linked = looks.filter((look) => look.itemIds.includes(item.id)); return <button className="index-item" onClick={() => onOpen(item.id)} key={item.id}><ItemThumb item={item} /><div className="index-copy"><span>{item.category}</span><h2>{item.name}</h2><p>{item.brand}</p>{item.origin === 'suggested' ? <small><Sparkles size={11} /> Suggested from a look</small> : null}</div><div className="linked-count">{linked.length ? <><div>{linked.slice(0, 2).map((look) => <img src={look.image} alt="" key={look.id} />)}</div><span>{linked.length} {linked.length === 1 ? 'look' : 'looks'}</span></> : <span>Not worn yet</span>}<ChevronRight size={18} /></div></button>; })}</div></main>;
}

function ItemDetail({ item, looks, onBack, onMove }: { item: WardrobeItem; looks: Look[]; onBack: () => void; onMove: () => void }) {
  return <main className="page detail-page"><button className="back" onClick={onBack}><ArrowLeft size={19} /> {item.source === 'wardrobe' ? 'Owning' : 'Wanting'}</button><div className="detail-hero"><ItemThumb item={item} large /><span>{item.source === 'wardrobe' ? 'I own this' : 'I want this'}</span></div><div className="detail-copy"><span className="kicker">{item.category}</span><h1>{item.name}</h1><p>{item.brand}</p><button className="move-button" onClick={onMove}>{item.source === 'wardrobe' ? <Bookmark size={17} /> : <Shirt size={17} />}{item.source === 'wardrobe' ? 'Move to Wanting' : 'Mark as owned'}</button></div><section className="linked-looks"><h2>Linked looks <span>{looks.length}</span></h2>{looks.length ? <div>{looks.map((look) => <article key={look.id}><img src={look.image} alt={look.title} /><span>{look.kind}</span><strong>{look.title}</strong></article>)}</div> : <div className="no-looks"><Link2 /><p>This item is not linked to a look yet.</p></div>}</section></main>;
}

function ItemThumb({ item, large = false }: { item: WardrobeItem; large?: boolean }) {
  return <div className={`item-thumb ${large ? 'large' : ''}`}>{item.image ? <img src={item.image} alt={item.name} /> : <><Shirt size={large ? 42 : 22} /><span>Suggestion</span></>}</div>;
}

function SnapSheet({ owned, onClose, onSave }: { owned: WardrobeItem[]; onClose: () => void; onSave: (look: Look) => void }) {
  const [image, setImage] = useState('');
  const [title, setTitle] = useState('Today’s outfit');
  const [selected, setSelected] = useState<string[]>([]);
  const input = useRef<HTMLInputElement>(null);
  return <Sheet title="Add a snap" subtitle="Upload a selfie or mirror photo, then mark what you are wearing." onClose={onClose}><button className="snap-upload" onClick={() => input.current?.click()}>{image ? <img src={image} alt="Preview" /> : <><Camera size={26} /><strong>Choose from photos</strong><span>Selfie, mirror snap, or full outfit</span></>}<input ref={input} type="file" accept="image/*" onChange={async (event) => setImage(await readImage(event.target.files?.[0]))} /></button><label className="field"><span>Look name</span><input value={title} onChange={(event) => setTitle(event.target.value)} /></label><div className="item-picker"><span>Mark items in the photo</span>{owned.map((item) => <button className={selected.includes(item.id) ? 'selected' : ''} onClick={() => setSelected((current) => current.includes(item.id) ? current.filter((id) => id !== item.id) : [...current, item.id])} key={item.id}><ItemThumb item={item} /><strong>{item.name}</strong>{selected.includes(item.id) ? <Check size={16} /> : <Plus size={16} />}</button>)}</div><button className="sheet-primary" disabled={!image} onClick={() => onSave({ id: createId(), title, image, itemIds: selected, note: 'Uploaded from my camera roll.', createdAt: 'Just now', kind: 'snap', suggestions: [] })}><Camera size={18} />Add to Looks</button></Sheet>;
}

function GenerateSheet({ characterImage, items, onClose, onSave, onError }: { characterImage: string; items: WardrobeItem[]; onClose: () => void; onSave: (look: Look) => void; onError: (message: string) => void }) {
  const [selected, setSelected] = useState<string[]>([]);
  const [note, setNote] = useState('Relaxed everyday look, natural daylight');
  const quality: ImageGenerationQuality = 'high';
  const [busy, setBusy] = useState(false);
  const generate = async () => { setBusy(true); try { const chosen = items.filter((item) => selected.includes(item.id) && item.image); const generation: GeneratedLookSettings = { characterImage, items: chosen.map(({ name, category, image }) => ({ name, category, image })), note, quality }; const result = await generateTryOn(generation); onSave({ id: createId(), title: 'New generated look', image: result.image, itemIds: selected, note, createdAt: 'Just now', kind: 'generated', suggestions: [], generation }); } catch (reason) { onError(reason instanceof Error ? reason.message : 'Could not generate look'); } finally { setBusy(false); } };
  return <Sheet title="Generate a look" subtitle="Pick pieces from Owning or Wanting. Every image is generated at high quality." onClose={onClose}><div className="item-picker generate-picker">{items.map((item) => <button className={selected.includes(item.id) ? 'selected' : ''} onClick={() => setSelected((current) => current.includes(item.id) ? current.filter((id) => id !== item.id) : [...current, item.id])} key={item.id}><ItemThumb item={item} /><div><span>{item.source === 'wardrobe' ? 'OWNING' : 'WANTING'}</span><strong>{item.name}</strong></div>{selected.includes(item.id) ? <Check size={16} /> : <Plus size={16} />}</button>)}</div><label className="field"><span>Direction</span><textarea rows={3} value={note} onChange={(event) => setNote(event.target.value)} /></label><button className="sheet-primary" disabled={busy || !selected.length} onClick={generate}>{busy ? <LoaderCircle className="spin" size={18} /> : <WandSparkles size={18} />}{busy ? 'Generating…' : 'Generate look'}</button></Sheet>;
}

function AddItemSheet({ source, onClose, onSave }: { source: 'wardrobe' | 'wishlist'; onClose: () => void; onSave: (item: WardrobeItem) => void }) {
  const [url, setUrl] = useState(''); const [name, setName] = useState(''); const [brand, setBrand] = useState(''); const [image, setImage] = useState(''); const [category, setCategory] = useState<Category>('Tops'); const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const input = useRef<HTMLInputElement>(null);
  const fetchProduct = async () => { setBusy(true); setError(''); try { const item = await importProduct(url); setName(item.name || ''); setBrand(item.brand || ''); setImage(item.image || ''); } catch (reason) { setError(reason instanceof Error ? reason.message : 'Could not import product'); } finally { setBusy(false); } };
  return <Sheet title={`Add to ${source === 'wardrobe' ? 'Owning' : 'Wanting'}`} subtitle="Paste a shop link or add a photo." onClose={onClose}><div className="url-field"><input value={url} onChange={(event) => setUrl(event.target.value)} placeholder="Zalando, ASOS, or image URL" /><button disabled={!url || busy} onClick={fetchProduct}>{busy ? <LoaderCircle className="spin" size={16} /> : 'Fetch'}</button></div><button className="small-upload" onClick={() => input.current?.click()}>{image ? <img src={image} alt="" /> : <ImagePlus />}<span>{image ? 'Change image' : 'Add product photo'}</span><input ref={input} type="file" accept="image/*" onChange={async (event) => setImage(await readImage(event.target.files?.[0]))} /></button><label className="field"><span>Name</span><input value={name} onChange={(event) => setName(event.target.value)} /></label><label className="field"><span>Brand</span><input value={brand} onChange={(event) => setBrand(event.target.value)} /></label><label className="field"><span>Category</span><select value={category} onChange={(event) => setCategory(event.target.value as Category)}>{categories.map((value) => <option key={value}>{value}</option>)}</select></label>{error ? <p className="form-error">{error}</p> : null}<button className="sheet-primary" disabled={!name} onClick={() => onSave({ id: createId(), name, brand: brand || 'Unknown brand', category, image: image || undefined, source, origin: url ? 'shop' : 'manual', url: url || undefined })}><Plus size={18} />Add item</button></Sheet>;
}

function Sheet({ title, subtitle, onClose, children }: { title: string; subtitle: string; onClose: () => void; children: React.ReactNode }) {
  return <div className="sheet-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="sheet"><div className="sheet-handle" /><button className="sheet-close" onClick={onClose}><X /></button><header><h2>{title}</h2><p>{subtitle}</p></header>{children}</section></div>;
}
