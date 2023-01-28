Message :: struct {
    kind : MessageKind;
    union {
        oldCoord : Coord;
        position : *Position;
        union {
            ply : *PlyEntity;
            oldPly : *PlyEntity;
        }
        variation : *VariationEntity;
        entity : *Sill.Entity;
        study : *Study;
        moves : [3]Move;
    }
}

MessageKind :: enum u32 {
    Unknown :: 0;
    SystemReflow;                           // ()
    SelectTab;                              // (entity : *Sill.Entity)
    CurrentGameChanged;                     // ()
    SelectedPlyChanged;                     // (oldPly : *PlyEntity)
    PositionHighlightsChanged;              // (position : *Position)
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
    PlyCommentEditStarted;                  // ()
    PlyCommentEditStopped;                  // ()
    PlyTextCursorPositionChanged;           // (ply : *PlyEntity)
    PlyInited;                              // (ply : *PlyEntity)
    VariationCollapsedChanged;              // (variation : *VariationEntity)
    VariationContentChanged;                // (variation : *VariationEntity)
    SmartMoverMovesChanged;                 // ()
    SmartMoverDisplayedMovesChanged;        // ()
    SmartMoverKeysChanged;                  // ()
    StudyCurrentGameChanged;                // (study : *Study)
    StudyGamesChanged;                      // (study : *Study)
    StudyUnsavedModificationsChanged;       // (study : *Study)
}

send :: (kind : MessageKind) {
    message : Message = ---;
    message.kind = kind;
    Sill.message_send(instance.engine, message);
}

send :: (kind : MessageKind, oldCoord : Coord) {
    message : Message = ---;
    message.kind = kind;
    message.oldCoord = oldCoord;
    Sill.message_send(instance.engine, message);
}

send :: (kind : MessageKind, position : *Position) {
    message : Message = ---;
    message.kind = kind;
    message.position = position;
    Sill.message_send(instance.engine, message);
}

send :: (kind : MessageKind, ply : *PlyEntity) {
    message : Message = ---;
    message.kind = kind;
    message.ply = ply;
    Sill.message_send(instance.engine, message);
}

send :: (kind : MessageKind, entity : *Sill.Entity) {
    message : Message = ---;
    message.kind = kind;
    message.entity = entity;
    Sill.message_send(instance.engine, message);
}

send :: (kind : MessageKind, variation : *VariationEntity) {
    message : Message = ---;
    message.kind = kind;
    message.variation = variation;
    Sill.message_send(instance.engine, message);
}

send :: (kind : MessageKind, study : *Study) {
    message : Message = ---;
    message.kind = kind;
    message.study = study;
    Sill.message_send(instance.engine, message);
}
