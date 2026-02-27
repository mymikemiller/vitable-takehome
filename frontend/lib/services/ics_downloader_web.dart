// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Downloads an ICS file in the browser by creating a Blob URL and clicking it.
Future<void> downloadIcs(String icsContent, String filename) async {
  final blob = html.Blob([icsContent], 'text/calendar');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
