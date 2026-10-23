// Signs the page's browser context in as the populated fixture account
// (fixtureCredentials.populated in packages/service/src/fixtures.ts). The
// session cookie is shared with every page of that context.
export async function signIn(page) {
  const response = await page.request.post('http://127.0.0.1:18444/v1/auth/sign-in', {
    data: { email: 'test@example.test', password: 'test', transport: 'cookie' },
  });
  if (!response.ok()) throw new Error(`Fixture sign-in failed with ${response.status()}.`);
}
