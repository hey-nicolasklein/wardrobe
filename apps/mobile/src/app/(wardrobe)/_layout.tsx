import { NativeTabs } from 'expo-router/unstable-native-tabs';

import { useAppColors } from '@/theme/colors';

export default function WardrobeTabsLayout() {
  const colors = useAppColors();

  return (
    <NativeTabs minimizeBehavior="onScrollDown" tintColor={colors.tint}>
      <NativeTabs.Trigger name="(owning)">
        <NativeTabs.Trigger.Icon sf={{ default: 'hanger', selected: 'hanger' }} md="checkroom" />
        <NativeTabs.Trigger.Label>Owning</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(wanting)">
        <NativeTabs.Trigger.Icon sf={{ default: 'heart', selected: 'heart.fill' }} md="favorite" />
        <NativeTabs.Trigger.Label>Wanting</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
