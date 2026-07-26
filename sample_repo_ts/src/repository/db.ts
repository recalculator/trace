const TABLES: Record<string, Record<string, unknown>[]> = { users: [] };
const SEQUENCE: Record<string, number> = { users: 0 };

export function connect() {
  return { tables: TABLES, sequence: SEQUENCE };
}

export function nextId(table: string): number {
  SEQUENCE[table] = (SEQUENCE[table] ?? 0) + 1;
  return SEQUENCE[table];
}

export function execute(table: string, row: Record<string, unknown>) {
  const handle = connect();
  const id = nextId(table);
  const stored = { ...row, id };
  handle.tables[table].push(stored);
  return stored;
}

export function queryBy(table: string, field: string, value: string) {
  const handle = connect();
  return handle.tables[table].find((r) => r[field] === value) ?? {};
}
