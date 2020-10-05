import 'dart:async';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../blocs.dart';

part 'upload_event.dart';
part 'upload_state.dart';

class UploadBloc extends Bloc<UploadEvent, UploadState> {
  final _uuid = Uuid();
  final ProfileBloc _profileBloc;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  UploadBloc(
      {@required ProfileBloc profileBloc,
      @required DriveDao driveDao,
      @required ArweaveService arweave})
      : _profileBloc = profileBloc,
        _driveDao = driveDao,
        _arweave = arweave,
        super(UploadIdle());

  @override
  Stream<UploadState> mapEventToState(
    UploadEvent event,
  ) async* {
    if (event is PrepareFileUpload) {
      yield* _mapPrepareFileUploadToState(event);
    } else if (event is UploadFileToNetwork) {
      yield* _mapUploadFileToNetworkToState(event);
    }
  }

  Stream<UploadState> _mapPrepareFileUploadToState(
      PrepareFileUpload event) async* {
    yield UploadBeingPrepared();

    final fileEntity = event.fileEntity;

    var existingFileId = await _driveDao.fileExistsInFolder(
      fileEntity.parentFolderId,
      fileEntity.name,
    );
    event.fileEntity.id = existingFileId ?? _uuid.v4();

    final wallet = (_profileBloc.state as ProfileLoaded).wallet;
    final transactions = <Transaction>[];

    final uploadTxs = await _arweave.prepareFileUploadTxs(
      fileEntity,
      event.fileStream,
      wallet,
      event.driveKey,
    );

    transactions.add(uploadTxs.entityTx);
    transactions.add(uploadTxs.dataTx);

    yield UploadFileReady(
      existingFileId,
      fileEntity.name,
      uploadTxs.dataTx.reward,
      fileEntity.size,
      UploadFileToNetwork(
        fileEntity,
        event.filePath,
        transactions,
      ),
    );
  }

  Stream<UploadState> _mapUploadFileToNetworkToState(
      UploadFileToNetwork event) async* {
    yield UploadInProgress();

    final fileEntity = event.fileEntity;

    await _arweave.batchPostTxs(event.uploadTransactions);

    await _driveDao.writeFileEntity(
      fileEntity,
      event.filePath,
    );

    yield UploadComplete();

    yield UploadIdle();
  }
}