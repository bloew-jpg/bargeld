import 'backup_io_stub.dart'
    if (dart.library.html) 'backup_io_web.dart';

Future<void> downloadTextFile(List<int> bytes, String fileName) {
  return downloadTextFileWeb(bytes, fileName);
}

Future<String?> pickTextFile() {
  return pickTextFileWeb();
}
