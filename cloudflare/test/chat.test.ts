import { describe, expect, it } from "vitest";
import {
  cleanChatText,
  maxChatMessages,
  maxChatTextLength,
  normalizeChatMessages,
} from "../src/chat";

describe("chat da mesa", () => {
  it("limpa espaços, controles e limita o tamanho", () => {
    expect(cleanChatText("  Olá\n\u0000 mesa   ")).toBe("Olá mesa");
    expect(Array.from(cleanChatText("x".repeat(400)) ?? "")).toHaveLength(
      maxChatTextLength,
    );
    expect(cleanChatText("   \n\t ")).toBeNull();
  });

  it("mantém somente mensagens válidas e as 100 mais recentes", () => {
    const source = Array.from({ length: maxChatMessages + 5 }, (_, index) => ({
      id: `m-${index}`,
      seatIndex: index % 6,
      author: `Jogador ${index % 6}`,
      text: `Mensagem ${index}`,
      sentAt: 1000 + index,
    }));
    source.splice(8, 0, {
      id: "inválida",
      seatIndex: 9,
      author: "Intruso",
      text: "não entra",
      sentAt: 1008,
    });

    const messages = normalizeChatMessages(source);
    expect(messages).toHaveLength(maxChatMessages);
    expect(messages[0]?.id).toBe("m-5");
    expect(messages.at(-1)?.id).toBe(`m-${maxChatMessages + 4}`);
  });
});
