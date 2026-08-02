// PROTOTYPE: upload-first fitting-profile creation inside Settings.
// Question: can 2–5 real photos plus conversational revisions create a useful reusable identity reference?
import { AlertCircle, ArrowLeft, Camera, Check, ImagePlus, LoaderCircle, MessageCircle, Plus, RefreshCw, Send, ShieldCheck, Sparkles, Trash2, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { generateCharacter } from './api';
import { createId } from './id';
import { clearFittingDraft, loadFittingDraft, saveFittingDraft } from './profileStorage';
import type { FittingProfile, FittingProfileDraft, ProfileMessage } from './types';

const MAX_PHOTOS = 5;
const MAX_BYTES = 10 * 1024 * 1024;

function readPhoto(file: File): Promise<string> {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
    return Promise.reject(new Error(`${file.name} is not a JPEG, PNG, or WebP image.`));
  }
  if (file.size > MAX_BYTES) return Promise.reject(new Error(`${file.name} is over 10 MB.`));
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error(`Could not read ${file.name}.`));
    reader.readAsDataURL(file);
  });
}

function errorMessage(reason: unknown) {
  return reason instanceof Error ? reason.message : 'Something went wrong while creating the image.';
}

export default function ProfileSettings({ profile, onBack, onChange, onToast }: {
  profile: FittingProfile | null;
  onBack: () => void;
  onChange: (profile: FittingProfile | null) => void;
  onToast: (message: string) => void;
}) {
  const [photos, setPhotos] = useState(profile?.referencePhotos ?? []);
  const [name, setName] = useState(profile?.name ?? 'Me');
  const [notes, setNotes] = useState(profile?.notes ?? 'Keep my natural proportions and everyday appearance.');
  const [editingSources, setEditingSources] = useState(!profile);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [failedMessage, setFailedMessage] = useState('');
  const [draftReady, setDraftReady] = useState(false);
  const [storageWarning, setStorageWarning] = useState('');
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let active = true;
    void loadFittingDraft()
      .then((draft) => {
        if (!active || !draft) return;
        setPhotos(draft.photos);
        setName(draft.name);
        setNotes(draft.notes);
        setEditingSources(draft.editingSources);
      })
      .catch(() => { if (active) setStorageWarning('This browser could not restore the last draft. New changes may not survive a reload.'); })
      .finally(() => { if (active) setDraftReady(true); });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (!draftReady) return;
    const draft: FittingProfileDraft = { photos, name, notes, editingSources, savedAt: new Date().toISOString() };
    const timer = window.setTimeout(() => {
      void saveFittingDraft(draft)
        .then(() => setStorageWarning(''))
        .catch(() => setStorageWarning('Draft saving failed. Keep FORM open until you can remove a photo or free browser storage.'));
    }, 250);
    return () => window.clearTimeout(timer);
  }, [draftReady, editingSources, name, notes, photos]);

  const attach = async (files: FileList | null) => {
    if (!files?.length) return;
    setError('');
    const available = MAX_PHOTOS - photos.length;
    if (available <= 0) {
      setError('You already have five photos. Remove one before adding another.');
      return;
    }
    if (files.length > available) setError(`Only the first ${available} ${available === 1 ? 'photo' : 'photos'} were added. The limit is five.`);
    try {
      const next = await Promise.all(Array.from(files).slice(0, available).map(readPhoto));
      setPhotos((current) => [...current, ...next]);
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      if (input.current) input.current.value = '';
    }
  };

  const create = async () => {
    if (photos.length < 2) {
      setError('Add at least two photos so the fitting profile is not guessed from one angle.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const result = await generateCharacter(photos, notes);
      const messages: ProfileMessage[] = [
        { id: createId(), role: 'assistant', text: 'Your first fitting profile is ready. Tell me what looks off—face, hair, proportions, pose, or studio treatment—and I’ll revise the image.' },
      ];
      onChange({ name: name.trim() || 'Me', image: result.image, referencePhotos: photos, notes, messages, updatedAt: 'Just now' });
      setEditingSources(false);
      onToast('Fitting profile created');
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setBusy(false);
    }
  };

  const refine = async () => {
    const instruction = (failedMessage || message).trim();
    if (!profile || !instruction || busy) return;
    setBusy(true);
    setError('');
    setFailedMessage('');
    const userMessage: ProfileMessage = { id: createId(), role: 'user', text: instruction };
    onChange({ ...profile, messages: [...profile.messages, userMessage] });
    setMessage('');
    try {
      const result = await generateCharacter(profile.referencePhotos, instruction, profile.image);
      const assistant: ProfileMessage = { id: createId(), role: 'assistant', text: 'I revised the fitting profile from your note. Keep this version, or tell me one more thing to change.', image: result.image };
      onChange({ ...profile, image: result.image, messages: [...profile.messages, userMessage, assistant], updatedAt: 'Just now' });
      onToast('Fitting profile updated');
    } catch (reason) {
      setFailedMessage(instruction);
      setError(errorMessage(reason));
      onChange(profile);
    } finally {
      setBusy(false);
    }
  };

  const saveSources = async () => {
    if (!profile) return create();
    if (photos.length < 2) {
      setError('Keep at least two reference photos.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const result = await generateCharacter(photos, `Rebuild the fitting profile using these updated reference photos. ${notes}`);
      const assistant: ProfileMessage = { id: createId(), role: 'assistant', text: 'I rebuilt the fitting profile using your updated reference photos.', image: result.image };
      onChange({ ...profile, name: name.trim() || 'Me', image: result.image, referencePhotos: photos, notes, messages: [...profile.messages, assistant], updatedAt: 'Just now' });
      setEditingSources(false);
      onToast('Reference photos updated');
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="page settings-page">
      <button className="back" onClick={onBack}><ArrowLeft size={19} /> Settings</button>
      <div className="settings-heading"><span className="kicker">Private identity reference</span><h1>Fitting profile</h1><p>Teach FORM what you look like once, then reuse that profile for every try-on.</p></div>

      {error ? <div className="profile-error" role="alert"><AlertCircle size={19} /><div><strong>We couldn’t finish that</strong><span>{error}</span></div><button aria-label="Dismiss error" onClick={() => setError('')}><X size={17} /></button></div> : null}
      {storageWarning ? <div className="profile-storage-warning" role="status"><ShieldCheck size={18} /><div><strong>Draft storage unavailable</strong><span>{storageWarning}</span></div></div> : null}

      {!profile || editingSources ? (
        <section className="profile-builder">
          <div className="builder-step"><span>1</span><div><strong>Add 2–5 clear photos</strong><p>Use a front view, side view, and a relaxed full-body shot. Different angles matter more than different outfits.</p></div></div>
          <div className="photo-grid">
            {photos.map((photo, index) => <div className="source-photo" key={`${photo.slice(-24)}-${index}`}><img src={photo} alt={`Reference ${index + 1}`} /><span>{index + 1}</span><button aria-label={`Remove photo ${index + 1}`} disabled={busy} onClick={() => setPhotos((current) => current.filter((_, item) => item !== index))}><X size={15} /></button></div>)}
            {photos.length < MAX_PHOTOS ? <button className="add-source" disabled={busy} onClick={() => input.current?.click()}><ImagePlus size={24} /><strong>Add photo</strong><span>{photos.length}/{MAX_PHOTOS}</span></button> : null}
          </div>
          <input ref={input} className="hidden-input" type="file" multiple accept="image/jpeg,image/png,image/webp" onChange={(event) => void attach(event.target.files)} />
          <div className="scan-guidance"><div><Camera size={17} /><span>Face visible</span></div><div><RefreshCw size={17} /><span>Several angles</span></div><div><Check size={17} /><span>Natural posture</span></div></div>

          <div className="builder-step second"><span>2</span><div><strong>Name and guide it</strong><p>These notes are reused when FORM generates your profile image.</p></div></div>
          <label className="field"><span>Profile name</span><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Me" /></label>
          <label className="field"><span>What should FORM preserve?</span><textarea rows={3} value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="My natural build, current haircut…" /></label>
          <div className="privacy-note"><ShieldCheck size={17} /><span>Your source photos are sent only to OpenAI for this generation. This prototype keeps them in memory for the current session.</span></div>
          <button className="sheet-primary profile-create" disabled={busy || photos.length < 2} onClick={() => void saveSources()}>{busy ? <LoaderCircle className="spin" size={19} /> : <Sparkles size={19} />}{busy ? 'Building low-cost draft…' : profile ? 'Rebuild fitting profile' : 'Create fitting profile'}</button>
          {profile ? <button className="text-action" disabled={busy} onClick={() => { setPhotos(profile.referencePhotos); setEditingSources(false); setError(''); }}>Cancel changes</button> : null}
        </section>
      ) : (
        <>
          <section className="profile-card">
            <div className="profile-image"><img src={profile.image} alt={`${profile.name} fitting profile`} /><span><Sparkles size={12} /> AI DRAFT</span></div>
            <div className="profile-card-copy"><div><span className="kicker">Your reusable identity</span><h2>{profile.name}</h2><p>Updated {profile.updatedAt} · GPT Image 2, high quality</p></div><button onClick={() => setEditingSources(true)}><ImagePlus size={16} /> Change source photos</button></div>
          </section>

          <section className="profile-chat">
            <div className="chat-title"><MessageCircle size={18} /><div><h2>Refine this profile</h2><p>Changes create a new low-cost draft; the current image stays until one succeeds.</p></div></div>
            <div className="chat-thread">
              {profile.messages.map((item) => <div className={`chat-message ${item.role}`} key={item.id}><p>{item.text}</p>{item.image ? <img src={item.image} alt="Revised fitting profile" /> : null}</div>)}
              {busy ? <div className="chat-message assistant typing"><span /><span /><span /></div> : null}
            </div>
            {failedMessage ? <button className="retry-message" disabled={busy} onClick={() => void refine()}><RefreshCw size={15} /> Retry “{failedMessage}”</button> : null}
            <div className="chat-composer"><textarea rows={2} disabled={busy} value={message} onChange={(event) => { setMessage(event.target.value); if (failedMessage) setFailedMessage(''); }} placeholder="Make the face closer to photo 2, keep my shoulders natural…" /><button aria-label="Send revision" disabled={busy || (!message.trim() && !failedMessage)} onClick={() => void refine()}>{busy ? <LoaderCircle className="spin" size={19} /> : <Send size={19} />}</button></div>
          </section>

          <section className="settings-danger"><div><strong>Remove fitting profile</strong><p>Try-ons will be disabled until you create another one.</p></div><button onClick={() => { if (window.confirm('Remove this fitting profile?')) { setPhotos([]); setName('Me'); setNotes('Keep my natural proportions and everyday appearance.'); setEditingSources(true); void clearFittingDraft(); onChange(null); } }}><Trash2 size={16} /> Remove</button></section>
        </>
      )}
    </main>
  );
}
