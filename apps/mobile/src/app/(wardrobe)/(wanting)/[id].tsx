import { useLocalSearchParams } from 'expo-router';

import { WardrobeItemDetail } from '@/components/wardrobe-item-detail';

export default function WantingItemScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <WardrobeItemDetail collection="wanting" wardrobeItemId={id} />;
}
