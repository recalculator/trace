import { requireAuth } from "./middleware";
import { createUser, findUser } from "../services/userService";
import { validateSignupInput } from "../services/validation";

export function signup(payload: Record<string, string>) {
  const clean = validateSignupInput(payload);
  const result = createUser(clean);
  return { status: "created", data: result };
}

export function me(headers: Record<string, string>) {
  const user = requireAuth(headers);
  return { status: "ok", data: user };
}

export const getUser = (email: string) => {
  return { status: "ok", data: findUser(email) };
};
