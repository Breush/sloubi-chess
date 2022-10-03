// The board entity is really the squares and arrows.
BoardEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    ui : Sill.UiComponent;
    mesh : Sill.MeshComponent;
    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;

    squareShader : *Magma.Shader;
    piecesTextures : [PieceIdCount]*Magma.Texture;

    arrows : [..]*MeshEntity;
    movingPiece : MeshEntity;
    pawnPromotionSelecter : PawnPromotionSelecterEntity;

    #as state : BoardState;

    on_cleanup :: (using board : *BoardEntity) {
        Basic.array_free(arrows);
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

board_init :: (using board : *BoardEntity) {
    ui.draggable = true;
    ui.extent.width = 8;
    ui.extent.height = 8;

    Sill.listener_on_message(*board.listener, _on_message);

    _init_resources(board);
    _init_meshes(board);

    Sill.ui_on_trigger(*ui, (trigger : Sill.UiTrigger, using board : *BoardEntity) {
        if trigger.flags & (Sill.UiCallbackFlags.Hovering | .HoverStop | .Dragging)  {
            relativeMousePointerPosition := Sill.ui_relative_mouse_pointer_position(*ui);

            normalizedCoord : Chamber.vec2;
            normalizedCoord.x = -8.0 * relativeMousePointerPosition.y / ui.extent.width + 4.0;
            normalizedCoord.y =  8.0 * relativeMousePointerPosition.x / ui.extent.width + 4.0;

            if normalizedCoord.x >= 0 && normalizedCoord.x < 8 && normalizedCoord.y >= 0 && normalizedCoord.y < 8 {
                board_state_hover_coord(board, coord(normalizedCoord.x, normalizedCoord.y));
            } else {
                board_state_hover_coord(board, 0xFF);
            }
        }

        board_state_ui_trigger(board, trigger);

        if trigger.flags & .Dragging && state.grabbedCoord != 0xFF {
            relativeMousePointerPosition := Sill.ui_relative_mouse_pointer_position(*ui);
            movingPiece.transform.translation.xy = relativeMousePointerPosition;
            Sill.transform_commit(*movingPiece.transform);
        }
    }, Sill.UiCallbackFlags.ClickStart | .ClickStop | .Hovering | .HoverStop | .DragStart | .Dragging | .DragStop | .DragDrop, board);

    // Drawing a position
    board_state_set_position(board, *STARTING_POSITION);
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

#scope_file

_on_message :: (using board : *BoardEntity, message : *Message) {
    if message.kind == {
    case .ModeGameStarted;
        board_state_interactive(board, true);
    case .ModeGameStopped;
        _hide_pawn_promotion_selecter(board);
        board_state_interactive(board, false);
    case .PositionHighlightsChanged;
        if message.position != state.position then return;
        _update_highlights(board);
    case .BoardStatePositionChanged;
        _update_from_position(board);
    case .BoardStateSelectedCoordChanged;
        _update_from_selected_coord(board, message.oldCoord);
    case .BoardStateHoveredCoordChanged;
        _update_from_hovered_coord(board, message.oldCoord);
    case .BoardStateGrabbedCoordChanged;
        _update_from_grabbed_coord(board, message.oldCoord);
    case .BoardStateTargetableCoordsChanged;
        _update_from_targetable_coords(board);
    case .BoardStateHintedCoordsChanged;
        _update_from_hinted_coords(board);
    case .BoardStatePawnPromotionSelectionStarted;
        _show_pawn_promotion_selecter(board);
    case .BoardStatePawnPromotionSelectionStopped;
        _hide_pawn_promotion_selecter(board);
    }
}

_update_from_position :: (using board : *BoardEntity) {
    position := state.position;
    enPassantCoord := position_en_passant_coord(position);
    for coord : 0 .. CoordCount - 1 {
        node := *mesh.nodes[coord];
        pieceTexture := piecesTextures[piece_id(position.board[coord])];
        moved := coord == position.lastMove.sourceCoord || coord == position.lastMove.targetCoord;
        Magma.material_set(node.primitives[0].material, "moved", moved);
        Magma.material_set(node.primitives[0].material, "selected", false);
        Magma.material_set(node.primitives[0].material, "capturable", position.board[coord].kind != .Empty || coord == enPassantCoord);
        Magma.material_set(node.primitives[0].material, "pieceTexture", pieceTexture);
    }

    _update_highlights(board);
}

_update_from_selected_coord :: (using board : *BoardEntity, oldCoord : Coord) {
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(mesh.nodes[coord].primitives[0].material, "selected", coord == state.selectedCoord);
    }
}

_update_from_hovered_coord :: (using board : *BoardEntity, oldCoord : Coord) {
    if oldCoord != 0xFF {
        Magma.material_set(mesh.nodes[oldCoord].primitives[0].material, "hovered", false);
    }

    if state.hoveredCoord != 0xFF {
        Magma.material_set(mesh.nodes[state.hoveredCoord].primitives[0].material, "hovered", true);

        if instance.engine.ui.draggingState == .None {
            pointerStyle := ifx piece_at_coord(state.hoveredCoord).kind != .Empty then Crater.PointerStyle.Hand else .Default;
            Crater.window_pointer_style(instance.engine.window, pointerStyle);
        }
    }
}

_update_from_grabbed_coord :: (using board : *BoardEntity, oldCoord : Coord) {
    Sill.entity_set_disabled(*movingPiece, state.grabbedCoord == 0xFF);

    if oldCoord != 0xFF {
        Magma.material_set(mesh.nodes[oldCoord].primitives[0].material, "pieceTranslucency", 0.0);
    }

    if state.grabbedCoord != 0xFF {
        movingPieceMaterial := movingPiece.mesh.nodes[0].primitives[0].material;
        pieceTexture := piecesTextures[piece_id(instance.game.ply.position.board[state.grabbedCoord])];
        Magma.material_set(movingPieceMaterial, "pieceTexture", pieceTexture);
        Magma.material_set(mesh.nodes[state.grabbedCoord].primitives[0].material, "pieceTranslucency", 1.0 - instance.config.board.dragAndDropMove.ghostOpacity);
        Crater.window_pointer_style(instance.engine.window, .HandGrabbing);
    }
}

_update_from_targetable_coords :: (using board : *BoardEntity) {
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(mesh.nodes[coord].primitives[0].material, "targetable", Basic.array_find(state.targetableCoords, coord));
    }
}

_update_from_hinted_coords :: (using board : *BoardEntity) {
    for coord : 0 .. CoordCount - 1 {
        Magma.material_set(mesh.nodes[coord].primitives[0].material, "selected", Basic.array_find(state.hintedCoords, coord));
    }
}

_update_highlights :: (using board : *BoardEntity) {
    position := state.position;
    if position == null then return;

    for coord : 0 .. CoordCount - 1 {
        node := *mesh.nodes[coord];
        Magma.material_set(node.primitives[0].material, "highlightColor", Chamber.vec4.{0, 0, 0, 0});
    }

    for squareHighlight : position.highlights.squares {
        node := *mesh.nodes[squareHighlight.coord];
        Magma.material_set(node.primitives[0].material, "highlightColor", highlight_color_to_vec4(squareHighlight.color));
    }

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

    emptyPieceId := piece_id(.{ kind = .Empty });
    piecesTextures[emptyPieceId] = null;

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
        Sill.ui_on_trigger(*(<<button).ui, (trigger : Sill.UiTrigger, button : *PawnPromotionSelecterButtonEntity) {
            if trigger.flags & .Hovering {
                <<trigger.stopPropagation = true;
            }

            using board := cast(*BoardEntity) button.parent.parent;
            if trigger.flags & (Sill.UiCallbackFlags.HoverStart | .HoverStop) {
                Magma.material_set(button.mesh.nodes[0].primitives[0].material, "selected", cast(bool) trigger.flags & .HoverStart);
            } else if trigger.flags & .ClickStop {
                board_state_play_pawn_promotion(*state, button.pieceKind);
            }
        }, Sill.UiCallbackFlags.HoverStart | .Hovering | .HoverStop | .ClickStop, <<button);
    }
}

_init_meshes :: (using board : *BoardEntity) {
    for coord : 0 .. CoordCount - 1 {
        squareMesh := create_rect_mesh();
        squareMesh.material = Magma.create_material(squareShader);

        row, col := row_col(cast(u8) coord);
        color := ifx (row + col) % 2 then instance.config.board.lightSquareColor else instance.config.board.darkSquareColor;
        Magma.material_set(squareMesh.material, "color", Chamber.make_vec4(color, 1));
        Magma.material_fallback(squareMesh.material, "pieceTexture", *engine.renderEngine.textureInvisible);

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

_show_pawn_promotion_selecter :: (using board : *BoardEntity) {
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

    row, col := row_col(state.hoveredCoord);
    pawnPromotionSelecter.transform.translation.x = col - 3.5;
    pawnPromotionSelecter.transform.translation.y = 3.5 - row;
    Sill.transform_commit(*pawnPromotionSelecter.transform);
}

_hide_pawn_promotion_selecter :: (using board : *BoardEntity) {
    for button : pawnPromotionSelecter.buttons {
        Sill.entity_set_disabled(button, true);
    }
}
