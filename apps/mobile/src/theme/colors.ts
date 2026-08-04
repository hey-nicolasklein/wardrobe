import { Color } from 'expo-router';
import { Platform, type ColorValue, useColorScheme } from 'react-native';

export type AppColors = {
  error: ColorValue;
  label: ColorValue;
  onTint: ColorValue;
  secondaryBackground: ColorValue;
  secondaryLabel: ColorValue;
  separator: ColorValue;
  systemBackground: ColorValue;
  tint: ColorValue;
};

const nativeColors: AppColors = {
  error: Platform.select({
    ios: Color.ios.systemRed,
    android: Color.android.dynamic.error,
    default: '#b3261e',
  })!,
  label: Platform.select({
    ios: Color.ios.label,
    android: Color.android.dynamic.onSurface,
    default: '#111111',
  })!,
  onTint: Platform.select({
    ios: '#ffffff',
    android: Color.android.dynamic.onPrimary,
    default: '#ffffff',
  })!,
  secondaryBackground: Platform.select({
    ios: Color.ios.secondarySystemBackground,
    android: Color.android.dynamic.surfaceContainer,
    default: '#f2f2f7',
  })!,
  secondaryLabel: Platform.select({
    ios: Color.ios.secondaryLabel,
    android: Color.android.dynamic.onSurfaceVariant,
    default: '#5f6368',
  })!,
  separator: Platform.select({
    ios: Color.ios.separator,
    android: Color.android.dynamic.outlineVariant,
    default: '#d9d9de',
  })!,
  systemBackground: Platform.select({
    ios: Color.ios.systemBackground,
    android: Color.android.dynamic.surface,
    default: '#ffffff',
  })!,
  tint: Platform.select({
    ios: Color.ios.systemBlue,
    android: Color.android.dynamic.primary,
    default: '#1467d8',
  })!,
};

const webColors: Record<'light' | 'dark', AppColors> = {
  light: {
    error: '#b3261e',
    label: '#111111',
    onTint: '#ffffff',
    secondaryBackground: '#f2f2f7',
    secondaryLabel: '#5f6368',
    separator: '#d9d9de',
    systemBackground: '#ffffff',
    tint: '#1467d8',
  },
  dark: {
    error: '#ffb4ab',
    label: '#f5f5f7',
    onTint: '#0b326c',
    secondaryBackground: '#1c1c1e',
    secondaryLabel: '#aeb1b7',
    separator: '#3a3a3f',
    systemBackground: '#111113',
    tint: '#72a7ff',
  },
};

export function useAppColors(): AppColors {
  const colorScheme = useColorScheme();
  return process.env.EXPO_OS === 'web'
    ? webColors[colorScheme === 'dark' ? 'dark' : 'light']
    : nativeColors;
}
