Board :: struct {
    center : Chamber.vec2; // @todo :UiInStill Will become a transform2d component
    size : float;

    eye : *Magma.Eye;
    squares : [CoordCount]BoardSquare;

    squareShader : *Magma.Shader;
    squareSize : float;

    piecesTextures : [PieceIdCount]*Magma.Texture;

    // @fixme :UiInSill Make UI part of Sill.
    hoveredSquare : *BoardSquare;
}

BoardSquare :: struct {
    mesh : *Magma.Mesh;
}

board_init :: () {
    using *instance.board;

    _init_resources();
    _init_camera(); // @todo :UiInSill Should probably part of Sill.

    // We want to fit the board in the left part of the screen nicely à 95% of the available space.
    size = 0.95 * Basic.min(eye.extent.width / 2.0, cast(float) eye.extent.height);
    center.x = -size / 2.0;
    center.y = 0;
    squareSize = size / 8;

    _init_meshes();

    // Drawing a position
    position := get_starting_position();
    board_update_to_position(position);
}

board_handle_input_event :: (event : Crater.Event) {
    using instance.board;

    if event.kind == .MousePointerMoved {
        normalizedPosition : Chamber.vec2;
        normalizedPosition.x = (cast(float) -event.mousePointer.y + center.y + size / 2) / squareSize;
        normalizedPosition.y = (cast(float)  event.mousePointer.x - center.x + size / 2) / squareSize;

        if hoveredSquare != null {
            Magma.material_set(hoveredSquare.mesh.material, "hovered", false);
        }

        if normalizedPosition.x >= 0 && normalizedPosition.x < 8 &&
           normalizedPosition.y >= 0 && normalizedPosition.y < 8 {
            hoveredSquare = *squares[coord(cast(u8) normalizedPosition.x, cast(u8) normalizedPosition.y)];
        } else {
            hoveredSquare = null;
        }

        if hoveredSquare != null {
            Magma.material_set(hoveredSquare.mesh.material, "hovered", true);
        }
    }

    // @todo It's game controller's job to do that.
    else if event.kind == .KeyPressed {
        if event.key.which == .Right then game_go_to_next_move(*instance.game);
        else if event.key.which == .Left then game_go_to_previous_move(*instance.game);
        else if event.key.which == .Down then game_go_to_next_variant(*instance.game);
        else if event.key.which == .Up then game_go_to_previous_variant(*instance.game);
    }
}

board_update_to_position :: (position : Position) {
    using instance.board;

    for *square, coord : squares {
        pieceTexture := piecesTextures[piece_id(position.board[coord])];
        Magma.material_set(square.mesh.material, "pieceTexture", pieceTexture);
    }
}

#scope_file

// White/green
// whiteSquareColor :: Chamber.vec3.{0.933, 0.933, 0.824};
// blackSquareColor :: Chamber.vec3.{0.462, 0.588, 0.337};
// White/orange
whiteSquareColor :: Chamber.vec3.{0.905, 0.911, 0.822};
blackSquareColor :: Chamber.vec3.{0.703, 0.573, 0.335};

_init_resources :: () {
    using *instance.board;

    squareShader = Magma.create_shader(instance.renderer, "./assets/materials/square");

    init_piece_texture :: (pieceId : PieceId, filename : string) {
        piecesTextures[pieceId] = Magma.create_texture(instance.renderEngine);
        Magma.texture_load_from_file(piecesTextures[pieceId], filename);
    }

    init_piece_texture(piece_id(.{ .B, .White }), "./assets/images/pieces/staunty-wb.png");
    init_piece_texture(piece_id(.{ .K, .White }), "./assets/images/pieces/staunty-wk.png");
    init_piece_texture(piece_id(.{ .N, .White }), "./assets/images/pieces/staunty-wn.png");
    init_piece_texture(piece_id(.{ .P, .White }), "./assets/images/pieces/staunty-wp.png");
    init_piece_texture(piece_id(.{ .Q, .White }), "./assets/images/pieces/staunty-wq.png");
    init_piece_texture(piece_id(.{ .R, .White }), "./assets/images/pieces/staunty-wr.png");
    init_piece_texture(piece_id(.{ .B, .Black }), "./assets/images/pieces/staunty-bb.png");
    init_piece_texture(piece_id(.{ .K, .Black }), "./assets/images/pieces/staunty-bk.png");
    init_piece_texture(piece_id(.{ .N, .Black }), "./assets/images/pieces/staunty-bn.png");
    init_piece_texture(piece_id(.{ .P, .Black }), "./assets/images/pieces/staunty-bp.png");
    init_piece_texture(piece_id(.{ .Q, .Black }), "./assets/images/pieces/staunty-bq.png");
    init_piece_texture(piece_id(.{ .R, .Black }), "./assets/images/pieces/staunty-br.png");

    // Use a transparent texture for emptiness.
    // @fixme This could be done "automatically" by Magma when the texture is set to "null".
    emptyPieceId := piece_id(.{ kind = .Empty });
    piecesTextures[emptyPieceId] = Magma.create_texture(instance.renderEngine);
    Magma.texture_load_from_memory(piecesTextures[emptyPieceId], .[0, 0, 0, 0], .{1, 1});
}

_init_camera :: () {
    using *instance.board;

    eye = Magma.renderer_get_eye(instance.renderer, 0);

    extent : Chamber.vec2;
    extent.width = cast(float) eye.extent.width;
    extent.height = cast(float) eye.extent.height;

    eye.extent = Magma.renderer_get_extent(instance.renderer, 0);
    eye.viewMatrix = Chamber.look_at_matrix(.{0, 0, -1}, .{0, 0, 0}, .{0, -1, 0});
    Chamber.unnear_orthographic_projection(*eye.projectionMatrix, extent, 100.0); // Orthographic camera with 1 pixel = 1 unit
    Magma.eye_commit(eye);
}

_init_meshes :: () {
    using *instance.board;

    for *square, coord : squares {
        row, col := row_col(cast(u8) coord);
        square.mesh = _make_square_mesh();
        square.mesh.translation.x = center.x - size / 2 + (col + 0.5) * squareSize;
        square.mesh.translation.y = center.y + size / 2 - (row + 0.5) * squareSize;
        square.mesh.scaling.x = squareSize;
        square.mesh.scaling.y = squareSize;
        Magma.mesh_commit_instance(square.mesh);

        square.mesh.material = Magma.create_material(squareShader);

        color : Chamber.vec3 = ---;
        if ((row + col) % 2) {
            color = whiteSquareColor;
        } else {
            color = blackSquareColor;
        }

        Magma.material_set(square.mesh.material, "color", color);
    }
}

_make_square_mesh :: () -> *Magma.Mesh {
    mesh := Magma.create_mesh(instance.renderScene);

    positions := Chamber.vec3.[
        .{-0.5, -0.5, 0. },
        .{-0.5,  0.5, 0. },
        .{ 0.5,  0.5, 0. },
        .{ 0.5, -0.5, 0. },
    ];

    normals := Chamber.vec3.[
        .{ 0.,  0., 1. },
        .{ 0.,  0., 1. },
        .{ 0.,  0., 1. },
        .{ 0.,  0., 1. },
    ];

    uvs := Chamber.vec2.[
        .{ 0.,  0. },
        .{ 0.,  1. },
        .{ 1.,  1. },
        .{ 1.,  0. },
    ];

    indices := u16.[0,  1,  2,  2,  3,  0];

    Basic.array_resize(*mesh.vertices, positions.count);
    for *vertex, i : mesh.vertices {
        vertex.position = positions[i];
        vertex.normal = normals[i];
        vertex.uv = uvs[i];
    }

    Basic.array_resize(*mesh.indices, indices.count);
    memcpy(mesh.indices.data, indices.data, size_of(u16) * indices.count);

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);

    return mesh;
}
