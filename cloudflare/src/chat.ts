export const maxChatTextLength = 240;
export const maxChatMessages = 100;

export interface TableChatMessage {
  id: string;
  seatIndex: number;
  author: string;
  text: string;
  sentAt: number;
}

const chatWordPattern = /[A-Za-zÀ-ÖØ-öø-ÿ]+(?:-[A-Za-zÀ-ÖØ-öø-ÿ]+)*/g;

const profanityPatterns = [
  /^caralh(?:o|a|os|as|inho|inha|ao|oes)?$/,
  /^porr(?:a|as|inha|inhas|ao|oes)?$/,
  /^put(?:a|o|as|os|aria|arias|inha|inho|ona|ao)?$/,
  /^fod(?:a|as|ase|am|ao|er|eu|endo|ido|ida|idos|idas)?$/,
  /^merd(?:a|as|inha|inhas|ao|oes)?$/,
  /^bost(?:a|as|inha|inhas|ao|oes)?$/,
  /^(?:bucet|bocet)(?:a|as|inha|inhas|ao|oes)?$/,
  /^cacet(?:e|es|inho|inhos|ao|oes)?$/,
  /^desgrac(?:a|ado|ada|ados|adas|adinho|adinha)?$/,
  /^arrombad(?:o|a|os|as|inho|inha)?$/,
  /^viad(?:o|a|os|as|inho|inha)?$/,
  /^piroc(?:a|as|ao|oes|inha|inhas)?$/,
  /^cu(?:zao|zoes|zinho|zinhos)?$/,
  /^corn(?:o|a|os|as|inho|inha)?$/,
  /^vagabund(?:o|a|os|as)?$/,
  /^escrot(?:o|a|os|as)?$/,
  /^(?:fdp|pqp|vsf)$/,
];

export function moderateChatText(text: string): string {
  return text.replace(chatWordPattern, (word) => {
    const canonical = word
      .toLocaleLowerCase("pt-BR")
      .normalize("NFD")
      .replace(/[\u0300-\u036f-]/g, "");
    if (!profanityPatterns.some((pattern) => pattern.test(canonical))) {
      return word;
    }
    const characters = Array.from(word);
    return `${characters[0]}${"*".repeat(characters.length - 1)}`;
  });
}

export function cleanChatText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (normalized.length === 0) return null;
  return Array.from(moderateChatText(normalized))
    .slice(0, maxChatTextLength)
    .join("");
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
