import { router } from 'expo-router';
import { Pressable, Text, View } from 'react-native';

import { useSession } from '@/auth/session-context';
import { useAppColors } from '@/theme/colors';

export function WardrobeHeaderActions() {
  const colors = useAppColors();
  const { signOut } = useSession();

  return (
    <View style={{ alignItems: 'center', flexDirection: 'row', gap: 6 }}>
      <Pressable
        accessibilityLabel="Add wardrobe item"
        accessibilityRole="button"
        onPress={() => router.push('/add')}
        style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 8 })}>
        <Text style={{ color: colors.tint, fontSize: 16, fontWeight: '600' }}>Add</Text>
      </Pressable>
      <Pressable
        accessibilityLabel="Sign out"
        accessibilityRole="button"
        onPress={() => void signOut()}
        style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 8 })}>
        <Text style={{ color: colors.secondaryLabel, fontSize: 15 }}>Sign Out</Text>
      </Pressable>
    </View>
  );
}
