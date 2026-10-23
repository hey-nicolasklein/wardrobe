// Copy of the retired PWA's photo preparation, kept so the lab sends photos the same way.
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
