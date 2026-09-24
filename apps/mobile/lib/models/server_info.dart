import 'package:json_annotation/json_annotation.dart';

part 'server_info.g.dart';

@JsonSerializable()
class ServerInfo {
  const ServerInfo({required this.service, required this.contractVersion});

  factory ServerInfo.fromJson(Map<String, dynamic> json) =>
      _$ServerInfoFromJson(json);

  static const supportedContractVersion = 5;

  final String service;
  final int contractVersion;

  bool get isCompatible =>
      service == 'form-api' && contractVersion == supportedContractVersion;

  Map<String, dynamic> toJson() => _$ServerInfoToJson(this);
}

@JsonSerializable()
class PersonalSession {
  const PersonalSession({required this.accountId});

  factory PersonalSession.fromJson(Map<String, dynamic> json) =>
      _$PersonalSessionFromJson(json);

  final String accountId;

  Map<String, dynamic> toJson() => _$PersonalSessionToJson(this);
}
