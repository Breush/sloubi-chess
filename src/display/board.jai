// The board entity is really the squares and arrows.
BoardEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    ui : Sill.UiComponent;
    mesh : Sill.MeshComponent;
    transform : Sill.TransformComponent;

    squareShader : *Magma.Shader;
    piecesTextures : [PieceIdCount]*Magma.Texture;

    movingPiece : MeshEntity;
    pawnPromotionSelecter : PawnPromotionSelecterEntity;
    pieceDragging : bool;

    hoveredCoord : Coord = 0xFF;
    arrowingStartCoord : Coord = 0xFF;
    arrows : [..]*MeshEntity;

    selectedCoord : Coord = 0xFF; // Only valid if there's a piece there.
    pawnPromotionSourceCoord : Coord = 0xFF;
    pawnPromotionTargetCoord : Coord = 0xFF;
}

PawnPromotionSelecterEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;

    buttons : [4]*PawnPromotionSelecterButtonEntity;
}

PawnPromotionSelecterButtonEntity :: struct {
    using #as entity : Sill.Entity;

    ui : Sill.UiComponent;
    mesh : Sill.MeshComponent;
    transform : Sill.TransformComponent;

    pieceKind : PieceKind;
}

MeshEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
}

board_init :: (using board : *BoardEntity) {
    ui.draggable = true;
    ui.extent.width = 8;
    ui.extent.height = 8;

    _init_resources(board);
    _init_meshes(board);

    Sill.ui_on_update(*ui, _on_update, .Hover, userData = board);

    Sill.ui_on_trigger(*ui, (trigger : Sill.UiTrigger, using board : *BoardEntity) {
        if trigger.flags & .NoHover || trigger.flags & .Dragging  {
            _update_hovered_coord(board);
        }

        if !instance.game.ply then return;

        if trigger.flags & .ClickStart {
            if trigger.event.mouseButton.which == .Left {
                // Select a piece if there's one, or move the selected piece.
                if _update_coord_for_piece_movement(board, board.hoveredCoord, playAllowed = instance.config.board.clickClickMove.enabled) {
                    _set_selected_coord(board, board.hoveredCoord);
                } else {
                    // Reset the current highlights
                    instance.game.ply.position.highlights.squares.count = 0;
                    instance.game.ply.position.highlights.arrows.count = 0;
                    board_update_to_position(board, instance.game.ply.position);

                    _set_selected_coord(board, 0xFF);
                }
            }

            if trigger.event.mouseButton.which == instance.config.board.destinationSquareMove.mouseButton {
                _destination_square_piece_movement(board, board.hoveredCoord);
            }
        } else if trigger.flags & .Click {
            if trigger.event.mouseButton.which == .Left {
                // Unselect the square if clicking is not enabled
                if !instance.config.board.clickClickMove.enabled {
                    _set_selected_coord(board, 0xFF);
                }
            } else if trigger.event.mouseButton.which == .Right && hoveredCoord != 0xFF {
                _toggle_hovered_square_highlight(board);
                board_update_to_position(board, instance.game.ply.position);
            }
        } else if trigger.flags & .DragStart {
            if trigger.event.mouseButton.which == .Left {
                if instance.config.board.dragAndDropMove.enabled {
                    pieceDragging = selectedCoord != 0xFF;
                    if pieceDragging then _set_piece_grabbed(board, selectedCoord);
                }
            } else if trigger.event.mouseButton.which == .Right {
                pieceDragging = false;
                board.arrowingStartCoord = hoveredCoord;
            }
        } else if trigger.flags & .Dragging {
            if pieceDragging {
                relativeMousePointerPosition := Sill.ui_relative_mouse_pointer_position(*ui);
                movingPiece.transform.translation.xy = relativeMousePointerPosition;
                Sill.transform_commit(*movingPiece.transform);
            }
        } else if trigger.flags & .DragStop {
            if pieceDragging {
                // selectedCoord can be 0xFF here when we played a move
                if selectedCoord != 0xFF then _set_piece_grabbed(board, selectedCoord, grabbed = false);
                if !instance.config.board.clickClickMove.enabled then _set_selected_coord(board, 0xFF);
                pieceDragging = false;
            } else {
                arrowingStartCoord = 0xFF;
            }
        } else if trigger.flags & .DragDrop {
            if pieceDragging {
                _set_piece_grabbed(board, selectedCoord, grabbed = false);
                _update_coord_for_piece_movement(board, board.hoveredCoord, selectAllowed = false);
            } else {
                _update_hovered_coord(board);
                if board.arrowingStartCoord == board.hoveredCoord {
                    _toggle_hovered_square_highlight(board);
                } else {
                    arrowHighlight : ArrowHighlight;
                    arrowHighlight.color = highlight_color();
                    arrowHighlight.fromCoord = arrowingStartCoord;
                    arrowHighlight.toCoord = hoveredCoord;
                    position_add_arrow_highlight(*instance.game.ply.position, arrowHighlight);
                }
                board_update_to_position(board, instance.game.ply.position);
            }
        }
    }, Sill.UiCallbackFlags.ClickStart | .Click | .NoHover | .DragStart | .Dragging | .DragStop | .DragDrop, board);

    // Drawing a position
    position := get_starting_position();
    board_update_to_position(board, position);
}

board_update_to_size :: (using board : *BoardEntity, size : float) {
    // Each square mesh is created of extent (1,1) so we scale them here.
    transform.factor = size / 8.0;
    Sill.transform_commit(*transform);
}

board_update_from_orientation :: (using board : *BoardEntity, orientation : Color) {
    // 180° rotation around Z when black
    flipped := orientation == .Black;
    transform.rotation = ifx flipped then Chamber.quat.{0, 0, 1, 0} else .{0, 0, 0, 1};
    Sill.transform_commit(*transform);

    for coord : 0..CoordCount-1 {
        node := *mesh.nodes[coord];
        Magma.material_set(node.primitives[0].material, "flipped", flipped);
    }

    Magma.material_set(movingPiece.mesh.nodes[0].primitives[0].material, "flipped", flipped);

    for button : pawnPromotionSelecter.buttons {
        Magma.material_set(button.mesh.nodes[0].primitives[0].material, "flipped", flipped);
    }
}

board_update_to_position :: (using board : *BoardEntity, position : Position) {
    enPassantCoord := position_en_passant_coord(*position);
    for coord : 0 .. CoordCount - 1 {
        node := *mesh.nodes[coord];
        pieceTexture := piecesTextures[piece_id(position.board[coord])];
        moved := coord == position.lastMove.sourceCoord || coord == position.lastMove.targetCoord;
        Magma.material_set(node.primitives[0].material, "moved", moved);
        Magma.material_set(node.primitives[0].material, "selected", false);
        Magma.material_set(node.primitives[0].material, "capturable", position.board[coord].kind != .Empty || coord == enPassantCoord);
        Magma.material_set(node.primitives[0].material, "pieceTexture", pieceTexture);
        Magma.material_set(node.primitives[0].material, "highlightColor", Chamber.vec4.{0, 0, 0, 0});
    }

    for squareHighlight : position.highlights.squares {
        node := *mesh.nodes[squareHighlight.coord];
        Magma.material_set(node.primitives[0].material, "highlightColor", highlight_color_to_vec4(squareHighlight.color));
    }

    _set_selected_coord(board, 0xFF);

    // Destroy old arrows entities.
    // @todo Maybe reuse them if existing!
    for arrow : arrows {
        Sill.destroy_entity(arrow);
    }
    arrows.count = 0;

    for arrowHighlight, arrowIndex : position.highlights.arrows {
        arrow := SillMeta.create_mesh_entity(instance.engine);
        Basic.array_add(*arrows, arrow);

        arrowDirection := coords_direction(arrowHighlight.fromCoord, arrowHighlight.toCoord);
        arrowLength := Math.length(arrowDirection);
        arrowDirection.std /= arrowLength;
        theta := Math.atan2(-arrowDirection.x, arrowDirection.y); // Angle between (0,1) and the arrow direction

        Basic.array_add(*arrow.mesh.nodes, .{});
        Basic.array_add(*arrow.mesh.nodes[0].primitives, create_arrow_mesh(arrowLength, thickness = 0.16, basePadding = 0.24, headPadding = 0.08));

        // Position the arrow
        row, col := row_col(arrowHighlight.fromCoord);
        Sill.entity_set_parent(arrow, board);
        arrow.transform.translation.x = 0.5 + col - 4;
        arrow.transform.translation.y = 0.5 + (7 - row) - 4;
        arrow.transform.translation.z = -0.1; // As this is multiplied by the parent's scaling, cannot use better unit.
        arrow.transform.translation.z -= 0.01 * cast(float) arrowIndex; // Preventing z-fight between arrows.
        Sill.transform_rotate(*arrow.transform, theta, .{0, 0, 1});
        Sill.transform_commit(*arrow.transform);

        arrow.mesh.nodes[0].primitives[0].material = Magma.create_material(instance.shaders.translucentMonochrome);
        Magma.material_set(arrow.mesh.nodes[0].primitives[0].material, "color", highlight_color_to_vec4(arrowHighlight.color));
    }
}

#scope_file

_init_resources :: (using board : *BoardEntity) {
    squareShader = Magma.create_shader(instance.engine.renderer, "./assets/materials/square", .{ alphaBlendingEnabled = true });

    init_piece_texture :: (using board : *BoardEntity, pieceId : PieceId, filename : string) {
        piecesTextures[pieceId] = Magma.create_texture(instance.engine.renderEngine);
        Magma.texture_load_from_file(piecesTextures[pieceId], filename);
    }

    init_piece_texture(board, piece_id(.{ .B, .White }), Basic.tprint("./assets/images/pieces/%-wb.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .K, .White }), Basic.tprint("./assets/images/pieces/%-wk.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .N, .White }), Basic.tprint("./assets/images/pieces/%-wn.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .P, .White }), Basic.tprint("./assets/images/pieces/%-wp.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .Q, .White }), Basic.tprint("./assets/images/pieces/%-wq.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .R, .White }), Basic.tprint("./assets/images/pieces/%-wr.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .B, .Black }), Basic.tprint("./assets/images/pieces/%-bb.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .K, .Black }), Basic.tprint("./assets/images/pieces/%-bk.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .N, .Black }), Basic.tprint("./assets/images/pieces/%-bn.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .P, .Black }), Basic.tprint("./assets/images/pieces/%-bp.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .Q, .Black }), Basic.tprint("./assets/images/pieces/%-bq.png", instance.config.board.pieces));
    init_piece_texture(board, piece_id(.{ .R, .Black }), Basic.tprint("./assets/images/pieces/%-br.png", instance.config.board.pieces));

    // Use a transparent texture for emptiness.
    // @fixme This could be done "automatically" by Magma when the texture is set to "null".
    emptyPieceId := piece_id(.{ kind = .Empty });
    piecesTextures[emptyPieceId] = Magma.create_texture(instance.engine.renderEngine);
    Magma.texture_load_from_memory(piecesTextures[emptyPieceId], .[0, 0, 0, 0], .{1, 1});

    // Moving piece
    Sill.entity_set_disabled(*movingPiece, true);
    Sill.entity_set_parent(*movingPiece, board);

    // Pawn promotion selecter
    Sill.entity_set_parent(*pawnPromotionSelecter, board);
    for *button, buttonIndex : pawnPromotionSelecter.buttons {
        <<button = SillMeta.create_pawn_promotion_selecter_button_entity(instance.engine);
        if buttonIndex == 0 then (<<button).pieceKind = .Queen;
        else if buttonIndex == 1 then (<<button).pieceKind = .Knight;
        else if buttonIndex == 2 then (<<button).pieceKind = .Rook;
        else if buttonIndex == 3 then (<<button).pieceKind = .Bishop;
        Sill.entity_set_disabled(<<button, true);
        Sill.entity_set_parent(<<button, *pawnPromotionSelecter);

        (<<button).transform.translation.z -= 0.15;
        Sill.transform_commit(*(<<button).transform);

        (<<button).ui.anchor = .Center;
        // @todo These on_update/on_trigger are a bit cumbersome...
        Sill.ui_on_trigger(*(<<button).ui, (trigger : Sill.UiTrigger, button : *PawnPromotionSelecterButtonEntity) {
            if trigger.flags & (Sill.UiCallbackFlags.Hover | .NoHover) {
                Magma.material_set(button.mesh.nodes[0].primitives[0].material, "selected", trigger.flags & .Hover);
            } else if trigger.flags & .Click {
                // Effectively play the move to promote
                using *instance.metaBoard.board;
                if position_move_legal(*instance.game.ply.position, pawnPromotionSourceCoord, pawnPromotionTargetCoord, button.pieceKind) {
                    game_play_move(*instance.game, pawnPromotionSourceCoord, pawnPromotionTargetCoord, button.pieceKind);
                }
                _show_pawn_promotion_selecter(*instance.metaBoard.board, .White, false);
            }
        }, Sill.UiCallbackFlags.Hover | .NoHover | .Click, <<button);
        Sill.ui_on_update(*(<<button).ui, (update : Sill.UiUpdate, button : *PawnPromotionSelecterButtonEntity) {
            <<update.stopPropagation = true;
        }, .Hover, <<button);
    }
}

_init_meshes :: (using board : *BoardEntity) {
    for coord : 0 .. CoordCount - 1 {
        squareMesh := create_rect_mesh();
        squareMesh.material = Magma.create_material(squareShader);

        row, col := row_col(cast(u8) coord);
        color := ifx (row + col) % 2 then instance.config.board.lightSquareColor else instance.config.board.darkSquareColor;
        Magma.material_set(squareMesh.material, "color", Chamber.make_vec4(color, 1));

        node := Basic.array_add(*mesh.nodes);
        Basic.array_add(*node.primitives, squareMesh);

        node.transform.translation.x = -4 + (col + 0.5);
        node.transform.translation.y =  4 - (row + 0.5);
    }

    // Moving piece
    movingPieceMesh := create_rect_mesh();
    movingPieceMesh.material = Magma.create_material(squareShader);
    movingPieceNode := Basic.array_add(*movingPiece.mesh.nodes);
    movingPieceNode.transform.translation.z -= 0.3;
    Basic.array_add(*movingPieceNode.primitives, movingPieceMesh);

    // Pawn promotion selecter
    for button, buttonIndex : pawnPromotionSelecter.buttons {
        buttonMesh := create_rect_mesh();
        buttonMesh.material = Magma.create_material(squareShader);
        Magma.material_set(buttonMesh.material, "color", instance.config.board.promotionSelecterColor);
        buttonNode := Basic.array_add(*button.mesh.nodes);
        Basic.array_add(*buttonNode.primitives, buttonMesh);
    }
}

_on_update :: (update : Sill.UiUpdate, board : *BoardEntity) {
    _update_hovered_coord(board);
}

_update_hovered_coord :: (using board : *BoardEntity) {
    relativeMousePointerPosition := Sill.ui_relative_mouse_pointer_position(*ui);

    normalizedCoord : Chamber.vec2;
    normalizedCoord.x = -8.0 * relativeMousePointerPosition.y / ui.extent.width + 4.0;
    normalizedCoord.y =  8.0 * relativeMousePointerPosition.x / ui.extent.width + 4.0;

    if hoveredCoord != 0xFF {
        Magma.material_set(mesh.nodes[hoveredCoord].primitives[0].material, "hovered", false);
    }

    if normalizedCoord.x >= 0 && normalizedCoord.x < 8 && normalizedCoord.y >= 0 && normalizedCoord.y < 8 {
        hoveredCoord = coord(normalizedCoord.x, normalizedCoord.y);
    } else {
        hoveredCoord = 0xFF;
    }

    if hoveredCoord != 0xFF {
        Magma.material_set(mesh.nodes[hoveredCoord].primitives[0].material, "hovered", true);

        if instance.engine.ui.draggingState == .None {
            pointerStyle := ifx piece_at_coord(hoveredCoord).kind != .Empty then Crater.PointerStyle.Hand else .Default;
            Crater.window_pointer_style(instance.engine.window, pointerStyle);
        }
    }
}

_toggle_hovered_square_highlight :: (using board : *BoardEntity) {
    squareHighlight : SquareHighlight;
    squareHighlight.coord = hoveredCoord;
    squareHighlight.color = highlight_color();
    position_toggle_highlight(*instance.game.ply.position, squareHighlight);
}

_destination_square_piece_movement :: (using board : *BoardEntity, targetCoord : Coord) {
    if !instance.config.board.destinationSquareMove.enabled then return;
    position := *instance.game.ply.position;
    colorToPlay := position_color_to_play(position);

    if position.board[targetCoord].kind != .Empty && position.board[targetCoord].color == colorToPlay then return;

    sourceCoords := position_square_source_pieces(position, targetCoord, colorToPlay);

    if sourceCoords.count == 1 {
        selectedCoord = sourceCoords[0];
        _update_coord_for_piece_movement(board, targetCoord, selectAllowed = false);
    } else {
        if instance.config.board.destinationSquareMove.disambiguateWithLastMovedPiece {
            previousPly := ply_previous_ply(instance.game.ply);
            if previousPly && Basic.array_find(sourceCoords, previousPly.position.lastMove.targetCoord) {
                selectedCoord = previousPly.position.lastMove.targetCoord;
                _update_coord_for_piece_movement(board, targetCoord, selectAllowed = false);
                return;
            }
        }

        _set_selected_coord(board, 0xFF);
        for coord : 0 .. CoordCount - 1 {
            Magma.material_set(mesh.nodes[coord].primitives[0].material, "selected", Basic.array_find(sourceCoords, coord));
        }
    }
}

// Called each time a square is simply-clicked.
// Return true if a coord is selected.
_update_coord_for_piece_movement :: (using board : *BoardEntity, targetCoord : Coord, selectAllowed := true, playAllowed := true) -> bool {
    position := *instance.game.ply.position;

    // If we're selecting a piece of our color, just select that square.
    if selectAllowed {
        piece := piece_at_coord(targetCoord);
        if piece.kind != .Empty && piece.color == position_color_to_play(position) {
            return true;
        }
    }

    // Try to play a move if we already had a selected piece.
    if playAllowed && selectedCoord != 0xFF {
        // Pawn promotion query
        row, col := row_col(targetCoord);
        if position.board[selectedCoord].kind == .Pawn && (row == 0 || row == 7) {
            pawnPromotionSourceCoord = selectedCoord;
            pawnPromotionTargetCoord = targetCoord;
            _show_pawn_promotion_selecter(board, position_color_to_play(position));
        } else if position_move_legal(position, selectedCoord, targetCoord, .Empty) {
            game_play_move(*instance.game, selectedCoord, targetCoord, .Empty);
        }
    }

    return false;
}

_set_selected_coord :: (using board : *BoardEntity, coord : Coord) {
    if selectedCoord == coord then return;

    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(mesh.nodes[coord].primitives[0].material, "selected", false);
        Magma.material_set(mesh.nodes[coord].primitives[0].material, "targetable", false);
    }

    selectedCoord = coord;

    if selectedCoord != 0xFF {
        Magma.material_set(mesh.nodes[selectedCoord].primitives[0].material, "selected", true);
        if instance.config.board.highlightValidSquares {
            for targetCoord : position_find_piece_targets(*instance.game.ply.position, coord) {
                Magma.material_set(mesh.nodes[targetCoord].primitives[0].material, "targetable", true);
            }
        }
    }
}

_set_piece_grabbed :: (using board : *BoardEntity, coord : Coord, grabbed := true) {
    Sill.entity_set_disabled(*movingPiece, !grabbed);
    squareMaterial := mesh.nodes[coord].primitives[0].material;

    if grabbed {
        movingPieceMaterial := movingPiece.mesh.nodes[0].primitives[0].material;
        pieceTexture := piecesTextures[piece_id(instance.game.ply.position.board[selectedCoord])];
        Magma.material_set(movingPieceMaterial, "pieceTexture", pieceTexture);
        Magma.material_set(squareMaterial, "pieceTranslucency", 1.0 - instance.config.board.dragAndDropMove.ghostOpacity);
        Crater.window_pointer_style(instance.engine.window, .HandGrabbing);
    } else {
        Magma.material_set(mesh.nodes[selectedCoord].primitives[0].material, "pieceTranslucency", 0);
    }
}

_show_pawn_promotion_selecter :: (using board : *BoardEntity, color : Color, shown := true) {
    for button : pawnPromotionSelecter.buttons {
        Sill.entity_set_disabled(button, !shown);
        if shown {
            buttonMaterial := button.mesh.nodes[0].primitives[0].material;
            Magma.material_set(buttonMaterial, "pieceTexture", piecesTextures[piece_id(button.pieceKind, color)]);
        }
    }

    if shown {
        // In case of a promotion at the bottom, we should reverse the order.
        for button, buttonIndex : pawnPromotionSelecter.buttons {
            button.transform.translation.y = ifx color == instance.metaBoard.orientation then cast(float) buttonIndex else cast(float) -buttonIndex;
        }

        row, col := row_col(hoveredCoord);
        pawnPromotionSelecter.transform.translation.x = col - 3.5;
        pawnPromotionSelecter.transform.translation.y = 3.5 - row;
        Sill.transform_commit(*pawnPromotionSelecter.transform);
    }
}
