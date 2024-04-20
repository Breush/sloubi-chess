// The boardView entity is really the squares and arrows.
BoardView :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    ui : Sill.UiComponent;
    mesh : Sill.MeshComponent;
    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;

    squareShader : *Magma.Shader;
    piecesTextures : [PieceIdCount]*Magma.Texture;

    arrows : [..]*MeshEntity;
    bestMoveCentipawnsMeshNode : *Sill.MeshNode;
    movingPiece : MeshEntity;
    pawnPromotionSelecter : PawnPromotionSelecterEntity;

    #as state : Board;

    on_cleanup :: (using boardView : *BoardView) {
        Basic.array_free(arrows);
        board_cleanup(boardView);
    }
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

board_view_init :: (using boardView : *BoardView) {
    ui.draggable = true;
    ui.extent.width = 8;
    ui.extent.height = 8;

    Sill.listener_on_message(*boardView.listener, _on_message);

    _init_resources(boardView);
    _init_meshes(boardView);

    Sill.ui_on_trigger(*ui, (trigger : Sill.UiTrigger, using boardView : *BoardView) {
        if trigger.flags & (Sill.UiCallbackFlags.Hovering | .HoverStop | .Dragging)  {
            relativeMousePointerPosition := Sill.ui_relative_mouse_pointer_position(*ui);

            normalizedCoord : Chamber.vec2;
            normalizedCoord.x = -8.0 * relativeMousePointerPosition.y / ui.extent.width + 4.0;
            normalizedCoord.y =  8.0 * relativeMousePointerPosition.x / ui.extent.width + 4.0;

            if normalizedCoord.x >= 0 && normalizedCoord.x < 8 && normalizedCoord.y >= 0 && normalizedCoord.y < 8 {
                board_hover_coord(boardView, coord(normalizedCoord.x, normalizedCoord.y));
            } else {
                board_hover_coord(boardView, 0xFF);
            }
        } else if trigger.flags & .ClickStart {
            Sill.ui_set_focused(*boardView.ui);
        } else if trigger.flags & .Key {
            if !state.positionEdit then smart_mover_ui_trigger(*instance.metaBoard.smartMover, trigger);
        }

        board_ui_trigger(*state, trigger);

        if trigger.flags & .Dragging && state.grabbedCoord != 0xFF {
            relativeMousePointerPosition := Sill.ui_relative_mouse_pointer_position(*ui);
            movingPiece.transform.translation.xy = relativeMousePointerPosition;
            Sill.transform_commit(*movingPiece.transform);
        }
    }, userData = boardView);

    // Drawing a position
    board_set_position(boardView, *STARTING_POSITION);
    board_interactive(boardView, false);
}

board_view_update_to_size :: (using boardView : *BoardView, size : float) {
    squareScaling := Math.floor(size / 8 + 0.5);

    movingPiece.transform.factor = squareScaling;

    mesh.nodes[0].transform.scaling.x = squareScaling;
    mesh.nodes[0].transform.scaling.y = squareScaling;
    Sill.transform_commit(*transform);

    boardView.ui.extent.width = size;
    boardView.ui.extent.height = size;

    _update_highlights(boardView);
}

board_view_update_from_orientation :: (using boardView : *BoardView, orientation : Color) {
    // 180° rotation around Z when black
    flipped := orientation == .Black;
    transform.rotation = ifx flipped then Chamber.quat.{0, 0, 1, 0} else .{0, 0, 0, 1};
    Sill.transform_commit(*transform);

    for coord : 0..CoordCount-1 {
        Magma.material_set(_square_mesh(boardView, coord).material, "flipped", flipped);
    }

    Magma.material_set(movingPiece.mesh.nodes[0].primitives[0].material, "flipped", flipped);

    for button : pawnPromotionSelecter.buttons {
        Magma.material_set(button.mesh.nodes[0].primitives[0].material, "flipped", flipped);
    }
}

board_view_preview_summary :: (using boardView : *BoardView, game : Game) {
    _update_from_board_view_position(boardView, board_position(game.summary.lastBoardPosition));
    board_view_update_from_orientation(boardView, game.summary.lastBoardOrientation);

    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(_square_mesh(boardView, coord).material, "pieceTranslucency", 0);
    }

    // @todo A better looking tracing would be a good idea,
    // but this might require to separate pieces from the boardView mesh.
    lastMove := game.summary.lastMove;
    if coord_is_valid(lastMove.sourceCoord) && coord_is_valid(lastMove.targetCoord) {
        Magma.material_set(_square_mesh(boardView, lastMove.sourceCoord).material, "moved", true);
        Magma.material_set(_square_mesh(boardView, lastMove.targetCoord).material, "moved", true);
    }
}

#scope_file

_on_message :: (using boardView : *BoardView, message : *Message) {
    if message.kind == {
    case .PositionHighlightsChanged;
        if message.position != state.position then return;
        _update_highlights(boardView);
    case .BoardInteractiveChanged;
        _update_from_interactive(boardView);
    case .BoardPositionChanged;
        _update_from_position(boardView);
    case .BoardSelectedCoordChanged;
        _update_from_selected_coord(boardView, message.oldCoord);
    case .BoardHoveredCoordChanged;
        _update_from_hovered_coord(boardView, message.oldCoord);
    case .BoardGrabbedCoordChanged;
        _update_from_grabbed_coord(boardView, message.oldCoord);
    case .BoardTargetableCoordsChanged;
        _update_from_targetable_coords(boardView);
    case .BoardHintedCoordsChanged;
        _update_from_hinted_coords(boardView);
    case .BoardPawnPromotionSelectionStarted;
        _show_pawn_promotion_selecter(boardView);
    case .BoardPawnPromotionSelectionStopped;
        _hide_pawn_promotion_selecter(boardView);
    case .BoardPositionEditChanged;
        _update_from_position_edit(boardView);
    case .CurrentGameChanged;
        board_interactive(boardView, instance.currentGame != null);
    case .PositionBoardCoordChanged;
        _update_from_position_coord(boardView, message.coord);
    case .UciBestMoveChanged;
        _update_highlights(boardView);
    case .UciBestMoveCentipawnsChanged;
        _update_best_move_centipawns(boardView);
    }
}

_update_from_position_edit :: (using boardView : *BoardView) {
    pieceTranslucency := ifx state.positionEdit then 0.2 else 0.0;
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(_square_mesh(boardView, coord).material, "pieceTranslucency", pieceTranslucency);
    }

    if state.positionEdit then _reset_highlights(boardView);
    else _update_highlights(boardView);
}

_update_from_interactive :: (using boardView : *BoardView) {
    // Make all pieces ghost-like when not interactive.
    pieceTranslucency := ifx state.interactive then 0.0 else 0.4;
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(_square_mesh(boardView, coord).material, "pieceTranslucency", pieceTranslucency);
    }

    if !state.interactive {
        _hide_pawn_promotion_selecter(boardView);
    }
}

_update_from_board_view_position :: (using boardView : *BoardView, boardPosition : BoardPosition) {
    for coord : 0 .. CoordCount - 1 {
        squareMesh := _square_mesh(boardView, coord);
        piece := boardPosition[coord];
        pieceTexture := piecesTextures[piece_id(piece)];
        Magma.material_set(squareMesh.material, "moved", false);
        Magma.material_set(squareMesh.material, "selected", false);
        Magma.material_set(squareMesh.material, "pieceTexture", pieceTexture);
    }
}

_update_from_position :: (using boardView : *BoardView, position : *Position = null) {
    if position == null then position = state.position;
    enPassantCoord := position_en_passant_coord(position);
    for coord : 0 .. CoordCount - 1 {
        squareMesh := _square_mesh(boardView, coord);
        pieceTexture := piecesTextures[piece_id(position.board[coord])];
        moved := coord == position.lastMove.sourceCoord || coord == position.lastMove.targetCoord;
        Magma.material_set(squareMesh.material, "moved", moved);
        Magma.material_set(squareMesh.material, "selected", false);
        Magma.material_set(squareMesh.material, "capturable", position.board[coord].kind != .None || coord == enPassantCoord);
        Magma.material_set(squareMesh.material, "pieceTexture", pieceTexture);
    }

    _update_highlights(boardView, position);
}

_update_from_position_coord :: inline (using boardView : *BoardView, coord : Coord) {
    pieceTexture := piecesTextures[piece_id(state.position.board[coord])];
    Magma.material_set(_square_mesh(boardView, coord).material, "pieceTexture", pieceTexture);
}

_update_from_selected_coord :: (using boardView : *BoardView, oldCoord : Coord) {
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(_square_mesh(boardView, coord).material, "selected", coord == state.selectedCoord);
    }
}

_update_from_hovered_coord :: (using boardView : *BoardView, oldCoord : Coord) {
    if oldCoord != 0xFF {
        Magma.material_set(_square_mesh(boardView, oldCoord).material, "hovered", false);
    }

    if state.hoveredCoord != 0xFF {
        Magma.material_set(_square_mesh(boardView, state.hoveredCoord).material, "hovered", true);

        if instance.engine.ui.draggingState == .None {
            pointerStyle := ifx piece_at_coord(state.hoveredCoord).kind != .None then Crater.PointerStyle.Hand else .Default;
            Crater.window_pointer_style(instance.engine.window, pointerStyle);
        }
    }
}

_update_from_grabbed_coord :: (using boardView : *BoardView, oldCoord : Coord) {
    Sill.entity_set_disabled(*movingPiece, state.grabbedCoord == 0xFF);

    if oldCoord != 0xFF {
        Magma.material_set(_square_mesh(boardView, oldCoord).material, "pieceTranslucency", 0.0);
    }

    if state.grabbedCoord != 0xFF {
        movingPieceMaterial := movingPiece.mesh.nodes[0].primitives[0].material;
        pieceTexture := piecesTextures[piece_id(instance.currentGame.ply.position.board[state.grabbedCoord])];
        Magma.material_set(movingPieceMaterial, "pieceTexture", pieceTexture);
        Magma.material_set(_square_mesh(boardView, state.grabbedCoord).material, "pieceTranslucency", 1.0 - instance.config.board.dragAndDropMove.ghostOpacity);
        Crater.window_pointer_style(instance.engine.window, .HandGrabbing);
    }
}

_update_from_targetable_coords :: (using boardView : *BoardView) {
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(_square_mesh(boardView, coord).material, "targetable", Basic.array_find(state.targetableCoords, coord));
    }
}

_update_from_hinted_coords :: (using boardView : *BoardView) {
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(_square_mesh(boardView, coord).material, "selected", Basic.array_find(state.hintedCoords, coord));
    }
}

_reset_highlights :: (using boardView : *BoardView) {
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set_color(_square_mesh(boardView, coord).material, "highlightColor", Chamber.vec4.{0, 0, 0, 0});
    }

    // Destroy old arrows entities.
    // @todo Maybe reuse them if existing!
    for arrow : arrows {
        Sill.destroy_entity(arrow);
    }
    arrows.count = 0;
}

_update_highlights :: (using boardView : *BoardView, position : *Position = null) {
    if position == null then position = state.position;
    if position == null then return;

    _reset_highlights(boardView);

    for squareHighlight : position.highlights.squares {
        Magma.material_set_color(_square_mesh(boardView, squareHighlight.coord).material, "highlightColor", highlight_color_to_vec4(squareHighlight.color));
    }

    _create_arrow_mesh :: (using boardView : *BoardView, fromCoord : Coord, toCoord : Coord, color : Chamber.vec4, textNeeded := false) {
        arrow := SillMeta.create_mesh_entity(instance.engine);
        Basic.array_add(*arrows, arrow);

        squareSize := Math.floor(boardView.ui.extent.width / 8 + 0.5);

        arrowDirection := coords_direction(fromCoord, toCoord);
        arrowLength := Math.length(arrowDirection);
        arrowDirection.std /= arrowLength;
        theta := Math.atan2(-arrowDirection.x, arrowDirection.y); // Angle between (0,1) and the arrow direction

        arrowNode := Basic.array_add(*arrow.mesh.nodes);
        arrowNode.transform.scaling.x = squareSize;
        arrowNode.transform.scaling.y = squareSize;
        arrowNode.transform.rotation = Chamber.quat.{0, 0, Math.sin(theta / 2), Math.cos(theta / 2)};

        Basic.array_add(*arrowNode.primitives, create_arrow_mesh(arrowLength, thickness = 0.16, basePadding = 0.24, headPadding = 0.08));

        if textNeeded {
            bestMoveCentipawnsMeshNode = Basic.array_add(*arrow.mesh.nodes);
            bestMoveCentipawnsMeshNode.transform.translation.x = -arrowLength / 2 * Math.sin(theta) * squareSize;
            bestMoveCentipawnsMeshNode.transform.translation.y = arrowLength / 2 * Math.cos(theta) * squareSize;
            Basic.array_add(*bestMoveCentipawnsMeshNode.primitives, create_text_mesh());

            if instance.metaBoard.orientation == .Black {
                bestMoveCentipawnsMeshNode.transform.rotation = Chamber.quat.{0, 0, 1, 0};
            }
        }

        // Position the arrow
        row, col := row_col(fromCoord);
        Sill.entity_set_parent(arrow, boardView);
        arrow.transform.translation.x = (0.5 + col - 4) * squareSize;
        arrow.transform.translation.y = (0.5 + (7 - row) - 4) * squareSize;
        arrow.transform.translation.z = UiConstants.DepthMetaBoardViewArrow;
        arrow.transform.translation.z -= 0.1 * cast(float) (arrows.count - 1); // Preventing z-fight between arrows.
        Sill.transform_commit(*arrow.transform);

        arrow.mesh.nodes[0].primitives[0].material = Magma.create_material(instance.shaders.translucentMonochrome);
        Magma.material_set_color(arrow.mesh.nodes[0].primitives[0].material, "color", color);
    }

    // Keep the engine arrow first so that it is always below userdef ones.
    bestMove := instance.uci.bestMove;
    if coord_is_valid(bestMove.sourceCoord) && coord_is_valid(bestMove.targetCoord) {
        _create_arrow_mesh(boardView, bestMove.sourceCoord, bestMove.targetCoord, instance.config.analysis.highlightColor, textNeeded = true);
        _update_best_move_centipawns(boardView);
    } else {
        bestMoveCentipawnsMeshNode = null;
    }

    for arrowHighlight : position.highlights.arrows {
        _create_arrow_mesh(boardView, arrowHighlight.fromCoord, arrowHighlight.toCoord, highlight_color_to_vec4(arrowHighlight.color));
    }
}

_update_best_move_centipawns :: (using boardView : *BoardView) {
    text := centipawns_to_display(instance.uci.bestMoveCentipawns);
    text_mesh_update(bestMoveCentipawnsMeshNode.primitives[0], text, "mainLight", instance.config.env.textColor, anchor = .Center);
}

_init_resources :: (using boardView : *BoardView) {
    squareShader = Magma.create_shader(instance.engine.renderer, "./assets/materials/square", .{ alphaBlendingEnabled = true });

    init_piece_texture :: (using boardView : *BoardView, pieceId : PieceId, filename : string) {
        piecesTextures[pieceId] = Magma.create_texture(instance.engine.renderEngine);
        Magma.texture_load_from_file(piecesTextures[pieceId], filename);
    }

    init_piece_texture(boardView, piece_id(.{ .B, .White }), Basic.tprint("./assets/images/pieces/%-wb.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .K, .White }), Basic.tprint("./assets/images/pieces/%-wk.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .N, .White }), Basic.tprint("./assets/images/pieces/%-wn.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .P, .White }), Basic.tprint("./assets/images/pieces/%-wp.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .Q, .White }), Basic.tprint("./assets/images/pieces/%-wq.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .R, .White }), Basic.tprint("./assets/images/pieces/%-wr.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .B, .Black }), Basic.tprint("./assets/images/pieces/%-bb.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .K, .Black }), Basic.tprint("./assets/images/pieces/%-bk.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .N, .Black }), Basic.tprint("./assets/images/pieces/%-bn.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .P, .Black }), Basic.tprint("./assets/images/pieces/%-bp.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .Q, .Black }), Basic.tprint("./assets/images/pieces/%-bq.png", instance.config.board.pieces));
    init_piece_texture(boardView, piece_id(.{ .R, .Black }), Basic.tprint("./assets/images/pieces/%-br.png", instance.config.board.pieces));

    emptyPieceId := piece_id(.{ kind = .None });
    piecesTextures[emptyPieceId] = null;

    // Moving piece
    Sill.entity_set_disabled(*movingPiece, true);
    Sill.entity_set_parent(*movingPiece, boardView);

    // Pawn promotion selecter
    Sill.entity_set_parent(*pawnPromotionSelecter, boardView);
    for *button, buttonIndex : pawnPromotionSelecter.buttons {
        button.* = SillMeta.create_pawn_promotion_selecter_button_entity(instance.engine);
        if buttonIndex == 0 then button.*.pieceKind = .Queen;
        else if buttonIndex == 1 then button.*.pieceKind = .Knight;
        else if buttonIndex == 2 then button.*.pieceKind = .Rook;
        else if buttonIndex == 3 then button.*.pieceKind = .Bishop;
        Sill.entity_set_disabled(button.*, true);
        Sill.entity_set_parent(button.*, *pawnPromotionSelecter);

        button.*.transform.translation.z -= 0.15;
        Sill.transform_commit(*button.*.transform);

        button.*.ui.anchor = .Center;
        Sill.ui_on_trigger(*button.*.ui, (trigger : Sill.UiTrigger, button : *PawnPromotionSelecterButtonEntity) {
            if trigger.flags & .Hovering {
                trigger.stopPropagation.* = true;
            }

            using boardView := cast(*BoardView) button.parent.parent;
            if trigger.flags & (Sill.UiCallbackFlags.HoverStart | .HoverStop) {
                Magma.material_set(button.mesh.nodes[0].primitives[0].material, "selected", cast(bool) trigger.flags & .HoverStart);
            } else if trigger.flags & .ClickStop {
                board_play_pawn_promotion(*state, button.pieceKind);
            }
        }, Sill.UiCallbackFlags.HoverStart | .Hovering | .HoverStop | .ClickStop, button.*);
    }
}

_init_meshes :: (using boardView : *BoardView) {
    // Root node, children are those who are placed in a normalized board (i.e. squareSize == 1).
    Basic.array_add(*mesh.nodes, .{});

    for coord : 0 .. CoordCount - 1 {
        squareMesh := create_rect_mesh();
        squareMesh.material = Magma.create_material(squareShader);

        row, col := row_col(cast(u8) coord);
        color := ifx (row + col) % 2 then instance.config.board.lightSquareColor else instance.config.board.darkSquareColor;
        Magma.material_set_color(squareMesh.material, "color", Chamber.make_vec4(color, 1));
        Magma.material_fallback(squareMesh.material, "pieceTexture", *engine.renderEngine.textureInvisible);

        node := Basic.array_add(*mesh.nodes);
        Sill.mesh_set_parent(*mesh, coord + 1, 0);
        Basic.array_add(*node.primitives, squareMesh);

        node.transform.translation.x = -4 + (col + 0.5);
        node.transform.translation.y =  4 - (row + 0.5);
    }

    // Moving piece
    movingPieceMesh := create_rect_mesh();
    movingPieceMesh.material = Magma.create_material(squareShader);
    movingPieceNode := Basic.array_add(*movingPiece.mesh.nodes);
    movingPieceNode.transform.translation.z = UiConstants.DepthMetaBoardViewMovingPiece;
    Basic.array_add(*movingPieceNode.primitives, movingPieceMesh);

    // Pawn promotion selecter
    for button, buttonIndex : pawnPromotionSelecter.buttons {
        buttonMesh := create_rect_mesh();
        buttonMesh.material = Magma.create_material(squareShader);
        Magma.material_set_color(buttonMesh.material, "color", instance.config.board.promotionSelecterColor);
        buttonNode := Basic.array_add(*button.mesh.nodes);
        Basic.array_add(*buttonNode.primitives, buttonMesh);
    }
}

_show_pawn_promotion_selecter :: (using boardView : *BoardView) {
    color := position_color_to_play(state.position);

    for button : pawnPromotionSelecter.buttons {
        Sill.entity_set_disabled(button, false);
        buttonMaterial := button.mesh.nodes[0].primitives[0].material;
        Magma.material_set(buttonMaterial, "pieceTexture", piecesTextures[piece_id(button.pieceKind, color)]);
    }

    // In case of a promotion at the bottom, we should reverse the order.
    for button, buttonIndex : pawnPromotionSelecter.buttons {
        button.transform.translation.y = ifx color == .White then cast(float) buttonIndex else cast(float) -buttonIndex;
    }

    row, col := row_col(state.pawnPromotionTargetCoord);
    pawnPromotionSelecter.transform.translation.x = col - 3.5;
    pawnPromotionSelecter.transform.translation.y = 3.5 - row;
    Sill.transform_commit(*pawnPromotionSelecter.transform);
}

_hide_pawn_promotion_selecter :: (using boardView : *BoardView) {
    for button : pawnPromotionSelecter.buttons {
        Sill.entity_set_disabled(button, true);
    }
}

_square_mesh_node :: (using boardView : *BoardView, coord : Coord) -> *Sill.MeshNode {
    // Root node is at 0.
    return *mesh.nodes[coord + 1];
}

_square_mesh :: (using boardView : *BoardView, coord : Coord) -> *Magma.Mesh {
    return _square_mesh_node(boardView, coord).primitives[0];
}
