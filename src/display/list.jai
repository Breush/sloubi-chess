ListEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    ui : Sill.UiComponent;

    scroll : ScrollEntity; // @note Not a pointer, no need to allocate it on the heap.
    textCursor : TextCursorEntity;
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

list_create :: () -> *ListEntity {
    using list := SillMeta.create_list_entity(instance.engine);
    Sill.listener_on_message(*listener, _on_message);
    Sill.entity_add_child(list, *scroll);

    textCursorMesh := Sill.mesh_make_primitive(*textCursor.mesh);
    create_rect_mesh(1, UiConstants.HeightLine, existingMesh = textCursorMesh);
    textCursorMesh.material = Magma.create_material(instance.shaders.monochrome);
    Sill.entity_set_disabled(*textCursor, true);
    Magma.material_set(textCursorMesh.material, "color", Chamber.vec3.{1, 1, 1});

    return list;
}

list_scroll :: (using list : *ListEntity, scrollDelta : float) {
    scroll.transform.translation.y += Math.floor(scrollDelta);

    // Clever scrolling, don't go outside the limits
    // Find the last ply, to know the size of the total displayed list
    ply := Basic.peek(instance.game.mainVariation.plies);
    while ply.variations.count != 0 {
        ply = Basic.peek(Basic.peek(ply.variations).plies);
    }

    maxY := (ply.transform.translation.y + ply.ui.extent.height) - ui.extent.height / 2;
    maxY = Basic.max(maxY, 0);

    if scroll.transform.translation.y > 0 {
        scroll.transform.translation.y = 0;
    } else if scroll.transform.translation.y < -maxY {
        scroll.transform.translation.y = -maxY;
    }

    Sill.transform_commit(*scroll.transform);
}

#scope_file

_on_message :: (using list : *ListEntity, message : *Message) {
    if message.kind == {
    case .PlyInited;
        Sill.entity_set_parent(message.ply, *list.scroll);
    case .SystemReflow;
        _reflow(list);
    case .ModeGameStarted;
        _show(list, instance.game);
    case .ModePlyEditCommentStarted;
        _show_text_cursor(list, true);
    case .ModePlyEditCommentStopped;
        _show_text_cursor(list, false);
    case .GameSelectedPlyChanged;
        _update_to_current_move(list, instance.game);
    case .PlyTextCursorPositionChanged;
        _update_text_cursor(list, instance.game.ply);
    }
}

_show :: (using list : *ListEntity, game : Game) {
    variation_init(game.mainVariation);
}

_reflow :: (using list : *ListEntity) {
    extent := Crater.window_get_extent(instance.engine.window);

    transform.translation.x = UiConstants.PaddingHorizontal;
    transform.translation.y = - cast(s32) extent.height / 2 + UiConstants.PaddingVertical;

    // @fixme What this sums up is that having the center at (0,0) is a bad idea because it can be half a pixel.
    if (extent.width / 2) % 2 == 1 {
        transform.translation.x += 0.5;
    }
    if (extent.height / 2) % 2 == 1 {
        transform.translation.y += 0.5;
    }

    ui.extent.width = extent.width / 2 - 2 * UiConstants.PaddingHorizontal;
    ui.extent.height = extent.height - 2 * UiConstants.PaddingVertical;
    ui.anchor = .TopLeft;

    Sill.transform_commit(*list.transform);

    if instance.game.mainVariation != null {
        ply_place(instance.game.mainVariation.plies[0], propagate = true);
    }
}

_update_to_current_move :: (using list : *ListEntity, game : Game) {
    // Uncollapse the tree if needed
    // @todo have it dynamic and hide it back when leaving?
    if game.ply != null {
        topUncollapsedVariation : *VariationEntity;
        variation := game.ply.parentVariation;
        while variation != null {
            if variation.collapsed {
                variation.collapsed = false;
                topUncollapsedVariation = variation;
            }
            variation = ifx variation.parentPly != null then variation.parentPly.parentVariation else null;
        }

        if topUncollapsedVariation != null {
            ply_place(topUncollapsedVariation.plies[0], propagate = true);
        }
    }

    plyY := 0.0;
    plyHeight := 0.0;
    if game.ply != null {
        plyY = game.ply.transform.translation.y;
        plyHeight = game.ply.ui.extent.height;
    }

    // Clever scrolling, don't scroll if all the node is already visible
    if scroll.transform.translation.y + plyY > 0 &&
        scroll.transform.translation.y + plyY + plyHeight < ui.extent.height {
        return;
    }

    // We need to fit the ply at the screen. To do so, either move the list down or up
    // given which side is the closest. This makes navigating the moves downwards more
    // natural by having them appearing at the bottom.
    deltaToFitAtTop := 0 - scroll.transform.translation.y - plyY;
    deltaToFitAtBottom := ui.extent.height - scroll.transform.translation.y - (plyY + plyHeight);
    delta := ifx Math.abs(deltaToFitAtTop) < Math.abs(deltaToFitAtBottom) then deltaToFitAtTop else deltaToFitAtBottom;

    list_scroll(list, delta);
}

_update_text_cursor :: (using list : *ListEntity, ply : *PlyEntity) {
    commentMesh := ply.commentMeshNode.primitives[0];

    Sill.entity_set_parent(*textCursor, ply);

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

_show_text_cursor :: (using list : *ListEntity, show := true) {
    Sill.entity_set_disabled(*textCursor, !show);

    if (show) {
        _update_text_cursor(list, instance.game.ply);
    }
}
