Board :: struct {
    // Model part, use these to update the view
    selectedCoord : Coord = 0xFF; // Only valid if there's a piece there.
    hoveredCoord : Coord = 0xFF;
    grabbedCoord : Coord = 0xFF;
    targetableCoords : [..]Coord;
    hintedCoords : [..]Coord;

    // Controller part
    position : *Position; // The currently displayed position, not owned.
    interactive := true;
    focus : bool;
    arrowingStartCoord : Coord = 0xFF;
    pawnPromotionSourceCoord : Coord = 0xFF;
    pawnPromotionTargetCoord : Coord = 0xFF;
}

board_cleanup :: (using board : *Board) {
    Basic.array_free(targetableCoords);
    Basic.array_free(hintedCoords);
}

board_interactive :: (board : *Board, interactive := true) {
    if board.interactive == interactive then return;
    board.interactive = interactive;
    send(.BoardInteractiveChanged);
}

// Set coord to 0xFF to unselect.
board_select_coord :: (using board : *Board, coord : Coord, updateTargetableCoords := true) {
    if selectedCoord == coord then return;
    oldCoord := selectedCoord;
    selectedCoord = coord;
    send(.BoardSelectedCoordChanged, oldCoord);

    if updateTargetableCoords {
        if selectedCoord != 0xFF {
            if instance.config.board.highlightValidSquares {
                Basic.array_copy(*targetableCoords, position_find_piece_targets(position, selectedCoord));
            }
        } else {
            targetableCoords.count = 0;
        }
        send(.BoardTargetableCoordsChanged);
    }
}

// Set coord to 0xFF to unhover.
board_hover_coord :: (using board : *Board, coord : Coord) {
    if !interactive then return;
    if hoveredCoord == coord then return;
    oldCoord := hoveredCoord;
    hoveredCoord = coord;
    send(.BoardHoveredCoordChanged, oldCoord);
}

// Set coord to 0xFF to ungrab.
board_grab_coord :: (using board : *Board, coord : Coord) {
    if grabbedCoord == coord then return;
    oldCoord := grabbedCoord;
    grabbedCoord = coord;
    send(.BoardGrabbedCoordChanged, oldCoord);
}

board_hint_coords :: (using board : *Board, coords : []Coord) {
    Basic.array_copy(*hintedCoords, coords);
    send(.BoardHintedCoordsChanged);
}

board_start_pawn_promotion_selection :: (using board : *Board, sourceCoord : Coord, targetCoord : Coord) {
    pawnPromotionSourceCoord = sourceCoord;
    pawnPromotionTargetCoord = targetCoord;
    send(.BoardPawnPromotionSelectionStarted);
}

board_ui_trigger :: (using board : *Board, trigger : Sill.UiTrigger) {
    if position == null then return;
    if !interactive then return;

    if trigger.flags & .ClickStart {
        if trigger.event.mouseButton.which == .Left {
            // Select a piece if there's one, or move the selected piece.
            if _update_coord_for_piece_movement(board, hoveredCoord, playAllowed = instance.config.board.clickClickMove.enabled) {
                board_select_coord(board, hoveredCoord);
            } else {
                position_clear_highlights(position);
                board_select_coord(board, 0xFF);
            }
        }
        if trigger.event.mouseButton.which == instance.config.board.destinationSquareMove.mouseButton {
            _destination_square_piece_movement(board, hoveredCoord);
        }
    } else if trigger.flags & .ClickStop {
        if trigger.event.mouseButton.which == .Left {
            if !instance.config.board.clickClickMove.enabled {
                board_select_coord(board, 0xFF);
            }
        } else if trigger.event.mouseButton.which == .Right && hoveredCoord != 0xFF {
            _toggle_hovered_coord_square_highlight(board);
        }
    } else if trigger.flags & .DragStart {
        if trigger.event.mouseButton.which == .Left {
            if instance.config.board.dragAndDropMove.enabled {
                board_grab_coord(board, selectedCoord);
            }
        } else if trigger.event.mouseButton.which == .Right {
            arrowingStartCoord = hoveredCoord;
        }
    } else if trigger.flags & .DragStop {
        if grabbedCoord != 0xFF {
            if !instance.config.board.clickClickMove.enabled then board_select_coord(board, 0xFF);
            board_grab_coord(board, 0xFF);
        } else {
            arrowingStartCoord = 0xFF;
        }
    } else if trigger.flags & .DragDrop {
        if grabbedCoord != 0xFF {
            board_grab_coord(board, 0xFF);
            _update_coord_for_piece_movement(board, hoveredCoord, selectAllowed = false);
        } else {
            if arrowingStartCoord == hoveredCoord {
                _toggle_hovered_coord_square_highlight(board);
            } else {
                arrowHighlight : ArrowHighlight;
                arrowHighlight.color = highlight_color();
                arrowHighlight.fromCoord = arrowingStartCoord;
                arrowHighlight.toCoord = hoveredCoord;
                position_add_arrow_highlight(*instance.currentGame.ply.position, arrowHighlight);
            }
        }
    } else if trigger.flags & .FocusStart {
        focus = true;
        send(.BoardFocusChanged);
    } else if trigger.flags & .FocusStop {
        focus = false;
        send(.BoardFocusChanged);
    }
}

board_set_position :: (board : *Board, position : *Position) {
    if board.position == position then return;
    board.position = position;
    send(.BoardPositionChanged);

    board_select_coord(board, 0xFF);
}

board_try_play_move :: (using board : *Board, sourceCoord : Coord, targetCoord : Coord) {
    selectedCoord = sourceCoord;
    _update_coord_for_piece_movement(board, targetCoord, selectAllowed = false);
}

board_play_pawn_promotion :: (using board : *Board, pieceKind : PieceKind) {
    if position_move_legal(position, pawnPromotionSourceCoord, pawnPromotionTargetCoord, pieceKind) {
        game_play_move(instance.currentGame, pawnPromotionSourceCoord, pawnPromotionTargetCoord, pieceKind);
    }
    send(.BoardPawnPromotionSelectionStopped);
}

board_prepare_move :: (using board : *Board, sourceCoord : Coord, targetCoord : Coord) {
    board_select_coord(board, sourceCoord, updateTargetableCoords = false);

    if targetCoord != 0xFF {
        Basic.array_resize(*board.targetableCoords, 1);
        board.targetableCoords[0] = targetCoord;
        send(.BoardTargetableCoordsChanged);
    } else {
        board.targetableCoords.count = 0;
        send(.BoardTargetableCoordsChanged);
    }
}

#scope_file

// Called each time a square is simply-clicked.
// Return true if a coord is selected.
_update_coord_for_piece_movement :: (using board : *Board, targetCoord : Coord, selectAllowed := true, playAllowed := true) -> bool {
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
            if isPromotion then board_start_pawn_promotion_selection(board, selectedCoord, targetCoord);
            else game_play_move(instance.currentGame, selectedCoord, targetCoord, .None);
        }
    }

    return false;
}

_toggle_hovered_coord_square_highlight :: (using board : *Board) {
    squareHighlight : SquareHighlight;
    squareHighlight.coord = hoveredCoord;
    squareHighlight.color = highlight_color();
    position_toggle_highlight(position, squareHighlight);
}

_destination_square_piece_movement :: (using board : *Board, targetCoord : Coord) {
    if !instance.config.board.destinationSquareMove.enabled then return;
    colorToPlay := position_color_to_play(position);

    if position.board[targetCoord].kind != .None && position.board[targetCoord].color == colorToPlay {
        board_hint_coords(board, .[]);
        return;
    }

    sourceCoords := position_square_source_pieces(position, targetCoord, colorToPlay);

    if sourceCoords.count == 0 {
        board_hint_coords(board, .[]);
    } else if sourceCoords.count == 1 {
        board_try_play_move(board, sourceCoords[0], targetCoord);
    } else {
        if instance.config.board.destinationSquareMove.disambiguateWithLastMovedPiece {
            previousPly := ply_previous_ply(instance.currentGame.ply);
            if previousPly && Basic.array_find(sourceCoords, previousPly.position.lastMove.targetCoord) {
                board_try_play_move(board, previousPly.position.lastMove.targetCoord, targetCoord);
                return;
            }
        }

        board_select_coord(board, 0xFF);
        board_hint_coords(board, sourceCoords);
    }
}
