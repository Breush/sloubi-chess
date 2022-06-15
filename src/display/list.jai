ListNodeData :: struct {
    plyEntity : *PlyEntity;
}

ListEntity :: struct {
    using entity : Sill.Entity;
    transform : Sill.TransformComponent;
    ui : Sill.UiComponent;

    scroll : ScrollEntity; // @note Not a pointer, no need to allocate it on the heap.
    cursorMesh : *Magma.Mesh;
}

ScrollEntity :: struct {
    using entity : Sill.Entity;
    transform : Sill.TransformComponent;
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
    depth : u8;

    // Below are just references to the corresponding primitive mesh within the component,
    // for easier use.
    moveMeshNode : *Sill.MeshNode;
    commentMeshNode : *Sill.MeshNode;
    decorumMeshNode : *Sill.MeshNode; // Might be null.

    moveColor : Chamber.vec3;
    moveTextWidth : float;

    on_cleanup :: (using this : *PlyEntity) {
        Basic.array_free(charInfos);
    }
}

list_init :: () {
    instance.list = SillMeta.create_list_entity(instance.engine);
    list := instance.list;

    SillMeta.entity_init(*list.scroll, instance.engine);
    Sill.entity_add_child(list, *list.scroll);

    list.cursorMesh = create_rect_mesh(1, UiConstants.HeightLine);
    list.cursorMesh.material = Magma.create_material(instance.shaders.monochrome);
    list.cursorMesh.disabled = true;
    Magma.material_set(list.cursorMesh.material, "color", Chamber.vec3.{1, 1, 1});

    list_reflow();
}

list_reflow :: () {
    list := instance.list;

    extent := Crater.window_get_extent(instance.engine.window);

    list.transform.translation.x = UiConstants.PaddingHorizontal;
    list.transform.translation.y = - cast(s32) extent.height / 2 + UiConstants.PaddingVertical;

    // @fixme What this sums up is that having the center at (0,0) is a bad idea because it can be half a pixel.
    if (extent.width / 2) % 2 == 1 {
        list.transform.translation.x += 0.5;
    }
    if (extent.height / 2) % 2 == 1 {
        list.transform.translation.y += 0.5;
    }

    list.ui.extent.width = extent.width / 2 - 2 * UiConstants.PaddingHorizontal;
    list.ui.extent.height = extent.height - 2 * UiConstants.PaddingVertical;
    list.ui.anchor = .TopLeft;

    Sill.transform_commit(*list.transform);

    if instance.game.mainVariation.nodes.count > 0 {
        _place_ply_entity(instance.game.mainVariation.nodes[0], propagate = true);
    }
}

list_reset_ui :: (node : *Variation.Node) {
    Sill.destroy_entity(node.plyEntity);
}

list_show :: (game : Game) {
    list_show_variation(*game.mainVariation);
    _rebuild_decorums(*game.mainVariation);
}

list_show_variation :: (variation : *Variation, depth : u8 = 0) {
    list := instance.list;

    for nodeIndex : 0..variation.nodes.count-1 {
        node := variation.nodes[nodeIndex];

        if node.plyEntity != null then Sill.destroy_entity(node.plyEntity);
        node.plyEntity = SillMeta.create_ply_entity(instance.engine);
        node.plyEntity.moveColor = annotation_color(node.position.lastMove.annotation);
        node.plyEntity.depth = depth;

        Sill.entity_set_parent(node.plyEntity, *list.scroll);
        _init_ply_entity(node);
        _place_ply_entity(node, propagate = false);

        for variation : node.variations {
            list_show_variation(variation, depth + 1);
        }
    }
}

list_update_to_current_move :: (game : *Game, oldNode : *Variation.Node) {
    list := instance.list;

    if oldNode != null {
        for *meshNode : oldNode.plyEntity.mesh.nodes {
            Magma.material_set(meshNode.primitives[0].material, "color", oldNode.plyEntity.moveColor);
        }
    }

    startY := 0.0;
    if game.node != null {
        startY = game.node.plyEntity.transform.translation.y;

        for *meshNode : game.node.plyEntity.mesh.nodes {
            color := ifx meshNode == game.node.plyEntity.commentMeshNode then instance.config.moves.selectedCommentColor
                                                                         else instance.config.moves.selectedColor;
            Magma.material_set(meshNode.primitives[0].material, "color", color);
        }
    }

    // @fixme Clever scrolling (i.e. don't if it's visible).
    list_scroll(-list.scroll.transform.translation.y - startY);
}

list_scroll :: (scrollDelta : float) {
    list := instance.list;
    list.scroll.transform.translation.y += Math.floor(scrollDelta);
    Sill.transform_commit(*list.scroll.transform);
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
    spaced : bool; // The preflushed comment should be spaced from the previous one.
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
        commentLocation.spaced = (node.parentVariation.depth == 1);
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
        commentLocation.spaced = (node.parentVariation.depth == 0);
    } else if commentLocation.color == .White || commentLocation.style == .Full || commentLocation.style == .SidedFull ||
              previousCommentStyle == .Full || previousCommentStyle == .SidedFull {
        commentLocation.preflushed = true;

        // Don't preflush a black comment when the white before was None or Inline.
        if commentLocation.color == .Black && commentLocation.style != .Full &&
           (previousCommentStyle == .None || previousCommentStyle == .Inline) {
            commentLocation.preflushed = false;
        }

        if commentLocation.preflushed && node.parentVariation.depth == 0  {
            if _is_style_spaced_after(previousCommentStyle) {
                commentLocation.spaced = true;
            } else if commentLocation.color == .White && node.index >= 2 && variation.nodes[node.index - 2].variations.count == 0 {
                previousPreviousCommentStyle := _detect_comment_style(variation.nodes[node.index - 2].comment);
                commentLocation.spaced = _is_style_spaced_after(previousPreviousCommentStyle);
            }
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

_is_style_spaced_after :: (commentStyle : CommentStyle) -> bool {
    return commentStyle == .Half || commentStyle == .SidedFull || commentStyle == .Full;
}

_init_ply_entity :: (node : *Variation.Node) {
    height : float;

    // ----- Move

    if node.index != 0 {
        Basic.array_add(*node.plyEntity.mesh.nodes, .{});
        Basic.array_add(*Basic.peek_pointer(node.plyEntity.mesh.nodes).primitives, create_text_mesh());
        node.plyEntity.moveMeshNode = Basic.peek_pointer(node.plyEntity.mesh.nodes);

        // @fixme Used to be font bold/light based on variation depth.
        moveIndex := (node.position.moveIndex + 1) / 2;
        moveText := Basic.tprint("%.% %", moveIndex, ifx node.position.moveIndex % 2 then "" else ".. ", position_last_move_to_san(node.position, annotations = true));
        charInfos := text_mesh_update(node.plyEntity.moveMeshNode.primitives[0], moveText, *instance.fonts.bold, node.plyEntity.moveColor);
        node.plyEntity.moveTextWidth = Basic.peek(charInfos).effective.xEnd;
        Basic.array_free(charInfos);
    } else if (node.parentVariation.parentNode != null) {
        Basic.array_add(*node.plyEntity.mesh.nodes, .{});
        Basic.array_add(*Basic.peek_pointer(node.plyEntity.mesh.nodes).primitives, _make_decorum_mesh(UiConstants.WidthDecorumVariation));
        node.plyEntity.decorumMeshNode = Basic.peek_pointer(node.plyEntity.mesh.nodes);
        node.plyEntity.decorumMeshNode.transform.translation.x -= UiConstants.PaddingHorizontalVariation / 2.0;
    }

    // ----- Comment

    Basic.array_add(*node.plyEntity.mesh.nodes, .{});
    Basic.array_add(*Basic.peek_pointer(node.plyEntity.mesh.nodes).primitives, create_text_mesh());
    node.plyEntity.commentMeshNode = Basic.peek_pointer(node.plyEntity.mesh.nodes);
    node.plyEntity.charInfos = text_mesh_update(node.plyEntity.commentMeshNode.primitives[0], node.comment, *instance.fonts.light, instance.config.moves.mainColor);

    Sill.ui_on_trigger(*node.plyEntity.ui, (trigger : Sill.UiTrigger, node : *Variation.Node) {
        // @fixme It "works" because the black comment is always created after the white one.
        // But we should check the charInfos I guess. (And have better BB.)
        <<trigger.stopPropagation = true;
        instance.list.cursorMesh.disabled = cast(bool) (trigger.flags & .NoFocus);

        if trigger.flags & .Click {
            Sill.ui_set_focused(*node.plyEntity.ui);
            game_update_to(*instance.game, node);
            _update_cursor(node);
        }
    }, Sill.UiCallbackFlags.Click | .NoFocus, node);

    Sill.ui_on_trigger(*node.plyEntity.ui, (trigger : Sill.UiTrigger, node : *Variation.Node) {
        textChanged := false;
        <<trigger.stopPropagation = true;

        if trigger.event.kind == .TextEntered {
            Chamber.insert_after_byte(*node.comment, node.plyEntity.cursorPosition, trigger.event.text.str);
            node.plyEntity.cursorPosition += cast(u32) trigger.event.text.str.count;
            textChanged = true;
        } else if trigger.event.kind == .KeyPressed {
            if trigger.event.key.which == .Delete {
                deletedBytes := Chamber.delete_after_byte(*node.comment, node.plyEntity.cursorPosition);
                if deletedBytes == 0 then return;
                textChanged = true;
            } else if trigger.event.key.which == .Backspace {
                deletedBytes := Chamber.delete_before_byte(*node.comment, node.plyEntity.cursorPosition);
                if deletedBytes == 0 then return;
                node.plyEntity.cursorPosition -= deletedBytes;
                textChanged = true;
            } else if trigger.event.key.which == .Left {
                if node.plyEntity.cursorPosition == 0 then return;
                node.plyEntity.cursorPosition -= Chamber.utf8_word_length_before_byte(node.comment, node.plyEntity.cursorPosition);
            } else if trigger.event.key.which == .Right {
                if node.plyEntity.cursorPosition == node.comment.count then return;
                node.plyEntity.cursorPosition += Chamber.utf8_word_length_after_byte(node.comment, node.plyEntity.cursorPosition);
            } else {
                return;
            }
        }

        // @todo Do a clever diff instead of regenerating everything?
        if textChanged then {
            Basic.array_free(node.plyEntity.charInfos);
            node.plyEntity.charInfos = text_mesh_update(node.plyEntity.commentMeshNode.primitives[0], node.comment, *instance.fonts.light, instance.config.moves.mainColor);
            _place_ply_entity(node, propagate = true);
        }

        _update_cursor(node);
    }, Sill.UiCallbackFlags.Text | .Key, node);
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

    variationOffset := node.plyEntity.depth * UiConstants.PaddingHorizontalVariation;
    maxWidth := instance.list.ui.extent.width - variationOffset;
    offsetToBlack := (maxWidth + UiConstants.PaddingHorizontalSplit) / 2;

    node.plyEntity.ui.anchor = .TopLeft;
    node.plyEntity.ui.extent.width = maxWidth;

    // Detect the comment location, and re-structure it as needed.
    commentLocation := _detect_comment_location(node);
    node.plyEntity.commentLocation = commentLocation;

    commentWidth := maxWidth;
    if commentLocation.style == .Half {
        commentWidth = (maxWidth - UiConstants.PaddingHorizontalSplit) / 2;
    } else if commentLocation.style == .SidedFull {
        commentWidth = maxWidth * instance.config.moves.comments.fullStyleWidth;
    } else if commentLocation.style == .Inline {
        commentWidth = maxWidth / 2.0 - node.plyEntity.moveTextWidth - UiConstants.PaddingCommentInline;
    }

    // Make the text fit the specified size
    commentHeight := justify_char_infos(node.plyEntity.charInfos, commentWidth, 0.0);
    _place_comment_from_char_infos(node);

    node.plyEntity.commentMeshNode.transform.translation = .{};
    if node.index != 0 {
        if commentLocation.style != .Inline {
            node.plyEntity.commentMeshNode.transform.translation.y = UiConstants.HeightLine;
            node.plyEntity.ui.extent.height = UiConstants.HeightLine + commentHeight;
        } else {
            node.plyEntity.commentMeshNode.transform.translation.x += node.plyEntity.moveTextWidth + UiConstants.PaddingCommentInline;
            node.plyEntity.commentMeshNode.transform.translation.y = 0.0;
            node.plyEntity.ui.extent.height = Basic.max(UiConstants.HeightLine, commentHeight);
        }

        if commentLocation.color == .Black &&
           (commentLocation.style == .SidedFull || commentLocation.style == .Full) {
            node.plyEntity.commentMeshNode.transform.translation.x = (maxWidth - commentWidth - offsetToBlack);
        }
    } else {
        node.plyEntity.ui.extent.height = commentHeight;
    }

    // Position the entity based on the above comment and the comment location.
    position : Chamber.vec2;
    position.x = variationOffset;

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
        position.y += abovePlyEntity.transform.translation.y;
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

    if commentLocation.spaced {
        position.y += 20;
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
        for i : variation.index + 1 .. variation.parentNode.variations.count - 1 {
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

            while lastNode.variations.count != 0 {
                lastNode = Basic.peek(Basic.peek(lastNode.variations).nodes);
            }

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
            instance.list.cursorMesh.translation.y += node.plyEntity.charInfos[0].effective.y + UiConstants.HeightLine / 2;
        }
        Magma.mesh_commit_instance(instance.list.cursorMesh);
    } else {
        byteIndex : u32;
        for i : 0..node.plyEntity.charInfos.count-1 {
            byteIndex += Chamber.utf8_word_length_after_byte(node.comment, byteIndex);

            if node.plyEntity.cursorPosition <= byteIndex {
                instance.list.cursorMesh.translation.x += node.plyEntity.charInfos[i].effective.xEnd;
                instance.list.cursorMesh.translation.y += node.plyEntity.charInfos[i].effective.y + UiConstants.HeightLine / 2;
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

    mesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set(mesh.material, "color", instance.config.moves.mainColor);

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);

    return mesh;
}

_update_decorum_mesh :: (mesh : *Magma.Mesh, height : float) {
    DECORUM_VERTICAL_PADDING := 2.0;

    mesh.vertices[0].position.y = DECORUM_VERTICAL_PADDING;
    mesh.vertices[1].position.y = height - DECORUM_VERTICAL_PADDING;
    mesh.vertices[2].position.y = height - DECORUM_VERTICAL_PADDING;
    mesh.vertices[3].position.y = DECORUM_VERTICAL_PADDING;

    Magma.mesh_commit_vertices(mesh);
}
