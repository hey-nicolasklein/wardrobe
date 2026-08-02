export type Category = 'Tops' | 'Bottoms' | 'Outerwear' | 'Shoes' | 'Accessories';

export interface WardrobeItem {
  id: string;
  name: string;
  brand: string;
  category: Category;
  image?: string;
  source: 'wardrobe' | 'wishlist';
  origin?: 'manual' | 'shop' | 'suggested';
  url?: string;
}

export interface LookSuggestion {
  id: string;
  name: string;
  category: Category;
  confidence: number;
  reason: string;
  status: 'pending' | 'accepted' | 'rejected';
}

export type ImageGenerationQuality = 'high';

export interface GeneratedLookSettings {
  characterImage: string;
  items: Array<Pick<WardrobeItem, 'name' | 'category' | 'image'>>;
  note: string;
  quality: ImageGenerationQuality;
}

export interface Look {
  id: string;
  title: string;
  itemIds: string[];
  image: string;
  note: string;
  createdAt: string;
  kind: 'generated' | 'snap';
  suggestions: LookSuggestion[];
  generation?: GeneratedLookSettings;
}

export interface ProfileMessage {
  id: string;
  role: 'assistant' | 'user';
  text: string;
  image?: string;
}

export interface FittingProfile {
  name: string;
  image: string;
  referencePhotos: string[];
  notes: string;
  messages: ProfileMessage[];
  updatedAt: string;
}

export interface FittingProfileDraft {
  photos: string[];
  name: string;
  notes: string;
  editingSources: boolean;
  savedAt: string;
}
