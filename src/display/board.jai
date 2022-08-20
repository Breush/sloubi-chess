// The board entity is really the squares and arrows.
BoardEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    ui : Sill.UiComponent;
    mesh : Sill.MeshComponent;
    transform : Sill.TransformComponent;

    squareShader : *Magma.Shader;
    piecesTextures : [PieceIdCount]*Magma.Texture;

    hoveredCoord : Coord = 0xFF;
    arrowingStartCoord : Coord = 0xFF;
    arrows : [..]*ArrowEntity;
}

ArrowEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
}

board_init :: (using board : *BoardEntity) {
    ui.draggable = true;

    _init_resources(board);
    _init_meshes(board);

    Sill.ui_on_update(*ui, _on_update, userData = board);

    Sill.ui_on_trigger(*ui, (trigger : Sill.UiTrigger, using board : *BoardEntity) {
        if trigger.flags & .NoHover || trigger.flags & .Dragging  {
            _update_hovered_coord(board);
            return;
        }

        if !instance.game.ply then return;

        if trigger.flags & .Click {
            if trigger.event.mouseButton.which == .Left {
                instance.game.ply.position.highlights.squares.count = 0;
                instance.game.ply.position.highlights.arrows.count = 0;
            } else if trigger.event.mouseButton.which == .Right && hoveredCoord != 0xFF {
                _toggle_hovered_square_highlight(board);
            }
        } else if trigger.flags & .Drag {
            board.arrowingStartCoord = hoveredCoord;
        } else if trigger.flags & .NoDrag {
            if trigger.event.mouseButton.which == .Right {
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
            }
        }

        board_update_to_position(board, instance.game.ply.position);
    }, Sill.UiCallbackFlags.Click | .NoHover | .Drag | .Dragging | .NoDrag, board);

    // Drawing a position
    position := get_starting_position();
    board_update_to_position(board, position);
}

board_update_to_size :: (using board : *BoardEntity, size : float) {
    ui.extent.width, ui.extent.height = size, size;

    // Each square mesh is created of extent (1,1) so we scale them here.
    transform.factor = size / 8.0;
    Sill.transform_commit(*transform);
}

board_update_from_orientation :: (using board : *BoardEntity, orientation : Color) {
    // 180° rotation around Z when black
    transform.rotation = ifx orientation == .Black then Chamber.quat.{0, 0, 1, 0} else .{0, 0, 0, 1};
    Sill.transform_commit(*transform);

    for coord : 0..CoordCount-1 {
        node := *mesh.nodes[coord];
        Magma.material_set(node.primitives[0].material, "flipped", orientation == .Black);
    }
}

board_update_to_position :: (using board : *BoardEntity, position : Position) {
    for coord : 0..CoordCount-1 {
        node := *mesh.nodes[coord];
        pieceTexture := piecesTextures[piece_id(position.board[coord])];
        Magma.material_set(node.primitives[0].material, "pieceTexture", pieceTexture);
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
        arrow := SillMeta.create_arrow_entity(instance.engine);
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
    squareShader = Magma.create_shader(instance.engine.renderer, "./assets/materials/square");

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
}

_init_meshes :: (using board : *BoardEntity) {
    for coord : 0..CoordCount-1 {
        squareMesh := create_rect_mesh();
        squareMesh.material = Magma.create_material(squareShader);

        row, col := row_col(cast(u8) coord);
        color := ifx (row + col) % 2 then instance.config.board.lightSquareColor else instance.config.board.darkSquareColor;
        Magma.material_set(squareMesh.material, "color", color);

        node := Basic.array_add(*mesh.nodes);
        Basic.array_add(*node.primitives, squareMesh);

        node.transform.translation.x = -4 + (col + 0.5);
        node.transform.translation.y =  4 - (row + 0.5);
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
        hoveredCoord = coord(cast(u8) normalizedCoord.x, cast(u8) normalizedCoord.y);
    } else {
        hoveredCoord = 0xFF;
    }

    if hoveredCoord != 0xFF {
        Magma.material_set(mesh.nodes[hoveredCoord].primitives[0].material, "hovered", true);
    }
}

_toggle_hovered_square_highlight :: (using board : *BoardEntity) {
    squareHighlight : SquareHighlight;
    squareHighlight.coord = hoveredCoord;
    squareHighlight.color = highlight_color();
    position_toggle_highlight(*instance.game.ply.position, squareHighlight);
}
