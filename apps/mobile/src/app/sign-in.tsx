import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';

import { useSession } from '@/auth/session-context';
import { ApiClientError } from '@/lib/api-client';
import { useAppColors } from '@/theme/colors';

function signInErrorMessage(error: unknown): string {
  if (error instanceof ApiClientError) return error.detail.message;
  return 'FORM could not sign you in. Check the wardrobe service and try again.';
}

export default function SignInScreen() {
  const colors = useAppColors();
  const { signIn } = useSession();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const canSubmit = email.trim().length > 0 && password.length > 0 && !isSubmitting;

  async function submit() {
    if (!canSubmit) return;
    setError(null);
    setIsSubmitting(true);
    try {
      const login = email.trim().toLowerCase() === 'test' ? 'test@example.test' : email.trim();
      await signIn(login, password);
    } catch (caught) {
      setError(signInErrorMessage(caught));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <ScrollView
      automaticallyAdjustKeyboardInsets
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      contentContainerStyle={{
        alignItems: 'center',
        flexGrow: 1,
        justifyContent: 'center',
        paddingHorizontal: 24,
        paddingVertical: 48,
      }}
      style={{ backgroundColor: colors.systemBackground }}>
      <View style={{ gap: 24, maxWidth: 420, width: '100%' }}>
        <View style={{ gap: 8 }}>
          <Text
            selectable
            style={{
              color: colors.label,
              fontSize: 42,
              fontWeight: '700',
              letterSpacing: -1.5,
            }}>
            FORM
          </Text>
          <Text selectable style={{ color: colors.secondaryLabel, fontSize: 17, lineHeight: 24 }}>
            Sign in with your administrator-created wardrobe account.
          </Text>
        </View>

        <View style={{ gap: 12 }}>
          <TextInput
            accessibilityLabel="Email or test login"
            autoCapitalize="none"
            autoComplete="email"
            autoCorrect={false}
            keyboardType="email-address"
            onChangeText={setEmail}
            onSubmitEditing={() => undefined}
            placeholder="Email or test"
            placeholderTextColor={colors.secondaryLabel}
            returnKeyType="next"
            textContentType="username"
            value={email}
            style={{
              borderColor: colors.separator,
              borderCurve: 'continuous',
              borderRadius: 12,
              borderWidth: 1,
              color: colors.label,
              fontSize: 17,
              paddingHorizontal: 16,
              paddingVertical: 14,
            }}
          />
          <TextInput
            accessibilityLabel="Password"
            autoCapitalize="none"
            autoComplete="current-password"
            onChangeText={setPassword}
            onSubmitEditing={() => void submit()}
            placeholder="Password"
            placeholderTextColor={colors.secondaryLabel}
            returnKeyType="go"
            secureTextEntry
            textContentType="password"
            value={password}
            style={{
              borderColor: colors.separator,
              borderCurve: 'continuous',
              borderRadius: 12,
              borderWidth: 1,
              color: colors.label,
              fontSize: 17,
              paddingHorizontal: 16,
              paddingVertical: 14,
            }}
          />
          {error ? (
            <Text
              accessibilityRole="alert"
              selectable
              style={{ color: colors.error, lineHeight: 20 }}>
              {error}
            </Text>
          ) : null}
          <Pressable
            accessibilityRole="button"
            disabled={!canSubmit}
            onPress={() => void submit()}
            style={({ pressed }) => ({
              alignItems: 'center',
              backgroundColor: colors.tint,
              borderCurve: 'continuous',
              borderRadius: 12,
              minHeight: 50,
              justifyContent: 'center',
              opacity: !canSubmit ? 0.45 : pressed ? 0.72 : 1,
              paddingHorizontal: 18,
            })}>
            {isSubmitting ? (
              <ActivityIndicator color={colors.onTint} />
            ) : (
              <Text style={{ color: colors.onTint, fontSize: 17, fontWeight: '700' }}>Sign In</Text>
            )}
          </Pressable>
        </View>
      </View>
    </ScrollView>
  );
}
