import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadTextFileWeb(List<int> bytes, String fileName) async {
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body!.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<String?> pickTextFileWeb() async {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = '.json,application/json';

  void cleanup() {
    input.remove();
  }

  void onChange(html.Event event) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return;
    }

    final file = files.first;
    final reader = html.FileReader();
    reader.onLoad.first.then((_) {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(reader.result as String?);
      }
    });
    reader.onError.first.then((event) {
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(event);
      }
    });
    reader.readAsText(file);
  }

  input.onChange.listen((event) => onChange(event));
  input.onCancel.listen((_) {
    cleanup();
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  });

  html.document.body!.append(input);
  input.click();

  return completer.future;
}
