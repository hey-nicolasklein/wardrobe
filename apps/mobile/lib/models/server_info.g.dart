// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ServerInfo _$ServerInfoFromJson(Map<String, dynamic> json) => ServerInfo(
  service: json['service'] as String,
  contractVersion: (json['contractVersion'] as num).toInt(),
);

Map<String, dynamic> _$ServerInfoToJson(ServerInfo instance) =>
    <String, dynamic>{
      'service': instance.service,
      'contractVersion': instance.contractVersion,
    };

PersonalSession _$PersonalSessionFromJson(Map<String, dynamic> json) =>
    PersonalSession(accountId: json['accountId'] as String);

Map<String, dynamic> _$PersonalSessionToJson(PersonalSession instance) =>
    <String, dynamic>{'accountId': instance.accountId};
