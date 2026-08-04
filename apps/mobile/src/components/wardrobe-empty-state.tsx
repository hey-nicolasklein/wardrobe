import { router, Stack } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';

import { useSession } from '@/auth/session-context';
import { useAppColors } from '@/theme/colors';

export function WardrobeEmptyState({ kind }: { kind: 'Owning' | 'Wanting' }) {
  const colors = useAppColors();
  const sessionContext = useSession();
  const { session, signOut } = sessionContext;
  const signOutError =
    sessionContext.status === 'signed-in' ? sessionContext.signOutError : null;

  return (
    <>
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{
          alignItems: 'center',
          flexGrow: 1,
          justifyContent: 'center',
          padding: 24,
        }}
        style={{ backgroundColor: colors.systemBackground }}>
        <View style={{ alignItems: 'center', gap: 12, maxWidth: 420 }}>
          <Text
            selectable
            style={{
              color: colors.label,
              fontSize: 22,
              fontWeight: '700',
              textAlign: 'center',
            }}>
            Your {kind.toLowerCase()} wardrobe is empty
          </Text>
          <Text
            selectable
            style={{
              color: colors.secondaryLabel,
              fontSize: 16,
              lineHeight: 23,
              textAlign: 'center',
            }}>
            Add a Source Photo to begin building your private wardrobe.
          </Text>
          {signOutError ? (
            <Text
              accessibilityRole="alert"
              selectable
              style={{ color: colors.error, lineHeight: 21, textAlign: 'center' }}>
              {signOutError}
            </Text>
          ) : null}
          <Pressable
            accessibilityRole="button"
            onPress={() => router.push('/add')}
            style={({ pressed }) => ({
              borderColor: colors.separator,
              borderCurve: 'continuous',
              borderRadius: 999,
              borderWidth: 1,
              opacity: pressed ? 0.6 : 1,
              paddingHorizontal: 18,
              paddingVertical: 10,
            })}>
            <Text style={{ color: colors.tint, fontSize: 16, fontWeight: '600' }}>Add Item</Text>
          </Pressable>
        </View>
      </ScrollView>
      <Stack.Screen.Title large>{kind}</Stack.Screen.Title>
      {process.env.EXPO_OS === 'ios' ? (
        <Stack.Toolbar placement="right">
          <Stack.Toolbar.Button icon="plus" onPress={() => router.push('/add')} />
          <Stack.Toolbar.Menu icon="ellipsis.circle">
            <Stack.Toolbar.MenuAction
              disabled
              icon="person.circle"
              subtitle={session?.email ?? undefined}>
              Account
            </Stack.Toolbar.MenuAction>
            <Stack.Toolbar.MenuAction
              destructive
              icon="rectangle.portrait.and.arrow.right"
              onPress={() => void signOut()}>
              Sign Out
            </Stack.Toolbar.MenuAction>
          </Stack.Toolbar.Menu>
        </Stack.Toolbar>
      ) : null}
    </>
  );
}
