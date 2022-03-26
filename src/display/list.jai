List :: struct {
    ui : struct {
        position : Chamber.vec2;
        extent : Chamber.vec2;
    };

    selectedNode : *Variation.Node;

    decorumShader : *Magma.Shader;
    textShader : *Magma.Shader;

    cursorMesh : *Magma.Mesh;

    LINE_HEIGHT :: 22.0;
    HORIZONTAL_PADDING :: 50.0;
    VERTICAL_PADDING :: 50.0;
    SPLIT_PADDING :: 20.0;

    VARIATION_PADDING :: 40.0;
    VARIATION_DECORUM_WIDTH :: 3.0;
}

ListNodeData :: struct {
    moveColor : Chamber.vec3;

    plyEntity : *PlyEntity;
}

PlyEntity :: struct {
    using entity : Sill.Entity;
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    charInfos : []CharInfo;
    cursorPosition : u32; // Stored in bytes, not codepoints.
    startingOffsetX : float;
    commentLocation : CommentLocation;

    // Below are just references to the corresponding primitive mesh within the component,
    // for easier use.
    moveMeshNode : *Sill.MeshNode;
    commentMeshNode : *Sill.MeshNode;
    decorumMeshNode : *Sill.MeshNode; // Might be null.
}

list_init :: () {
    using *instance.list;

    ui.position.x = 0 + HORIZONTAL_PADDING;
    ui.position.y = -450 + VERTICAL_PADDING;
    ui.extent.width = 800 - 2 * HORIZONTAL_PADDING; // @todo Un-hardcode that
    ui.extent.height = 900 - 2 * VERTICAL_PADDING;

    decorumShader = Magma.create_shader(instance.engine.renderer, "./assets/materials/monochrome");
    textShader = Magma.create_shader(instance.engine.renderer, "./assets/materials/text", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });

    cursorMesh = _make_square_mesh();
    cursorMesh.scaling = .{1, LINE_HEIGHT, 1};
    cursorMesh.material = Magma.create_material(decorumShader);
    Magma.material_set(cursorMesh.material, "color", Chamber.vec3.{1, 1, 1});
}

list_show :: (game : Game) {
    using *instance.list;
    list_show_variation(*game.mainVariation, ui.extent.width);
    _rebuild_decorums(*game.mainVariation);
}

list_show_variation :: (variation : *Variation, width : float, depth : u8 = 0) {
    using *instance.list;

    splitWidth := (width - SPLIT_PADDING) / 2;
    offsetToBlack := (width + SPLIT_PADDING) / 2;
    fullStyleWidth := width * instance.config.moves.comments.fullStyleWidth;
    fullStyleOffsetToBlack := Math.floor(width - fullStyleWidth + 0.5);

    lastSplitHeight : float;

    for nodeIndex : 0..variation.nodes.count-1 {
        node := variation.nodes[nodeIndex];
        node.moveColor = annotation_color(node.position.lastMove.annotation);

        node.plyEntity = SillMeta.create_ply_entity(instance.engine);
        _init_ply_entity(node, width);
        _place_ply_entity(node);

        // Other variations.
        for variation : node.variations {
            list_show_variation(variation, width - VARIATION_PADDING, depth + 1);
        }
    }
}

list_update_to_current_move :: (game : *Game) {
    using *instance.list;

    if selectedNode != null {
        for *meshNode : selectedNode.plyEntity.mesh.nodes {
            Magma.material_set(meshNode.primitives[0].material, "color", selectedNode.moveColor);
        }
    }

    selectedNode = game.node;

    startY := -1.0;
    if selectedNode != null {
        for *meshNode : selectedNode.plyEntity.mesh.nodes {
            if startY == -1.0 || startY > meshNode.primitives[0].translation.y then startY = meshNode.primitives[0].translation.y;

            color := ifx meshNode == selectedNode.plyEntity.commentMeshNode then instance.config.moves.selectedCommentColor else instance.config.moves.selectedColor;
            Magma.material_set(meshNode.primitives[0].material, "color", color);
        }
    }

    // No mesh? It's the root node (others have a decorum or a full move mesh).
    if startY == -1.0 {
        startY = ui.position.y;
    }

    // Scroll to be sure that the selected node is visible.
    _scroll(ui.position.y - startY);
}

list_handle_input_event :: (event : Crater.Event) {
    using instance.board;

    // @fixme INTRODUCE PARENTED ENTITIES IN SILL!!!!
    // This would make the whole thing a lot easier to update the positions,
    // and also allow to handle the input events in the correct order.

    if event.kind == .MouseWheelScrolled {
        _scroll(25.0 * event.mouseWheel.dy);
    }
}

CommentStyle :: enum {
    None :: 0;
    Inline;
    Half;
    Full;
    SidedFull;
}

#scope_file

CommentLocation :: struct {
    color : Color;
    style : CommentStyle;
    preflushed : bool;
}

_detect_comment_location :: (node : *Variation.Node) -> CommentLocation {
    variation := node.parentVariation;

    commentLocation : CommentLocation;
    commentLocation.color = ifx node.position.moveIndex % 2 != 0 then Color.White else .Black;

    if node.index == 0 {
        // @fixme Intro comments before black ones should be more clever,
        // as if small enough, the following should not be preflushed.
        commentLocation.style = .Full;
        commentLocation.preflushed = true;
        return commentLocation;
    }

    commentLocation.style = _detect_comment_style(node.comment);
    nextCommentStyle := ifx node.index != variation.nodes.count - 1 then _detect_comment_style(variation.nodes[node.index + 1].comment) else .None;
    previousCommentStyle := ifx node.index != 0 then _detect_comment_style(variation.nodes[node.index - 1].comment) else .None;

    // Promotion of white half comment to a long style comment if next black is expected to be full.
    if commentLocation.style == .Half && commentLocation.color == .White &&
       (nextCommentStyle == .Full || nextCommentStyle == .SidedFull) {
        commentLocation.style = instance.config.moves.comments.longStyle;
    }
    // Promotion of white half comment to a long style comment if there are any variation.
    else if commentLocation.style == .Half && commentLocation.color == .White && node.variations.count > 0 {
        commentLocation.style = instance.config.moves.comments.longStyle;
    }

    // @todo Do that on option only?
    // Turn a Half or SidedFull to Full if it is the last move.
    if (/*commentLocation.style == .Half ||*/ commentLocation.style == .SidedFull) && node.index == variation.nodes.count - 1 {
        commentLocation.style = .Full;
    }

    // Always preflush if after a variation list or if at the start of a variation.
    if node.index != 0 && variation.nodes[node.index - 1].variations.count > 0 {
        commentLocation.preflushed = true;
    } else if commentLocation.color == .White || commentLocation.style == .Full || commentLocation.style == .SidedFull ||
              previousCommentStyle == .Full || previousCommentStyle == .SidedFull {
        commentLocation.preflushed = true;
        // Don't preflush a black comment when the white before was None or Inline.
        if commentLocation.color == .Black && commentLocation.style != .Full &&
           (previousCommentStyle == .None || previousCommentStyle == .Inline) {
            commentLocation.preflushed = false;
        }
    }

    return commentLocation;
}

_detect_comment_style :: (comment : string) -> CommentStyle {
    // @todo Completely arbitrary, but gives good enough results.
    if comment.count == 0 then return .None;
    if comment.count <= 30 then return instance.config.moves.comments.shortStyle;
    if comment.count <= 150 then return instance.config.moves.comments.normalStyle;
    return instance.config.moves.comments.longStyle;
}

_scroll :: (delta : float) {
    _scroll(delta, *instance.game.mainVariation);
}

_scroll :: (delta : float, variation : *Variation) {
    // Translate all meshes by the delta amount.
    for node : variation.nodes {
        node.plyEntity.transform.translation.y += delta;
        Sill.transform_commit(*node.plyEntity.transform);
        Sill.mesh_commit_nodes(*node.plyEntity.mesh, instantly = true);

        for variation : node.variations {
            _scroll(delta, variation);
        }
    }
}

_make_text_mesh :: () -> *Magma.Mesh {
    mesh := Magma.create_mesh(instance.engine.scene);
    mesh.material = Magma.create_material(instance.list.textShader);
    return mesh;
}

_make_text_mesh :: (text : string, position: Chamber.vec2, font : *Chamber.Font, color : Chamber.vec3, maxWidth : float, startingOffsetX := 0.0) -> (float, *Magma.Mesh) {
    mesh := _make_text_mesh();
    return _update_text_mesh(mesh, text, font, color, maxWidth, startingOffsetX), mesh;
}

Unicode :: #import "Unicode";

CharInfo :: struct { // @fixme Also store how many bytes it is worth.
    // Original glyph info, where the vertices should be
    // without special placement.
    glyphBlank : bool;
    glyphOffset : Chamber.vec2;
    glyphExtent : Chamber.vec2;
    glyphAdvance : float;

    effective : struct {
        glyphOffset : Chamber.vec2;
        xStart : float;
        xEnd : float;
        y : float;
    }
}

_update_text_mesh :: (mesh : *Magma.Mesh, text : string, font : *Chamber.Font, color : Chamber.vec3, maxWidth : float, startingOffsetX := 0.0) -> float, []CharInfo {
    using *instance.list;

    mesh.disabled = (text.count == 0);
    if mesh.disabled then return LINE_HEIGHT, .[];

    // @todo Have a clever way to keep the texture up-to-date.
    // And not recreate it each time...
    glyphInfos := Chamber.font_glyph_infos(font, text); // @todo Get them without the blanks characters.
    fontTexture := Magma.create_texture(instance.engine.renderEngine);
    Magma.texture_load_from_memory(fontTexture, font.pixels, font.extent);

    Magma.material_set(mesh.material, "fontTexture", fontTexture);
    Magma.material_set(mesh.material, "color", color);

    charInfos : [..]CharInfo;
    Basic.array_resize(*charInfos, glyphInfos.count);

    totalBlanks := 0;

    for *glyphInfo, index : glyphInfos {
        if glyphInfo.blank then totalBlanks += 1;
        charInfos[index].glyphBlank = glyphInfo.blank;
        charInfos[index].glyphOffset = glyphInfo.offset;
        charInfos[index].glyphExtent = glyphInfo.extent;
        charInfos[index].glyphAdvance = glyphInfo.advance;
    }

    // @todo Is baking all that into one texture worth it?
    Basic.array_resize(*mesh.vertices, 4 * (glyphInfos.count - totalBlanks));
    Basic.array_resize(*mesh.indices, 6 * (glyphInfos.count - totalBlanks));

    index := 0;
    for *glyphInfo : glyphInfos {
        if glyphInfo.blank then continue;

        mesh.vertices[4 * index + 0].position.x = glyphInfo.offset.x;
        mesh.vertices[4 * index + 0].position.y = glyphInfo.offset.y;
        mesh.vertices[4 * index + 1].position.x = glyphInfo.offset.x;
        mesh.vertices[4 * index + 1].position.y = glyphInfo.offset.y + glyphInfo.extent.height;
        mesh.vertices[4 * index + 2].position.x = glyphInfo.offset.x + glyphInfo.extent.width;
        mesh.vertices[4 * index + 2].position.y = glyphInfo.offset.y + glyphInfo.extent.height;
        mesh.vertices[4 * index + 3].position.x = glyphInfo.offset.x + glyphInfo.extent.width;
        mesh.vertices[4 * index + 3].position.y = glyphInfo.offset.y;
        mesh.vertices[4 * index + 0].uv.x = glyphInfo.minUv.x;
        mesh.vertices[4 * index + 0].uv.y = glyphInfo.minUv.y;
        mesh.vertices[4 * index + 1].uv.x = glyphInfo.minUv.x;
        mesh.vertices[4 * index + 1].uv.y = glyphInfo.maxUv.y;
        mesh.vertices[4 * index + 2].uv.x = glyphInfo.maxUv.x;
        mesh.vertices[4 * index + 2].uv.y = glyphInfo.maxUv.y;
        mesh.vertices[4 * index + 3].uv.x = glyphInfo.maxUv.x;
        mesh.vertices[4 * index + 3].uv.y = glyphInfo.minUv.y;

        mesh.indices[6 * index + 0] = cast(u16) (4 * index + 0);
        mesh.indices[6 * index + 1] = cast(u16) (4 * index + 1);
        mesh.indices[6 * index + 2] = cast(u16) (4 * index + 2);
        mesh.indices[6 * index + 3] = cast(u16) (4 * index + 2);
        mesh.indices[6 * index + 4] = cast(u16) (4 * index + 3);
        mesh.indices[6 * index + 5] = cast(u16) (4 * index + 0);

        index += 1;
    }

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);
    Magma.mesh_commit_instance(mesh);

    return /*offset.y +*/ LINE_HEIGHT, charInfos;
}

_init_ply_entity :: (node : *Variation.Node, width : float, startingOffsetX := 0.0) {
    node.plyEntity.startingOffsetX = startingOffsetX;
    node.plyEntity.ui.anchor = .TopLeft;
    node.plyEntity.ui.extent.width = width; // @fixme Also depends on other things, right?
    height : float;

    // ----- Move

    if node.index != 0 {
        Basic.array_add(*node.plyEntity.mesh.nodes, .{});
        Basic.array_add(*Basic.peek_pointer(node.plyEntity.mesh.nodes).primitives, _make_text_mesh());
        node.plyEntity.moveMeshNode = Basic.peek_pointer(node.plyEntity.mesh.nodes);

        // @fixme Used to be font bold/light based on variation depth.
        moveIndex := (node.position.moveIndex + 1) / 2;
        moveText := Basic.tprint("%.% %", moveIndex, ifx node.position.moveIndex % 2 then "" else ".. ", position_last_move_to_san(node.position, annotations = true));
        _update_text_mesh(node.plyEntity.moveMeshNode.primitives[0], moveText, *instance.fonts.bold, node.moveColor, width);
    } else if (node.parentVariation.parentNode != null) {
        Basic.array_add(*node.plyEntity.mesh.nodes, .{});
        Basic.array_add(*Basic.peek_pointer(node.plyEntity.mesh.nodes).primitives, _make_decorum_mesh(List.VARIATION_DECORUM_WIDTH));
        node.plyEntity.decorumMeshNode = Basic.peek_pointer(node.plyEntity.mesh.nodes);
        node.plyEntity.decorumMeshNode.transform.translation.x -= List.VARIATION_PADDING / 2.0;
    }

    // ----- Comment

    Basic.array_add(*node.plyEntity.mesh.nodes, .{});
    Basic.array_add(*Basic.peek_pointer(node.plyEntity.mesh.nodes).primitives, _make_text_mesh());
    node.plyEntity.commentMeshNode = Basic.peek_pointer(node.plyEntity.mesh.nodes);

    commentHeight, charInfos := _update_text_mesh(node.plyEntity.commentMeshNode.primitives[0], node.comment, *instance.fonts.light, instance.config.moves.mainColor, width, startingOffsetX);
    node.plyEntity.charInfos = charInfos;

    Sill.ui_on_trigger(*node.plyEntity.ui, xx (flags : Sill.UiComponent.CallbackFlags, event : Crater.Event, stopPropagation : *bool, node : *Variation.Node) {
        Sill.ui_set_focused(*node.plyEntity.ui);
        game_update_to(*instance.game, node);
        _update_cursor(node);

        // @fixme On Unfocused, hide cursor.
    }, .Click, node);

    Sill.ui_on_trigger(*node.plyEntity.ui, xx (flags : Sill.UiComponent.CallbackFlags, event : Crater.Event, stopPropagation : *bool, node : *Variation.Node) {
        textChanged := false;
        <<stopPropagation = true;

        if event.kind == .TextEntered {
            Chamber.insert_after_byte(*node.comment, node.plyEntity.cursorPosition, event.text.str);
            node.plyEntity.cursorPosition += cast(u32) event.text.str.count;
            textChanged = true;
        } else if event.kind == .KeyPressed {
            if event.key.which == .Delete {
                deletedBytes := Chamber.delete_after_byte(*node.comment, node.plyEntity.cursorPosition);
                if deletedBytes == 0 then return;
                textChanged = true;
            } else if event.key.which == .Backspace {
                deletedBytes := Chamber.delete_before_byte(*node.comment, node.plyEntity.cursorPosition);
                if deletedBytes == 0 then return;
                node.plyEntity.cursorPosition -= deletedBytes;
                textChanged = true;
            } else if event.key.which == .Left {
                if node.plyEntity.cursorPosition == 0 then return;
                node.plyEntity.cursorPosition -= Chamber.utf8_word_length_before_byte(node.comment, node.plyEntity.cursorPosition);
            } else if event.key.which == .Right {
                if node.plyEntity.cursorPosition == node.comment.count then return;
                node.plyEntity.cursorPosition += Chamber.utf8_word_length_after_byte(node.comment, node.plyEntity.cursorPosition);
            } else {
                return;
            }
        }

        // @todo Do a clever diff instead of regenerating everything?
        if textChanged then {
            _, charInfos := _update_text_mesh(node.plyEntity.commentMeshNode.primitives[0], node.comment, *instance.fonts.light, instance.config.moves.mainColor, node.plyEntity.ui.extent.width, node.plyEntity.startingOffsetX);
            node.plyEntity.charInfos = charInfos;
            _place_ply_entity(node, propagate = true);
        }

        _update_cursor(node);
    }, Sill.UiComponent.CallbackFlags.Text | .Key, node);
}

// Will modify the effective positions of the charInfos to justify the text
// according to the provided maxWidth.
_justify_char_infos :: (charInfos : []CharInfo, maxWidth : float, startingOffsetX : float) -> float {
    if charInfos.count == 0 then return 0.0;

    offset : Chamber.vec2;
    offset.x = startingOffsetX;

    for *charInfo, index : charInfos {
        charInfo.effective.glyphOffset.std = charInfo.glyphOffset + offset;
        charInfo.effective.y = offset.y;
        currentWidth := charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;

        if currentWidth > maxWidth {
            // Moving the whole word down to the next line.
            i := index;
            while i >= 0 && !charInfos[i].glyphBlank {
                charInfos[i].effective.glyphOffset.y += List.LINE_HEIGHT;
                charInfos[i].effective.y += List.LINE_HEIGHT;
                i -= 1;
            }

            // @fixme crash if not blank...
            if i == -1 {
                return List.LINE_HEIGHT;
            }

            // Justify the whole line.
            j := i;
            blankCount := 0;
            while j >= 0 && charInfos[j].glyphBlank { j -= 1; } // Ignore ending blanks.
            while j >= 0 && charInfos[j].effective.y == charInfos[j + 1].effective.y {
                if charInfos[j].glyphBlank then blankCount += 1;
                j -= 1;
            }

            j = i;
            extraSpacePerBlank := (maxWidth - (offset.x + charInfos[j].glyphOffset.x + charInfos[j].glyphExtent.width)) / blankCount;
            while j >= 0 && charInfos[j].glyphBlank {
                charInfos[j].effective.glyphOffset.x += Math.floor(blankCount * extraSpacePerBlank + 0.5);
                j -= 1;
            }
            while j >= 0 && charInfos[j].effective.y == charInfos[j + 1].effective.y {
                charInfos[j].effective.glyphOffset.x += Math.floor(blankCount * extraSpacePerBlank + 0.5);
                if charInfos[j].glyphBlank then blankCount -= 1;
                j -= 1;
            }

            // Leave the ending blank character to the line above.
            if charInfos[i].glyphBlank {
                i += 1;
            }

            offset.x = -charInfos[i].glyphOffset.x;
            offset.y += List.LINE_HEIGHT;

            preOffset := -charInfos[i].effective.glyphOffset.x;
            while i <= index {
                charInfos[i].effective.glyphOffset.x += preOffset;
                i += 1;
            }
        }
    }

    for *charInfo : charInfos {
        charInfo.effective.xStart = charInfo.effective.glyphOffset.x;
        charInfo.effective.xEnd = charInfo.effective.glyphOffset.x + charInfo.glyphAdvance;
    }

    return offset.y + List.LINE_HEIGHT;
}

_place_comment_from_char_infos :: (node : *Variation.Node) {
    mesh := node.plyEntity.commentMeshNode.primitives[0];

    if node.plyEntity.charInfos.count == 0 {
        mesh.disabled = true;
        return;
    }

    mesh.disabled = false;
    index := 0;
    for *charInfo : node.plyEntity.charInfos {
        if charInfo.glyphBlank then continue;

        mesh.vertices[4 * index + 0].position.x = charInfo.effective.glyphOffset.x;
        mesh.vertices[4 * index + 0].position.y = charInfo.effective.glyphOffset.y;
        mesh.vertices[4 * index + 1].position.x = charInfo.effective.glyphOffset.x;
        mesh.vertices[4 * index + 1].position.y = charInfo.effective.glyphOffset.y + charInfo.glyphExtent.height;
        mesh.vertices[4 * index + 2].position.x = charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;
        mesh.vertices[4 * index + 2].position.y = charInfo.effective.glyphOffset.y + charInfo.glyphExtent.height;
        mesh.vertices[4 * index + 3].position.x = charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;
        mesh.vertices[4 * index + 3].position.y = charInfo.effective.glyphOffset.y;

        index += 1;
    }

    Magma.mesh_commit_vertices(mesh);
}

// The ply entity mesh position (0,0) means the top left of the move text.
// Which means that the comment mesh node might be offseted to the left
// for black moves.
_place_ply_entity :: (node : *Variation.Node, propagate := false) {
    maxWidth := node.plyEntity.ui.extent.width;
    variationOffset := (instance.list.ui.extent.width - maxWidth);
    offsetToBlack := (maxWidth + List.SPLIT_PADDING) / 2;

    // Detect the comment location, and re-structure it as needed.
    commentLocation := _detect_comment_location(node);
    node.plyEntity.commentLocation = commentLocation;

    commentWidth := maxWidth;
    if commentLocation.style == .Half {
        commentWidth = (maxWidth - List.SPLIT_PADDING) / 2;
    } else if commentLocation.style == .SidedFull {
        commentWidth = maxWidth * instance.config.moves.comments.fullStyleWidth;
    }

    // Make the text fit the specified size
    commentHeight := _justify_char_infos(node.plyEntity.charInfos, commentWidth, 0.0);
    _place_comment_from_char_infos(node);

    node.plyEntity.commentMeshNode.transform.translation = .{};
    if node.index != 0 {
        if commentLocation.style != .Inline {
            node.plyEntity.commentMeshNode.transform.translation.y = List.LINE_HEIGHT;
            node.plyEntity.ui.extent.height = List.LINE_HEIGHT + commentHeight;
        } else {
            node.plyEntity.commentMeshNode.transform.translation.x += Math.floor(maxWidth / 8.0 + 0.5);
            node.plyEntity.commentMeshNode.transform.translation.y = 0.0;
            node.plyEntity.ui.extent.height = List.LINE_HEIGHT;
        }

        if commentLocation.color == .Black &&
           (commentLocation.style == .SidedFull || commentLocation.style == .Full) {
            node.plyEntity.commentMeshNode.transform.translation.x = (maxWidth - commentWidth - offsetToBlack);
        }
    } else {
        node.plyEntity.ui.extent.height = commentHeight;
    }

    // Position the entity based on the above comment and the comment location.
    // position := instance.list.ui.position;
    position : Chamber.vec2;
    position.x = 50; // @fixme
    position.x += variationOffset;

    aboveNode : *Variation.Node;
    if node.index > 0 {
        if commentLocation.color == .Black then position.x += offsetToBlack;

        // The above ply entity is either the previous node,
        // or the last node of its last variant.
        aboveNode = node.parentVariation.nodes[node.index - 1];
        while aboveNode.variations.count != 0 {
            aboveNode = Basic.peek(Basic.peek(aboveNode.variations).nodes);
        }

    } else {
        aboveNode = node.parentVariation.parentNode;
        if aboveNode != null && node.parentVariation.index > 0 {
            aboveNode = Basic.peek(aboveNode.variations[node.parentVariation.index - 1].nodes);
            while aboveNode.variations.count != 0 {
                aboveNode = Basic.peek(Basic.peek(aboveNode.variations).nodes);
            }
        }
    }


    if aboveNode != null {
        abovePlyEntity := aboveNode.plyEntity;
        position.y = abovePlyEntity.transform.translation.y;
        if commentLocation.preflushed {
            // We want to preflush but if the previous one is a half black,
            // we need to take the max between this one and the corresponding half white.
            height := abovePlyEntity.ui.extent.height;
            if abovePlyEntity.commentLocation.color == .Black && !abovePlyEntity.commentLocation.preflushed {
                correspondingAbovePlyEntity := aboveNode.parentVariation.nodes[aboveNode.index - 1].plyEntity;
                height = Basic.max(height, correspondingAbovePlyEntity.ui.extent.height);
            }
            position.y += height;
        }
    }

    node.plyEntity.transform.translation.xy = position;
    Sill.transform_commit(*node.plyEntity.transform);

    // If propagate, we replace also all downstream nodes.
    // @todo Do that only on commentLocation or height change?
    if propagate {
        _place_ply_entities(node.parentVariation, node.index);
        _rebuild_decorums(*instance.game.mainVariation);
    }
}

_place_ply_entities :: (variation : *Variation, nodeIndex : u16, upstream := true) {
    // Downstream
    for i : nodeIndex .. variation.nodes.count - 1 {
        node := variation.nodes[i];
        _place_ply_entity(node);

        for subVariation : node.variations {
            _place_ply_entities(subVariation, 0, false);
        }
    }

    // Upstream
    if upstream && variation.parentNode != null {
        // Same-level variations.
        for i : variation.index + 1 .. variation.parentNode.variations.count {
            _place_ply_entities(variation.parentNode.variations[variation.index + 1], 0, false);
        }

        _place_ply_entities(variation.parentNode.parentVariation, variation.parentNode.index + 1);
    }
}

_rebuild_decorums :: (variation : *Variation) {
    for node : variation.nodes {
        for subVariation : node.variations {
            firstNode := subVariation.nodes[0];
            lastNode := Basic.peek(subVariation.nodes);

            position := firstNode.plyEntity.transform.translation;
            height := lastNode.plyEntity.transform.translation.y + lastNode.plyEntity.ui.extent.height - position.y;
            _update_decorum_mesh(firstNode.plyEntity.decorumMeshNode.primitives[0], height);

            _rebuild_decorums(subVariation);
        }
    }
}

_update_cursor :: (node : *Variation.Node) {
    commentMesh := node.plyEntity.commentMeshNode.primitives[0];

    // @note We always update the cursor, because when the text changed and not the cursor position,
    // the justification of the line might slightly move the cursor itself.
    instance.list.cursorMesh.translation.xy = commentMesh.translation.xy;
    if node.plyEntity.cursorPosition == 0 {
        if node.plyEntity.charInfos.count != 0 {
            instance.list.cursorMesh.translation.x += node.plyEntity.charInfos[0].effective.xStart;
            instance.list.cursorMesh.translation.y += node.plyEntity.charInfos[0].effective.y + instance.list.LINE_HEIGHT / 2;
        }
        Magma.mesh_commit_instance(instance.list.cursorMesh);
    } else {
        byteIndex : u32;
        for i : 0..node.plyEntity.charInfos.count-1 {
            byteIndex += Chamber.utf8_word_length_after_byte(node.comment, byteIndex);

            if node.plyEntity.cursorPosition <= byteIndex {
                instance.list.cursorMesh.translation.x += node.plyEntity.charInfos[i].effective.xEnd;
                instance.list.cursorMesh.translation.y += node.plyEntity.charInfos[i].effective.y + instance.list.LINE_HEIGHT / 2;
                Magma.mesh_commit_instance(instance.list.cursorMesh);
                break;
            }
        }
    }
}

_make_decorum_mesh :: (width : float) -> *Magma.Mesh {
    mesh := Magma.create_mesh(instance.engine.scene);

    Basic.array_resize(*mesh.vertices, 4);
    Basic.array_resize(*mesh.indices, 6);

    mesh.vertices[0].position.x = 0.0;
    mesh.vertices[0].position.y = 0.0;
    mesh.vertices[1].position.x = 0.0;
    mesh.vertices[1].position.y = 1.0; // Will be height
    mesh.vertices[2].position.x = width;
    mesh.vertices[2].position.y = 1.0 ;// Will be height
    mesh.vertices[3].position.x = width;
    mesh.vertices[3].position.y = 0.0;

    mesh.indices[0] = 0;
    mesh.indices[1] = 1;
    mesh.indices[2] = 2;
    mesh.indices[3] = 2;
    mesh.indices[4] = 3;
    mesh.indices[5] = 0;

    mesh.material = Magma.create_material(instance.list.decorumShader);
    Magma.material_set(mesh.material, "color", instance.config.moves.mainColor);

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);

    return mesh;
}

_update_decorum_mesh :: (mesh : *Magma.Mesh, height : float) {
    DECORUM_VERTICAL_PADDING := 3.0;

    mesh.vertices[0].position.y = DECORUM_VERTICAL_PADDING;
    mesh.vertices[1].position.y = height - DECORUM_VERTICAL_PADDING;
    mesh.vertices[2].position.y = height - DECORUM_VERTICAL_PADDING;
    mesh.vertices[3].position.y = DECORUM_VERTICAL_PADDING;

    Magma.mesh_commit_vertices(mesh);
}
