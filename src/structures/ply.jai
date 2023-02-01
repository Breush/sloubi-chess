PlyEntity :: struct {
    using #as entity : Sill.Entity;

    collider : Sill.ColliderComponent;
    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    // -- Main properties
    position : Position;
    variations : [..]*VariationEntity;
    parentVariation : *VariationEntity;
    index : u16; // Index of the ply in the parent variation.

    // -- Display
    charInfos : CharInfos;
    textCursorPosition : u32; // Stored in bytes, not codepoints.
    startingOffsetX : float;
    plyLocation : PlyLocation;

    // Below are just references to the corresponding primitive mesh within the component,
    // for easier use.
    moveIndexMeshNode : *Sill.MeshNode;
    moveMeshNode : *Sill.MeshNode;
    commentMeshNode : *Sill.MeshNode;

    moveHovered : bool;
    moveColor : Chamber.vec3;
    moveIndexTextWidth : float;
    moveTextWidth : float;
    moveWidth : float; // Computed with above values, based on whether the move index is visible or not.

    on_cleanup :: (using this : *PlyEntity) {
        position_cleanup(*position);
        Basic.array_free(charInfos.infos);
    }
}

CommentStyle :: enum {
    None :: 0;
    Inline;
    Half;
    Full;
    SidedFull;
}

MoveStyle :: enum {
    None :: 0;
    Compact;
    WhiteColumn;
    BlackColumn;
}

PlyLocation :: struct {
    moveStyle : MoveStyle;
    commentStyle : CommentStyle;
    preflushed : bool;
    spaced : bool; // The preflushed comment should be spaced from the previous one.
    moveNumbered : bool;
    fitWidth : bool; // The ply extent.width should perfectly fit the display, this is used for compact plies.
}

ply_init :: (ply : *PlyEntity, place := true) {
    height : float;

    ply.moveColor = annotation_color(ply.position.lastMove.annotation);

    Sill.listener_on_message(*ply.listener, _on_message);

    // ----- Move

    if ply.index != 0 {
        moveIndexMesh, moveIndexMeshNode := Sill.mesh_make_primitive(*ply.mesh);
        moveMesh, moveMeshNode := Sill.mesh_make_primitive(*ply.mesh);
        create_text_mesh(existingMesh = moveIndexMesh);
        create_text_mesh(existingMesh = moveMesh);

        fontId := ifx ply.parentVariation.depth == 0 then "mainBold" else "mainLight";
        moveIndex := (ply.position.moveIndex + 1) / 2;
        moveIndexText := Basic.tprint("%.%", moveIndex, ifx ply.position.moveIndex % 2 then "" else ".. ");
        moveText := position_last_move_to_san(ply.position, annotations = true);
        ply.moveIndexTextWidth = text_mesh_update(moveIndexMesh, moveIndexText, fontId, ply.moveColor);
        ply.moveTextWidth = text_mesh_update(moveMesh, moveText, fontId, ply.moveColor);
        ply.moveIndexMeshNode = moveIndexMeshNode;
        ply.moveMeshNode = moveMeshNode;
    }

    // ----- Comment

    Basic.array_add(*ply.mesh.nodes, .{});
    Basic.array_add(*Basic.peek_pointer(ply.mesh.nodes).primitives, create_text_mesh());
    ply.commentMeshNode = Basic.peek_pointer(ply.mesh.nodes);
    textWidth : float;
    textWidth, ply.charInfos = text_mesh_update(ply.commentMeshNode.primitives[0], ply.position.comment, "mainLight", instance.config.moves.mainColor, computeCharInfos = true);
    Basic.array_add(*ply.collider.boxShapes, .{});

    Sill.ui_on_trigger(*ply.ui, (trigger : Sill.UiTrigger, ply : *PlyEntity) {
        // Either select the ply, or start editing the comment if already selected
        gameView := cast(*GameView) ply.parent;
        if gameView.game.ply != ply {
            game_update_to(gameView.game, ply);
        } else {
            ply_edit_comment(ply, textCursorAtMouse = true);
        }
    }, .ClickStop, ply);

    Sill.ui_on_trigger(*ply.ui, (trigger : Sill.UiTrigger, ply : *PlyEntity) {
        if trigger.flags & .FocusStart {
            send(.PlyCommentEditStarted);
        } else {
            send(.PlyCommentEditStopped);
        }
    }, Sill.UiCallbackFlags.FocusStart | .FocusStop, ply);

    Sill.ui_on_trigger(*ply.ui, (trigger : Sill.UiTrigger, ply : *PlyEntity) {
        textChanged := false;
        << trigger.stopPropagation = true;

        if trigger.event.kind == .TextEntered {
            // :RelativePointerIssue
            length := c_style_strlen(*trigger.event.text.utf8[0]);
            Chamber.insert_after_byte(*ply.position.comment, ply.textCursorPosition, Basic.to_string(*trigger.event.text.utf8[0], length));
            ply.textCursorPosition += cast(u32) length;
            textChanged = true;
        } else if trigger.event.kind == .KeyPressed {
            if trigger.event.key.which == .Escape {
                Sill.ui_set_focused(*ply.ui, false);
            } else if trigger.event.key.which == .Delete {
                if ply.textCursorPosition == ply.position.comment.count then return;
                bytesToDelete : u32;
                if input_action_active(instance.engine, "game.ply.comment.edit.word-modifier") {
                    bytesToDelete = Chamber.word_length_after_byte(ply.position.comment, ply.textCursorPosition);
                } else {
                    bytesToDelete = Chamber.utf8_word_length_after_byte(ply.position.comment, ply.textCursorPosition);
                }
                if bytesToDelete == 0 then return;
                Chamber.delete_after_byte(*ply.position.comment, ply.textCursorPosition, bytesToDelete);
                textChanged = true;
            } else if trigger.event.key.which == .Backspace {
                if ply.textCursorPosition == 0 then return;
                bytesToDelete : u32;
                if input_action_active(instance.engine, "game.ply.comment.edit.word-modifier") {
                    bytesToDelete = Chamber.word_length_before_byte(ply.position.comment, ply.textCursorPosition);
                } else {
                    bytesToDelete = Chamber.utf8_word_length_before_byte(ply.position.comment, ply.textCursorPosition);
                }
                if bytesToDelete == 0 then return;
                Chamber.delete_before_byte(*ply.position.comment, ply.textCursorPosition, bytesToDelete);
                ply.textCursorPosition -= bytesToDelete;
                textChanged = true;
            } else if trigger.event.key.which == .Left {
                if ply.textCursorPosition == 0 then return;
                if input_action_active(instance.engine, "game.ply.comment.edit.word-modifier") {
                    ply.textCursorPosition -= Chamber.word_length_before_byte(ply.position.comment, ply.textCursorPosition);
                } else {
                    ply.textCursorPosition -= Chamber.utf8_word_length_before_byte(ply.position.comment, ply.textCursorPosition);
                }
            } else if trigger.event.key.which == .Right {
                if ply.textCursorPosition == ply.position.comment.count then return;
                if input_action_active(instance.engine, "game.ply.comment.edit.word-modifier") {
                    ply.textCursorPosition += Chamber.word_length_after_byte(ply.position.comment, ply.textCursorPosition);
                } else {
                    ply.textCursorPosition += Chamber.utf8_word_length_after_byte(ply.position.comment, ply.textCursorPosition);
                }
            } else if trigger.event.key.which == .Return {
                Chamber.insert_after_byte(*ply.position.comment, ply.textCursorPosition, "\n");
                ply.textCursorPosition += 1;
                textChanged = true;
            } else if trigger.event.key.which == .ControlLeft || trigger.event.key.which == .ControlRight {
                << trigger.stopPropagation = false;
            } else {
                return;
            }
        } else {
            Crater.window_pointer_style(instance.engine.window, .Default);
            return;
        }

        // @todo Do a clever diff instead of regenerating everything?
        if textChanged then {
            Basic.array_free(ply.charInfos.infos);
            textWidth : float;
            textWidth, ply.charInfos = text_mesh_update(ply.commentMeshNode.primitives[0], ply.position.comment, "mainLight", instance.config.moves.selectedCommentColor, computeCharInfos = true);
            ply_place(ply, propagate = true);
            study_mark_unsaved_modifications(instance.currentGame.study);
        }

        send(.PlyTextCursorPositionChanged, ply);
    }, Sill.UiCallbackFlags.Text | .Key | .HoverStop, ply);

    Sill.ui_check_hovered_handler(*ply.ui, (hovered : bool, relativeMousePointerPosition : Chamber.vec2, ply : *PlyEntity) -> bool {
        ray : Ray = ---;
        ray.origin.x = cast(float) instance.engine.window.mousePosition.x - instance.engine.options.windowExtent.width / 2.0;
        ray.origin.y = cast(float) instance.engine.window.mousePosition.y - instance.engine.options.windowExtent.height / 2.0;
        ray.origin.z = -40;
        ray.direction = .{0, 0, 1};

        ply.moveHovered = false;

        if hovered && ply.moveMeshNode {
            moveStartPosition := ply.moveIndexMeshNode.transform.translation.xy;
            if relativeMousePointerPosition.x >= moveStartPosition.x &&
               relativeMousePointerPosition.x <= moveStartPosition.x + ply.moveWidth &&
               relativeMousePointerPosition.y >= moveStartPosition.y &&
               relativeMousePointerPosition.y <= moveStartPosition.y + UiConstants.HeightLine {
                ply.moveHovered = true;
                Crater.window_pointer_style(instance.engine.window, .HandPointing);
                return true;
            }
        }

        if ply.commentMeshNode {
            distance := Sill.collider_distance_from(*ply.collider, ray);
            if distance > 0.0 {
                gameView := cast(*GameView) ply.parent;
                pointerStyle := ifx gameView.game.ply == ply then Crater.PointerStyle.Text else .HandPointing;
                Crater.window_pointer_style(instance.engine.window, pointerStyle);
                return true;
            }
        }

        return false;
    }, ply);

    send(.PlyInited, ply);

    if place {
        ply_place(ply, propagate = true);
    }
}

ply_cleanup :: (ply : *PlyEntity) {
    for variation : ply.variations {
        variation_cleanup(variation);
    }
    Basic.array_free(ply.variations);

    Sill.destroy_entity(ply);
}

// The ply entity mesh position (0,0) means the top left of the move text.
// Which means that the comment mesh ply might be offseted to the left
// for black moves.
ply_place :: (ply : *PlyEntity, propagate := false, hidden := false) {
    gameView := cast(*GameView) ply.parent; // ply.parent is scroll, and its parent is gameView

    variationOffset := ply.parentVariation.depth * UiConstants.PaddingHorizontalVariation;
    maxWidth := gameView.ui.extent.width - variationOffset;
    offsetToBlack := (maxWidth + UiConstants.PaddingHorizontalSplit) / 2;
    parentVariationCollapsed := ply.parentVariation.collapsed;

    ply.ui.anchor = .TopLeft;

    // Detect the comment location, and re-structure it as needed.
    plyLocation := _detect_ply_location(ply);
    ply.plyLocation = plyLocation;
    ply.moveWidth = ply.moveTextWidth;
    if plyLocation.moveNumbered {
        ply.moveWidth += ply.moveIndexTextWidth + UiConstants.PaddingHorizontalSmall;
    }

    commentWidth := maxWidth;
    if hidden || parentVariationCollapsed {
        commentWidth = Math.FLOAT32_INFINITY;
    } else if plyLocation.commentStyle == .Half {
        commentWidth = (maxWidth - UiConstants.PaddingHorizontalSplit) / 2;
    } else if plyLocation.commentStyle == .SidedFull {
        commentWidth = maxWidth * instance.config.moves.comments.fullStyleWidth;
    } else if plyLocation.commentStyle == .Inline {
        commentWidth = maxWidth / 2.0 - ply.moveWidth - UiConstants.PaddingCommentInline;
    }
    ply.ui.extent.width = maxWidth;

    // Detect whether the comment mesh will be visible or not
    if ply.commentMeshNode == null then return;
    ply.commentMeshNode.primitives[0].disabled &= ~.Application;
    Basic.peek_pointer(ply.collider.boxShapes).disabled = false;
    Sill.entity_set_disabled(ply, hidden || parentVariationCollapsed);

    if hidden || parentVariationCollapsed {
        if !hidden && ply.index == 1 {
            // Show only the first move mesh in collapsed thingy
            ply.commentMeshNode.primitives[0].disabled |= .Application;
            Basic.peek_pointer(ply.collider.boxShapes).disabled = true;
            Sill.entity_set_disabled(ply, false);
        } else {
            ply.ui.extent.height = 0.0;
        }
    }

    // Position the comment mesh based on its location.
    // Make the text fit the specified size.
    // @note Waiting for the comment mesh ply to be positioned so that we can place the collider accordingly.
    if !(ply.flags & .Disabled) {
        commentHeight : float;
        needCommentMeshUpdate := false;
        if !parentVariationCollapsed {
            commentHeight, needCommentMeshUpdate = justify_char_infos(*ply.charInfos, commentWidth, 0.0);
        }

        ply.commentMeshNode.transform.translation = .{};
        if ply.index != 0 {
            if plyLocation.commentStyle == .Inline || ply.position.comment.count == 0 || parentVariationCollapsed {
                ply.commentMeshNode.transform.translation.x += ply.moveWidth + UiConstants.PaddingCommentInline;
                ply.commentMeshNode.transform.translation.y = 0.0;
                ply.ui.extent.height = Basic.max(UiConstants.HeightLine, commentHeight);
            } else {
                ply.commentMeshNode.transform.translation.y = UiConstants.HeightLine;
                ply.ui.extent.height = UiConstants.HeightLine + commentHeight;
            }

            if plyLocation.moveStyle == .BlackColumn &&
               (plyLocation.commentStyle == .SidedFull || plyLocation.commentStyle == .Full) {
                ply.commentMeshNode.transform.translation.x = (maxWidth - commentWidth - offsetToBlack);
            }
        } else {
            ply.moveWidth = 0;
            ply.ui.extent.height = commentHeight;
        }

        if needCommentMeshUpdate {
            _place_comment_from_char_infos(ply);
        }
    }

    // Position the entity based on the above comment and the comment location.
    position : Chamber.vec2;
    position.x = variationOffset;

    abovePly : *PlyEntity;
    if ply.index > 0 {
        if plyLocation.moveStyle == .BlackColumn then position.x += offsetToBlack;

        // The above ply entity is either the previous ply,
        // or the last ply of its last variant.
        abovePly = ply.parentVariation.plies[ply.index - 1];
        while abovePly.variations.count != 0 {
            lastVariation := Basic.peek(abovePly.variations);
            if lastVariation.collapsed {
                abovePly = lastVariation.plies[1];
                break;
            } else {
                abovePly = Basic.peek(lastVariation.plies);
            }
        }

        if !plyLocation.moveNumbered {
            ply.moveIndexMeshNode.primitives[0].disabled |= .Application;
            ply.moveMeshNode.transform.translation.x = 0;
        } else {
            ply.moveIndexMeshNode.primitives[0].disabled &= ~.Application;
            ply.moveMeshNode.transform.translation.x = UiConstants.PaddingHorizontalSmall + ply.moveIndexTextWidth;
        }
    } else {
        abovePly = ply.parentVariation.parentPly;
        if abovePly != null && ply.parentVariation.index > 0 {
            abovePly = Basic.peek(abovePly.variations[ply.parentVariation.index - 1].plies);
            while abovePly.variations.count != 0 {
                abovePly = Basic.peek(Basic.peek(abovePly.variations).plies);
            }
        }

        // Allow the collapsed decorum dots to be next to the black move
        if plyLocation.moveStyle == .WhiteColumn && !hidden && parentVariationCollapsed {
            position.x += offsetToBlack;
        }
    }

    if plyLocation.fitWidth {
        ply.ui.extent.width = ply.moveWidth;
        if plyLocation.commentStyle == .Inline {
            commentWidth := ply.collider.boxShapes[0].extent.x;
            ply.ui.extent.width += commentWidth + UiConstants.PaddingCommentInline;
        }
    }

    if abovePly != null {
        position.y += abovePly.transform.translation.y;
        if plyLocation.preflushed {
            // We want to preflush but if the previous one is a half black,
            // we need to take the max between this one and the corresponding half white.
            height := abovePly.ui.extent.height;
            if abovePly.plyLocation.moveStyle == .BlackColumn && !abovePly.plyLocation.preflushed {
                correspondingAbovePly := abovePly.parentVariation.plies[abovePly.index - 1];
                height = Basic.max(height, correspondingAbovePly.ui.extent.height);
            }
            position.y += height;
        }
        if plyLocation.moveStyle == .Compact {
            // In compact mode, the above ply is just the previous one, and we are placed accordingly.
            position.x = abovePly.transform.translation.x + abovePly.ui.extent.width + UiConstants.PaddingHorizontalMedium;
            if position.x + ply.ui.extent.width > maxWidth {
                position.y += abovePly.ui.extent.height;
                position.x = variationOffset;
            }
        }
    }

    if plyLocation.spaced {
        position.y += ifx hidden || parentVariationCollapsed then 5 else 15;
    }

    ply.transform.translation.xy = position;
    Sill.transform_commit(*ply.transform);

    // If propagate, we replace also all downstream plys.
    // @todo Do that only on plyLocation or height change?
    if propagate {
        variation_place_plies(ply.parentVariation, ply.index, hidden = hidden);
    }
}

ply_edit_comment :: (ply : *PlyEntity, textCursorAtMouse := false) {
    Sill.ui_set_focused(*ply.ui);
    if textCursorAtMouse {
        _set_text_cursor_position_from_mouse(ply);
    }
}

ply_previous_ply :: (ply : *PlyEntity) -> *PlyEntity {
    if ply.index == 0 {
        parentPly := ply.parentVariation.parentPly;
        if parentPly == null || parentPly.index < 2 then return null;
        return parentPly.parentVariation.plies[parentPly.index - 2];
    }
    return ply.parentVariation.plies[ply.index - 1];
}

ply_next_ply :: (ply : *PlyEntity) -> *PlyEntity {
    if ply.index == ply.parentVariation.plies.count - 1 then return null;

    // If we're the first ply in our variation, we're not real,
    // so better get the real ply!
    if ply.index == 0 && ply.parentVariation.parentPly != null {
        return ply.parentVariation.parentPly;
    }

    return ply.parentVariation.plies[ply.index + 1];
}

// gameView of all plies after this one that already exist in the current game.
ply_next_plies :: (ply : *PlyEntity) -> []*PlyEntity {
    nextPly := ply_next_ply(ply);
    if nextPly == null then return .[];

    Basic.push_allocator(Basic.temp);
    nextPlies : [..]*PlyEntity;

    Basic.array_add(*nextPlies, nextPly);
    for nextPlyVariation : nextPly.variations {
        Basic.array_add(*nextPlies, nextPlyVariation.plies[1]);
    }

    return nextPlies;
}

#scope_file

_on_message :: (ply : *PlyEntity, message : *Message) {
    if message.kind == {
    case .SelectedPlyChanged;
        gameView := cast(*GameView) ply.parent;
        if message.oldPly == ply || gameView.game.ply == ply {
            _update_from_selected(ply);
        }
    case .VariationCollapsedChanged;
        if message.variation.plies[0] == ply {
            ply_place(ply, propagate = true);
        }
    }
}

_update_from_selected :: (ply : *PlyEntity) {
    gameView := cast(*GameView) ply.parent;

    for *meshNode : ply.mesh.nodes {
        color :=  ply.moveColor;
        if gameView.game.ply == ply {
            if meshNode == gameView.game.ply.commentMeshNode {
                color = instance.config.moves.selectedCommentColor;
            } else {
                color = instance.config.moves.selectedColor;
            }
        }

        Magma.material_set_color(meshNode.primitives[0].material, "color", color);
    }
}

_detect_ply_location :: (ply : *PlyEntity) -> PlyLocation {
    variation := ply.parentVariation;
    color := ifx ply.position.moveIndex % 2 != 0 then Color.White else .Black;

    plyLocation : PlyLocation;
    plyLocation.moveStyle = ifx color == .White then MoveStyle.WhiteColumn else .BlackColumn;

    if ply.index == 0 {
        plyLocation.commentStyle = ifx variation.depth == 0 then .Full else _detect_comment_style(ply.position.comment);
        plyLocation.preflushed = true;
        plyLocation.spaced = (variation.depth == 1);
        return plyLocation;
    }

    plyLocation.moveNumbered = true;

    previousPly := variation.plies[ply.index - 1];
    nextPly := ifx ply.index != variation.plies.count - 1 then variation.plies[ply.index + 1] else null;
    plyLocation.commentStyle = _detect_comment_style(ply.position.comment);
    nextCommentStyle := ifx nextPly != null then _detect_comment_style(nextPly.position.comment) else .None;
    previousCommentStyle := _detect_comment_style(previousPly.position.comment);
    nextCompact := ifx nextPly != null then _is_within_compact_sequence(nextPly) else true;

    if ply.index == 1 && variation.depth == 0 {
        previousCommentStyle = .Full;
    }

    // Promotion of white half comment to a long style comment if next black is expected to be full.
    if plyLocation.commentStyle == .Half && color == .White &&
       (nextCommentStyle == .Full || nextCommentStyle == .SidedFull) {
        plyLocation.commentStyle = instance.config.moves.comments.longStyle;
    }
    // Promotion of white half comment to a long style comment if there are any variation.
    else if plyLocation.commentStyle == .Half && color == .White && ply.variations.count > 0 {
        plyLocation.commentStyle = instance.config.moves.comments.longStyle;
    }

    // Turn a half to a SidedFull if the next ply is compact.
    if plyLocation.commentStyle == .Half && nextCompact {
        plyLocation.commentStyle = .SidedFull;
    }

    // Turn a SidedFull to Full if it is the last move.
    if plyLocation.commentStyle == .SidedFull && nextPly == null {
        plyLocation.commentStyle = .Full;
    }

    // Always preflush if after a variation gameView or if at the start of a variation.
    if previousPly.variations.count > 0 {
        plyLocation.preflushed = true;
        plyLocation.spaced = (variation.depth == 0);
    } else if color == .White || plyLocation.commentStyle == .Full || plyLocation.commentStyle == .SidedFull ||
              previousCommentStyle == .Full || previousCommentStyle == .SidedFull {
        plyLocation.preflushed = true;

        // Don't preflush a black comment when the white before was None or Inline.
        if color == .Black && plyLocation.commentStyle != .Full &&
           (previousCommentStyle == .None || previousCommentStyle == .Inline) {
            plyLocation.preflushed = false;
        }

        if plyLocation.preflushed && variation.depth == 0  {
            if _is_style_spaced_after(previousCommentStyle) {
                plyLocation.spaced = true;
            } else if color == .White && ply.index >= 2 && variation.plies[ply.index - 2].variations.count == 0 {
                previousPreviousCommentStyle := _detect_comment_style(variation.plies[ply.index - 2].position.comment);
                plyLocation.spaced = _is_style_spaced_after(previousPreviousCommentStyle);
            }
        }
    }

    // Detect whether the ply is in a compact section.
    compact, firstInCompactSequence := _is_within_compact_sequence(ply);
    if compact {
        plyLocation.fitWidth = true;
        if firstInCompactSequence {
            plyLocation.preflushed = true;
            plyLocation.spaced = variation.depth == 0;
        } else {
            plyLocation.spaced = false;
            plyLocation.preflushed = false;
            plyLocation.moveNumbered = color == .White;
            plyLocation.moveStyle = .Compact;
        }
    } else if _is_within_compact_sequence(previousPly) {
        // Usually, after a compact sequence, we flush.
        // But if we're the last ply in a variation, we don't need to.
        plyLocation.preflushed = nextPly != null;
        plyLocation.spaced = variation.depth == 0;
    }

    return plyLocation;
}

_detect_comment_style :: (comment : string) -> CommentStyle {
    // @todo Completely arbitrary, but gives good enough results.
    if comment.count == 0 then return .None;
    if comment.count <= 30 then return instance.config.moves.comments.shortStyle;
    if comment.count <= 150 then return instance.config.moves.comments.normalStyle;
    return instance.config.moves.comments.longStyle;
}

_is_within_compact_sequence :: (ply : *PlyEntity) -> (compact : bool, firstInSequence : bool) {
    // Consider a ply being compact if it has no variations and no comment or only inline ones.
    is_compact :: inline (ply : *PlyEntity) -> bool {
        commentStyle := _detect_comment_style(ply.position.comment);
        if ply.variations.count != 0 || (commentStyle != .None && commentStyle != .Inline) then return false;
        return true;
    }

    if ply.index == 0 || !is_compact(ply) then return false, false;

    compactPreviousPlyCount := 0;
    for <i : ply.index - 1 .. 1 {
        previousPly := ply.parentVariation.plies[i];
        if is_compact(previousPly) then compactPreviousPlyCount += 1;
        else break;
    }

    compactNextPlyCount := 0;
    for i : ply.index + 1 .. ply.parentVariation.plies.count - 1 {
        nextPly := ply.parentVariation.plies[i];
        if is_compact(nextPly) then compactNextPlyCount += 1;
        else break;
    }

    firstInSequence := compactPreviousPlyCount == 0;
    return (compactPreviousPlyCount + compactNextPlyCount + 1) >= instance.config.moves.compactThreshold, firstInSequence;
}

_is_style_spaced_after :: (commentStyle : CommentStyle) -> bool {
    return commentStyle == .Half || commentStyle == .SidedFull || commentStyle == .Full;
}

_place_comment_from_char_infos :: (ply : *PlyEntity) {
    mesh := ply.commentMeshNode.primitives[0];

    if ply.charInfos.infos.count == 0 {
        mesh.disabled |= .Application;
        return;
    }

    minBounds := Chamber.vec2.{Math.FLOAT32_INFINITY, Math.FLOAT32_INFINITY};
    maxBounds := Chamber.vec2.{-Math.FLOAT32_INFINITY, -Math.FLOAT32_INFINITY};

    mesh.disabled &= ~.Application;
    index := 0;
    for *charInfo : ply.charInfos.infos {
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

_set_text_cursor_position_from_mouse :: (ply : *PlyEntity) {
    relativePosition := Sill.ui_relative_mouse_pointer_position(*ply.ui);
    relativePosition.std -= ply.commentMeshNode.transform.translation.xy;

    // Find the closest char info.
    byteIndex : u32;
    xStart := 0.0;
    lastYStart := -1.0;
    for *charInfo : ply.charInfos.infos {
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
        } else if charInfo.effective.yStart > relativePosition.y {
            break;
        }

        byteIndex += Chamber.utf8_word_length_after_byte(ply.position.comment, byteIndex);
        xStart = charInfo.effective.xEnd;
        lastYStart = charInfo.effective.yStart;
    }

    ply.textCursorPosition = byteIndex;
    send(.PlyTextCursorPositionChanged, ply);
}
