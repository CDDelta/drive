import 'package:drive/repositories/entities/entity.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'drive_entity.g.dart';

@JsonSerializable()
class DriveEntity extends Entity {
  @JsonKey(ignore: true)
  String id;
  @JsonKey(ignore: true)
  String owner;

  String rootFolderId;

  DriveEntity({this.id, this.rootFolderId});

  factory DriveEntity.fromRawEntity(RawEntity entity) =>
      DriveEntity.fromJson(entity.jsonData)
        ..id = entity.getTag(EntityTag.driveId)
        ..owner = entity.owner;

  factory DriveEntity.fromJson(Map<String, dynamic> json) =>
      _$DriveEntityFromJson(json);
  Map<String, dynamic> toJson() => _$DriveEntityToJson(this);
}