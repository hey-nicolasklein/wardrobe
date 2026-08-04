# FORM mobile

The Expo SDK 57 client is the authenticated iPhone-first interface for the private FORM wardrobe. It uses Expo Router protected routes, native Owning and Wanting tabs, nested native stacks, and a toolbar Add action. Web uses the same routes with a responsive tab treatment; Android uses Material-native tab icons and headers.

## Run

Install once from the repository root, copy `.env.example` to an ignored `.env.local`, and start in Expo Go first:

```sh
npm install
npm run dev:mobile
```

`EXPO_PUBLIC_API_URL` is the only client-visible environment value. Browser sessions use an HTTP-only cookie; iOS and Android store the opaque native session token in Expo SecureStore.

## Verify

```sh
npm run verify --workspace=@form/mobile
npm exec --workspace=@form/mobile -- expo install --check
```

Verification typechecks the client, exercises session-state transitions, and creates the static web export.
