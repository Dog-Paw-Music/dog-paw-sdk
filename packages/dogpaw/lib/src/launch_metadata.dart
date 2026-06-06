import 'dart:convert';
import 'dart:io';

/// Canonical executable flag used to pass Dog Paw launch metadata files.
const String dogpawLaunchMetadataFlag = '--dogpaw-launch-metadata';

/// Parse Dog Paw launch metadata from executable arguments.
///
/// Purpose:
/// Reads the standard Dog Paw launch-metadata flag and decodes the referenced
/// JSON object so Flutter apps can share the same startup convention as native
/// Dog Paw apps launched by Epiphany or IDE configs.
///
/// Parameters:
/// - `executableArguments`: Full executable argument list to inspect for the
///   `--dogpaw-launch-metadata` flag and its following JSON file path.
///
/// Return value:
/// - Parsed JSON object when the launch flag is present.
/// - `null` when the launch flag is absent.
///
/// Requirements/Preconditions:
/// - If the launch flag is present, it must be followed by a readable file path.
/// - The referenced file must contain a top-level JSON object.
///
/// Guarantees/Postconditions:
/// - Missing launch metadata is treated as a normal manual-launch case.
/// - Throws `FormatException` when the flag is missing its path or when the
///   metadata file does not contain a JSON object.
/// - Propagates `FileSystemException` when the referenced file cannot be read.
///
/// Invariants:
/// - This helper only reads launch metadata and does not mutate process state.
Future<Map<String, dynamic>?> parseDogpawLaunchMetadata({
  required List<String> executableArguments,
}) async {
  for (int index = 0; index < executableArguments.length; index++) {
    if (executableArguments[index] != dogpawLaunchMetadataFlag) {
      continue;
    }

    if (index + 1 >= executableArguments.length) {
      throw const FormatException(
        'Expected a JSON file path after --dogpaw-launch-metadata.',
      );
    }

    final File metadataFile = File(executableArguments[index + 1]);
    final Object? decodedMetadata =
        jsonDecode(await metadataFile.readAsString());

    if (decodedMetadata is! Map) {
      throw const FormatException(
        'Dog Paw launch metadata must decode to a JSON object.',
      );
    }

    return Map<String, dynamic>.from(decodedMetadata as Map<Object?, Object?>);
  }

  return null;
}
