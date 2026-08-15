export const MINIMUM_PASSWORD_LENGTH = 12;

export type PasswordValidation =
  | { ok: true; password: string }
  | { ok: false; error: string };

export function validatePasswordChange(
  passwordValue: unknown,
  confirmationValue: unknown,
): PasswordValidation {
  const password = typeof passwordValue === "string" ? passwordValue : "";
  const confirmation = typeof confirmationValue === "string" ? confirmationValue : "";

  if (password.length < MINIMUM_PASSWORD_LENGTH) {
    return { ok: false, error: `Password must contain at least ${MINIMUM_PASSWORD_LENGTH} characters.` };
  }
  if (password !== confirmation) {
    return { ok: false, error: "Passwords do not match." };
  }
  return { ok: true, password };
}
