import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/entities/entities.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';

part 'drive_detail_event.dart';
part 'drive_detail_state.dart';

class DriveDetailBloc extends Bloc<DriveDetailEvent, DriveDetailState> {
  final String _driveId;
  final UserBloc _userBloc;
  final UploadBloc _uploadBloc;
  final ArweaveDao _arweaveDao;
  final DriveDao _driveDao;

  StreamSubscription _folderSubscription;

  DriveDetailBloc(
      {@required String driveId,
      @required ArweaveDao arweaveDao,
      @required UserBloc userBloc,
      @required UploadBloc uploadBloc,
      @required DriveDao driveDao})
      : _driveId = driveId,
        _arweaveDao = arweaveDao,
        _userBloc = userBloc,
        _uploadBloc = uploadBloc,
        _driveDao = driveDao,
        super(FolderOpening()) {
    if (driveId != null) add(OpenFolder(''));
  }

  @override
  Stream<DriveDetailState> mapEventToState(
    DriveDetailEvent event,
  ) async* {
    if (event is OpenFolder)
      yield* _mapOpenFolderToState(event);
    else if (event is OpenedFolder)
      yield* _mapOpenedFolderToState(event);
    else if (event is NewFolder)
      yield* _mapNewFolderToState(event);
    else if (event is UploadFile) yield* _mapUploadFileToState(event);
  }

  Stream<DriveDetailState> _mapOpenFolderToState(OpenFolder event) async* {
    _folderSubscription?.cancel();
    _folderSubscription = Rx.combineLatest2(
      _driveDao.watchDrive(_driveId),
      _driveDao.watchFolder(_driveId, event.folderPath),
      (drive, folderContents) => OpenedFolder(drive, folderContents),
    ).listen((event) => add(event));
  }

  Stream<DriveDetailState> _mapOpenedFolderToState(OpenedFolder event) async* {
    yield FolderOpened(
      currentDrive: event.openedDrive,
      hasWritePermissions: event.openedDrive.owner ==
          (_userBloc.state as UserAuthenticated).userWallet.address,
      currentFolder: event.openedFolder,
    );
  }

  Stream<DriveDetailState> _mapNewFolderToState(NewFolder event) async* {
    if (state is FolderOpened) {
      final currentFolder = (state as FolderOpened).currentFolder.folder;

      final newFolderId = await _driveDao.createNewFolder(
        _driveId,
        currentFolder.id,
        event.folderName,
        '${currentFolder.path}/${event.folderName}',
      );

      final folderTx = await _arweaveDao.prepareFolderEntityTx(
          FolderEntity(
            id: newFolderId,
            parentFolderId: currentFolder.id,
            name: event.folderName,
          ),
          (_userBloc.state as UserAuthenticated).userWallet);
      await _arweaveDao.postTx(folderTx);
    }
  }

  Stream<DriveDetailState> _mapUploadFileToState(UploadFile event) async* {
    if (state is FolderOpened) {
      final currentFolder = (state as FolderOpened).currentFolder.folder;
      event.fileEntity
        ..driveId = _driveId
        ..parentFolderId = currentFolder.id;

      _uploadBloc.add(
        PrepareFileUpload(
          event.fileEntity,
          '${currentFolder.path}/${event.fileEntity.name}',
          event.fileStream,
        ),
      );
    }
  }
}