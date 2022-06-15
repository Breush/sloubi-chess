BoardEntity :: struct {
    using entity : Sill.Entity;

    ui : Sill.UiComponent;
    mesh : Sill.MeshComponent;
    transform : Sill.TransformComponent;

    squareShader : *Magma.Shader;
    piecesTextures : [PieceIdCount]*Magma.Texture;

    info : struct {
        whitePlayerName : *PlayerNameEntity;
        blackPlayerName : *PlayerNameEntity;
    };

    PLAYER_NAME_PADDING :: 2;

    orientation : Color;

    hoveredCoord : Coord = 0xFF;
}

PlayerNameEntity :: struct {
    using entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
}

board_init :: () {
    using instance.board;

    instance.board = SillMeta.create_board_entity(instance.engine);

    _init_resources();
    _init_meshes();
    board_reflow();

    Sill.ui_on_update(*ui, _on_update, userData = instance.board);

    // Drawing a position
    position := get_starting_position();
    board_update_to_position(position);
}

board_reflow :: () {
    using instance.board;

    // We want to fit the board in the left part of the screen nicely à 95% of the available space.
    eye := Magma.renderer_get_eye(engine.renderer, 0);
    size := 0.95 * Basic.min(eye.extent.width / 2.0, cast(float) eye.extent.height);
    ui.extent.width, ui.extent.height = size, size;

    transform.translation.x = -size / 2.0;
    transform.factor = size;
    Sill.transform_commit(*transform);

    _reflow_board_info();
}

board_orient :: (_orientation : Color) {
    using instance.board;

    orientation = _orientation;

    for coord : 0..CoordCount-1 {
        node := *mesh.nodes[coord + 1];
        row, col := row_col(cast(u8) coord);
        if orientation == .White {
            node.transform.translation.x = -4 + (col + 0.5);
            node.transform.translation.y =  4 - (row + 0.5);
        } else {
            node.transform.translation.x = -4 + (7 - col + 0.5);
            node.transform.translation.y =  4 - (7 - row + 0.5);
        }
    }

    Sill.mesh_commit_nodes(*mesh);
}

board_info_show :: (game : Game) {
    using instance.board;

    info.whitePlayerName.mesh.nodes[0].primitives[0].disabled = true;
    info.blackPlayerName.mesh.nodes[0].primitives[0].disabled = true;

    _set_name :: (playerNameEntity : *PlayerNameEntity, name : string) {
        playerNameEntity.mesh.nodes[0].primitives[0].disabled = false;
        charInfos := text_mesh_update(playerNameEntity.mesh.nodes[0].primitives[0], name, *instance.fonts.bold, instance.config.env.textColor);
        Basic.array_free(charInfos);

    }

    if game.tags.white != "" {
        name := ifx game.tags.whiteElo == 0 then game.tags.white
                                            else Basic.tprint("% (%)", game.tags.white, game.tags.whiteElo);
        _set_name(info.whitePlayerName, name);
    }

    if game.tags.black != "" {
        name := ifx game.tags.blackElo == 0 then game.tags.black
                                            else Basic.tprint("% (%)", game.tags.black, game.tags.blackElo);
        _set_name(info.blackPlayerName, name);
    }

    _reflow_board_info();
}

board_update_to_position :: (position : Position) {
    using instance.board;

    for coord : 0..CoordCount-1 {
        node := *mesh.nodes[coord + 1];
        pieceTexture := piecesTextures[piece_id(position.board[coord])];
        Magma.material_set(node.primitives[0].material, "pieceTexture", pieceTexture);
    }
}

#scope_file

_init_resources :: () {
    using instance.board;

    squareShader = Magma.create_shader(instance.engine.renderer, "./assets/materials/square");

    init_piece_texture :: (pieceId : PieceId, filename : string) {
        using instance.board;
        piecesTextures[pieceId] = Magma.create_texture(instance.engine.renderEngine);
        Magma.texture_load_from_file(piecesTextures[pieceId], filename);
    }

    init_piece_texture(piece_id(.{ .B, .White }), Basic.tprint("./assets/images/pieces/%-wb.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .K, .White }), Basic.tprint("./assets/images/pieces/%-wk.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .N, .White }), Basic.tprint("./assets/images/pieces/%-wn.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .P, .White }), Basic.tprint("./assets/images/pieces/%-wp.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .Q, .White }), Basic.tprint("./assets/images/pieces/%-wq.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .R, .White }), Basic.tprint("./assets/images/pieces/%-wr.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .B, .Black }), Basic.tprint("./assets/images/pieces/%-bb.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .K, .Black }), Basic.tprint("./assets/images/pieces/%-bk.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .N, .Black }), Basic.tprint("./assets/images/pieces/%-bn.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .P, .Black }), Basic.tprint("./assets/images/pieces/%-bp.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .Q, .Black }), Basic.tprint("./assets/images/pieces/%-bq.png", instance.config.board.pieces));
    init_piece_texture(piece_id(.{ .R, .Black }), Basic.tprint("./assets/images/pieces/%-br.png", instance.config.board.pieces));

    // Use a transparent texture for emptiness.
    // @fixme This could be done "automatically" by Magma when the texture is set to "null".
    emptyPieceId := piece_id(.{ kind = .Empty });
    piecesTextures[emptyPieceId] = Magma.create_texture(instance.engine.renderEngine);
    Magma.texture_load_from_memory(piecesTextures[emptyPieceId], .[0, 0, 0, 0], .{1, 1});
}

_init_meshes :: () {
    using instance.board;

    // @note We create the square meshes to be size 1,
    // but set the root node size to 1/8 so that the board is of size 1.
    Basic.array_add(*mesh.nodes, .{});
    mesh.nodes[0].transform.scaling = .{1.0 / 8.0, 1.0 / 8.0, 1.0};

    for coord : 0..CoordCount-1 {
        squareMesh := create_rect_mesh();
        squareMesh.material = Magma.create_material(squareShader);

        row, col := row_col(cast(u8) coord);
        color := ifx (row + col) % 2 then instance.config.board.lightSquareColor else instance.config.board.darkSquareColor;
        Magma.material_set(squareMesh.material, "color", color);

        Basic.array_add(*mesh.nodes[0].children, cast(s64) mesh.nodes.count);
        Basic.array_add(*mesh.nodes, .{});

        node := Basic.peek_pointer(mesh.nodes);
        node.parent = 0;
        Basic.array_add(*node.primitives, squareMesh);
    }

    // Will update the position of the squares
    board_orient(orientation);

    // @todo Make on_create functions (like on_destroy) that act like constructors?
    info.whitePlayerName = SillMeta.create_player_name_entity(instance.engine);
    Basic.array_add(*info.whitePlayerName.mesh.nodes, .{});
    Basic.array_add(*info.whitePlayerName.mesh.nodes[0].primitives, create_text_mesh());
    info.whitePlayerName.mesh.nodes[0].transform.translation.y -= instance.config.env.fontSize / 2;
    info.whitePlayerName.mesh.nodes[0].transform.translation.z = -0.2;

    info.blackPlayerName = SillMeta.create_player_name_entity(instance.engine);
    Basic.array_add(*info.blackPlayerName.mesh.nodes, .{});
    Basic.array_add(*info.blackPlayerName.mesh.nodes[0].primitives, create_text_mesh());
    info.blackPlayerName.mesh.nodes[0].transform.translation.y -= instance.config.env.fontSize / 2;
    info.blackPlayerName.mesh.nodes[0].transform.translation.z = 0.2;
}

_reflow_board_info :: () {
    using instance.board;

    info.whitePlayerName.transform.translation.x = -ui.extent.width;
    info.whitePlayerName.transform.translation.y = ui.extent.height / 2 + instance.config.env.fontSize / 2 + BoardEntity.PLAYER_NAME_PADDING;
    info.blackPlayerName.transform.translation.x = -ui.extent.width;
    info.blackPlayerName.transform.translation.y = -ui.extent.height / 2 - instance.config.env.fontSize / 2 - BoardEntity.PLAYER_NAME_PADDING;

    if orientation == .Black {
        info.whitePlayerName.transform.translation.y *= -1;
        info.blackPlayerName.transform.translation.y *= -1;
    }

    Sill.transform_commit(*info.whitePlayerName.transform);
    Sill.transform_commit(*info.blackPlayerName.transform);
}

_on_update :: (update : Sill.UiUpdate, using board : *BoardEntity) {
    normalizedCoord : Chamber.vec2;
    normalizedCoord.x = -8.0 * ui.relativeMousePointerPosition.y / ui.extent.width + 4.0;
    normalizedCoord.y =  8.0 * ui.relativeMousePointerPosition.x / ui.extent.width + 4.0;

    if orientation == .Black {
        normalizedCoord.x = 8 - normalizedCoord.x;
        normalizedCoord.y = 8 - normalizedCoord.y;
    }

    if hoveredCoord != 0xFF {
        Magma.material_set(mesh.nodes[hoveredCoord + 1].primitives[0].material, "hovered", false);
    }

    if normalizedCoord.x >= 0 && normalizedCoord.x < 8 && normalizedCoord.y >= 0 && normalizedCoord.y < 8 {
        hoveredCoord = coord(cast(u8) normalizedCoord.x, cast(u8) normalizedCoord.y);
    } else {
        hoveredCoord = 0xFF;
    }

    if hoveredCoord != 0xFF {
        Magma.material_set(mesh.nodes[hoveredCoord + 1].primitives[0].material, "hovered", true);
    }
}
