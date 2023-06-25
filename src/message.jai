Message :: struct {
    kind : MessageKind;
    union {
        coord : Coord;
        oldCoord : Coord;
        position : *Position;
        struct {
            newPly : *PlyEntity;
            oldPly : *PlyEntity;
        }
        ply : *PlyEntity;
        variation : *VariationEntity;
        entity : *Sill.Entity;
        newGame : *Game;
        study : *Study;
        moves : [3]Move;
        struct {
            mode : Mode;
            oldMode : Mode;
        }
    }
}

MessageKind :: enum u32 {
    Unknown :: 0;
    SystemReflow;                           // ()
    SelectTab;                              // (entity : *Sill.Entity)
    CurrentGameChanged;                     // (newGame : *Game)
    CurrentGameTitleChanged;                // ()
    SelectedPlyChanged;                     // (newPly : *PlyEntity, oldPly : *PlyEntity)
    PositionMoveAnnotationChanged;          // (position : *Position)
    PositionHighlightsChanged;              // (position : *Position)
    PositionBoardChanged;                   // ()
    PositionBoardCoordChanged;              // (coord : Coord)
    BoardFocusChanged;                      // ()
    BoardPositionChanged;                   // ()
    BoardSelectedCoordChanged;              // (oldCoord : Coord)
    BoardHoveredCoordChanged;               // (oldCoord : Coord)
    BoardGrabbedCoordChanged;               // (oldCoord : Coord)
    BoardTargetableCoordsChanged;           // ()
    BoardHintedCoordsChanged;               // ()
    BoardPawnPromotionSelectionStarted;     // ()
    BoardPawnPromotionSelectionStopped;     // ()
    BoardInteractiveChanged;                // ()
    BoardPositionEditChanged;               // ()
    PlyCommentEditStarted;                  // ()
    PlyCommentEditStopped;                  // ()
    PlyTextCursorPositionChanged;           // (ply : *PlyEntity)
    PlyParentChanged;                       // (ply : *PlyEntity)
    PlyResultChanged;                       // (ply : *PlyEntity)
    VariationCollapsedChanged;              // (variation : *VariationEntity)
    VariationContentChanged;                // (variation : *VariationEntity)
    SmartMoverMovesChanged;                 // ()
    SmartMoverDisplayedMovesChanged;        // ()
    SmartMoverKeysChanged;                  // ()
    StudyCurrentGameChanged;                // (study : *Study)
    StudyGamesChanged;                      // (study : *Study)
    StudyUnsavedModificationsChanged;       // (study : *Study)
    ModeChanged;                            // (mode : Mode, oldMode : Mode)
}

send :: (kind : MessageKind) {
    message : Message = ---;
    message.kind = kind;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, oldCoord : Coord) {
    message : Message = ---;
    message.kind = kind;
    message.oldCoord = oldCoord;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, position : *Position) {
    message : Message = ---;
    message.kind = kind;
    message.position = position;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, ply : *PlyEntity) {
    message : Message = ---;
    message.kind = kind;
    message.ply = ply;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, newPly : *PlyEntity, oldPly : *PlyEntity) {
    message : Message = ---;
    message.kind = kind;
    message.newPly = newPly;
    message.oldPly = oldPly;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, entity : *Sill.Entity) {
    message : Message = ---;
    message.kind = kind;
    message.entity = entity;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, variation : *VariationEntity) {
    message : Message = ---;
    message.kind = kind;
    message.variation = variation;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, study : *Study) {
    message : Message = ---;
    message.kind = kind;
    message.study = study;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, newGame : *Game) {
    message : Message = ---;
    message.kind = kind;
    message.newGame = newGame;
    Sill.message_send(*instance.engine.message, message);
}

send :: (kind : MessageKind, mode : Mode, oldMode : Mode) {
    message : Message = ---;
    message.kind = kind;
    message.mode = mode;
    message.oldMode = oldMode;
    Sill.message_send(*instance.engine.message, message);
}
