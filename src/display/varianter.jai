Varianter :: struct {
    meshInfos : [..]struct {
        fullMoveMesh : *Magma.Mesh;
        commentMesh : *Magma.Mesh;
    };

    ui : struct {
        position : Chamber.vec2;
        extent : Chamber.vec2;
    };

    selectedNodeIndex := 0xFFFF_FFFF;

    textShader : *Magma.Shader;

    LINE_HEIGHT :: 25.0;
    HORIZONTAL_PADDING :: 50.0;
    VERTICAL_PADDING :: 50.0;
    SPLIT_PADDING :: 20.0;
}

varianter_init :: () {
    using *instance.varianter;


    ui.position.x = 0 + HORIZONTAL_PADDING;
    ui.position.y = -450 + VERTICAL_PADDING;
    ui.extent.width = 800 - 2 * HORIZONTAL_PADDING; // @todo Un-hardcode that
    ui.extent.height = 900 - 2 * VERTICAL_PADDING;

    textShader = Magma.create_shader(instance.renderer, "./assets/materials/text", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });
}

varianter_show :: (game : Game) {
    using *instance.varianter;

    variant := *game.mainVariant;

    splitWidth := (ui.extent.width - SPLIT_PADDING) / 2;
    offsetToBlack := (ui.extent.width + SPLIT_PADDING) / 2;

    position := ui.position;
    lastSplitHeight : float;

    for nodeIndex : 0..variant.nodes.count-1 {
        node := *variant.nodes[nodeIndex];

        Basic.array_add(*meshInfos, .{});
        meshInfo := Basic.peek_pointer(meshInfos);

        isWhiteMove := (node.position.moveIndex % 2 != 0);
        splitHeight : float;
        flushSplitHeight := !isWhiteMove;

        if nodeIndex == 0 {
            commentHeight, mesh := _make_text_mesh(node.comment, position, *instance.fonts.light, ui.extent.width);
            meshInfo.commentMesh = mesh;
            position.y += commentHeight + LINE_HEIGHT;
            continue;
        }

        commentLocation := _detect_comment_location(variant, nodeIndex, isWhiteMove);
        if commentLocation == .Full {
            // Flushing
            position.y += lastSplitHeight;
            lastSplitHeight = 0;
        }

        // @note Full move number, always aligned in the player column.
        {
            commentPosition := position;
            if !isWhiteMove then commentPosition.x += offsetToBlack;
            fullMoveIndex := (node.position.moveIndex + 1) / 2;
            fullMoveText := Basic.tprint("%.% %", fullMoveIndex, ifx node.position.moveIndex % 2 then "" else ".. ", position_last_move_to_san(node.position));
            fullMoveHeight, mesh := _make_text_mesh(fullMoveText, commentPosition, *instance.fonts.bold, splitWidth);
            splitHeight = fullMoveHeight;
            meshInfo.fullMoveMesh = mesh;
        }

        if commentLocation == .Half {
            commentPosition := position;
            commentPosition.y += LINE_HEIGHT;
            if !isWhiteMove then commentPosition.x += offsetToBlack;

            commentHeight, mesh := _make_text_mesh(node.comment, commentPosition, *instance.fonts.light, splitWidth);
            meshInfo.commentMesh = mesh;
            splitHeight += commentHeight + LINE_HEIGHT;
        } else if commentLocation == .Full {
            commentPosition := position;
            commentPosition.y += LINE_HEIGHT;

            flushSplitHeight = true;
            startingOffsetX := ifx isWhiteMove then 0.0 else offsetToBlack;
            commentHeight, mesh := _make_text_mesh(node.comment, commentPosition, *instance.fonts.light, ui.extent.width, startingOffsetX);
            meshInfo.commentMesh = mesh;
            splitHeight += commentHeight + LINE_HEIGHT;
        } else if commentLocation == .Inline {
            commentPosition := position;
            commentPosition.x += Math.floor(splitWidth / 4);
            if !isWhiteMove then commentPosition.x += offsetToBlack;
            commentHeight, mesh := _make_text_mesh(Basic.tprint("(%)", node.comment), commentPosition, *instance.fonts.light, 10000);
            meshInfo.commentMesh = mesh;
        }

        if flushSplitHeight {
            position.y += Basic.max(lastSplitHeight, splitHeight);
            lastSplitHeight = 0;
        } else {
            lastSplitHeight = splitHeight;
        }

        // @todo Display multiple variants.
        // for variant : node.variants {
        // }
    }
}

varianter_update_to_current_move :: (game : *Game) {
    using *instance.varianter;

    if game.variantIndices.count != 0 then return; // @todo Not handled yet
    if game.nodeIndex == selectedNodeIndex then return;

    if selectedNodeIndex != 0xFFFF_FFFF && meshInfos[selectedNodeIndex].fullMoveMesh != null {
        Magma.material_set(meshInfos[selectedNodeIndex].fullMoveMesh.material, "color", Chamber.vec3.{1, 1, 1});
    }
    if selectedNodeIndex != 0xFFFF_FFFF && meshInfos[selectedNodeIndex].commentMesh != null {
        Magma.material_set(meshInfos[selectedNodeIndex].commentMesh.material, "color", Chamber.vec3.{1, 1, 1});
    }

    selectedNodeIndex = game.nodeIndex;

    if meshInfos[selectedNodeIndex].fullMoveMesh != null {
        Magma.material_set(meshInfos[selectedNodeIndex].fullMoveMesh.material, "color", Chamber.vec3.{1, 0.7, 0.3});
    }
    if meshInfos[selectedNodeIndex].commentMesh != null {
        Magma.material_set(meshInfos[selectedNodeIndex].commentMesh.material, "color", Chamber.vec3.{1, 0.9, 0.7});
    }
}

#scope_file

CommentLocation :: enum {
    None :: 0;
    Inline;
    Half;
    Full;
}

_detect_comment_location :: (variant : *Variant, nodeIndex : s64, isWhiteMove : bool) -> CommentLocation {
    node := variant.nodes[nodeIndex];
    commentLocation := _detect_comment_location(node.comment);

    // Promotion of half comment to full if
    if commentLocation == .Half && isWhiteMove && nodeIndex + 1 < variant.nodes.count &&
       _detect_comment_location(variant.nodes[nodeIndex + 1].comment) == .Full {
        commentLocation = .Full;
    }

    return commentLocation;
}

_detect_comment_location :: (comment : string) -> CommentLocation {
    // @todo Completely arbitrary, but gives good enough results.
    if comment.count == 0 then return .None;
    if comment.count <= 25 then return .Inline;
    if comment.count <= 150 then return .Half;
    return .Full;
}

_make_text_mesh :: (text : string, position: Chamber.vec2, font : *Chamber.Font, maxWidth : float, startingOffsetX := 0.0) -> (float, *Magma.Mesh) {
    using instance.varianter;

    if text.count == 0 then return 0.0, null;

    // @todo Have a clever way to keep the texture up-to-date.
    // And not recreate it each time...
    glyphInfos := Chamber.font_glyph_infos(font, text); // @todo Get them without the blanks characters.
    fontTexture := Magma.create_texture(instance.renderEngine);
    Magma.texture_load_from_memory(fontTexture, font.pixels, font.extent);

    mesh := Magma.create_mesh(instance.renderScene);
    mesh.material = Magma.create_material(textShader);
    mesh.translation.xy = position;
    mesh.translation.z = -0.1;
    Magma.material_set(mesh.material, "fontTexture", fontTexture);
    Magma.material_set(mesh.material, "color", Chamber.vec3.{1, 1, 1});

    currentWidth := 0.0;
    offset : Chamber.vec2;
    offset.x = startingOffsetX;

    // @todo Is baking all that into one texture worth it?
    Basic.array_resize(*mesh.vertices, 4 * glyphInfos.count);
    Basic.array_resize(*mesh.indices, 6 * glyphInfos.count);
    for *glyphInfo, glyphIndex : glyphInfos {
        // @todo Split at word, not a letter, of course...
        currentWidth = offset.x + glyphInfo.offset.x + glyphInfo.extent.width;
        if currentWidth > maxWidth {
            offset.x = -glyphInfo.offset.x;
            offset.y += LINE_HEIGHT;
        }

        mesh.vertices[4 * glyphIndex + 0].position.x = offset.x + glyphInfo.offset.x;
        mesh.vertices[4 * glyphIndex + 0].position.y = offset.y + glyphInfo.offset.y;
        mesh.vertices[4 * glyphIndex + 1].position.x = offset.x + glyphInfo.offset.x;
        mesh.vertices[4 * glyphIndex + 1].position.y = offset.y + glyphInfo.offset.y + glyphInfo.extent.height;
        mesh.vertices[4 * glyphIndex + 2].position.x = offset.x + glyphInfo.offset.x + glyphInfo.extent.width;
        mesh.vertices[4 * glyphIndex + 2].position.y = offset.y + glyphInfo.offset.y + glyphInfo.extent.height;
        mesh.vertices[4 * glyphIndex + 3].position.x = offset.x + glyphInfo.offset.x + glyphInfo.extent.width;
        mesh.vertices[4 * glyphIndex + 3].position.y = offset.y + glyphInfo.offset.y;
        mesh.vertices[4 * glyphIndex + 0].uv.x = glyphInfo.minUv.x;
        mesh.vertices[4 * glyphIndex + 0].uv.y = glyphInfo.minUv.y;
        mesh.vertices[4 * glyphIndex + 1].uv.x = glyphInfo.minUv.x;
        mesh.vertices[4 * glyphIndex + 1].uv.y = glyphInfo.maxUv.y;
        mesh.vertices[4 * glyphIndex + 2].uv.x = glyphInfo.maxUv.x;
        mesh.vertices[4 * glyphIndex + 2].uv.y = glyphInfo.maxUv.y;
        mesh.vertices[4 * glyphIndex + 3].uv.x = glyphInfo.maxUv.x;
        mesh.vertices[4 * glyphIndex + 3].uv.y = glyphInfo.minUv.y;

        mesh.indices[6 * glyphIndex + 0] = cast(u16) (4 * glyphIndex + 0);
        mesh.indices[6 * glyphIndex + 1] = cast(u16) (4 * glyphIndex + 1);
        mesh.indices[6 * glyphIndex + 2] = cast(u16) (4 * glyphIndex + 2);
        mesh.indices[6 * glyphIndex + 3] = cast(u16) (4 * glyphIndex + 2);
        mesh.indices[6 * glyphIndex + 4] = cast(u16) (4 * glyphIndex + 3);
        mesh.indices[6 * glyphIndex + 5] = cast(u16) (4 * glyphIndex + 0);
    }

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);
    Magma.mesh_commit_instance(mesh);

    return offset.y + LINE_HEIGHT, mesh;
}
