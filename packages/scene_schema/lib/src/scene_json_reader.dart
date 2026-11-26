import 'scene_style.dart';

typedef JsonMap = Map<String, Object?>;

void validateSceneAssetPath(String path) {
  if (!isSceneAssetPath(path)) {
    throw FormatException('Invalid scene asset path: $path');
  }
}

double getNonNegative(JsonMap json, String key) {
  final value = getDouble(json, key, fallback: 0);
  if (value < 0) {
    throw FormatException('$key must be finite and >= 0.');
  }
  return value;
}

T getEnumValue<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  throw FormatException('Invalid $field value: $name');
}

JsonMap getMap(JsonMap json, String key, {JsonMap? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  return getMapValue(value, key);
}

JsonMap getMapValue(Object? value, String field) {
  if (value is JsonMap) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return value.map<String, Object?>(
      (key, entryValue) => MapEntry(key.toString(), entryValue),
    );
  }
  throw FormatException('$field must be an object.');
}

List<Object?> getList(JsonMap json, String key) {
  final value = json[key];
  if (value is List<Object?>) {
    return value;
  }
  throw FormatException('$key must be a list.');
}

String getString(JsonMap json, String key, {String? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  return getStringValue(value, key);
}

String? findString(JsonMap json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  return getStringValue(value, key);
}

String getNonEmptyKey(String key, String field) {
  if (key.isEmpty) {
    throw FormatException('$field keys must be non-empty strings.');
  }
  return key;
}

String getStringValue(Object? value, String field) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$field must be a non-empty string.');
}

bool getBool(JsonMap json, String key, {required bool fallback}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

double getDouble(JsonMap json, String key, {double? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  throw FormatException('$key must be a number.');
}

int getInt(JsonMap json, String key, {int? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('$key must be an integer.');
}
