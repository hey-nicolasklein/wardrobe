import { Image } from 'expo-image';
import { Stack, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, { useAnimatedStyle, useSharedValue, withSpring } from 'react-native-reanimated';

import { useWardrobeData } from '@/wardrobe/wardrobe-data';

export function FullscreenWardrobeMedia() {
  const { assetId, title } = useLocalSearchParams<{ assetId: string; title?: string }>();
  const { cache, mediaUrl } = useWardrobeData();
  const [url, setUrl] = useState(cache.mediaUrls[assetId] ?? null);
  const scale = useSharedValue(1);
  const savedScale = useSharedValue(1);

  useEffect(() => {
    let active = true;
    void mediaUrl(assetId).then((next) => {
      if (active && next) setUrl(next);
    });
    return () => {
      active = false;
    };
  }, [assetId, mediaUrl]);

  const pinch = Gesture.Pinch()
    .onUpdate((event) => {
      scale.value = Math.min(6, Math.max(1, savedScale.value * event.scale));
    })
    .onEnd(() => {
      savedScale.value = scale.value;
      if (scale.value < 1.05) {
        scale.value = withSpring(1);
        savedScale.value = 1;
      }
    });
  const doubleTap = Gesture.Tap().numberOfTaps(2).onEnd(() => {
    const next = scale.value > 1 ? 1 : 2.5;
    scale.value = withSpring(next);
    savedScale.value = next;
  });
  const imageStyle = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }));

  return (
    <GestureDetector gesture={Gesture.Simultaneous(pinch, doubleTap)}>
      <View style={{ backgroundColor: '#000000', flex: 1, justifyContent: 'center', overflow: 'hidden' }}>
        <Stack.Screen options={{ contentStyle: { backgroundColor: '#000000' }, headerStyle: { backgroundColor: '#000000' }, headerTintColor: '#ffffff', title: title ?? 'Media' }} />
        {url ? (
          <Animated.View style={[{ height: '100%', width: '100%' }, imageStyle]}>
            <Image cachePolicy="disk" contentFit="contain" source={{ uri: url, cacheKey: assetId }} style={{ height: '100%', width: '100%' }} />
          </Animated.View>
        ) : (
          <ActivityIndicator accessibilityLabel="Loading media" color="#ffffff" size="large" />
        )}
      </View>
    </GestureDetector>
  );
}
