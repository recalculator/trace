import { execute, queryBy } from "./db";

export class UserRepository {
  table = "users";

  persist(user: Record<string, unknown>) {
    return execute(this.table, user);
  }

  findByEmail(email: string) {
    return queryBy(this.table, "email", email);
  }
}

export function getRepository(): UserRepository {
  return new UserRepository();
}
