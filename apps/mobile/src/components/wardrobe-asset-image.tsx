import { Image } from 'expo-image';
import { useEffect, useState } from 'react';
import { Text, View, type ImageStyle, type StyleProp } from 'react-native';

import { useAppColors } from '@/theme/colors';
import { useWardrobeData } from '@/wardrobe/wardrobe-data';

export function WardrobeAssetImage({
  assetId,
  fallback,
  style,
  contentFit = 'cover',
}: {
  assetId: string | null;
  fallback: string;
  style: StyleProp<ImageStyle>;
  contentFit?: 'contain' | 'cover';
}) {
  const colors = useAppColors();
  const { cache, mediaUrl } = useWardrobeData();
  const [url, setUrl] = useState<string | null>(assetId ? cache.mediaUrls[assetId] ?? null : null);

  useEffect(() => {
    let active = true;
    setUrl(assetId ? cache.mediaUrls[assetId] ?? null : null);
    if (assetId) {
      void mediaUrl(assetId).then((next) => {
        if (active && next) setUrl(next);
      });
    }
    return () => {
      active = false;
    };
  }, [assetId, mediaUrl]);

  if (!assetId || !url) {
    return (
      <View
        style={[
          style,
          {
            alignItems: 'center',
            backgroundColor: colors.secondaryBackground,
            justifyContent: 'center',
          },
        ]}>
        <Text selectable style={{ color: colors.secondaryLabel, fontSize: 28, fontWeight: '700' }}>
          {fallback.slice(0, 1).toLocaleUpperCase()}
        </Text>
      </View>
    );
  }

  return (
    <Image
      cachePolicy="disk"
      contentFit={contentFit}
      source={{ uri: url, cacheKey: assetId }}
      style={style}
      transition={180}
    />
  );
}
