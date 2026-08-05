import { useLocalSearchParams } from 'expo-router';

import { WardrobeItemDetail } from '@/components/wardrobe-item-detail';

export default function OwningItemScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <WardrobeItemDetail collection="owning" wardrobeItemId={id} />;
}
