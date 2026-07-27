import { verifyToken } from "../services/security";
import { findUser } from "../services/userService";

export class AuthError extends Error {}

export function extractBearer(headers: Record<string, string>): string {
  const raw = headers["authorization"] ?? "";
  if (!raw.startsWith("Bearer ")) {
    throw new AuthError("missing bearer token");
  }
  return raw.slice("Bearer ".length);
}

export function authenticateRequest(headers: Record<string, string>) {
  const token = extractBearer(headers);
  const claims = verifyToken(token);
  const user = findUser(claims.email as string);
  if (!user) {
    throw new AuthError("unknown user");
  }
  return user;
}

export function requireAuth(headers: Record<string, string>) {
  return authenticateRequest(headers);
}
