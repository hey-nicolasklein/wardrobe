import sharp from 'sharp';

// Justified rows preserve photo order and proportions without square-cell padding.
// Search all contiguous row breaks (at most 128 layouts for eight photos).
export function planPhotoBoard(dimensions) {
  if (!dimensions.length || dimensions.length > 8) throw Error('Choose 1–8 photos for the reference board.');
  const ratios = dimensions.map(({ width, height }) => width / height);
  let best;
  for (let mask = 0; mask < 2 ** (dimensions.length - 1); mask++) {
    const rows = [[]];
    ratios.forEach((ratio, i) => {
      rows.at(-1).push({ index: i, ratio });
      if (i < ratios.length - 1 && (mask & (1 << i))) rows.push([]);
    });
    const sums = rows.map(row => row.reduce((sum, item) => sum + item.ratio, 0));
    const heightFactor = sums.reduce((sum, ratio) => sum + 1 / ratio, 0);
    const score = Math.abs(Math.log(heightFactor)) + .2 * Math.log(Math.max(...sums) / Math.min(...sums));
    if (!best || score < best.score) best = { rows, sums, heightFactor, score };
  }
  // Bound total pixels and avoid magnifying small inputs. The old board could
  // reach nine million pixels, much of it padding.
  const width = Math.max(1, Math.floor(Math.min(
    2048, 2048 / best.heightFactor, Math.sqrt(2_000_000 / best.heightFactor),
    ...best.rows.map((row, i) => best.sums[i] * Math.min(1000, ...row.map(p => dimensions[p.index].height))),
  )));
  let top = 0;
  const panels = [];
  best.rows.forEach((row, i) => {
    const height = Math.max(1, Math.floor(width / best.sums[i]));
    let left = 0, cumulative = 0;
    row.forEach((item, j) => {
      cumulative += item.ratio;
      const right = j === row.length - 1 ? width : Math.round(width * cumulative / best.sums[i]);
      panels.push({ index: item.index, left, top, width: right - left, height });
      left = right;
    });
    top += height;
  });
  return { width, height: top, panels };
}

export async function makePhotoBoard(references) {
  if (!references.length || references.length > 8) throw Error('Choose 1–8 photos for the reference board.');
  const sources = await Promise.all(references.map(bytes => sharp(bytes).rotate().png().toBuffer({ resolveWithObject: true })));
  const layout = planPhotoBoard(sources.map(source => source.info));
  const panels = await Promise.all(layout.panels.map(async panel => ({
    // Only subpixel rounding differs from the original aspect ratio. Keep the
    // entire crop rather than trimming image edges to fit a cell.
    input: await sharp(sources[panel.index].data).resize(panel.width, panel.height, { fit: 'fill' }).png().toBuffer(),
    left: panel.left, top: panel.top,
  })));
  return sharp({ create: { width: layout.width, height: layout.height, channels: 3, background: '#e8e8e8' } }).composite(panels).png().toBuffer();
}
