import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Svara',
      'NewPipeExtractor',
    ], await rootBundle.loadString('assets/licenses/GPL-3.0.txt'));
    yield LicenseEntryWithLineBreaks([
      'Android extractor dependencies',
    ], await rootBundle.loadString('assets/licenses/NOTICE.txt'));
    for (final entry in {
      'Apache-2.0.txt': ['OkHttp', 'Okio', 'nanojson', 'jsr305', 'Kotlin'],
      'Jsoup.txt': ['jsoup'],
      'Rhino.txt': ['Rhino', 'rhino-engine'],
      'Protobuf.txt': ['protobuf-javalite'],
      'Desugar.txt': ['Android desugar JDK libraries'],
      'OkHttp-PublicSuffix-NOTICE.txt': ['OkHttp public suffix data'],
    }.entries) {
      yield LicenseEntryWithLineBreaks(
        entry.value,
        await rootBundle.loadString('assets/licenses/${entry.key}'),
      );
    }
  });
}
