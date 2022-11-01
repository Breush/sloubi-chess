SmartMoverEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    WIDTH :: 300;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    mesh : Sill.MeshComponent;

    keys : [..]Crater.Key;
    moves : [..]SmartMove;
    keysText : string;
    movesDisplayOffset : u32;

    movesMeshNodes : [4]*Sill.MeshNode; // 0 is the main one, 1 & 2 are forward, 3 is backward
    keysMeshNode : *Sill.MeshNode;
    dotsMeshNode : *Sill.MeshNode;

    on_cleanup :: (using smartMover : *SmartMoverEntity) {
        Basic.array_free(keys);
        Basic.array_free(moves);
        Basic.free(keysText);
    }

    SmartMove :: struct {
        using #as move : Move;
        sanKeys : SanKeys;
    }
}

smart_mover_init :: (using smartMover : *SmartMoverEntity) {
    if !instance.config.board.keyboardMove.enabled then return;

    Sill.listener_on_message(*smartMover.listener, _on_message);
    Sill.entity_set_disabled(smartMover, true); // Start disabled, focusing the board will show it.

    _init_meshes(smartMover);
}

smart_mover_ui_trigger :: (using smartMover : *SmartMoverEntity, trigger : Sill.UiTrigger) {
    if !(trigger.flags & .Key) then return;
    if !instance.config.board.keyboardMove.enabled then return;

    if Basic.array_find(instance.config.board.keyboardMove.playSelected, trigger.event.key.which) {
        smart_mover_play_selected(smartMover);
        return;
    } else if Basic.array_find(instance.config.board.keyboardMove.selectNext, trigger.event.key.which) {
        smart_mover_select_next(smartMover);
        return;
    } else if trigger.event.key.which == .Backspace {
        smart_mover_remove_last_key(smartMover);
        return;
    }

    // Check that the new key represents something.
    possibleSanKeys := _key_to_possible_san_keys(trigger.event.key.which);
    if possibleSanKeys[0] == .None then return;
    movesDisplayOffset = 0;

    // If this is the first time, set the matching moves to the legal ones.
    if keys.count == 0 then _reset_to_legal_moves(smartMover);

    // Update keys text.
    Basic.array_add(*keys, trigger.event.key.which);
    inputText := "";
    for sanKey, sanKeyIndex : possibleSanKeys {
        if sanKey == .None then break;
        sanKeyText := san_key_to_symbol(sanKey);
        inputText = Basic.tprint("%1%2%3", inputText, ifx sanKeyIndex == 0 then "" else "|", sanKeyText);
    }
    newKeysText := Basic.sprint("%[%]", keysText, inputText);
    if keysText.count != 0 then Basic.free(keysText);
    keysText = newKeysText;
    send(.SmartMoverKeysChanged);

    // @todo Would be awesome to ignore disambiguation unless we know it is specified, somehow.

    // Filter out moves that do not match the new key.
    _filter_moves(smartMover, possibleSanKeys);

    send(.SmartMoverMovesChanged);
}

smart_mover_play_selected :: (using smartMover : *SmartMoverEntity) {
    defer smart_mover_reset(smartMover);

    if movesDisplayOffset >= moves.count return;

    game_play_move(*instance.game, moves[movesDisplayOffset].sourceCoord, moves[movesDisplayOffset].targetCoord, moves[movesDisplayOffset].promotionPieceKind);
}

smart_mover_select_next :: (using smartMover : *SmartMoverEntity) {
    if moves.count == 0 return;

    movesDisplayOffset += 1;
    if movesDisplayOffset >= moves.count {
        movesDisplayOffset = 0;
    }

    send(.SmartMoverDisplayedMovesChanged);
}

smart_mover_reset :: (using smartMover : *SmartMoverEntity) {
    if moves.count != 0 {
        moves.count = 0;
        movesDisplayOffset = 0;
        send(.SmartMoverMovesChanged);
    }

    if keys.count != 0 {
        keys.count = 0;
        keysText = "";
        send(.SmartMoverKeysChanged);
    }
}

smart_mover_remove_last_key :: (using smartMover : *SmartMoverEntity) {
    if keys.count == 0 return;

    keys.count -= 1;
    for <i : keysText.count - 1 .. 0 {
        if keysText[i] == #char "[" {
            keysText.count = i;
            break;
        }
    }
    send(.SmartMoverKeysChanged);

    // Refilter
    _reset_to_legal_moves(smartMover);

    for key : keys {
        possibleSanKeys := _key_to_possible_san_keys(key);
        _filter_moves(smartMover, possibleSanKeys);
    }

    send(.SmartMoverMovesChanged);
}

#scope_file

_on_message :: (using smartMover : *SmartMoverEntity, message : *Message) {
    board := *(cast(*MetaBoardEntity) smartMover.parent).board;
    if !board.state.interactive then return;

    if message.kind == {
    case .GameSelectedPlyChanged;
        smart_mover_reset(smartMover);
    case .BoardStateFocusChanged;
        Sill.entity_set_disabled(smartMover, !board.state.focus);
    case .SmartMoverMovesChanged;
        _update_from_moves(smartMover);
    case .SmartMoverDisplayedMovesChanged;
        _update_from_moves(smartMover);
    case .SmartMoverKeysChanged;
        _update_from_keys(smartMover);
    }
}

_update_from_moves :: (using smartMover : *SmartMoverEntity) {
    board := *(cast(*MetaBoardEntity) smartMover.parent).board;

    for move, moveIndex : moves {
        displayMoveIndex := (moves.count + moveIndex - movesDisplayOffset) % moves.count;
        if displayMoveIndex >= movesMeshNodes.count - 1 then continue;

        moveText := position_move_to_san(board.state.position, move);
        font := ifx displayMoveIndex == 0 then "mainBold" else "mainLight";
        _, width := text_mesh_update(movesMeshNodes[displayMoveIndex].primitives[0], moveText, font, instance.config.env.textColor, computeCharInfos = false);
        movesMeshNodes[displayMoveIndex].transform.translation.x = -Math.floor(width / 2 + 0.5);
        Sill.mesh_commit_nodes(*smartMover.mesh);
    }

    // Backward move
    if moves.count >= movesMeshNodes.count {
        displayMoveIndex := (moves.count + movesDisplayOffset - 1) % moves.count;
        moveText := position_move_to_san(board.state.position, moves[displayMoveIndex]);
        _, width := text_mesh_update(Basic.peek(movesMeshNodes).primitives[0], moveText, "mainLight", instance.config.env.textColor, computeCharInfos = false);
        Basic.peek(movesMeshNodes).transform.translation.x = -Math.floor(width / 2 + 0.5);
        Sill.mesh_commit_nodes(*smartMover.mesh);
    }

    hiddenIndex := moves.count;
    while hiddenIndex < movesMeshNodes.count {
        movesMeshNodes[hiddenIndex].primitives[0].disabled |= .Application;
        hiddenIndex += 1;
    }

    dotsMeshNode.primitives[0].disabled |= .Application;
    if moves.count > movesMeshNodes.count {
        dotsMeshNode.primitives[0].disabled &= ~.Application;
    }

    if moves.count != 0 {
        board_state_prepare_move(*board.state, moves[movesDisplayOffset].sourceCoord, moves[movesDisplayOffset].targetCoord);
    } else {
        board_state_prepare_move(*board.state, 0xFF, 0xFF);
    }
}

_reset_to_legal_moves :: (using smartMover : *SmartMoverEntity) {
    boardState : *BoardState = *(cast(*MetaBoardEntity) smartMover.parent).board;
    legalMoves := position_legal_moves(boardState.position);
    Basic.array_resize(*moves, legalMoves.count);

    for legalMove, moveIndex : legalMoves {
        moves[moveIndex].move = legalMove;
        moves[moveIndex].sanKeys = position_move_to_san_keys(boardState.position, legalMove, showActions = false);
    }

    // Sort by the most centralizing moves first.
    Sort.quick_sort(moves, (a : SmartMove, b : SmartMove) -> s64 {
        aRow, aCol := row_col(a.targetCoord);
        bRow, bCol := row_col(b.targetCoord);

        distance := Sort.compare_floats(abs(aRow - 3.5) + abs(aCol - 3.5), abs(bRow - 3.5) + abs(bCol - 3.5));
        if distance != 0 then return distance;

        aRow = row_col(a.sourceCoord);
        bRow = row_col(b.sourceCoord);
        distance = cast(s8) aRow - cast(s8) bRow;
        if distance != 0 then return distance;

        return piece_kind_value(b.promotionPieceKind) - piece_kind_value(a.promotionPieceKind);
    });
}

_filter_moves :: (using smartMover : *SmartMoverEntity, sanKeys : []SanKey) {
    keyIndex := keys.count - 1;
    for *move, moveIndex : moves {
        sanKey := move.sanKeys[keyIndex];
        if sanKey == .None || !Basic.array_find(sanKeys, sanKey) {
            Basic.array_ordered_remove_by_index(*moves, moveIndex);
            moveIndex -= 1;
        }
    }
}

_update_from_keys :: (using smartMover : *SmartMoverEntity) {
    _, width := text_mesh_update(keysMeshNode.primitives[0], keysText, "mono", instance.config.env.textColor, computeCharInfos = false);
    keysMeshNode.transform.translation.x = -Math.floor(width / 2 + 0.5);
    Sill.mesh_commit_nodes(*mesh);
}

_init_meshes :: (using smartMover : *SmartMoverEntity) {
    Basic.array_resize(*mesh.nodes, 11);

    // Background
    Basic.array_add(*mesh.nodes[0].primitives, create_rect_mesh(SmartMoverEntity.WIDTH, 2 * UiConstants.HeightLine + 2 * UiConstants.PaddingVerticalMedium));
    mesh.nodes[0].transform.translation.y += UiConstants.HeightLine + UiConstants.PaddingVerticalMedium;
    mesh.nodes[0].primitives[0].material = Magma.create_material(instance.shaders.gradient);
    Magma.material_set(mesh.nodes[0].primitives[0].material, "color", instance.config.env.secondaryBackgroundColor);
    Magma.material_set(mesh.nodes[0].primitives[0].material, "fadeColor", instance.config.env.backgroundColor);

    // Moves
    for i : 0 .. 3 {
        nodeIndex := 1 + 2 * i;
        Basic.array_add(*mesh.nodes[nodeIndex].children, nodeIndex  + 1);
        mesh.nodes[nodeIndex].transform.translation.x = i * 60.0;
        if i == 3 then mesh.nodes[nodeIndex].transform.translation.x = -60.0;
        mesh.nodes[nodeIndex].transform.translation.y = UiConstants.PaddingVerticalMedium;
        Basic.array_add(*mesh.nodes[nodeIndex + 1].primitives, create_text_mesh());
        mesh.nodes[nodeIndex + 1].parent = nodeIndex;
        mesh.nodes[nodeIndex + 1].transform.translation.z -= 10;
        movesMeshNodes[i] = *mesh.nodes[nodeIndex + 1];
    }

    // Dots
    Basic.array_add(*mesh.nodes[9].primitives, create_text_mesh());
    text_mesh_update(mesh.nodes[9].primitives[0], "...", "mainLight", instance.config.env.textColor, computeCharInfos = false);
    mesh.nodes[9].transform.translation.x = -120.0;
    mesh.nodes[9].transform.translation.y = UiConstants.PaddingVerticalMedium;
    mesh.nodes[9].transform.translation.z -= 10;
    mesh.nodes[9].primitives[0].disabled |= .Application;
    dotsMeshNode = *mesh.nodes[9];

    // Keys
    Basic.array_add(*mesh.nodes[10].primitives, create_text_mesh());
    mesh.nodes[10].transform.translation.y = UiConstants.HeightLine + UiConstants.PaddingVerticalMedium + UiConstants.PaddingVerticalSmall;
    mesh.nodes[10].transform.translation.z -= 10;
    keysMeshNode = *mesh.nodes[10];
}

_key_to_possible_san_keys :: (key : Crater.Key) -> [3]SanKey {
    sanKeys : [3]SanKey;

    ROW_KEYS :: Crater.Key.[._1, ._2, ._3, ._4, ._5, ._6, ._7, ._8];
    ROW_KEYS_NUMPAD :: Crater.Key.[.Numpad1, .Numpad2, .Numpad3, .Numpad4, .Numpad5, .Numpad6, .Numpad7, .Numpad8];
    COL_KEYS :: Crater.Key.[.A, .B, .C, .D, .E, .F, .G, .H];

    isPiece, pieceIndex := Basic.array_find(instance.config.board.keyboardMove.piecesMap, key);
    isCol, colIndex := Basic.array_find(COL_KEYS, key);
    isRow, rowIndex := Basic.array_find(ROW_KEYS, key);
    if !isRow then isRow, rowIndex = Basic.array_find(ROW_KEYS_NUMPAD, key);
    if !isRow then isRow, rowIndex = Basic.array_find(instance.config.board.keyboardMove.numbersMap, key);

    offset := 0;
    if isPiece {
        if pieceIndex == 0 then sanKeys[offset] = .Rook;
        else if pieceIndex == 1 then sanKeys[offset] = .Knight;
        else if pieceIndex == 2 then sanKeys[offset] = .Bishop;
        else if pieceIndex == 3 then sanKeys[offset] = .Queen;
        else if pieceIndex == 4 then sanKeys[offset] = .King;
        offset += 1;
    }
    if isRow {
        sanKeys[offset] = .Row1 + cast(SanKey) rowIndex;
        offset += 1;
    }
    if isCol {
        sanKeys[offset] = .ColA + cast(SanKey) colIndex;
    }

    return sanKeys;
}
