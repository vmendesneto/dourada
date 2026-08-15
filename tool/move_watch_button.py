from pathlib import Path

path = Path('lib/ui/lobby_page.dart')
text = path.read_text()

old_header = '''              Flexible(\n                child: Container(\n                  padding:\n                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),\n                  decoration: BoxDecoration(\n                    color: color.withValues(alpha: .14),\n                    borderRadius: BorderRadius.circular(20),\n                  ),\n                  child: FittedBox(\n                    fit: BoxFit.scaleDown,\n                    child: Text(status,\n                        style: TextStyle(\n                            color: color,\n                            fontSize: 10,\n                            fontWeight: FontWeight.w900)),\n                  ),\n                ),\n              ),\n'''
new_header = '''              Flexible(\n                child: Container(\n                  padding:\n                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),\n                  decoration: BoxDecoration(\n                    color: color.withValues(alpha: .14),\n                    borderRadius: BorderRadius.circular(20),\n                  ),\n                  child: FittedBox(\n                    fit: BoxFit.scaleDown,\n                    child: Text(status,\n                        style: TextStyle(\n                            color: color,\n                            fontSize: 10,\n                            fontWeight: FontWeight.w900)),\n                  ),\n                ),\n              ),\n              if (table.phase == LobbyTablePhase.playing) ...[\n                const SizedBox(width: 6),\n                OutlinedButton.icon(\n                  key: ValueKey('ver-mesa-${table.tableNumber}'),\n                  onPressed: opening ? null : onWatch,\n                  style: OutlinedButton.styleFrom(\n                    foregroundColor: color,\n                    side: BorderSide(color: color.withValues(alpha: .8)),\n                    backgroundColor: color.withValues(alpha: .08),\n                    visualDensity: VisualDensity.compact,\n                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,\n                    minimumSize: const Size(0, 28),\n                    padding: const EdgeInsets.symmetric(horizontal: 8),\n                    textStyle: const TextStyle(\n                      fontSize: 10,\n                      fontWeight: FontWeight.w900,\n                    ),\n                  ),\n                  icon: opening\n                      ? const SizedBox.square(\n                          dimension: 12,\n                          child: CircularProgressIndicator(strokeWidth: 2),\n                        )\n                      : const Icon(Icons.visibility_rounded, size: 15),\n                  label: const Text('VER'),\n                ),\n              ],\n'''
if old_header not in text:
    raise SystemExit('Cabeçalho da mesa não encontrado')
text = text.replace(old_header, new_header, 1)

old_button = '''              onPressed: opening\n                  ? null\n                  : table.phase == LobbyTablePhase.playing\n                      ? onWatch\n                      : onEnter,\n'''
new_button = '''              onPressed: opening || table.phase == LobbyTablePhase.playing\n                  ? null\n                  : onEnter,\n'''
if old_button not in text:
    raise SystemExit('Ação do botão Entrar não encontrada')
text = text.replace(old_button, new_button, 1)

old_label = '''              child: opening\n                  ? const SizedBox.square(\n                      dimension: 18,\n                      child: CircularProgressIndicator(strokeWidth: 2),\n                    )\n                  : Text(table.phase == LobbyTablePhase.playing\n                      ? 'VER'\n                      : requiresLogin\n                          ? 'FAÇA LOGIN PARA ENTRAR'\n                          : 'ENTRAR EM UMA MESA'),\n'''
new_label = '''              child: opening && table.phase != LobbyTablePhase.playing\n                  ? const SizedBox.square(\n                      dimension: 18,\n                      child: CircularProgressIndicator(strokeWidth: 2),\n                    )\n                  : Text(requiresLogin\n                      ? 'FAÇA LOGIN PARA ENTRAR'\n                      : 'ENTRAR EM UMA MESA'),\n'''
if old_label not in text:
    raise SystemExit('Rótulo do botão Entrar não encontrado')
text = text.replace(old_label, new_label, 1)

path.write_text(text)
print('Botão VER separado do botão ENTRAR.')
