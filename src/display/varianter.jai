Varianter :: struct {
    ui : struct {
        position : Chamber.vec2;
        extent : Chamber.vec2;
    };

    selectedNode : *Variant.Node;

    decorumShader : *Magma.Shader;
    textShader : *Magma.Shader;

    LINE_HEIGHT :: 22.0;
    HORIZONTAL_PADDING :: 50.0;
    VERTICAL_PADDING :: 50.0;
    SPLIT_PADDING :: 20.0;
}

VarianterNodeData :: struct {
    fullMoveMesh : *Magma.Mesh;
    commentMesh : *Magma.Mesh;
    decorumMesh : *Magma.Mesh;
}

varianter_init :: () {
    using *instance.varianter;

    ui.position.x = 0 + HORIZONTAL_PADDING;
    ui.position.y = -450 + VERTICAL_PADDING;
    ui.extent.width = 800 - 2 * HORIZONTAL_PADDING; // @todo Un-hardcode that
    ui.extent.height = 900 - 2 * VERTICAL_PADDING;

    decorumShader = Magma.create_shader(instance.engine.renderer, "./assets/materials/monochrome");
    textShader = Magma.create_shader(instance.engine.renderer, "./assets/materials/text", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });
}

varianter_show :: (game : Game) {
    using *instance.varianter;
    varianter_show_variant(*game.mainVariant, ui.position, ui.extent.width);
}

varianter_show_variant :: (variant : *Variant, startPosition : Chamber.vec2, width : float, depth : u8 = 0) -> float {
    using *instance.varianter;

    position := startPosition;
    splitWidth := (width - SPLIT_PADDING) / 2;
    offsetToBlack := (width + SPLIT_PADDING) / 2;

    lastSplitHeight : float;

    for nodeIndex : 0..variant.nodes.count-1 {
        node := *variant.nodes[nodeIndex];

        isWhiteMove := (node.position.moveIndex % 2 != 0);
        splitHeight : float;
        flushSplitHeight := !isWhiteMove || node.variants.count != 0;

        if nodeIndex == 0 {
            commentHeight, mesh := _make_text_mesh(node.comment, position, *instance.fonts.light, width);
            if commentHeight == 0.0 then continue;
            node.commentMesh = mesh;
            position.y += commentHeight;
            if depth == 0 then position.y += LINE_HEIGHT;
            continue;
        }

        commentLocation := _detect_comment_location(variant, nodeIndex, isWhiteMove);

        // Pre-flushing before a non-aligned full.
        if commentLocation == .SidedFull || commentLocation == .Full {
            position.y += lastSplitHeight;
            lastSplitHeight = 0;
        }

        // @note Full move number, always aligned in the player column.
        {
            font := ifx depth == 0 then *instance.fonts.bold else *instance.fonts.light;

            commentPosition := position;
            if !isWhiteMove then commentPosition.x += offsetToBlack;
            fullMoveIndex := (node.position.moveIndex + 1) / 2;
            fullMoveText := Basic.tprint("%.% %", fullMoveIndex, ifx node.position.moveIndex % 2 then "" else ".. ", position_last_move_to_san(node.position));
            fullMoveHeight, mesh := _make_text_mesh(fullMoveText, commentPosition, font, splitWidth);
            splitHeight = fullMoveHeight;
            node.fullMoveMesh = mesh;
        }

        if commentLocation == .Half {
            commentPosition := position;
            commentPosition.y += LINE_HEIGHT;
            if !isWhiteMove then commentPosition.x += offsetToBlack;

            commentHeight, mesh := _make_text_mesh(node.comment, commentPosition, *instance.fonts.light, splitWidth);
            node.commentMesh = mesh;
            splitHeight += commentHeight;
            if depth == 0 then splitHeight += LINE_HEIGHT;
        } else if commentLocation == .SidedFull || commentLocation == .SidedFullAligned ||
                  commentLocation == .Full || commentLocation == .FullAligned {
            commentPosition := position;
            commentPosition.y += LINE_HEIGHT;

            flushSplitHeight = true;
            isSided := commentLocation == .SidedFull || commentLocation == .SidedFullAligned;
            startingOffsetX := ifx isSided && !isWhiteMove then offsetToBlack else 0.0;
            commentHeight, mesh := _make_text_mesh(node.comment, commentPosition, *instance.fonts.light, width, startingOffsetX);
            node.commentMesh = mesh;
            splitHeight += commentHeight;
            if depth == 0 then splitHeight += LINE_HEIGHT;
        } else if commentLocation == .Inline {
            commentPosition := position;
            commentPosition.x += Math.floor(splitWidth / 4);
            if !isWhiteMove then commentPosition.x += offsetToBlack;
            commentHeight, mesh := _make_text_mesh(Basic.tprint("(%)", node.comment), commentPosition, *instance.fonts.light, 10000);
            node.commentMesh = mesh;
        }

        if flushSplitHeight {
            position.y += Basic.max(lastSplitHeight, splitHeight);
            lastSplitHeight = 0;
        } else {
            lastSplitHeight = splitHeight;
        }

        // Other variants.
        for *variant : node.variants {
            VARIANT_DECORUM_OFFSET :: 20.0;
            VARIANT_PADDING :: 40.0;

            variantPosition := position;
            variantPosition.x += VARIANT_PADDING;
            variantHeight := varianter_show_variant(variant, variantPosition, width - VARIANT_PADDING, depth + 1);

            variantPosition.x -= VARIANT_DECORUM_OFFSET;
            variant.nodes[0].decorumMesh = _make_decorum_mesh(variantPosition, 4.0, variantHeight - LINE_HEIGHT / 5);

            position.y += variantHeight;
            if depth == 0 then position.y += LINE_HEIGHT;
        }
    }

    // Final flush to get effective height.
    position.y += lastSplitHeight;
    return position.y - startPosition.y;
}

varianter_update_to_current_move :: (game : *Game) {
    using *instance.varianter;

    variant := game_current_variant(game);

    if selectedNode != null && selectedNode.fullMoveMesh != null {
        Magma.material_set(selectedNode.fullMoveMesh.material, "color", instance.config.moves.mainColor);
    }
    if selectedNode != null && selectedNode.commentMesh != null {
        Magma.material_set(selectedNode.commentMesh.material, "color", instance.config.moves.mainColor);
    }
    if selectedNode != null && selectedNode.decorumMesh != null {
        Magma.material_set(selectedNode.decorumMesh.material, "color", instance.config.moves.mainColor);
    }

    selectedNode = *variant.nodes[game.nodeIndex];

    startY := 0.0;
    if selectedNode.fullMoveMesh != null {
        startY = selectedNode.fullMoveMesh.translation.y;
        Magma.material_set(selectedNode.fullMoveMesh.material, "color", instance.config.moves.selectedColor);
    }
    if selectedNode.commentMesh != null {
        if startY == 0.0 then startY = selectedNode.commentMesh.translation.y;
        Magma.material_set(selectedNode.commentMesh.material, "color", instance.config.moves.selectedCommentColor);
    }
    if selectedNode.decorumMesh != null {
        if startY == 0.0 then startY = selectedNode.decorumMesh.translation.y;
        Magma.material_set(selectedNode.decorumMesh.material, "color", instance.config.moves.selectedColor);
    }

    // Scroll to be sure that the selected node is visible.
    _scroll(ui.position.y - startY);
}

varianter_handle_input_event :: (event : Crater.Event) {
    using instance.board;

    // @fixme INTRODUCE PARENTED ENTITIES IN SILL!!!!
    // This would make the whole thing a lot easier to update the positions,
    // and also allow to handle the input events in the correct order.

    if event.kind == .MouseWheelScrolled {
        _scroll(25.0 * event.mouseWheel.dy);
    }
}

#scope_file

CommentLocation :: enum {
    None :: 0;
    Inline;
    Half;
    SidedFull;
    SidedFullAligned;
    Full;
    FullAligned;
}

_detect_comment_location :: (variant : *Variant, nodeIndex : s64, isWhiteMove : bool) -> CommentLocation {
    node := variant.nodes[nodeIndex];
    commentLocation := _detect_comment_location(node.comment);

    // Promotion of white half comment to full if next black is expected to be full.
    if commentLocation == .Half && isWhiteMove && nodeIndex + 1 < variant.nodes.count &&
       _detect_comment_location(variant.nodes[nodeIndex + 1].comment) == .SidedFull {
        commentLocation = .SidedFull;
    }
    // Promotion of white half comment to full if there are any variants.
    else if commentLocation == .Half && isWhiteMove && node.variants.count > 0 {
        commentLocation = .SidedFull;
    }
    // Align a black full comment when the white before was None or Inline.
    // So that we don't flush and the Black's full move info on the same line.
    else if commentLocation == .SidedFull && !isWhiteMove && nodeIndex > 0 &&
       (_detect_comment_location(variant.nodes[nodeIndex - 1].comment) == .None ||
        _detect_comment_location(variant.nodes[nodeIndex - 1].comment) == .Inline) {
        commentLocation = .SidedFullAligned;
    }

    // Promote a sided half or full to a non-sided full if it is the last move.
    if (commentLocation == .Half || commentLocation == .SidedFull) && nodeIndex == variant.nodes.count - 1 {
        if !isWhiteMove && nodeIndex > 0 &&
           (_detect_comment_location(variant.nodes[nodeIndex - 1].comment) == .None ||
            _detect_comment_location(variant.nodes[nodeIndex - 1].comment) == .Inline) {
            commentLocation = .FullAligned;
        } else {
            commentLocation = .Full;
        }
    }

    return commentLocation;
}

_detect_comment_location :: (comment : string) -> CommentLocation {
    // @todo Completely arbitrary, but gives good enough results.
    if comment.count == 0 then return .None;
    if comment.count <= 30 then return .Inline;
    if comment.count <= 150 then return .Half;
    return .SidedFull;
}

_scroll :: (delta : float) {
    _scroll(delta, *instance.game.mainVariant);
}

_scroll :: (delta : float, variant : *Variant) {
    // Translate all meshes by the delta amount.
    for *node : variant.nodes {
        if node.fullMoveMesh != null {
            node.fullMoveMesh.translation.y += delta;
            Magma.mesh_commit_instance(node.fullMoveMesh);
        }
        if node.commentMesh != null {
            node.commentMesh.translation.y += delta;
            Magma.mesh_commit_instance(node.commentMesh);
        }
        if node.decorumMesh != null {
            node.decorumMesh.translation.y += delta;
            Magma.mesh_commit_instance(node.decorumMesh);
        }

        for *variant : node.variants {
            _scroll(delta, variant);
        }
    }
}

_make_text_mesh :: (text : string, position: Chamber.vec2, font : *Chamber.Font, maxWidth : float, startingOffsetX := 0.0) -> (float, *Magma.Mesh) {
    using instance.varianter;

    if text.count == 0 then return 0.0, null;

    // @todo Have a clever way to keep the texture up-to-date.
    // And not recreate it each time...
    glyphInfos := Chamber.font_glyph_infos(font, text); // @todo Get them without the blanks characters.
    fontTexture := Magma.create_texture(instance.engine.renderEngine);
    Magma.texture_load_from_memory(fontTexture, font.pixels, font.extent);

    mesh := Magma.create_mesh(instance.engine.scene);
    mesh.material = Magma.create_material(textShader);
    mesh.translation.xy = position;
    mesh.translation.z = -0.1;
    Magma.material_set(mesh.material, "fontTexture", fontTexture);
    Magma.material_set(mesh.material, "color", instance.config.moves.mainColor);

    currentWidth := 0.0;
    offset : Chamber.vec2;
    offset.x = startingOffsetX;

    // @todo Is baking all that into one texture worth it?
    Basic.array_resize(*mesh.vertices, 4 * glyphInfos.count);
    Basic.array_resize(*mesh.indices, 6 * glyphInfos.count);

    // @todo Have a placement algorithm that manages all words positions.
    // And getting a stream of words instead of glyphs would make it easier.
    for *glyphInfo, glyphIndex : glyphInfos {
        currentWidth = offset.x + glyphInfo.offset.x + glyphInfo.extent.width;
        if currentWidth > maxWidth {
            // Moving the whole word down to the next line.
            i := glyphIndex;
            while i >= 0 && !glyphInfos[i].blank {
                mesh.vertices[4 * i + 0].position.y += LINE_HEIGHT;
                mesh.vertices[4 * i + 1].position.y += LINE_HEIGHT;
                mesh.vertices[4 * i + 2].position.y += LINE_HEIGHT;
                mesh.vertices[4 * i + 3].position.y += LINE_HEIGHT;
                i -= 1;
            }

            // Justify the whole line.
            j := i - 1;
            blankCount := 0;
            while j >= 0 && mesh.vertices[4 * j].position.x < mesh.vertices[4 * (j + 1)].position.x {
                if glyphInfos[j].blank then blankCount += 1;
                j -= 1;
            }

            j = i - 1;
            extraSpacePerBlank := (maxWidth - mesh.vertices[4 * j + 2].position.x) / blankCount;
            while j >= 0 && mesh.vertices[4 * j].position.x < mesh.vertices[4 * (j + 1)].position.x {
                mesh.vertices[4 * j + 0].position.x += Math.floor(blankCount * extraSpacePerBlank + 0.5);
                mesh.vertices[4 * j + 1].position.x += Math.floor(blankCount * extraSpacePerBlank + 0.5);
                mesh.vertices[4 * j + 2].position.x += Math.floor(blankCount * extraSpacePerBlank + 0.5);
                mesh.vertices[4 * j + 3].position.x += Math.floor(blankCount * extraSpacePerBlank + 0.5);
                if glyphInfos[j].blank then blankCount -= 1;
                j -= 1;
            }

            i += 1; // Do return to line on a blank at first.
            offset.x = -glyphInfos[i].offset.x;
            while i <= glyphIndex {
                mesh.vertices[4 * i + 0].position.x = offset.x + glyphInfos[i].offset.x;
                mesh.vertices[4 * i + 1].position.x = offset.x + glyphInfos[i].offset.x;
                mesh.vertices[4 * i + 2].position.x = offset.x + glyphInfos[i].offset.x + glyphInfos[i].extent.width;
                mesh.vertices[4 * i + 3].position.x = offset.x + glyphInfos[i].offset.x + glyphInfos[i].extent.width;
                i += 1;
            }

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

_make_decorum_mesh :: (position : Chamber.vec2, width : float, height : float) -> *Magma.Mesh {
    mesh := Magma.create_mesh(instance.engine.scene);

    Basic.array_resize(*mesh.vertices, 4);
    Basic.array_resize(*mesh.indices, 6);

    mesh.vertices[0].position.x = 0.0;
    mesh.vertices[0].position.y = 0.0;
    mesh.vertices[1].position.x = 0.0;
    mesh.vertices[1].position.y = height;
    mesh.vertices[2].position.x = width;
    mesh.vertices[2].position.y = height;
    mesh.vertices[3].position.x = width;
    mesh.vertices[3].position.y = 0.0;

    mesh.indices[0] = 0;
    mesh.indices[1] = 1;
    mesh.indices[2] = 2;
    mesh.indices[3] = 2;
    mesh.indices[4] = 3;
    mesh.indices[5] = 0;

    mesh.material = Magma.create_material(instance.varianter.decorumShader);
    Magma.material_set(mesh.material, "color", instance.config.moves.mainColor);

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);

    mesh.translation.xy = position;
    Magma.mesh_commit_instance(mesh);

    return mesh;
}
