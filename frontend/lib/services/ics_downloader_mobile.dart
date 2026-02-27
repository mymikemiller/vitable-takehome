import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves ICS content to a temp file then opens the OS share sheet.
Future<void> downloadIcs(String icsContent, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(icsContent);
  await Share.shareXFiles([XFile(file.path, mimeType: 'text/calendar')]);
}
