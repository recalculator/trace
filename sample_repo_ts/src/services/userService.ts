import { getRepository } from "../repository/userRepository";
import { generateToken, hashPassword } from "./security";

export function buildRecord(payload: Record<string, string>, passwordHash: string) {
  return {
    email: payload.email,
    displayName: payload.displayName,
    passwordHash,
  };
}

export function publicView(stored: Record<string, unknown>) {
  return { id: stored.id, email: stored.email, displayName: stored.displayName };
}

export function createUser(payload: Record<string, string>) {
  const passwordHash = hashPassword(payload.password, payload.email);
  const record = buildRecord(payload, passwordHash);
  const repo = getRepository();
  const stored = repo.persist(record);
  const token = generateToken(stored.id as number, stored.email as string);
  return { user: publicView(stored), token };
}

export function findUser(email: string) {
  const repo = getRepository();
  return repo.findByEmail(email);
}
