class Menu {
  List<String> names;
  List<MenuAction> actions;
  String msg;

  Menu() : names = [], actions = [], msg = "Escolha uma opcao...";

  Menu.withMessage(this.msg) : names = [], actions = [];

  void addItem(String name, MenuAction action) {
    _check1(name);
    _checkAction(action);
    names.add(name);
    actions.add(action);
  }

  void removeItem(String name) {
    _check2(name);
    int pos = names.indexOf(name);
    names.removeAt(pos);
    actions.removeAt(pos);
  }

  String getMessage() {
    return msg;
  }

  void setMessage(String str) {
    if (str == null || str.isEmpty) {
      throw ArgumentError("Invalid Message: $str");
    }
    msg = str;
  }

  String getItemName(int i) {
    if (i < 0 || i >= names.length) {
      throw ArgumentError("Invalid name pos: $i");
    }
    return names[i];
  }

  MenuAction getAction(String name) {
    _check2(name);
    int pos = names.indexOf(name);
    return actions[pos];
  }

  MenuAction getActionInt(int i) {
    if (i < 0 || i >= actions.length) {
      throw ArgumentError("Invalid action pos: $i");
    }
    return actions[i];
  }

  List<String> getNames() {
    return List<String>.from(names);
  }

  List<MenuAction> getActions() {
    return List<MenuAction>.from(actions);
  }

  void display() {
    print(getMessage());
    for (int i = 0; i < names.length; i++) {
      print("\t$i: ${names[i]}");
    }
  }

  void _check2(String str) {
    if (str == null || str.isEmpty) {
      throw ArgumentError("Name error: $str");
    }
    if (!names.contains(str)) {
      throw ArgumentError("Invalid name");
    }
  }

  void _check1(String str) {
    if (str == null || str.isEmpty) {
      throw ArgumentError("Name error: $str");
    }
    if (names.contains(str)) {
      throw ArgumentError("Duplicate item");
    }
  }

  void _checkAction(MenuAction action) {
    if (action == null) {
      throw ArgumentError("Invalid action: $action");
    }
  }
}

abstract class MenuAction {
  execute();
}
