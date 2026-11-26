/// Slash commands and @mentions in the composer: finding the word being typed and removing it once chosen.
class SlashCommand {
  const SlashCommand(this.name, this.label, {this.choices});
  final String name, label;
  /// Fixed choices (priority), or null for free text. /module's choices come from the department.
  final List<String>? choices;
  bool get freeText => choices == null && name != 'module';
}

const slashCommands = [
  SlashCommand('priority', 'Priority', choices: ['High', 'Medium', 'Low']),
  SlashCommand('customer', 'Customer name or number'),
  SlashCommand('license', 'Licence number'),
  SlashCommand('module', 'Module'),
];

/// The word under the cursor, if it starts with [trigger] at the start of a word.
class ActiveToken {
  const ActiveToken(this.start, this.end, this.query);
  final int start, end;
  final String query;

  static ActiveToken? at(String text, int cursor, String trigger) {
    if (cursor < 0 || cursor > text.length) return null;
    var start = cursor;
    while (start > 0 && !_isSpace(text[start - 1])) {
      start--;
    }
    if (start >= text.length || text[start] != trigger) return null;
    var end = cursor;
    while (end < text.length && !_isSpace(text[end])) {
      end++;
    }
    return ActiveToken(start, end, text.substring(start + 1, cursor).toLowerCase());
  }

  /// The text with this word taken out (and one space tidied up).
  String removeFrom(String text) {
    final before = text.substring(0, start), after = text.substring(end);
    return (before.endsWith(' ') && after.startsWith(' ') ? before + after.substring(1) : before + after).trimLeft();
  }

  static bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t';
}

List<SlashCommand> matchingCommands(String query) => slashCommands.where((c) => c.name.startsWith(query)).toList();

/// Chip text for a chosen value.
String overrideLabel(String name, String value) => switch (name) {
      'priority' => 'Priority: $value',
      'customer' => 'Customer: $value',
      'license' => 'Licence: $value',
      'module' => 'Module: $value',
      _ => value,
    };
