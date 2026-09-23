import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final input = _parseArguments(arguments);
  final decoded = jsonDecode(await File(input).readAsString());
  if (decoded is! Map<String, dynamic> || decoded['traceEvents'] is! List) {
    throw const FormatException('Timeline must contain a traceEvents list.');
  }

  final events = _readDartEvents(decoded['traceEvents'] as List);
  final buildScopes = events.where((event) => event.name == 'BUILD').toList();
  if (buildScopes.isEmpty) {
    throw const FormatException('Timeline contains no Flutter BUILD events.');
  }
  final phaseScopes = events
      .where((event) => event.name.startsWith('MOZAIS_PERF.'))
      .toList();
  if (phaseScopes.isEmpty) {
    throw const FormatException('Timeline contains no Mozais phase markers.');
  }

  final threadCounts = <int, int>{};
  for (final event in buildScopes) {
    threadCounts.update(
      event.threadId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final uiThread = threadCounts.entries.reduce(
    (left, right) => left.value >= right.value ? left : right,
  );
  final uiEvents = events
      .where((event) => event.threadId == uiThread.key)
      .toList();

  for (final phase in phaseScopes) {
    final phaseEvents = uiEvents
        .where((event) => event != phase && _isWithinAny(event, [phase]))
        .toList();
    final phaseBuildScopes = phaseEvents
        .where((event) => event.name == 'BUILD')
        .toList();
    if (phaseBuildScopes.isEmpty) {
      throw FormatException('${phase.name} contains no Flutter BUILD events.');
    }
    stdout.writeln(
      '${phase.name}: UI BUILD scopes ${phaseBuildScopes.length}; '
      'p95 ${_percentile(phaseBuildScopes, 0.95).toStringAsFixed(2)} ms; '
      'max ${_maximum(phaseBuildScopes).toStringAsFixed(2)} ms',
    );

    final widgetBuilds = phaseEvents
        .where(
          (event) =>
              event.name != 'BUILD' && _isWithinAny(event, phaseBuildScopes),
        )
        .toList();
    final layoutScopes = phaseEvents
        .where(
          (event) => event.name == 'LAYOUT' || event.name == 'LAYOUT (root)',
        )
        .toList();
    final paintScopes = phaseEvents
        .where((event) => event.name == 'PAINT' || event.name == 'PAINT (root)')
        .toList();
    final renderObjects = phaseEvents
        .where((event) => event.name.startsWith('Render'))
        .toList();
    final layoutEvents = renderObjects
        .where((event) => _isWithinAny(event, layoutScopes))
        .toList();
    final paintEvents = renderObjects
        .where((event) => _isWithinAny(event, paintScopes))
        .toList();

    _writeRankedEvents('  Longest widget build events', widgetBuilds);
    _writeRankedEvents('  Longest RenderObject layout events', layoutEvents);
    _writeRankedEvents('  Longest RenderObject paint events', paintEvents);
  }
}

void _writeRankedEvents(String title, List<_TimelineEvent> events) {
  stdout.writeln('$title (inclusive duration):');
  final byName = <String, List<_TimelineEvent>>{};
  for (final event in events) {
    byName.putIfAbsent(event.name, () => []).add(event);
  }
  final ranked = byName.entries.toList()
    ..sort(
      (left, right) => _maximum(right.value).compareTo(_maximum(left.value)),
    );
  for (final entry in ranked.take(15)) {
    stdout.writeln(
      '  ${entry.key}: n=${entry.value.length}, '
      'max=${_maximum(entry.value).toStringAsFixed(2)} ms, '
      'p95=${_percentile(entry.value, 0.95).toStringAsFixed(2)} ms',
    );
  }
}

bool _isWithinAny(_TimelineEvent event, List<_TimelineEvent> scopes) {
  return scopes.any(
    (scope) =>
        event.startMicros >= scope.startMicros &&
        event.endMicros <= scope.endMicros,
  );
}

List<_TimelineEvent> _readDartEvents(List traceEvents) {
  final openEvents = <String, List<_OpenTimelineEvent>>{};
  final completeEvents = <_TimelineEvent>[];

  for (final value in traceEvents) {
    if (value is! Map<String, dynamic> || value['cat'] != 'Dart') {
      continue;
    }
    final name = value['name'];
    final phase = value['ph'];
    final timestamp = value['ts'];
    final threadId = value['tid'];
    if (name is! String || timestamp is! num || threadId is! int) {
      continue;
    }

    final thread = '${value['pid']}:$threadId';
    if (phase == 'B') {
      openEvents
          .putIfAbsent(thread, () => [])
          .add(
            _OpenTimelineEvent(name: name, timestampMicros: timestamp.toInt()),
          );
    } else if (phase == 'E') {
      final stack = openEvents[thread];
      if (stack == null) {
        continue;
      }
      final matchingIndex = stack.lastIndexWhere((event) => event.name == name);
      if (matchingIndex < 0) {
        continue;
      }
      final start = stack.removeAt(matchingIndex);
      final durationMicros = timestamp.toInt() - start.timestampMicros;
      if (durationMicros > 0) {
        completeEvents.add(
          _TimelineEvent(
            name: name,
            threadId: threadId,
            startMicros: start.timestampMicros,
            endMicros: timestamp.toInt(),
            durationMs: durationMicros / 1000,
          ),
        );
      }
    } else if (phase == 'X' && value['dur'] is num) {
      final durationMs = (value['dur'] as num) / 1000;
      if (durationMs > 0) {
        completeEvents.add(
          _TimelineEvent(
            name: name,
            threadId: threadId,
            startMicros: timestamp.toInt(),
            endMicros: timestamp.toInt() + (value['dur'] as num).toInt(),
            durationMs: durationMs.toDouble(),
          ),
        );
      }
    }
  }

  return completeEvents;
}

double _percentile(List<_TimelineEvent> events, double percentile) {
  final durations = events.map((event) => event.durationMs).toList()..sort();
  final index = ((durations.length - 1) * percentile).round();
  return durations[index];
}

double _maximum(List<_TimelineEvent> events) {
  return events
      .map((event) => event.durationMs)
      .reduce((left, right) => left > right ? left : right);
}

String _parseArguments(List<String> arguments) {
  if (arguments.length != 2 || arguments.first != '--input') {
    throw ArgumentError('Usage: --input <timeline.json>');
  }
  return arguments.last;
}

class _OpenTimelineEvent {
  const _OpenTimelineEvent({required this.name, required this.timestampMicros});

  final String name;
  final int timestampMicros;
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.name,
    required this.threadId,
    required this.startMicros,
    required this.endMicros,
    required this.durationMs,
  });

  final String name;
  final int threadId;
  final int startMicros;
  final int endMicros;
  final double durationMs;
}
