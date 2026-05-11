import 'package:freezed_annotation/freezed_annotation.dart';

part 'singbox_rule.freezed.dart';
part 'singbox_rule.g.dart';

class StringListJsonConverter implements JsonConverter<String?, Object?> {
  const StringListJsonConverter();

  @override
  String? fromJson(Object? json) {
    if (json == null) return null;
    if (json is String) return json;
    if (json is List) {
      return json.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');
    }
    return json.toString();
  }

  @override
  Object? toJson(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

@freezed
class SingboxRule with _$SingboxRule {
  const SingboxRule._();

  @JsonSerializable(fieldRename: FieldRename.kebab)
  const factory SingboxRule({
    String? ruleSetUrl,
    @StringListJsonConverter()
    @JsonKey(name: 'domain', includeIfNull: false)
    String? domains,
    @StringListJsonConverter()
    @JsonKey(name: 'ip', includeIfNull: false)
    String? ip,
    String? port,
    String? protocol,
    @Default(RuleNetwork.tcpAndUdp) RuleNetwork network,
    @Default(RuleOutbound.proxy) RuleOutbound outbound,
  }) = _SingboxRule;

  factory SingboxRule.fromJson(Map<String, dynamic> json) => _$SingboxRuleFromJson(json);
}

enum RuleOutbound { proxy, bypass, block }

@JsonEnum(valueField: 'key')
enum RuleNetwork {
  tcpAndUdp(""),
  tcp("tcp"),
  udp("udp");

  const RuleNetwork(this.key);

  final String? key;
}
