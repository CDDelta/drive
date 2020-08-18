import 'dart:async';

import 'package:drive/repositories/entities/entities.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/models.dart';

part 'drive_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries, FileEntries])
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  final _uuid = Uuid();

  DriveDao(Database db) : super(db);

  Stream<Drive> watchDrive(String driveId) =>
      (select(drives)..where((d) => d.id.equals(driveId))).watchSingle();

  Future<Drive> getDriveById(String driveId) =>
      (select(drives)..where((d) => d.id.equals(driveId))).getSingle();

  Future<FolderEntry> getFolderById(String folderId) =>
      (select(folderEntries)..where((d) => d.id.equals(folderId))).getSingle();

  Stream<FolderWithContents> watchFolder(String driveId, String folderPath) {
    final folderStream = (select(folderEntries)
          ..where((f) => f.driveId.equals(driveId) & f.path.equals(folderPath)))
        .watchSingle();

    final subfoldersStream = (select(folderEntries)
          ..where((f) =>
              f.driveId.equals(driveId) &
              f.path.like('$folderPath/%') &
              f.path.like('$folderPath/%/%').not()))
        .watch();

    final filesStream = (select(fileEntries)
          ..where((f) =>
              f.driveId.equals(driveId) &
              f.path.like('$folderPath/%') &
              f.path.like('$folderPath/%/%').not()))
        .watch();

    return Rx.combineLatest3(
      folderStream,
      subfoldersStream,
      filesStream,
      (folder, subfolders, files) => FolderWithContents(
        folder: folder,
        subfolders: subfolders,
        files: files,
      ),
    );
  }

  Future<String> fileExistsInFolder(String folderId, String filename) async {
    final file = await (select(fileEntries)
          ..where((f) =>
              f.parentFolderId.equals(folderId) & f.name.equals(filename)))
        .getSingle();

    return file != null ? file.id : null;
  }

  /// Create a new folder entry.
  /// Returns the id of the created folder.
  Future<String> createNewFolder(
    String driveId,
    String parentFolderId,
    String folderName,
    String path,
  ) async {
    final id = _uuid.v4();

    await into(folderEntries).insert(
      FolderEntriesCompanion(
        id: Value(id),
        driveId: Value(driveId),
        parentFolderId: Value(parentFolderId),
        name: Value(folderName),
        path: Value(path),
      ),
    );

    return id;
  }

  Future<void> writeFileEntity(
    FileEntity entity,
    String path,
  ) =>
      into(fileEntries).insertOnConflictUpdate(
        FileEntriesCompanion(
          id: Value(entity.id),
          driveId: Value(entity.driveId),
          parentFolderId: Value(entity.parentFolderId),
          name: Value(entity.name),
          path: Value(path),
          dataTxId: Value(entity.dataTxId),
          size: Value(entity.size),
          ready: Value(false),
        ),
      );
}

class FolderWithContents {
  final FolderEntry folder;
  final List<FolderEntry> subfolders;
  final List<FileEntry> files;

  FolderWithContents({this.folder, this.subfolders, this.files});
}