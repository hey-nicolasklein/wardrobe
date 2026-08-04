import { DarkTheme, DefaultTheme, ThemeProvider } from 'expo-router/react-navigation';
import Stack from 'expo-router/stack';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';
import { ActivityIndicator, Pressable, ScrollView, Text, useColorScheme, View } from 'react-native';

import { SessionProvider, useSession } from '@/auth/session-context';
import { useAppColors } from '@/theme/colors';

void SplashScreen.preventAutoHideAsync().catch(() => undefined);

function RootNavigator() {
  const colorScheme = useColorScheme();
  const colors = useAppColors();
  const { restore, session, status } = useSession();

  useEffect(() => {
    if (status !== 'restoring') void SplashScreen.hideAsync();
  }, [status]);

  if (status === 'restoring') {
    return (
      <View
        style={{
          alignItems: 'center',
          backgroundColor: colors.systemBackground,
          flex: 1,
          justifyContent: 'center',
        }}>
        <ActivityIndicator accessibilityLabel="Restoring session" color={colors.tint} size="large" />
      </View>
    );
  }

  if (status === 'restore-error') {
    return (
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{
          alignItems: 'center',
          flexGrow: 1,
          gap: 12,
          justifyContent: 'center',
          padding: 24,
        }}
        style={{ backgroundColor: colors.systemBackground }}>
        <Text selectable style={{ color: colors.label, fontSize: 22, fontWeight: '700' }}>
          FORM couldn&apos;t restore your session
        </Text>
        <Text selectable style={{ color: colors.secondaryLabel, maxWidth: 420, textAlign: 'center' }}>
          Check that the wardrobe service is reachable, then try again.
        </Text>
        <Pressable
          accessibilityRole="button"
          onPress={() => void restore()}
          style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 12 })}>
          <Text style={{ color: colors.tint, fontSize: 17, fontWeight: '600' }}>Try Again</Text>
        </Pressable>
      </ScrollView>
    );
  }

  return (
    <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Protected guard={!session}>
          <Stack.Screen name="sign-in" />
        </Stack.Protected>
        <Stack.Protected guard={session !== null}>
          <Stack.Screen name="(wardrobe)" />
          <Stack.Screen
            name="add"
            options={{
              contentStyle: { backgroundColor: colors.systemBackground },
              headerShown: true,
              presentation: process.env.EXPO_OS === 'ios' ? 'formSheet' : 'modal',
              sheetAllowedDetents: [0.55, 1],
              sheetGrabberVisible: true,
              title: 'Add Item',
            }}
          />
        </Stack.Protected>
      </Stack>
    </ThemeProvider>
  );
}

export default function RootLayout() {
  return (
    <SessionProvider>
      <RootNavigator />
    </SessionProvider>
  );
}
