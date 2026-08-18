export const maxChatTextLength = 240;
export const maxChatMessages = 100;

export interface TableChatMessage {
  id: string;
  seatIndex: number;
  author: string;
  text: string;
  sentAt: number;
}

export function cleanChatText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (normalized.length === 0) return null;
  return Array.from(normalized).slice(0, maxChatTextLength).join("");
}

export function normalizeChatMessages(value: unknown): TableChatMessage[] {
  if (!Array.isArray(value)) return [];
  const messages: TableChatMessage[] = [];
  for (const raw of value) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    const candidate = raw as Partial<TableChatMessage>;
    const text = cleanChatText(candidate.text);
    const author = typeof candidate.author === "string"
      ? Array.from(candidate.author.trim()).slice(0, 80).join("")
      : "";
    if (
      typeof candidate.id !== "string" ||
      !Number.isInteger(candidate.seatIndex) ||
      candidate.seatIndex! < 0 ||
      candidate.seatIndex! > 5 ||
      author.length === 0 ||
      text === null ||
      typeof candidate.sentAt !== "number" ||
      !Number.isFinite(candidate.sentAt)
    ) {
      continue;
    }
    messages.push({
      id: candidate.id,
      seatIndex: candidate.seatIndex!,
      author,
      text,
      sentAt: candidate.sentAt,
    });
  }
  return messages.slice(-maxChatMessages);
}
