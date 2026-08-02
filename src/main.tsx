import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import GarmentPreviewPrototype from './GarmentPreviewPrototype';
import './styles.css';

const prototype = new URLSearchParams(window.location.search).get('prototype');

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {prototype === 'garment' ? <GarmentPreviewPrototype /> : <App />}
  </StrictMode>,
);
