export const characterSheetPromptVersion = 'identity-face-only-v1';
export const characterSheetRefinePromptVersion = 'identity-face-only-refine-v1';

const views = 'Show exactly three large face close-ups in one horizontal row, in this left-to-right order: face turned slightly towards the left, direct front-facing view looking into the camera, face turned slightly towards the right. The left and right views must show opposite sides of the face. Use subtle three-quarter angles with both eyes and the far cheek visible, as in the previous sheet layout, not full side profiles. Frame each view from the top of the hair to just below the chin, with the entire head visible. No full-body views, torso views, extra rows, or extra faces.';
const identity = 'Preserve the actual facial proportions, face shape, jaw, cheeks, eyes, nose, mouth, hairline, facial hair, skin texture, glasses when present, and natural asymmetry of the person in the reference photos. Do not beautify, slim, symmetrize, or otherwise redesign the face. Keep the expression natural and consistent across the three views. Use soft neutral lighting and a plain background. No text, labels, callouts, borders, decoration, or watermark.';

export const characterPrompt = note =>
  `Create a face-only identity reference sheet of the same person shown in the reference photos. Facial likeness is the primary requirement. ${views} ${identity}${note ? ` Stable details: ${note}` : ''}`;

export const refinementPrompt = (note, instruction) =>
  `The first reference image is an existing identity sheet. The remaining reference photos show the real person and are the ground truth for facial likeness. Create a face-only revision, removing any body views from the existing sheet. ${views} Apply this correction: ${instruction}. Preserve already accurate facial details, but correct discrepancies using the real photos rather than carrying forward errors from the generated sheet. ${identity}${note ? ` Stable details: ${note}` : ''}`;

export const fitPromptVersion = 'direct-photo-fit-v1';
export const fitPrompt = (photoCount, items, scene, note) =>
  `Create one photorealistic 4:5 outfit photograph, not a collage or character sheet. Reference images 1 through ${photoCount} are real photographs of the person. Use them directly as the ground truth for identity. The first photo is the primary reference for facial proportions, head angle, expression, hairstyle, facial hair and glasses. Preserve those details, including natural asymmetry and skin texture. Do not beautify, slim, symmetrize or redesign the face. The remaining person photos provide supporting identity details. Ignore other people and the clothing in the identity photos. ${items.map((item, i) => `Reference image ${photoCount + i + 1} is a clothing reference. Use its visible garment details.`).join(' ')} Dress the person in the selected clothing, matching its cut, colors, material and details. Keep every selected garment fully visible, including shoes when selected. Do not copy a face or body from a clothing reference. Use plain incidental basics only where the outfit is incomplete. ${scene || 'A natural standing outfit photo in soft daylight against a simple neutral wall. Keep the head angle and expression from the first identity photo.'}${note ? ` Stable identity details: ${note}.` : ''} Keep realistic body proportions. No text, watermark, collage, extra people or extra views.`;

export const boardFitPrompt = (photoCount, items, scene, note) =>
  fitPrompt(1, items, scene, note).replace(
    'Reference images 1 through 1 are real photographs of the person.',
    `Reference image 1 is a reference board assembled from ${photoCount} real photographs of the same person. Its panels are original photographs, not generated views. Read them left to right, then top to bottom. The top-left panel is the primary identity photo; the other panels are supporting references. The board is input evidence only; the output must be a single outfit photograph.`
  ).replaceAll('first photo', 'top-left photo in the board').replaceAll('first identity photo', 'top-left photo in the board');
