import { router, Stack } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';

import { useAppColors } from '@/theme/colors';

export default function AddItemScreen() {
  const colors = useAppColors();

  return (
    <>
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ gap: 20, padding: 24 }}
        style={{ backgroundColor: colors.systemBackground }}>
        <View style={{ gap: 8 }}>
          <Text selectable style={{ color: colors.label, fontSize: 22, fontWeight: '700' }}>
            Start with a Source Photo
          </Text>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: 16, lineHeight: 23 }}>
            FORM will use one private photo to identify one or more wardrobe items. You will review every proposal before generation.
          </Text>
        </View>
        <View
          style={{
            borderColor: colors.separator,
            borderCurve: 'continuous',
            borderRadius: 16,
            borderWidth: 1,
            gap: 8,
            padding: 18,
          }}>
          <Text selectable style={{ color: colors.label, fontSize: 17, fontWeight: '600' }}>
            Photo intake is coming next
          </Text>
          <Text selectable style={{ color: colors.secondaryLabel, lineHeight: 21 }}>
            This release establishes the secure app shell. Camera and photo-library intake will be connected in the guided Add flow.
          </Text>
        </View>
        {process.env.EXPO_OS !== 'ios' ? (
          <Pressable
            accessibilityRole="button"
            onPress={() => router.back()}
            style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, paddingVertical: 10 })}>
            <Text style={{ color: colors.tint, fontSize: 17, fontWeight: '600' }}>Done</Text>
          </Pressable>
        ) : null}
      </ScrollView>
      {process.env.EXPO_OS === 'ios' ? (
        <Stack.Toolbar placement="right">
          <Stack.Toolbar.Button onPress={() => router.back()}>Done</Stack.Toolbar.Button>
        </Stack.Toolbar>
      ) : null}
    </>
  );
}
