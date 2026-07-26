import { createUser } from "../services/userService";
import { validateSignupInput } from "../services/validation";

const DEMO_USERS = [
  { email: "ada@example.com", password: "correct-horse-battery", displayName: "Ada" },
  { email: "grace@example.com", password: "hopper-was-here-42", displayName: "Grace" },
];

export function seedDemoUsers() {
  return DEMO_USERS.map((raw) => createUser(validateSignupInput(raw)));
}

export function main(): void {
  seedDemoUsers();
}
