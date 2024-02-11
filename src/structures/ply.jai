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
    // Whether this ply is the first one of a subgame.
    first : bool;
    // Whether there is a custom position and needs to generate an inline FEN tag.
    customPosition : bool;

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
    moveTextDirty : bool;

    game : *Game;

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
    moveVisible : bool;
    moveIndexVisible : bool;
    fitWidth : bool; // The ply extent.width should perfectly fit the display, this is used for compact plies.
}

ply_init :: (ply : *PlyEntity, game : *Game) {
    height : float;

    ply.game = game; // @todo Remove this link, as we have gameView as parent?
    ply.moveColor = annotation_color(ply.position.lastMove.annotation);

    Basic.assert(game.view != null);
    Sill.entity_set_parent(ply, game.view);

    Sill.listener_on_message(*ply.listener, _on_message);

    // ----- Move

    if !ply.first {
        moveIndexMesh, moveIndexMeshNode := Sill.mesh_make_primitive(*ply.mesh);
        moveMesh, moveMeshNode := Sill.mesh_make_primitive(*ply.mesh);

        // @todo Don't create the text mesh as long as not needed?
        create_text_mesh(existingMesh = moveIndexMesh, withMaterial = false);
        create_text_mesh(existingMesh = moveMesh, withMaterial = false);

        ply.moveIndexMeshNode = moveIndexMeshNode;
        ply.moveMeshNode = moveMeshNode;
        ply.moveTextDirty = true;
    }

    // ----- Comment

    Basic.array_add(*ply.mesh.nodes, .{});
    Basic.array_add(*Basic.peek_pointer(ply.mesh.nodes).primitives, create_text_mesh(withMaterial = false));
    ply.commentMeshNode = Basic.peek_pointer(ply.mesh.nodes);
    textWidth : float;
    textWidth, ply.charInfos = text_mesh_update(ply.commentMeshNode.primitives[0], ply.position.comment, "mainLight", ply.moveColor, computeCharInfos = true, useMaterialCache = true);
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
        trigger.stopPropagation.* = true;

        if trigger.flags & .MousePasting {
            clipboard := Crater.window_get_clipboard(instance.engine.window, .MousePaste);
            if clipboard.count != 0 {
                Chamber.insert_after_byte(*ply.position.comment, ply.textCursorPosition, clipboard);
                ply.textCursorPosition += cast(u32) clipboard.count;
                textChanged = true;
            }
        } else if trigger.event.kind == .TextEntered {
            // If we enter text at the very beggining of the comment with ! or ?, we consider
            // it as a move annotation.
            if ply.textCursorPosition == 0 {
                if trigger.event.text.utf8[0] == #char "!" {
                    position_move_annotation_compose(*ply.position, .Good);
                    return;
                } else if trigger.event.text.utf8[0] == #char "?" {
                    position_move_annotation_compose(*ply.position, .Mistake);
                    return;
                }
            }

            length := c_style_strlen(*trigger.event.text.utf8[0]);
            Chamber.insert_after_byte(*ply.position.comment, ply.textCursorPosition, Basic.to_string(*trigger.event.text.utf8[0], length));
            ply.textCursorPosition += cast(u32) length;
            textChanged = true;
        } else if trigger.event.kind == .KeyPressed {
            if trigger.event.key.which == .Delete {
                if ply.textCursorPosition == ply.position.comment.count then return;
                bytesToDelete : u32;
                if input_action_active(*instance.engine.input, "game.text.edit.word-modifier") {
                    bytesToDelete = Chamber.word_length_after_byte(ply.position.comment, ply.textCursorPosition);
                } else {
                    bytesToDelete = Chamber.utf8_word_length_after_byte(ply.position.comment, ply.textCursorPosition);
                }
                if bytesToDelete == 0 then return;
                Chamber.delete_after_byte(*ply.position.comment, ply.textCursorPosition, bytesToDelete);
                textChanged = true;
            } else if trigger.event.key.which == .Backspace {
                if ply.textCursorPosition == 0 {
                    position_move_annotation_compose(*ply.position, .None); // Remove move annotation if any.
                    return;
                }

                bytesToDelete : u32;
                if input_action_active(*instance.engine.input, "game.text.edit.word-modifier") {
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
                if input_action_active(*instance.engine.input, "game.text.edit.word-modifier") {
                    ply.textCursorPosition -= Chamber.word_length_before_byte(ply.position.comment, ply.textCursorPosition);
                } else {
                    ply.textCursorPosition -= Chamber.utf8_word_length_before_byte(ply.position.comment, ply.textCursorPosition);
                }
            } else if trigger.event.key.which == .Right {
                if ply.textCursorPosition == ply.position.comment.count then return;
                if input_action_active(*instance.engine.input, "game.text.edit.word-modifier") {
                    ply.textCursorPosition += Chamber.word_length_after_byte(ply.position.comment, ply.textCursorPosition);
                } else {
                    ply.textCursorPosition += Chamber.utf8_word_length_after_byte(ply.position.comment, ply.textCursorPosition);
                }
            } else if trigger.event.key.which == .Return {
                Chamber.insert_after_byte(*ply.position.comment, ply.textCursorPosition, "\n");
                ply.textCursorPosition += 1;
                textChanged = true;
            } else if trigger.event.key.which == .ControlLeft || trigger.event.key.which == .ControlRight {
                trigger.stopPropagation.* = false;
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
            textWidth, ply.charInfos = text_mesh_update(ply.commentMeshNode.primitives[0], ply.position.comment, "mainLight", instance.config.moves.selectedCommentColor, computeCharInfos = true, useMaterialCache = true);
            ply_place(ply, propagate = true);
            study_mark_unsaved_modifications(instance.currentGame.study);
        }

        send(.PlyTextCursorPositionChanged, ply);
    }, Sill.UiCallbackFlags.Text | .Key | .HoverStop | .MousePasting, ply);

    Sill.ui_check_hovered_handler(*ply.ui, (hovered : bool, relativeMousePointerPosition : Chamber.vec2, ply : *PlyEntity) -> bool {
        ray : Chamber.Ray = ---;
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

        distance := Sill.collider_distance_from(*ply.collider, ray);
        if distance > 0.0 {
            gameView := cast(*GameView) ply.parent;
            pointerStyle := ifx gameView.game.ply == ply then Crater.PointerStyle.Text else .HandPointing;
            Crater.window_pointer_style(instance.engine.window, pointerStyle);
            return true;
        }

        return false;
    }, ply);
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
    // @todo Not trying to be clever here...
    // This is considerably more stupid than what we have at the end of this function,
    // but hey, it's easier to do that since the introduction of compact moves,
    // which depend on both before and after moves.
    if propagate {
        variation_place_plies(ply.parentVariation, 0, hidden = hidden);
        return;
    }

    // @todo We have a bug which forces this set_disabled here.
    // - The ply entity is directly created with disabled = true.
    // - Then, after a frame, DisabledChanged is set to false.
    // - In this new frame, the ply adds meshes, but these are disabled = false by default.
    // - And because DisabledChanged is already false, the meshes are not updated.
    // - So we have to force DisabledChanged to update here.
    Sill.entity_set_disabled(ply, false);

    gameView := cast(*GameView) ply.parent;
    variationOffset := ply.parentVariation.depth * UiConstants.PaddingHorizontalVariation;
    maxWidth := gameView.ui.extent.width - variationOffset;
    offsetToBlack := (maxWidth + UiConstants.PaddingHorizontalSplit) / 2;
    parentVariationCollapsed := ply.parentVariation.collapsed;

    ply.ui.anchor = .TopLeft;

    // Update move text if needed.
    if ply.moveTextDirty {
        fontId := ifx ply.parentVariation.depth == 0 then "mainBold" else "mainLight";
        moveIndex := (ply.position.moveIndex + 1) / 2;
        moveIndexText := Basic.tprint("%.%", moveIndex, ifx ply.position.moveIndex % 2 then "" else ".. ");
        parentPosition := ply.parentVariation.plies[ply.index - 1].position;
        moveText := position_move_to_san(parentPosition, ply.position);
        ply.moveIndexTextWidth = text_mesh_update(ply.moveIndexMeshNode.primitives[0], moveIndexText, fontId, ply.moveColor, useMaterialCache = true);
        ply.moveTextWidth = text_mesh_update(ply.moveMeshNode.primitives[0], moveText, fontId, ply.moveColor, useMaterialCache = true);
        ply.moveTextDirty = false;
    }

    // Detect the ply location
    plyLocation := _detect_ply_location(ply);
    ply.plyLocation = plyLocation;
    ply.moveWidth = ply.moveTextWidth;
    if plyLocation.moveIndexVisible {
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

    ply.commentMeshNode.primitives[0].disabled &= ~.Application;
    Basic.peek_pointer(ply.collider.boxShapes).disabled = false;
    Sill.entity_set_disabled(ply, hidden || parentVariationCollapsed);

    // Detect whether the comment mesh will be visible or not
    if ply.flags & .DirectlyDisabled {
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
    if !(ply.flags & .DirectlyDisabled) {
        commentHeight : float;
        needCommentMeshUpdate := false;
        if !parentVariationCollapsed {
            commentHeight, needCommentMeshUpdate = justify_char_infos(*ply.charInfos, commentWidth, 0.0);
        }

        ply.commentMeshNode.transform.translation = .{};
        if plyLocation.moveVisible {
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

    if !ply.first {
        if plyLocation.moveStyle == .BlackColumn then position.x += offsetToBlack;

        if !plyLocation.moveVisible {
            ply.moveIndexMeshNode.primitives[0].disabled |= .Application;
            ply.moveMeshNode.primitives[0].disabled |= .Application;
        } else if !plyLocation.moveIndexVisible {
            ply.moveIndexMeshNode.primitives[0].disabled |= .Application;
            ply.moveMeshNode.primitives[0].disabled &= ~.Application;
            ply.moveMeshNode.transform.translation.x = 0.0;
        } else {
            ply.moveIndexMeshNode.primitives[0].disabled &= ~.Application;
            ply.moveMeshNode.primitives[0].disabled &= ~.Application;
            ply.moveMeshNode.transform.translation.x = UiConstants.PaddingHorizontalSmall + ply.moveIndexTextWidth;
        }
    } else {
        // Allow the collapsed decorum dots to be next to the black move
        if plyLocation.moveStyle == .WhiteColumn && !hidden && parentVariationCollapsed {
            position.x += offsetToBlack;
        }
    }

    if plyLocation.fitWidth {
        ply.ui.extent.width = ply.moveWidth;
        if plyLocation.commentStyle == .Inline {
            commentWidth := ifx ply.collider.boxShapes[0].disabled then 0 else ply.collider.boxShapes[0].extent.x;
            ply.ui.extent.width += commentWidth + UiConstants.PaddingCommentInline;
        }
    }

    abovePly := ply_above(ply);
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
    Chamber.round(*ply.transform.translation.xy);
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

ply_above :: (ply : *PlyEntity) -> *PlyEntity {
    abovePly : *PlyEntity = null;

    if ply.index != 0 {
        // The above ply entity is either the previous ply,
        // or the last ply of its last variation.
        abovePly = ply.parentVariation.plies[ply.index - 1];
        while abovePly.variations.count != 0 {
            lastVariation := Basic.peek(abovePly.variations);
            if lastVariation.collapsed && lastVariation.plies.count > 1 {
                abovePly = lastVariation.plies[1];
                break;
            } else {
                abovePly = Basic.peek(lastVariation.plies);
            }
        }
    } else {
        abovePly = ply.parentVariation.parentPly;
        if abovePly != null && ply.parentVariation.index > 0 {
            abovePly = Basic.peek(abovePly.variations[ply.parentVariation.index - 1].plies);
            while abovePly.variations.count != 0 {
                abovePly = Basic.peek(Basic.peek(abovePly.variations).plies);
            }
        }
        // Looks like the variation is collapsed, go get the ply representing its position.
        if abovePly != null && abovePly.flags & .Disabled {
            abovePly = abovePly.parentVariation.plies[1];
        }
    }

    return abovePly;
}

ply_effective_tag :: (ply : *PlyEntity, tagName : TagName) -> *TagValue {
    if ply == null then return null;

    // Check all plies in our variation, backwards.
    for < index : ply.index .. 0 {
        attributeValue := Hash.table_find_pointer(*ply.parentVariation.plies[index].position.tags, tagName);
        if attributeValue != null then return attributeValue;
    }

    // Not found here, maybe in the variation above?
    return ply_effective_tag(ply.parentVariation.parentPly, tagName);
}

ply_subgame_first_ply :: (ply : *PlyEntity) -> *PlyEntity {
    if ply == null then return null;

    // Check all plies in our variation, backwards.
    for < index : ply.index .. 0 {
        if ply.first then return ply;
        if ply.parentVariation.plies[index].first {
            return ply.parentVariation.plies[index];
        }
    }

    // Not found here, maybe in the variation above?
    return ply_subgame_first_ply(ply.parentVariation.parentPly);
}

#scope_file

_on_message :: (ply : *PlyEntity, message : *Message) {
    if message.kind == {
    case .PlyResultChanged;
        if message.ply == ply {
            if !ply.first {
                ply.moveTextDirty = true;
                ply_place(ply, propagate = false);
            }
        }
    case .PlyParentChanged;
        if message.ply == ply {
            ply_place(ply, propagate = false);
        }
    case .SelectedPlyChanged;
        gameView := cast(*GameView) ply.parent;
        if message.oldPly == ply || message.newPly == ply {
            _update_from_selected(ply, message.newPly == ply);
        }
    case .VariationCollapsedChanged;
        if message.variation.plies[0] == ply {
            ply_place(ply, propagate = true);
        }
    case .PositionMoveAnnotationChanged;
        if message.position == *ply.position {
            ply.moveTextDirty = true;
            ply.moveColor = annotation_color(ply.position.lastMove.annotation);
            ply_place(ply, propagate = true);
            send(.PlyTextCursorPositionChanged, ply);
            study_mark_unsaved_modifications(instance.currentGame.study);
        }
    }
}

_update_from_selected :: (ply : *PlyEntity, selected : bool) {
    gameView := cast(*GameView) ply.parent;

    for *meshNode : ply.mesh.nodes {
        color :=  ply.moveColor;
        if selected {
            if meshNode == ply.commentMeshNode {
                color = instance.config.moves.selectedCommentColor;
            } else {
                color = instance.config.moves.selectedColor;
            }
        }

        if meshNode.primitives[0].material != null {
            text_mesh_set_color(meshNode.primitives[0], color, useMaterialCache = true);
        }
    }
}

_detect_ply_location :: (ply : *PlyEntity) -> PlyLocation {
    variation := ply.parentVariation;
    color := ifx ply.position.moveIndex % 2 != 0 then Color.White else .Black;

    plyLocation : PlyLocation;
    plyLocation.moveStyle = ifx color == .White then MoveStyle.WhiteColumn else .BlackColumn;
    plyLocation.moveVisible = true;
    plyLocation.moveIndexVisible = true;

    if ply.first {
        plyLocation.commentStyle = ifx variation.depth == 0 then .Full else _detect_comment_style(ply.position.comment);
        plyLocation.preflushed = true;
        plyLocation.spaced = ply.index != 0 || variation.depth == 1;
        plyLocation.moveVisible = false;
        plyLocation.moveIndexVisible = false;
        return plyLocation;
    }

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
            plyLocation.moveStyle = .Compact;
            plyLocation.moveIndexVisible = color == .White;
        }
    } else if _is_within_compact_sequence(previousPly) {
        // Usually, after a compact sequence, we flush.
        // But if we're the last ply in a variation, we don't need to.
        plyLocation.preflushed = plyLocation.commentStyle == .Full || nextPly != null;
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
    if instance.config.moves.compactThreshold == 0 then return false, false;

    // Consider a ply being compact if it has no variations and no comment or only inline ones.
    is_compact :: inline (ply : *PlyEntity) -> bool {
        commentStyle := _detect_comment_style(ply.position.comment);
        if ply.variations.count != 0 || (commentStyle != .None && commentStyle != .Inline) then return false;
        return true;
    }

    if ply.first || !is_compact(ply) then return false, false;

    compactPlyCount := 1;
    for <i : ply.index - 1 .. 1 {
        previousPly := ply.parentVariation.plies[i];
        if !is_compact(previousPly) break;
        compactPlyCount += 1;
        if compactPlyCount >= instance.config.moves.compactThreshold then return true, false;
    }

    firstInSequence := compactPlyCount == 1;

    for i : ply.index + 1 .. ply.parentVariation.plies.count - 1 {
        nextPly := ply.parentVariation.plies[i];
        if !is_compact(nextPly) then break;
        compactPlyCount += 1;
        if compactPlyCount >= instance.config.moves.compactThreshold then return true, firstInSequence;
    }

    return compactPlyCount >= instance.config.moves.compactThreshold, firstInSequence;
}

_is_style_spaced_after :: (commentStyle : CommentStyle) -> bool {
    return commentStyle == .Half || commentStyle == .SidedFull || commentStyle == .Full;
}

_place_comment_from_char_infos :: (ply : *PlyEntity) {
    minBounds, maxBounds := place_from_char_infos(ply.commentMeshNode.primitives[0], *ply.charInfos, .TopLeft);

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

    ply.textCursorPosition = byte_index_from_mouse_position(relativePosition, ply.position.comment, *ply.charInfos);
    send(.PlyTextCursorPositionChanged, ply);
}
