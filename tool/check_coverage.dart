import 'dart:io';

void main(List<String> arguments) {
  final path = arguments.isEmpty ? 'coverage/lcov.info' : arguments.first;
  final threshold = arguments.length < 2 ? 30.0 : double.tryParse(arguments[1]);
  if (threshold == null || threshold < 0 || threshold > 100) {
    stderr.writeln('Coverage threshold must be between 0 and 100.');
    exitCode = 2;
    return;
  }

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Coverage file not found: $path');
    exitCode = 2;
    return;
  }

  var linesFound = 0;
  var linesHit = 0;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      linesFound += int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      linesHit += int.parse(line.substring(3));
    }
  }
  if (linesFound == 0) {
    stderr.writeln('Coverage file contains no line records: $path');
    exitCode = 2;
    return;
  }

  final percentage = linesHit * 100 / linesFound;
  stdout.writeln(
    'Line coverage: $linesHit/$linesFound '
    '(${percentage.toStringAsFixed(2)}%), '
    'required: ${threshold.toStringAsFixed(2)}%',
  );
  if (percentage < threshold) exitCode = 1;
}
