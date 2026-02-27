// Conditional export: web implementation on web, mobile on iOS/Android.
export 'ics_downloader_mobile.dart'
    if (dart.library.html) 'ics_downloader_web.dart';
