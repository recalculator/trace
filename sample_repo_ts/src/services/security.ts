import { createHash, createHmac } from "crypto";

const SECRET = "demo-secret-not-for-production";

export function saltFor(email: string): string {
  return createHash("sha256").update(email).digest("hex").slice(0, 16);
}

export function hashPassword(password: string, email: string): string {
  const salt = saltFor(email);
  return createHash("sha256").update(salt + password).digest("hex");
}

export function signBody(body: string): string {
  return createHmac("sha256", SECRET).update(body).digest("base64url");
}

export function generateToken(userId: number, email: string): string {
  const body = Buffer.from(JSON.stringify({ sub: userId, email })).toString("base64url");
  return body + "." + signBody(body);
}

export function verifyToken(token: string): Record<string, unknown> {
  const [body, signature] = token.split(".");
  if (signBody(body) !== signature) {
    throw new Error("bad signature");
  }
  return decodeToken(body);
}

export function decodeToken(body: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
}
