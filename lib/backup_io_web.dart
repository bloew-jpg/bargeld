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
  final input = html.FileUploadInputElement()..accept = '.json,application/json';
  input.click();

  await Future<void>.delayed(const Duration(milliseconds: 200));

  final file = input.files?.isEmpty ?? true ? null : input.files!.first;
  if (file == null) {
    return null;
  }

  final reader = html.FileReader();
  reader.readAsText(file);
  await reader.onLoad.first;
  return reader.result as String?;
}
