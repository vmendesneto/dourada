import 'dart:io';

class SimpleFile {
  final File _file;

  SimpleFile(String filePath) : _file = File(filePath);

  bool createFile() {
    try {
      _file.createSync();
      return true; // Presumindo sucesso se não houver exceção
    } catch (e) {
      print(e);
      return false;
    }
  }

  bool writeFile(String txt) {
    try {
      _file.writeAsStringSync(txt);
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  String readFile() {
    try {
      return _file.readAsStringSync();
    } catch (e) {
      print(e);
      return '';
    }
  }

  List<String> readFileLines() {
    try {
      return _file.readAsLinesSync();
    } catch (e) {
      print(e);
      return [];
    }
  }

  bool fileExists() {
    return _file.existsSync();
  }
}
