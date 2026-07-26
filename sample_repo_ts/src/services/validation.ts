const EMAIL = /^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$/;
const MIN_PASSWORD_LENGTH = 10;

export class ValidationError extends Error {}

export function checkEmail(email: string): string {
  const cleaned = email.trim().toLowerCase();
  if (!EMAIL.test(cleaned)) {
    throw new ValidationError("invalid email address");
  }
  return cleaned;
}

export function checkPassword(password: string): string {
  if (password.length < MIN_PASSWORD_LENGTH) {
    throw new ValidationError("password too short");
  }
  return password;
}

export function normaliseName(displayName: string): string {
  const cleaned = displayName.trim();
  return cleaned ? cleaned : "anonymous";
}

export function validateSignupInput(payload: Record<string, string>) {
  const email = checkEmail(payload.email ?? "");
  const password = checkPassword(payload.password ?? "");
  const displayName = normaliseName(payload.displayName ?? "");
  return { email, password, displayName };
}
