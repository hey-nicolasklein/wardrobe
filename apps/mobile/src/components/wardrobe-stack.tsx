import Stack from 'expo-router/stack';

import { WardrobeHeaderActions } from '@/components/wardrobe-header-actions';
import { useAppColors } from '@/theme/colors';

export function WardrobeStack({ title }: { title: string }) {
  const colors = useAppColors();

  return (
    <Stack
      screenOptions={{
        contentStyle: { backgroundColor: colors.systemBackground },
        headerBackButtonDisplayMode: 'minimal',
        headerLargeTitle: process.env.EXPO_OS === 'ios',
        headerLargeTitleShadowVisible: false,
        headerShadowVisible: false,
        headerTitleStyle: { color: colors.label },
      }}>
      <Stack.Screen
        name="index"
        options={{
          headerRight: process.env.EXPO_OS === 'ios' ? undefined : () => <WardrobeHeaderActions />,
          title,
        }}
      />
      <Stack.Screen name="[id]" options={{ headerLargeTitle: false }} />
      <Stack.Screen name="media" options={{ headerLargeTitle: false }} />
    </Stack>
  );
}
