Board :: struct {
    center : Chamber.vec2; // @todo :UiInStill Will become a transform2d component
    size : float;

    eye : *Magma.Eye;
    squares : [8][8]BoardSquare;

    squareShader : *Magma.Shader;
    squareSize : float;

    piecesTextures : [PieceIdCount]*Magma.Texture;

    // @fixme :UiInSill Make UI part of Sill.
    hoveredSquare : *BoardSquare;
}

BoardSquare :: struct {
    mesh : *Magma.Mesh;
}

init_board :: () {
    using instance.board;

    _init_resources();
    _init_camera(); // @todo :UiInSill Should probably part of Sill.

    size = cast(float) Basic.min(eye.extent.width, eye.extent.height);
    center.x = cast(float) eye.extent.width / 2;
    center.y = cast(float) eye.extent.height / 2;
    squareSize = size / 8;

    _init_meshes();

    // Drawing a position
    position := get_starting_position();
    update_board_to_position(position);
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
            hoveredSquare = *squares[cast(int) normalizedPosition.x][cast(int) normalizedPosition.y];
        } else {
            hoveredSquare = null;
        }

        if hoveredSquare != null {
            Magma.material_set(hoveredSquare.mesh.material, "hovered", true);
        }
    }
}

update_board_to_position :: (position : Position) {
    using instance.board;

    for row : 0..7 {
        for col : 0..7 {
            square := *squares[row][col];

            pieceId := get_piece_id(position.squares[row][col].piece);
            pieceTexture := piecesTextures[pieceId];
            Magma.material_set(square.mesh.material, "pieceTexture", pieceTexture);
        }
    }
}

#scope_file

whiteSquareColor :: Chamber.vec3.{0.933, 0.933, 0.824};
blackSquareColor :: Chamber.vec3.{0.462, 0.588, 0.337};

_init_resources :: () {
    using instance.board;

    squareShader = Magma.create_shader(instance.renderer, "./assets/materials/square");

    init_piece_texture :: (pieceId : PieceId, filename : string) {
        piecesTextures[pieceId] = Magma.create_texture(instance.renderEngine);
        Magma.texture_load_from_file(piecesTextures[pieceId], filename);
    }

    init_piece_texture(get_piece_id(.{ .B, .White }), "./assets/images/pieces/merida-wb.png");
    init_piece_texture(get_piece_id(.{ .K, .White }), "./assets/images/pieces/merida-wk.png");
    init_piece_texture(get_piece_id(.{ .N, .White }), "./assets/images/pieces/merida-wn.png");
    init_piece_texture(get_piece_id(.{ .P, .White }), "./assets/images/pieces/merida-wp.png");
    init_piece_texture(get_piece_id(.{ .Q, .White }), "./assets/images/pieces/merida-wq.png");
    init_piece_texture(get_piece_id(.{ .R, .White }), "./assets/images/pieces/merida-wr.png");
    init_piece_texture(get_piece_id(.{ .B, .Black }), "./assets/images/pieces/merida-bb.png");
    init_piece_texture(get_piece_id(.{ .K, .Black }), "./assets/images/pieces/merida-bk.png");
    init_piece_texture(get_piece_id(.{ .N, .Black }), "./assets/images/pieces/merida-bn.png");
    init_piece_texture(get_piece_id(.{ .P, .Black }), "./assets/images/pieces/merida-bp.png");
    init_piece_texture(get_piece_id(.{ .Q, .Black }), "./assets/images/pieces/merida-bq.png");
    init_piece_texture(get_piece_id(.{ .R, .Black }), "./assets/images/pieces/merida-br.png");

    // Use a transparent texture for emptiness.
    // @fixme This could be done "automatically" by Magma when the texture is set to "null".
    emptyPieceId := get_piece_id(.{ kind = .Empty });
    piecesTextures[emptyPieceId] = Magma.create_texture(instance.renderEngine);
    Magma.texture_load_from_memory(piecesTextures[emptyPieceId], .[0, 0, 0, 0], .{1, 1});
}

_init_camera :: () {
    using instance.board;

    eye = Magma.renderer_get_eye(instance.renderer, 0);

    extent : Chamber.vec2;
    extent.width = cast(float) eye.extent.width;
    extent.height = cast(float) eye.extent.height;

    eye.extent = Magma.renderer_get_extent(instance.renderer, 0);
    eye.viewMatrix = Chamber.look_at_matrix(.{0, 0, -1}, .{0, 0, 0}, .{0, -1, 0});
    Chamber.infinite_orthographic_projection(*eye.projectionMatrix, .{0, 0}, extent, 0.01); // Orthographic camera with 1 pixel = 1 unit
    Magma.eye_commit(eye);
}

_init_meshes :: () {
    using instance.board;

    for row : 0..7 {
    for col : 0..7 {
        square := *squares[row][col];
        square.mesh = _make_square_mesh();
        square.mesh.translation.x = -size / 2 + (col + 0.5) * squareSize;
        square.mesh.translation.y =  size / 2 - (row + 0.5) * squareSize;
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
