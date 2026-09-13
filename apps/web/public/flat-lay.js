// Coordinates use a 100 × 125 artboard. The same composition is used on screen
// and in the downloaded image; category and ID make it independent of API order.
const order = ['hat', 'top', 'dress', 'jacket', 'pants', 'skirt', 'scarf', 'bag', 'shoes'];
export function flatLayLayout(garments) {
  const sorted = [...garments].sort((a, b) => {
    const rank = (item) => {
      const index = order.indexOf(item.metadata?.category);
      return index < 0 ? order.length : index;
    };
    return rank(a) - rank(b) || a.id.localeCompare(b.id);
  });
  if (!sorted.length) return [];
  if (sorted.length === 1) return [{ item: sorted[0], x: 50, y: 61, size: 80, angle: -3 }];
  const kinds = sorted.map((item) => item.metadata?.category);
  // Multiple pieces of a category need their own space, not a stack that hides
  // one of the choices. Larger collections use evenly spaced editorial rows.
  if (sorted.length > 6 || new Set(kinds).size !== kinds.length ||
      (kinds.includes('top') && kinds.includes('dress') && kinds.includes('jacket')) ||
      (kinds.includes('pants') && kinds.includes('skirt')) ||
      !kinds.some((kind) => ['top', 'jacket', 'dress', 'pants', 'skirt'].includes(kind))) {
    const columns = sorted.length > 6 ? 3 : 2;
    const rows = Math.ceil(sorted.length / columns);
    const cellWidth = 90 / columns;
    const cellHeight = 113 / rows;
    return sorted.map((item, index) => {
      const row = Math.floor(index / columns);
      const inRow = Math.min(columns, sorted.length - row * columns);
      return {
        item,
        x: 50 + (index % columns - (inRow - 1) / 2) * cellWidth,
        y: 6 + (row + 0.5) * cellHeight,
        size: Math.min(cellWidth, cellHeight) * 0.92,
        angle: index % 2 ? 4 : -4,
      };
    });
  }
  const dress = kinds.includes('dress');
  const outer = kinds.includes('jacket');
  const sidePieces = kinds.some((kind) => ['jacket', 'bag', 'scarf', 'hat'].includes(kind));
  const templates = dress ? {
    dress: [35, 58, 65, -3], jacket: [77, 33, 39, 6],
    top: [76, 29, 37, -4], pants: [76, 66, 36, 3], skirt: [75, 65, 35, 4],
    bag: [77, 77, 29, 7], shoes: [63, 108, 32, -6],
    hat: [32, 16, 23, -8], scarf: [78, 52, 25, 8],
  } : {
    top: [outer ? 30 : sidePieces ? 39 : 50, 30, outer ? 49 : 57, -4],
    jacket: [kinds.includes('top') ? 75 : 36, 34, kinds.includes('top') ? 43 : 58, 5],
    pants: [sidePieces ? 35 : 45, 81, 53, 2], skirt: [sidePieces ? 35 : 45, 79, 51, -3],
    bag: [78, 77, 30, 7], shoes: [72, 109, 31, -6],
    hat: [78, 15, 24, -8], scarf: [78, 53, 26, 8], dress: [35, 60, 65, -3],
  };
  return sorted.map((item, index) => {
    const [x, y, size, angle] = templates[item.metadata?.category] || [76, 54 + index * 6, 26, 4];
    return { item, x, y, size, angle };
  });
}
