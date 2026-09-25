export const PERSONAL_RESET_LEGACY_CONFIRMATION = 'ALLES LÖSCHEN';

export const PERSONAL_RESET_CONFIRMATION = 'DELETE EVERYTHING';

export function isPersonalResetConfirmation(value: unknown): boolean {
  return (
    value === PERSONAL_RESET_LEGACY_CONFIRMATION ||
    value === PERSONAL_RESET_CONFIRMATION
  );
}
