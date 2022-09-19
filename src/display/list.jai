ListEntity :: struct {
    using #as entity : Sill.Entity;
    transform : Sill.TransformComponent;
    ui : Sill.UiComponent;

    scroll : ScrollEntity; // @note Not a pointer, no need to allocate it on the heap.
    textCursor : TextCursorEntity;
}

PlyEntity :: struct {
    using #as entity : Sill.Entity;
    collider : Sill.ColliderComponent;
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    // -- Main properties
    position : Position;
    variations : [..]*Variation;
    parentVariation : *Variation;
    index : u16; // Index of the ply in the parent variation.

    // -- Display
    charInfos : []CharInfo;
    textCursorPosition : u32; // Stored in bytes, not codepoints.
    startingOffsetX : float;
    commentLocation : CommentLocation;
    depth : u8;

    decorum : *DecorumEntity; // Might be null.

    // Below are just references to the corresponding primitive mesh within the component,
    // for easier use.
    moveMeshNode : *Sill.MeshNode;
    commentMeshNode : *Sill.MeshNode;

    moveHovered : bool;
    moveColor : Chamber.vec3;
    moveTextWidth : float;

    on_cleanup :: (using this : *PlyEntity) {
        Basic.free(position.comment);
        Basic.array_free(charInfos);

        if decorum != null {
            Sill.destroy_entity(decorum);
        }
    }
}

DecorumEntity :: struct {
    using #as entity : Sill.Entity;
    transform : Sill.TransformComponent;
    ui : Sill.UiComponent;
    mesh : Sill.MeshComponent;
}

ScrollEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage
    transform : Sill.TransformComponent;
}

TextCursorEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
}

replace_ply_recursively :: (ply : *PlyEntity) {
    _place_ply(ply, propagate = true);
}

list_init :: () {
    instance.list = SillMeta.create_list_entity(instance.engine);
    list := instance.list;

    Sill.entity_add_child(list, *list.scroll);

    textCursorMesh := Sill.mesh_make_primitive(*list.textCursor.mesh);
    create_rect_mesh(1, UiConstants.HeightLine, existingMesh = textCursorMesh);
    textCursorMesh.material = Magma.create_material(instance.shaders.monochrome);
    Sill.entity_set_disabled(*list.textCursor, true);
    Magma.material_set(textCursorMesh.material, "color", Chamber.vec3.{1, 1, 1});

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

    if instance.game.mainVariation.plies.count > 0 {
        _place_ply(instance.game.mainVariation.plies[0], propagate = true);
    }
}

list_show :: (game : Game) {
    list_show_variation(*game.mainVariation);
    _rebuild_decorums(*game.mainVariation);
}

list_show_variation :: (variation : *Variation, firstOne := true) {
    for plyIndex : 0 .. variation.plies.count - 1 {
        ply := variation.plies[plyIndex];
        ply_init(ply, place = false);

        for variation : ply.variations {
            list_show_variation(variation, firstOne = false);
        }
    }

    if firstOne {
        _place_ply(variation.plies[0], propagate = true);
    }
}

list_update_to_current_move :: (game : *Game, oldPly : *PlyEntity) {
    list := instance.list;

    // Uncollapse the tree if needed
    // @todo have it dynamic and hide it back when leaving?
    if game.ply != null {
        topUncollapsedVariation : *Variation;
        variation := game.ply.parentVariation;
        while variation != null {
            if variation.collapsed {
                variation.collapsed = false;
                topUncollapsedVariation = variation;
            }
            variation = ifx variation.parentPly != null then variation.parentPly.parentVariation else null;
        }

        if topUncollapsedVariation != null {
            replace_ply_recursively(topUncollapsedVariation.plies[0]);
        }
    }

    if oldPly != null {
        for *meshNode : oldPly.mesh.nodes {
            Magma.material_set(meshNode.primitives[0].material, "color", oldPly.moveColor);
        }
        if oldPly.decorum {
            Magma.material_set(oldPly.decorum.mesh.nodes[0].primitives[0].material, "color", instance.config.moves.mainColor);
        }
    }

    plyY := 0.0;
    plyHeight := 0.0;
    if game.ply != null {
        plyY = game.ply.transform.translation.y;
        plyHeight = game.ply.ui.extent.height;

        for *meshNode : game.ply.mesh.nodes {
            color := ifx meshNode == game.ply.commentMeshNode then instance.config.moves.selectedCommentColor
                                                              else instance.config.moves.selectedColor;
            Magma.material_set(meshNode.primitives[0].material, "color", color);
        }
        if game.ply.decorum {
            Magma.material_set(game.ply.decorum.mesh.nodes[0].primitives[0].material, "color", instance.config.moves.selectedColor);
        }
    }

    // Clever scrolling, don't scroll if all the node is already visible
    if list.scroll.transform.translation.y + plyY > 0 &&
        list.scroll.transform.translation.y + plyY + plyHeight < list.ui.extent.height {
        return;
    }

    // We need to fit the ply at the screen. To do so, either move the list down or up
    // given which side is the closest. This makes navigating the moves downwards more
    // natural by having them appearing at the bottom.
    deltaToFitAtTop := 0 - list.scroll.transform.translation.y - plyY;
    deltaToFitAtBottom := list.ui.extent.height - list.scroll.transform.translation.y - (plyY + plyHeight);
    delta := ifx Math.abs(deltaToFitAtTop) < Math.abs(deltaToFitAtBottom) then deltaToFitAtTop else deltaToFitAtBottom;

    list_scroll(delta);
}

list_scroll :: (scrollDelta : float) {
    list := instance.list;

    list.scroll.transform.translation.y += Math.floor(scrollDelta);

    // Clever scrolling, don't go outside the limits
    // Find the last ply, to know the size of the total displayed list
    ply := Basic.peek(instance.game.mainVariation.plies);
    while ply.variations.count != 0 {
        ply = Basic.peek(Basic.peek(ply.variations).plies);
    }

    maxY := (ply.transform.translation.y + ply.ui.extent.height) - list.ui.extent.height / 2;
    maxY = Basic.max(maxY, 0);

    if list.scroll.transform.translation.y > 0 {
        list.scroll.transform.translation.y = 0;
    } else if list.scroll.transform.translation.y < -maxY {
        list.scroll.transform.translation.y = -maxY;
    }

    Sill.transform_commit(*list.scroll.transform);
}

ply_edit_comment :: (ply : *PlyEntity, textCursorAtMouse := false) {
    Sill.ui_set_focused(*ply.ui);
    if textCursorAtMouse {
        _set_text_cursor_position_from_mouse(ply);
    }
    _update_text_cursor(ply);
}

ply_init :: (ply : *PlyEntity, place := true) {
    height : float;

    ply.moveColor = annotation_color(ply.position.lastMove.annotation);
    if ply.parentVariation.parentPly != null {
        ply.depth = ply.parentVariation.parentPly.depth + 1;
    } else {
        ply.depth = 0;
    }

    Sill.entity_set_parent(ply, *instance.list.scroll);

    // ----- Move

    if ply.index != 0 {
        Basic.array_add(*ply.mesh.nodes, .{});
        Basic.array_add(*Basic.peek_pointer(ply.mesh.nodes).primitives, create_text_mesh());
        ply.moveMeshNode = Basic.peek_pointer(ply.mesh.nodes);

        moveIndex := (ply.position.moveIndex + 1) / 2;
        moveText := Basic.tprint("%.% %", moveIndex, ifx ply.position.moveIndex % 2 then "" else ".. ", position_last_move_to_san(ply.position, annotations = true));
        fontId := ifx ply.depth == 0 then "mainBold" else "mainLight";
        charInfos := text_mesh_update(ply.moveMeshNode.primitives[0], moveText, fontId, ply.moveColor);
        ply.moveTextWidth = Basic.peek(charInfos).effective.xEnd;
        Basic.array_free(charInfos);
    } else if (ply.parentVariation.parentPly != null) {
        ply.decorum = _make_decorum();
        ply.decorum.transform.translation.x = -UiConstants.PaddingHorizontalVariation / 2.0;
        Sill.entity_set_parent(ply.decorum, ply);
    }

    // ----- Comment

    Basic.array_add(*ply.mesh.nodes, .{});
    Basic.array_add(*Basic.peek_pointer(ply.mesh.nodes).primitives, create_text_mesh());
    ply.commentMeshNode = Basic.peek_pointer(ply.mesh.nodes);
    ply.charInfos = text_mesh_update(ply.commentMeshNode.primitives[0], ply.position.comment, "mainLight", instance.config.moves.mainColor);
    Basic.array_add(*ply.collider.boxShapes, .{});

    Sill.ui_on_trigger(*ply.ui, (trigger : Sill.UiTrigger, ply : *PlyEntity) {
        // Either select the ply, or start editing the comment if already selected
        if instance.game.ply != ply {
            game_update_to(*instance.game, ply);
        } else {
            ply_edit_comment(ply, textCursorAtMouse = true);
        }
    }, Sill.UiCallbackFlags.Click, ply);

    Sill.ui_on_trigger(*ply.ui, (trigger : Sill.UiTrigger, ply : *PlyEntity) {
        _show_text_cursor(!(trigger.flags & .NoFocus));
    }, Sill.UiCallbackFlags.Focus | .NoFocus, ply);

    Sill.ui_on_trigger(*ply.ui, (trigger : Sill.UiTrigger, ply : *PlyEntity) {
        textChanged := false;
        <<trigger.stopPropagation = true;

        if trigger.event.kind == .TextEntered {
            // :RelativePointerIssue
            length := Basic.c_style_strlen(*trigger.event.text.utf8[0]);
            Chamber.insert_after_byte(*ply.position.comment, ply.textCursorPosition, Basic.to_string(*trigger.event.text.utf8[0], length));
            ply.textCursorPosition += cast(u32) length;
            textChanged = true;
        } else if trigger.event.kind == .KeyPressed {
            if trigger.event.key.which == .Escape {
                Sill.ui_set_focused(*ply.ui, false);
            } else if trigger.event.key.which == .Delete {
                deletedBytes := Chamber.delete_after_byte(*ply.position.comment, ply.textCursorPosition);
                if deletedBytes == 0 then return;
                textChanged = true;
            } else if trigger.event.key.which == .Backspace {
                deletedBytes := Chamber.delete_before_byte(*ply.position.comment, ply.textCursorPosition);
                if deletedBytes == 0 then return;
                ply.textCursorPosition -= deletedBytes;
                textChanged = true;
            } else if trigger.event.key.which == .Left {
                if ply.textCursorPosition == 0 then return;
                ply.textCursorPosition -= Chamber.utf8_word_length_before_byte(ply.position.comment, ply.textCursorPosition);
            } else if trigger.event.key.which == .Right {
                if ply.textCursorPosition == ply.position.comment.count then return;
                ply.textCursorPosition += Chamber.utf8_word_length_after_byte(ply.position.comment, ply.textCursorPosition);
            } else {
                return;
            }
        } else {
            Crater.window_pointer_style(instance.engine.window, .Default);
            return;
        }

        // @todo Do a clever diff instead of regenerating everything?
        if textChanged then {
            Basic.array_free(ply.charInfos);
            ply.charInfos = text_mesh_update(ply.commentMeshNode.primitives[0], ply.position.comment, "mainLight", instance.config.moves.mainColor);
            _place_ply(ply, propagate = true);
        }

        _update_text_cursor(ply);
    }, Sill.UiCallbackFlags.Text | .Key | .NoHover, ply);

    Sill.ui_check_hovered_handler(*ply.ui, (hovered : bool, ply : *PlyEntity) -> bool {
        ray : Ray = ---;
        ray.origin.x = cast(float) instance.engine.window.mousePosition.x - instance.engine.options.windowExtent.width / 2.0;
        ray.origin.y = cast(float) instance.engine.window.mousePosition.y - instance.engine.options.windowExtent.height / 2.0;
        ray.origin.z = -40;
        ray.direction = .{0, 0, 1};

        ply.moveHovered = false;

        if hovered && ply.moveMeshNode {
            mesh := ply.moveMeshNode.primitives[0];
            distance := Magma.mesh_distance_from(mesh, ray, .MeshFirstHit);
            if distance > 0.0 {
                ply.moveHovered = true;
                Crater.window_pointer_style(instance.engine.window, .HandPointing);
                return true;
            }
        }

        if ply.commentMeshNode {
            distance := Sill.collider_distance_from(*ply.collider, ray);
            if distance > 0.0 {
                pointerStyle := ifx instance.game.ply == ply then Crater.PointerStyle.Text else .HandPointing;
                Crater.window_pointer_style(instance.engine.window, pointerStyle);
                return true;
            }
        }

        return false;
    }, ply);

    if place {
        _place_ply(ply, propagate = true);
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
    spaced : bool; // The preflushed comment should be spaced from the previous one.
}

_detect_comment_location :: (ply : *PlyEntity) -> CommentLocation {
    variation := ply.parentVariation;

    commentLocation : CommentLocation;
    commentLocation.color = ifx ply.position.moveIndex % 2 != 0 then Color.White else .Black;

    if ply.index == 0 {
        commentLocation.style = .Full;
        commentLocation.preflushed = true;
        commentLocation.spaced = (ply.parentVariation.depth == 1);
        return commentLocation;
    }

    commentLocation.style = _detect_comment_style(ply.position.comment);
    nextCommentStyle := ifx ply.index != variation.plies.count - 1 then _detect_comment_style(variation.plies[ply.index + 1].position.comment) else .None;
    previousCommentStyle := ifx ply.index != 0 then _detect_comment_style(variation.plies[ply.index - 1].position.comment) else .None;

    // Promotion of white half comment to a long style comment if next black is expected to be full.
    if commentLocation.style == .Half && commentLocation.color == .White &&
       (nextCommentStyle == .Full || nextCommentStyle == .SidedFull) {
        commentLocation.style = instance.config.moves.comments.longStyle;
    }
    // Promotion of white half comment to a long style comment if there are any variation.
    else if commentLocation.style == .Half && commentLocation.color == .White && ply.variations.count > 0 {
        commentLocation.style = instance.config.moves.comments.longStyle;
    }

    // @todo Do that on option only?
    // Turn a Half or SidedFull to Full if it is the last move.
    if (/*commentLocation.style == .Half ||*/ commentLocation.style == .SidedFull) && ply.index == variation.plies.count - 1 {
        commentLocation.style = .Full;
    }

    // Always preflush if after a variation list or if at the start of a variation.
    if ply.index != 0 && variation.plies[ply.index - 1].variations.count > 0 {
        commentLocation.preflushed = true;
        commentLocation.spaced = (ply.parentVariation.depth == 0);
    } else if commentLocation.color == .White || commentLocation.style == .Full || commentLocation.style == .SidedFull ||
              previousCommentStyle == .Full || previousCommentStyle == .SidedFull {
        commentLocation.preflushed = true;

        // Don't preflush a black comment when the white before was None or Inline.
        if commentLocation.color == .Black && commentLocation.style != .Full &&
           (previousCommentStyle == .None || previousCommentStyle == .Inline) {
            commentLocation.preflushed = false;
        }

        if commentLocation.preflushed && ply.parentVariation.depth == 0  {
            if _is_style_spaced_after(previousCommentStyle) {
                commentLocation.spaced = true;
            } else if commentLocation.color == .White && ply.index >= 2 && variation.plies[ply.index - 2].variations.count == 0 {
                previousPreviousCommentStyle := _detect_comment_style(variation.plies[ply.index - 2].position.comment);
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

_place_comment_from_char_infos :: (ply : *PlyEntity) {
    mesh := ply.commentMeshNode.primitives[0];

    if ply.charInfos.count == 0 {
        mesh.disabled |= .Application;
        return;
    }

    minBounds := Chamber.vec2.{Math.FLOAT32_INFINITY, Math.FLOAT32_INFINITY};
    maxBounds := Chamber.vec2.{-Math.FLOAT32_INFINITY, -Math.FLOAT32_INFINITY};

    mesh.disabled &= ~.Application;
    index := 0;
    for *charInfo : ply.charInfos {
        if charInfo.glyphBlank then continue;

        if charInfo.effective.xStart < minBounds.x then minBounds.x = charInfo.effective.xStart;
        if charInfo.effective.yStart < minBounds.y then minBounds.y = charInfo.effective.yStart;
        if charInfo.effective.xEnd > maxBounds.x then maxBounds.x = charInfo.effective.xEnd;
        if charInfo.effective.yEnd > maxBounds.y then maxBounds.y = charInfo.effective.yEnd;

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

    ply.collider.boxShapes[0].transform.translation = ply.commentMeshNode.transform.translation;
    ply.collider.boxShapes[0].transform.rotation = ply.commentMeshNode.transform.rotation;
    ply.collider.boxShapes[0].transform.translation.xy.std += (maxBounds + minBounds) / 2.0;
    ply.collider.boxShapes[0].extent.xy.std = maxBounds - minBounds;
    ply.collider.boxShapes[0].extent.z = 1.0;

    Sill.collider_commit_shapes(*ply.collider);
}

// The ply entity mesh position (0,0) means the top left of the move text.
// Which means that the comment mesh ply might be offseted to the left
// for black moves.
_place_ply :: (ply : *PlyEntity, propagate := false, hidden := false) {
    variationOffset := ply.depth * UiConstants.PaddingHorizontalVariation;
    maxWidth := instance.list.ui.extent.width - variationOffset;
    offsetToBlack := (maxWidth + UiConstants.PaddingHorizontalSplit) / 2;
    parentVariationCollapsed := ply.parentVariation.collapsed;

    ply.ui.anchor = .TopLeft;
    ply.ui.extent.width = maxWidth;

    // Detect the comment location, and re-structure it as needed.
    commentLocation := _detect_comment_location(ply);
    ply.commentLocation = commentLocation;

    commentWidth := maxWidth;
    if hidden || parentVariationCollapsed {
        commentWidth = Math.FLOAT32_INFINITY;
    } else if commentLocation.style == .Half {
        commentWidth = (maxWidth - UiConstants.PaddingHorizontalSplit) / 2;
    } else if commentLocation.style == .SidedFull {
        commentWidth = maxWidth * instance.config.moves.comments.fullStyleWidth;
    } else if commentLocation.style == .Inline {
        commentWidth = maxWidth / 2.0 - ply.moveTextWidth - UiConstants.PaddingCommentInline;
    }

    // Position the comment mesh based on its location.
    // Make the text fit the specified size.
    commentHeight := justify_char_infos(ply.charInfos, commentWidth, 0.0);

    ply.commentMeshNode.transform.translation = .{};
    if ply.index != 0 {
        if commentLocation.style == .Inline || ply.position.comment.count == 0 {
            ply.commentMeshNode.transform.translation.x += ply.moveTextWidth + UiConstants.PaddingCommentInline;
            ply.commentMeshNode.transform.translation.y = 0.0;
            ply.ui.extent.height = Basic.max(UiConstants.HeightLine, commentHeight);
        } else {
            ply.commentMeshNode.transform.translation.y = UiConstants.HeightLine;
            ply.ui.extent.height = UiConstants.HeightLine + commentHeight;
        }

        if commentLocation.color == .Black &&
           (commentLocation.style == .SidedFull || commentLocation.style == .Full) {
            ply.commentMeshNode.transform.translation.x = (maxWidth - commentWidth - offsetToBlack);
        }
    } else {
        ply.ui.extent.height = commentHeight;
    }

    // @note Waiting for the comment mesh ply to be positioned so that we can place the collider accordingly.
    _place_comment_from_char_infos(ply);

    if ply.commentMeshNode != null {
        ply.commentMeshNode.primitives[0].disabled &= ~.Application;
        Basic.peek_pointer(ply.collider.boxShapes).disabled = false;
    }
    Sill.entity_set_disabled(ply, hidden || parentVariationCollapsed);

    if hidden || parentVariationCollapsed {
        if !hidden && ply.index == 1 {
            ply.ui.extent.height = Basic.max(UiConstants.HeightLine, commentHeight);

            // Show only the first move mesh in collapsed thingy
            // @todo If move and comment were two separated entities,
            // it would make that thing easier.
            Sill.entity_set_disabled(ply, false);
            if ply.commentMeshNode != null {
                ply.commentMeshNode.primitives[0].disabled |= .Application;
                Basic.peek_pointer(ply.collider.boxShapes).disabled = true;
            }
        } else {
            ply.ui.extent.height = 0.0;
        }
    }

    // Position the entity based on the above comment and the comment location.
    position : Chamber.vec2;
    position.x = variationOffset;

    abovePly : *PlyEntity;
    if ply.index > 0 {
        if commentLocation.color == .Black then position.x += offsetToBlack;

        // The above ply entity is either the previous ply,
        // or the last ply of its last variant.
        abovePly = ply.parentVariation.plies[ply.index - 1];
        while abovePly.variations.count != 0 {
            abovePly = Basic.peek(Basic.peek(abovePly.variations).plies);
        }
    } else {
        abovePly = ply.parentVariation.parentPly;
        if abovePly != null && ply.parentVariation.index > 0 {
            abovePly = Basic.peek(abovePly.variations[ply.parentVariation.index - 1].plies);
            while abovePly.variations.count != 0 {
                abovePly = Basic.peek(Basic.peek(abovePly.variations).plies);
            }
        }

        // Move the collapsed decorum dots next to the black move
        if commentLocation.color == .White && !hidden && parentVariationCollapsed {
            position.x += offsetToBlack;
        }
    }

    if abovePly != null {
        position.y += abovePly.transform.translation.y;
        if commentLocation.preflushed {
            // We want to preflush but if the previous one is a half black,
            // we need to take the max between this one and the corresponding half white.
            height := abovePly.ui.extent.height;
            if abovePly.commentLocation.color == .Black && !abovePly.commentLocation.preflushed {
                correspondingAbovePly := abovePly.parentVariation.plies[abovePly.index - 1];
                height = Basic.max(height, correspondingAbovePly.ui.extent.height);
            }
            position.y += height;
        }
    }

    if commentLocation.spaced {
        position.y += ifx hidden || parentVariationCollapsed then 5 else 15;
    }

    ply.transform.translation.xy = position;
    Sill.transform_commit(*ply.transform);

    // If propagate, we replace also all downstream plys.
    // @todo Do that only on commentLocation or height change?
    if propagate {
        _place_variation_plies(ply.parentVariation, ply.index, hidden = hidden);
        _rebuild_decorums(*instance.game.mainVariation);
    }
}

_place_variation_plies :: (variation : *Variation, plyIndex : u16, upstream := true, hidden := false) {
    // Downstream
    for i : plyIndex .. variation.plies.count - 1 {
        ply := variation.plies[i];
        _place_ply(ply, hidden = hidden);

        for subVariation : ply.variations {
            _place_variation_plies(subVariation, 0, upstream = false, hidden || variation.collapsed);
        }
    }

    // Upstream
    if upstream && variation.parentPly != null {
        for i : variation.index + 1 .. variation.parentPly.variations.count - 1 {
            _place_variation_plies(variation.parentPly.variations[i], 0, upstream = false);
        }

        _place_variation_plies(variation.parentPly.parentVariation, variation.parentPly.index + 1);
    }
}

_rebuild_decorums :: (variation : *Variation, hidden := false) {
    // @fixme What isn't the decorum on the variation?
    // If it's because it's not an entity, that's not a good excuse, long term.
    if variation.plies[0].decorum != null {
        Sill.entity_set_disabled(variation.plies[0].decorum, hidden);
    }

    for ply : variation.plies {
        for subVariation : ply.variations {
            firstPly := subVariation.plies[0];
            lastPly := Basic.peek(subVariation.plies);

            while lastPly.variations.count != 0 {
                lastPly = Basic.peek(Basic.peek(lastPly.variations).plies);
            }

            position := firstPly.transform.translation;
            height := lastPly.transform.translation.y + lastPly.ui.extent.height - position.y;
            _update_decorum(firstPly.decorum, height, subVariation.collapsed);

            _rebuild_decorums(subVariation, hidden || variation.collapsed);
        }
    }
}

_set_text_cursor_position_from_mouse :: (ply : *PlyEntity) {
    relativePosition := Sill.ui_relative_mouse_pointer_position(*ply.ui);
    relativePosition.std -= ply.commentMeshNode.transform.translation.xy;

    // Find the closest char info.
    byteIndex : u32;
    xStart := 0.0;
    lastYStart := -1.0;
    for *charInfo : ply.charInfos {
        // New line, reset xStart.
        if lastYStart != charInfo.effective.yStart {
            xStart = charInfo.effective.xStart;
        }

        if xStart <= relativePosition.x && charInfo.effective.xEnd > relativePosition.x &&
           charInfo.effective.yStart <= relativePosition.y && charInfo.effective.yEnd > relativePosition.y {
            if relativePosition.x - xStart > charInfo.effective.xEnd - relativePosition.x {
                byteIndex += Chamber.utf8_word_length_after_byte(ply.position.comment, byteIndex);
            }
            break;
        }

        byteIndex += Chamber.utf8_word_length_after_byte(ply.position.comment, byteIndex);
        xStart = charInfo.effective.xEnd;
        lastYStart = charInfo.effective.yStart;
    }

    ply.textCursorPosition = byteIndex;
}

_update_text_cursor :: (ply : *PlyEntity) {
    textCursor := *instance.list.textCursor;
    commentMesh := ply.commentMeshNode.primitives[0];

    Sill.entity_set_parent(textCursor, ply);

    // @note We always update the cursor, because when the text changed and not the cursor position,
    // the justification of the line might slightly move the cursor itself.
    textCursor.transform.translation = ply.commentMeshNode.transform.translation;
    textCursor.transform.translation.y += UiConstants.HeightLine / 2;
    if ply.textCursorPosition == 0 {
        if ply.charInfos.count != 0 {
            textCursor.transform.translation.x += ply.charInfos[0].effective.xStart;
            textCursor.transform.translation.y += ply.charInfos[0].effective.yStart;
        }
    } else {
        byteIndex : u32;
        for i : 0 .. ply.charInfos.count - 1 {
            byteIndex += Chamber.utf8_word_length_after_byte(ply.position.comment, byteIndex);

            if ply.textCursorPosition <= byteIndex {
                textCursor.transform.translation.x += Math.floor(ply.charInfos[i].effective.xEndWithAdvance + 0.5);
                textCursor.transform.translation.y += ply.charInfos[i].effective.yStart;
                break;
            }
        }
    }

    Sill.transform_commit(*textCursor.transform);
}

_show_text_cursor :: (show := true) {
    Sill.entity_set_disabled(*instance.list.textCursor, !show);
}

_make_decorum :: () -> *DecorumEntity {
    decorum := SillMeta.create_decorum_entity(instance.engine);
    decorum.ui.anchor = .TopLeft;

    mesh := Magma.create_mesh(instance.engine.scene);
    create_rect_mesh(existingMesh = mesh);

    mesh.vertices[0].position.x = 0.0;
    mesh.vertices[0].position.y = 0.0;
    mesh.vertices[1].position.x = 0.0;
    mesh.vertices[1].position.y = 1.0; // Will be height
    mesh.vertices[2].position.x = 1.0; // Will be width
    mesh.vertices[2].position.y = 1.0; // Will be height
    mesh.vertices[3].position.x = 1.0; // Will be width
    mesh.vertices[3].position.y = 0.0;

    mesh.material = Magma.create_material(instance.shaders.decorum);
    Magma.material_set(mesh.material, "color", instance.config.moves.mainColor);
    Magma.mesh_commit_vertices(mesh);

    Basic.array_add(*decorum.mesh.nodes, .{});
    Basic.array_add(*Basic.peek_pointer(decorum.mesh.nodes).primitives, mesh);

    Sill.ui_on_trigger(*decorum.ui, (trigger : Sill.UiTrigger, decorum : *DecorumEntity) {
        if trigger.flags == .ClickStart {
            variation_collapse((cast(*PlyEntity) decorum.parent).parentVariation);
        } else {
            pointerStyle := ifx trigger.flags == .Hover then Crater.PointerStyle.HandPointing else .Default;
            color := ifx trigger.flags == .Hover then instance.config.moves.selectedColor else instance.config.moves.mainColor;
            Magma.material_set(decorum.mesh.nodes[0].primitives[0].material, "color", color);
            Crater.window_pointer_style(instance.engine.window, pointerStyle);
        }
    }, Sill.UiCallbackFlags.Hover | .NoHover | .ClickStart, decorum);

    return decorum;
}

_update_decorum :: (decorum : *DecorumEntity, height : float, collapsed := false) {
    mesh := decorum.mesh.nodes[0].primitives[0];

    height = Basic.max(height, UiConstants.HeightLine);

    decorum.ui.extent.width = UiConstants.WidthDecorumVariation + 1;
    decorum.ui.extent.height = height;
    decorum.ui.anchor = .TopLeft;

    mesh.vertices[0].position.x = 0.0;
    mesh.vertices[1].position.x = 0.0;
    mesh.vertices[2].position.x = UiConstants.WidthDecorumVariation;
    mesh.vertices[3].position.x = UiConstants.WidthDecorumVariation;
    mesh.vertices[0].position.y = UiConstants.PaddingVerticalDecorumVariation;
    mesh.vertices[1].position.y = height - UiConstants.PaddingVerticalDecorumVariation;
    mesh.vertices[2].position.y = height - UiConstants.PaddingVerticalDecorumVariation;
    mesh.vertices[3].position.y = UiConstants.PaddingVerticalDecorumVariation;

    Magma.material_set(mesh.material, "collapsed", collapsed);
    Magma.material_set(mesh.material, "height", height);

    Magma.mesh_commit_vertices(mesh);
}
