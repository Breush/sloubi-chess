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
        moves : [3]Move;
    }
}

MessageKind :: enum u32 {
    Unknown :: 0;
    SystemReflow;                               // ()
    ModeGameStarted;                            // ()
    ModeGameStopped;                            // ()
    ModePlyEditCommentStarted;                  // ()
    ModePlyEditCommentStopped;                  // ()
    GameSelectedPlyChanged;                     // (oldPly : *PlyEntity)
    PositionHighlightsChanged;                  // (position : *Position)
    BoardStateFocusChanged;                     // ()
    BoardStatePositionChanged;                  // ()
    BoardStateSelectedCoordChanged;             // (oldCoord : Coord)
    BoardStateHoveredCoordChanged;              // (oldCoord : Coord)
    BoardStateGrabbedCoordChanged;              // (oldCoord : Coord)
    BoardStateTargetableCoordsChanged;          // ()
    BoardStateHintedCoordsChanged;              // ()
    BoardStatePawnPromotionSelectionStarted;    // ()
    BoardStatePawnPromotionSelectionStopped;    // ()
    PlyTextCursorPositionChanged;               // (ply : *PlyEntity)
    PlyInited;                                  // (ply : *PlyEntity)
    VariationCollapsedChanged;                  // (variation : *VariationEntity)
    VariationContentChanged;                    // (variation : *VariationEntity)
    SmartMoverMovesChanged;                     // ()
    SmartMoverDisplayedMovesChanged;            // ()
    SmartMoverKeysChanged;                      // ()
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

send :: (kind : MessageKind, variation : *VariationEntity) {
    message : Message = ---;
    message.kind = kind;
    message.variation = variation;
    Sill.message_send(instance.engine, message);
}
