// Regenerates test/analytics/event_catalog.txt from lib/.
//
//   dart run tool/analytics_events.dart          # rewrite the catalog
//   dart run tool/analytics_events.dart --check  # print drift, exit 1 on any
//
// After regenerating, mirror the change in the Notion PostHog catalog
// (Kute docs -> PostHog -> Events pages): docs follow code.

import 'dart:io';

import '../test/analytics/event_catalog_extractor.dart';

const catalogPath = 'test/analytics/event_catalog.txt';

void main(List<String> args) {
  final scan = scanAnalyticsEvents();
  if (scan.unresolved.isNotEmpty) {
    stderr.writeln('Event names the scanner cannot resolve statically:');
    scan.unresolved.forEach(stderr.writeln);
    exit(2);
  }
  final names = scan.events.toList()..sort();
  final file = File(catalogPath);
  if (args.contains('--check')) {
    final current = file.existsSync()
        ? file.readAsLinesSync().where((l) => l.isNotEmpty).toSet()
        : <String>{};
    final added = names.where((n) => !current.contains(n)).toList();
    final removed = current.where((n) => !scan.events.contains(n)).toList()
      ..sort();
    for (final n in added) {
      stdout.writeln('+ $n');
    }
    for (final n in removed) {
      stdout.writeln('- $n');
    }
    stdout.writeln(
        '${names.length} events in lib/, ${current.length} catalogued');
    exit(added.isEmpty && removed.isEmpty ? 0 : 1);
  }
  file.writeAsStringSync('${names.join('\n')}\n');
  stdout.writeln('Wrote ${names.length} events to $catalogPath '
      '(${scan.filesScanned} files, ${scan.callsSeen} emitting calls).');
}
