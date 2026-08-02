// PROTOTYPE: three garment-preview presentations, switchable via ?variant=A|B|C.
// Question: does a transparent sticker or an in-context spotlight best highlight one visible garment?
import { ArrowLeft, ArrowRight, Check, Clock3, ImagePlus, Layers3, LoaderCircle, Shirt, Sparkles } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { createGarmentJob, loadGarmentJob, loadGarmentJobs, type GarmentJob, type GarmentKind } from './api';

const variants = [
  { key: 'A', name: 'Sticker first' },
  { key: 'B', name: 'Context spotlight' },
  { key: 'C', name: 'Evidence board' },
] as const;

const garments: Array<{ value: GarmentKind; label: string }> = [
  { value: 'top', label: 'Top / jacket' }, { value: 'pants', label: 'Pants' },
  { value: 'skirt', label: 'Skirt' }, { value: 'dress', label: 'Dress' },
  { value: 'shoes', label: 'Shoes' }, { value: 'bag', label: 'Bag' },
  { value: 'hat', label: 'Hat' }, { value: 'scarf', label: 'Scarf' },
];

export default function GarmentPreviewPrototype() {
  const params = new URLSearchParams(window.location.search);
  const requested = params.get('variant')?.toUpperCase();
  const initialVariant = variants.some((item) => item.key === requested) ? requested as 'A' | 'B' | 'C' : 'A';
  const initialJob = params.get('job');
  const initialTone = params.get('dim') === 'white' ? 'white' : 'black';
  const [variant, setVariant] = useState(initialVariant);
  const [tone, setTone] = useState<'black' | 'white'>(initialTone);
  const [job, setJob] = useState<GarmentJob | null>(null);
  const [jobs, setJobs] = useState<GarmentJob[]>([]);
  const [file, setFile] = useState<File | null>(null);
  const [garment, setGarment] = useState<GarmentKind>('top');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    void loadGarmentJobs().then(({ jobs: stored }) => {
      setJobs(stored);
      const restored = stored.find((candidate) => candidate.id === initialJob) ?? stored[0] ?? null;
      setJob(restored);
    }).catch((reason) => setError(reason instanceof Error ? reason.message : 'Could not restore prototype jobs'));
  }, [initialJob]);

  useEffect(() => {
    if (!job || (job.status !== 'queued' && job.status !== 'processing')) return;
    const timer = window.setInterval(() => {
      void loadGarmentJob(job.id).then(({ job: current }) => {
        setJob(current);
        setJobs((all) => all.map((candidate) => candidate.id === current.id ? current : candidate));
      }).catch(() => undefined);
    }, 1100);
    return () => window.clearInterval(timer);
  }, [job]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      if (event.target instanceof HTMLElement && (['INPUT', 'TEXTAREA', 'SELECT'].includes(event.target.tagName) || event.target.isContentEditable)) return;
      cycle(event.key === 'ArrowRight' ? 1 : -1);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const sourcePreview = useMemo(() => file ? URL.createObjectURL(file) : '', [file]);
  useEffect(() => () => { if (sourcePreview) URL.revokeObjectURL(sourcePreview); }, [sourcePreview]);

  const setUrl = (nextVariant: string, jobId = job?.id, nextTone = tone) => {
    const next = new URL(window.location.href);
    next.searchParams.set('prototype', 'garment');
    next.searchParams.set('variant', nextVariant);
    next.searchParams.set('dim', nextTone);
    if (jobId) next.searchParams.set('job', jobId);
    window.history.replaceState({}, '', next);
  };

  const cycle = (direction: number) => {
    const index = variants.findIndex((item) => item.key === variant);
    const next = variants[(index + direction + variants.length) % variants.length].key;
    setVariant(next);
    setUrl(next);
  };

  const submit = async () => {
    if (!file) return;
    setBusy(true);
    setError('');
    try {
      const result = await createGarmentJob(file, garment);
      setJob(result.job);
      setJobs((current) => [result.job, ...current]);
      setUrl(variant, result.job.id);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not enqueue extraction');
    } finally {
      setBusy(false);
    }
  };

  const chooseJob = (next: GarmentJob) => {
    setJob(next);
    setUrl(variant, next.id);
  };

  const changeTone = (nextTone: 'black' | 'white') => {
    setTone(nextTone);
    setUrl(variant, job?.id, nextTone);
  };

  return <div className="garment-prototype">
    <header className="prototype-header"><div><span>THROWAWAY PROTOTYPE</span><h1>Pull out the piece</h1><p>One segmentation mask. Three ways to make the garment legible.</p></div><Shirt size={28} /></header>

    <section className="prototype-input">
      <button className="prototype-upload" onClick={() => input.current?.click()}>{sourcePreview ? <img src={sourcePreview} alt="Chosen source" /> : <><ImagePlus /><strong>Choose an outfit photo</strong><span>The model keeps only visible garment pixels.</span></>}</button>
      <input ref={input} hidden type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setFile(event.target.files?.[0] ?? null)} />
      <label><span>Piece to highlight</span><select value={garment} onChange={(event) => setGarment(event.target.value as GarmentKind)}>{garments.map((item) => <option value={item.value} key={item.value}>{item.label}</option>)}</select></label>
      <button className="prototype-run" disabled={!file || busy} onClick={() => void submit()}>{busy ? <LoaderCircle className="spin" /> : <Sparkles />}{busy ? 'Adding to queue…' : 'Extract visible piece'}</button>
    </section>

    {error ? <p className="prototype-error">{error}</p> : null}
    {job?.status === 'complete' ? <div className="prototype-tone"><span>Dim surroundings</span><div><button className={tone === 'black' ? 'active dark' : 'dark'} onClick={() => changeTone('black')}>Black</button><button className={tone === 'white' ? 'active light' : 'light'} onClick={() => changeTone('white')}>White</button></div></div> : null}
    {job ? <JobResult job={job} variant={variant} tone={tone} /> : <section className="prototype-empty"><Layers3 /><strong>No experiment selected</strong><span>Upload an outfit photo, or restore a previous job below.</span></section>}

    <section className="prototype-state"><div><span>Durable queue</span><strong>{jobs.length} job{jobs.length === 1 ? '' : 's'}</strong></div>{jobs.map((candidate) => <button className={candidate.id === job?.id ? 'active' : ''} onClick={() => chooseJob(candidate)} key={candidate.id}><StatusIcon status={candidate.status} /><span>{garments.find((item) => item.value === candidate.garment)?.label}</span><small>{candidate.status}</small></button>)}</section>
    <pre className="prototype-debug">{JSON.stringify(job, null, 2)}</pre>

    {import.meta.env.DEV ? <nav className="prototype-switcher"><button aria-label="Previous variant" onClick={() => cycle(-1)}><ArrowLeft /></button><strong>{variant} — {variants.find((item) => item.key === variant)?.name}</strong><button aria-label="Next variant" onClick={() => cycle(1)}><ArrowRight /></button></nav> : null}
  </div>;
}

function StatusIcon({ status }: { status: GarmentJob['status'] }) {
  return status === 'complete' ? <Check /> : status === 'failed' ? <span>!</span> : status === 'processing' ? <LoaderCircle className="spin" /> : <Clock3 />;
}

function JobResult({ job, variant, tone }: { job: GarmentJob; variant: 'A' | 'B' | 'C'; tone: 'black' | 'white' }) {
  if (job.status !== 'complete') return <section className="prototype-processing"><StatusIcon status={job.status} /><strong>{job.progress}</strong><span>{job.status === 'failed' ? job.error : 'You can reload or close this window. The server owns the job.'}</span></section>;
  if (!job.sticker || !job.crop) return <section className="prototype-processing"><span>!</span><strong>This result predates contextual cropping</strong><span>Run the image once more to create the two-asset version.</span></section>;
  const ready = { ...job, sticker: job.sticker, crop: job.crop };
  if (variant === 'A') return <section className="variant-a"><div className="checkerboard"><img src={job.sticker} alt={`${job.garment} transparent sticker`} /></div><div><span>TRANSPARENT PNG</span><h2>The item becomes the object</h2><p>Best for wardrobe grids and drag-and-drop outfit building. Missing pixels stay honestly missing.</p><a href={job.sticker}>Open sticker</a></div></section>;
  if (variant === 'B') return <section className="variant-b"><div><ContextPreview job={ready} tone={tone} /><span>SELECTED · {job.garment}</span></div><h2>Keep just enough context</h2><p>The browser crops and dims the original, then places the stored PNG over it. No spotlight image is stored.</p></section>;
  return <section className="variant-c"><header><span>ONE ORIGINAL · ONE PNG</span><h2>Judge the extraction</h2></header><div><figure><img src={job.original} alt="Original source" /><figcaption>1 · Stored original</figcaption></figure><figure><ContextPreview job={ready} tone={tone} /><figcaption>2 · Live browser composite</figcaption></figure><figure className="checkerboard"><img src={job.sticker} alt="Transparent garment sticker" /><figcaption>3 · Stored PNG</figcaption></figure></div></section>;
}

function ContextPreview({ job, tone }: { job: GarmentJob & { sticker: string; crop: NonNullable<GarmentJob['crop']> }; tone: 'black' | 'white' }) {
  const { crop } = job;
  const sourceStyle = {
    width: `${crop.sourceWidth / crop.width * 100}%`,
    height: `${crop.sourceHeight / crop.height * 100}%`,
    left: `${-crop.x / crop.width * 100}%`,
    top: `${-crop.y / crop.height * 100}%`,
  };
  return <div className={`context-preview tone-${tone}`} style={{ aspectRatio: `${crop.width} / ${crop.height}` }}>
    <img className="context-source" src={job.original} alt="" style={sourceStyle} />
    <img className="context-sticker" src={job.sticker} alt={`${job.garment} highlighted`} />
  </div>;
}
