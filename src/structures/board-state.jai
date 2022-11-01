BoardState :: struct {
    // Model part, use these to update the view
    selectedCoord : Coord = 0xFF; // Only valid if there's a piece there.
    hoveredCoord : Coord = 0xFF;
    grabbedCoord : Coord = 0xFF;
    targetableCoords : [..]Coord;
    hintedCoords : [..]Coord;

    // Controller part
    position : *Position; // The currently displayed position, not owned.
    interactive : bool;
    focus : bool;
    arrowingStartCoord : Coord = 0xFF;
    pawnPromotionSourceCoord : Coord = 0xFF;
    pawnPromotionTargetCoord : Coord = 0xFF;
}

board_state_cleanup :: (using boardState : *BoardState) {
    Basic.array_free(targetableCoords);
    Basic.array_free(hintedCoords);
}

board_state_interactive :: (boardState : *BoardState, interactive := true) {
    boardState.interactive = interactive;
}

// Set coord to 0xFF to unselect.
board_state_select_coord :: (using boardState : *BoardState, coord : Coord, updateTargetableCoords := true) {
    if selectedCoord == coord then return;
    oldCoord := selectedCoord;
    selectedCoord = coord;
    send(.BoardStateSelectedCoordChanged, oldCoord);

    if updateTargetableCoords {
        if selectedCoord != 0xFF {
            if instance.config.board.highlightValidSquares {
                Basic.array_copy(*targetableCoords, position_find_piece_targets(position, selectedCoord));
            }
        } else {
            targetableCoords.count = 0;
        }
        send(.BoardStateTargetableCoordsChanged);
    }
}

// Set coord to 0xFF to unhover.
board_state_hover_coord :: (using boardState : *BoardState, coord : Coord) {
    if !interactive then return;
    if hoveredCoord == coord then return;
    oldCoord := hoveredCoord;
    hoveredCoord = coord;
    send(.BoardStateHoveredCoordChanged, oldCoord);
}

// Set coord to 0xFF to ungrab.
board_state_grab_coord :: (using boardState : *BoardState, coord : Coord) {
    if grabbedCoord == coord then return;
    oldCoord := grabbedCoord;
    grabbedCoord = coord;
    send(.BoardStateGrabbedCoordChanged, oldCoord);
}

board_state_hint_coords :: (using boardState : *BoardState, coords : []Coord) {
    Basic.array_copy(*hintedCoords, coords);
    send(.BoardStateHintedCoordsChanged);
}

board_state_start_pawn_promotion_selection :: (using boardState : *BoardState, sourceCoord : Coord, targetCoord : Coord) {
    pawnPromotionSourceCoord = sourceCoord;
    pawnPromotionTargetCoord = targetCoord;
    send(.BoardStatePawnPromotionSelectionStarted);
}

board_state_ui_trigger :: (using boardState : *BoardState, trigger : Sill.UiTrigger) {
    if position == null then return;
    if !interactive then return;

    if trigger.flags & .ClickStart {
        if trigger.event.mouseButton.which == .Left {
            // Select a piece if there's one, or move the selected piece.
            if _update_coord_for_piece_movement(boardState, hoveredCoord, playAllowed = instance.config.board.clickClickMove.enabled) {
                board_state_select_coord(boardState, hoveredCoord);
            } else {
                position_clear_highlights(position);
                board_state_select_coord(boardState, 0xFF);
            }
        }
        if trigger.event.mouseButton.which == instance.config.board.destinationSquareMove.mouseButton {
            _destination_square_piece_movement(boardState, hoveredCoord);
        }
    } else if trigger.flags & .ClickStop {
        if trigger.event.mouseButton.which == .Left {
            if !instance.config.board.clickClickMove.enabled {
                board_state_select_coord(boardState, 0xFF);
            }
        } else if trigger.event.mouseButton.which == .Right && hoveredCoord != 0xFF {
            _toggle_hovered_coord_square_highlight(boardState);
        }
    } else if trigger.flags & .DragStart {
        if trigger.event.mouseButton.which == .Left {
            if instance.config.board.dragAndDropMove.enabled {
                board_state_grab_coord(boardState, selectedCoord);
            }
        } else if trigger.event.mouseButton.which == .Right {
            arrowingStartCoord = hoveredCoord;
        }
    } else if trigger.flags & .DragStop {
        if grabbedCoord != 0xFF {
            if !instance.config.board.clickClickMove.enabled then board_state_select_coord(boardState, 0xFF);
            board_state_grab_coord(boardState, 0xFF);
        } else {
            arrowingStartCoord = 0xFF;
        }
    } else if trigger.flags & .DragDrop {
        if grabbedCoord != 0xFF {
            board_state_grab_coord(boardState, 0xFF);
            _update_coord_for_piece_movement(boardState, hoveredCoord, selectAllowed = false);
        } else {
            if arrowingStartCoord == hoveredCoord {
                _toggle_hovered_coord_square_highlight(boardState);
            } else {
                arrowHighlight : ArrowHighlight;
                arrowHighlight.color = highlight_color();
                arrowHighlight.fromCoord = arrowingStartCoord;
                arrowHighlight.toCoord = hoveredCoord;
                position_add_arrow_highlight(*instance.game.ply.position, arrowHighlight);
            }
        }
    } else if trigger.flags & .FocusStart {
        focus = true;
        send(.BoardStateFocusChanged);
    } else if trigger.flags & .FocusStop {
        focus = false;
        send(.BoardStateFocusChanged);
    }
}

board_state_set_position :: (boardState : *BoardState, position : *Position) {
    if boardState.position == position then return;
    boardState.position = position;
    send(.BoardStatePositionChanged);

    board_state_select_coord(boardState, 0xFF);
}

board_state_try_play_move :: (using boardState : *BoardState, sourceCoord : Coord, targetCoord : Coord) {
    selectedCoord = sourceCoord;
    _update_coord_for_piece_movement(boardState, targetCoord, selectAllowed = false);
}

board_state_play_pawn_promotion :: (using boardState : *BoardState, pieceKind : PieceKind) {
    if position_move_legal(position, pawnPromotionSourceCoord, pawnPromotionTargetCoord, pieceKind) {
        game_play_move(*instance.game, pawnPromotionSourceCoord, pawnPromotionTargetCoord, pieceKind);
    }
    send(.BoardStatePawnPromotionSelectionStopped);
}

board_state_prepare_move :: (using boardState : *BoardState, sourceCoord : Coord, targetCoord : Coord) {
    board_state_select_coord(boardState, sourceCoord, updateTargetableCoords = false);

    if targetCoord != 0xFF {
        Basic.array_resize(*boardState.targetableCoords, 1);
        boardState.targetableCoords[0] = targetCoord;
        send(.BoardStateTargetableCoordsChanged);
    } else {
        boardState.targetableCoords.count = 0;
        send(.BoardStateTargetableCoordsChanged);
    }
}

#scope_file

// Called each time a square is simply-clicked.
// Return true if a coord is selected.
_update_coord_for_piece_movement :: (using boardState : *BoardState, targetCoord : Coord, selectAllowed := true, playAllowed := true) -> bool {
    // If we're selecting a piece of our color, just select that square.
    if selectAllowed {
        piece := piece_at_coord(targetCoord);
        if piece.kind != .None && piece.color == position_color_to_play(position) {
            return true;
        }
    }

    // Try to play a move if we already had a selected piece.
    if playAllowed && selectedCoord != 0xFF {
        // Pawn promotion query
        row, col := row_col(targetCoord);
        isPromotion := position.board[selectedCoord].kind == .Pawn && (row == 0 || row == 7);
        // @note We just need a valid promotion piece to check if the move is legal,
        // but we won't make the promotion out of it.
        promotionPieceKind := ifx isPromotion then PieceKind.Queen else .None;

        if position_move_legal(position, selectedCoord, targetCoord, promotionPieceKind) {
            if isPromotion then board_state_start_pawn_promotion_selection(boardState, selectedCoord, targetCoord);
            else game_play_move(*instance.game, selectedCoord, targetCoord, .None);
        }
    }

    return false;
}

_toggle_hovered_coord_square_highlight :: (using boardState : *BoardState) {
    squareHighlight : SquareHighlight;
    squareHighlight.coord = hoveredCoord;
    squareHighlight.color = highlight_color();
    position_toggle_highlight(position, squareHighlight);
}

_destination_square_piece_movement :: (using boardState : *BoardState, targetCoord : Coord) {
    if !instance.config.board.destinationSquareMove.enabled then return;
    colorToPlay := position_color_to_play(position);

    if position.board[targetCoord].kind != .None && position.board[targetCoord].color == colorToPlay {
        board_state_hint_coords(boardState, .[]);
        return;
    }

    sourceCoords := position_square_source_pieces(position, targetCoord, colorToPlay);

    if sourceCoords.count == 0 {
        board_state_hint_coords(boardState, .[]);
    } else if sourceCoords.count == 1 {
        board_state_try_play_move(boardState, sourceCoords[0], targetCoord);
    } else {
        if instance.config.board.destinationSquareMove.disambiguateWithLastMovedPiece {
            previousPly := ply_previous_ply(instance.game.ply);
            if previousPly && Basic.array_find(sourceCoords, previousPly.position.lastMove.targetCoord) {
                board_state_try_play_move(boardState, previousPly.position.lastMove.targetCoord, targetCoord);
                return;
            }
        }

        board_state_select_coord(boardState, 0xFF);
        board_state_hint_coords(boardState, sourceCoords);
    }
}
