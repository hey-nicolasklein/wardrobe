import {
  TabList,
  TabSlot,
  Tabs,
  TabTrigger,
  type TabTriggerSlotProps,
} from 'expo-router/ui';
import { Pressable, Text } from 'react-native';

import { useAppColors } from '@/theme/colors';

function WebTabButton({ children, isFocused, ...props }: TabTriggerSlotProps) {
  const colors = useAppColors();

  return (
    <Pressable
      {...props}
      style={({ pressed }) => ({
        backgroundColor: isFocused ? colors.separator : 'transparent',
        borderRadius: 999,
        opacity: pressed ? 0.65 : 1,
        paddingHorizontal: 18,
        paddingVertical: 10,
      })}>
      <Text style={{ color: colors.label, fontWeight: '600' }}>{children}</Text>
    </Pressable>
  );
}

export default function WardrobeWebTabsLayout() {
  const colors = useAppColors();

  return (
    <Tabs>
      <TabSlot style={{ backgroundColor: colors.systemBackground, height: '100%' }} />
      <TabList
        style={{
          alignSelf: 'center',
          backgroundColor: colors.systemBackground,
          borderColor: colors.separator,
          borderCurve: 'continuous',
          borderRadius: 999,
          borderWidth: 1,
          bottom: 20,
          boxShadow: '0 8px 24px rgba(0, 0, 0, 0.12)',
          gap: 4,
          padding: 4,
          position: 'absolute',
        }}>
        <TabTrigger asChild href="/(wardrobe)/(owning)" name="owning">
          <WebTabButton>Owning</WebTabButton>
        </TabTrigger>
        <TabTrigger asChild href="/(wardrobe)/(wanting)" name="wanting">
          <WebTabButton>Wanting</WebTabButton>
        </TabTrigger>
      </TabList>
    </Tabs>
  );
}
