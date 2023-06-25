TextEntryEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    // @todo Have a component or something for editable text?
    text : string;
    charInfos : CharInfos;
    textCursorByteIndex : u32;

    callback : #type (textEntry : *TextEntryEntity, userData : *void);
    userData : *void;

    on_cleanup :: (using this : *TextEntryEntity) {
        Basic.free(text);
        Basic.array_free(charInfos.infos);
    }
}

create_text_entry :: (defaultText := "") -> *TextEntryEntity {
    textEntry := SillMeta.create_text_entry_entity(instance.engine);
    textEntry.text = Basic.copy_string(defaultText);
    textEntry.textCursorByteIndex = 0;

    // Text.
    textMesh, textMeshNode := Sill.mesh_make_primitive(*textEntry.mesh);
    create_text_mesh(existingMesh = textMesh);

    // Background.
    backgroundMesh := Sill.mesh_make_primitive(*textEntry.mesh);
    create_rect_mesh(UiConstants.WidthTextEntry, UiConstants.HeightLine, depth = 1, existingMesh = backgroundMesh);
    backgroundMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set_color(backgroundMesh.material, "color", instance.config.env.contrastColor);

    // Text cursor.
    textCursorMesh, textCursorMeshNode := Sill.mesh_make_primitive(*textEntry.mesh, parent = 0);
    create_rect_mesh(1, UiConstants.HeightLine, depth = -1, anchor = .Left, existingMesh = textCursorMesh);
    textCursorMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set_color(textCursorMesh.material, "color", instance.config.env.textColor);
    textCursorMesh.disabled |= .Application;

    textEntry.ui.extent.height = UiConstants.HeightLine;
    textEntry.ui.extent.width = UiConstants.WidthTextEntry;

    Sill.ui_on_trigger(*textEntry.ui, (trigger : Sill.UiTrigger, textEntry : *TextEntryEntity) {
        trigger.stopPropagation.* = true;
        textChanged := false;

        if trigger.flags & .HoverStart || trigger.flags & .HoverStop {
            hovered := cast(bool) (trigger.flags & .HoverStart);
            if textEntry.flags & .Destroyed then return;
            color := ifx hovered then instance.config.env.hoverColor else instance.config.env.contrastColor;
            Magma.material_set_color(textEntry.mesh.nodes[1].primitives[0].material, "color", color);
            Crater.window_pointer_style(instance.engine.window, ifx hovered then Crater.PointerStyle.Text else .Default);
        } else if trigger.flags & .ClickStop {
            ui_set_focused(*textEntry.ui);
            _set_text_cursor_position_from_mouse(textEntry);
        } else if trigger.flags & .FocusStart {
            textEntry.mesh.nodes[2].primitives[0].disabled &= ~.Application;
        } else if trigger.flags & .FocusStop {
            textEntry.mesh.nodes[2].primitives[0].disabled |= .Application;
        } else if trigger.flags & .Text {
            length := c_style_strlen(*trigger.event.text.utf8[0]);
            Chamber.insert_after_byte(*textEntry.text, textEntry.textCursorByteIndex, Basic.to_string(*trigger.event.text.utf8[0], length));
            textEntry.textCursorByteIndex += cast(u32) length;
            textChanged = true;
        } else if trigger.event.key.which == .Delete {
            if textEntry.textCursorByteIndex == textEntry.text.count then return;
            bytesToDelete : u32;
            if input_action_active(*instance.engine.input, "game.text.edit.word-modifier") {
                bytesToDelete = Chamber.word_length_after_byte(textEntry.text, textEntry.textCursorByteIndex);
            } else {
                bytesToDelete = Chamber.utf8_word_length_after_byte(textEntry.text, textEntry.textCursorByteIndex);
            }
            if bytesToDelete == 0 then return;
            Chamber.delete_after_byte(*textEntry.text, textEntry.textCursorByteIndex, bytesToDelete);
            textChanged = true;
        } else if trigger.event.key.which == .Backspace {
            if textEntry.textCursorByteIndex == 0 then return;
            bytesToDelete : u32;
            if input_action_active(*instance.engine.input, "game.text.edit.word-modifier") {
                bytesToDelete = Chamber.word_length_before_byte(textEntry.text, textEntry.textCursorByteIndex);
            } else {
                bytesToDelete = Chamber.utf8_word_length_before_byte(textEntry.text, textEntry.textCursorByteIndex);
            }
            if bytesToDelete == 0 then return;
            Chamber.delete_before_byte(*textEntry.text, textEntry.textCursorByteIndex, bytesToDelete);
            textEntry.textCursorByteIndex -= bytesToDelete;
            textChanged = true;
        } else if trigger.event.key.which == .Left {
            if textEntry.textCursorByteIndex == 0 then return;
            if input_action_active(*instance.engine.input, "game.text.edit.word-modifier") {
                textEntry.textCursorByteIndex -= Chamber.word_length_before_byte(textEntry.text, textEntry.textCursorByteIndex);
            } else {
                textEntry.textCursorByteIndex -= Chamber.utf8_word_length_before_byte(textEntry.text, textEntry.textCursorByteIndex);
            }
            _update_from_text_cursor(textEntry);
        } else if trigger.event.key.which == .Right {
            if textEntry.textCursorByteIndex == textEntry.text.count then return;
            if input_action_active(*instance.engine.input, "game.text.edit.word-modifier") {
                textEntry.textCursorByteIndex += Chamber.word_length_after_byte(textEntry.text, textEntry.textCursorByteIndex);
            } else {
                textEntry.textCursorByteIndex += Chamber.utf8_word_length_after_byte(textEntry.text, textEntry.textCursorByteIndex);
            }
            _update_from_text_cursor(textEntry);
        }

        if textChanged {
            _update_text(textEntry);
            _update_from_text_cursor(textEntry);
            if textEntry.callback != null {
                textEntry.callback(textEntry, textEntry.userData);
            }
        }
    }, Sill.UiCallbackFlags.HoverStart | .HoverStop | .FocusStart | .FocusStop | .ClickStop | .Text | .Key, textEntry);

    _update_text(textEntry);
    _update_from_text_cursor(textEntry);

    return textEntry;
}

#scope_file

_update_text :: (textEntry : *TextEntryEntity) {
    textMesh := textEntry.mesh.nodes[0].primitives[0];
    Basic.array_free(textEntry.charInfos.infos);
    _, textEntry.charInfos = text_mesh_update(textMesh, textEntry.text, "mainLight", instance.config.env.textColor, anchor = .Left, computeCharInfos = true);
}

_update_from_text_cursor :: (textEntry : *TextEntryEntity) {
    textCursorOffset : float32;
    textWidth : float32;

    if textEntry.charInfos.infos.count > 0 {
        if textEntry.textCursorByteIndex == 0 {
            textCursorOffset = Math.floor(textEntry.charInfos.infos[0].effective.xStart + 0.5);
        } else {
            byteIndex : u32;
            for *charInfo : textEntry.charInfos.infos {
                byteIndex += Chamber.utf8_word_length_after_byte(textEntry.text, byteIndex);
                if textEntry.textCursorByteIndex <= byteIndex {
                    textCursorOffset = Math.floor(charInfo.effective.xEndWithAdvance + 0.5);
                    break;
                }
            }
        }
        textWidth = Basic.peek(textEntry.charInfos.infos).effective.xEndWithAdvance;
    }

    textMeshNode := *textEntry.mesh.nodes[0];
    textCursorMeshNode := *textEntry.mesh.nodes[2];
    textCursorMeshNode.transform.translation.x = textCursorOffset;

    // If the text is not bigger than the text entry, make sure it's centered.
    if textWidth < UiConstants.WidthTextEntryWithoutPadding {
        textMeshNode.transform.translation.x = Math.floor(-textWidth / 2.0 + 0.5);
        Magma.material_set(textMeshNode.primitives[0].material, "scissor", Chamber.vec4.{});
        Sill.mesh_commit_nodes(*textEntry.mesh);
        return;
    }

    // If the text, which is bigger than the text entry, is not filling the text entry, make sure it is.
    if textMeshNode.transform.translation.x + UiConstants.WidthTextEntryWithoutPadding / 2.0 > 0 {
        textMeshNode.transform.translation.x = -UiConstants.WidthTextEntryWithoutPadding / 2.0;
    } else if textMeshNode.transform.translation.x - UiConstants.WidthTextEntryWithoutPadding / 2.0 < -textWidth {
        textMeshNode.transform.translation.x = -UiConstants.WidthTextEntryWithoutPadding / 2.0 - textWidth + UiConstants.WidthTextEntryWithoutPadding;
    }

    // If the text cursor is not visible, move the text to the left or right to make it visible.
    currentTextOffset := -textMeshNode.transform.translation.x - UiConstants.WidthTextEntryWithoutPadding / 2.0;
    if textCursorOffset - currentTextOffset < 0 {
        textMeshNode.transform.translation.x = -UiConstants.WidthTextEntryWithoutPadding / 2.0 - textCursorOffset;
    } else if textCursorOffset - currentTextOffset > UiConstants.WidthTextEntryWithoutPadding {
        textMeshNode.transform.translation.x = -UiConstants.WidthTextEntryWithoutPadding / 2.0 - textCursorOffset + UiConstants.WidthTextEntryWithoutPadding;
    }

    // If the text is bigger than the text entry, ensure it fills the text entry.
    scissorLeftBoundary := -textMeshNode.transform.translation.x - UiConstants.WidthTextEntryWithoutPadding / 2.0;
    Magma.material_set(textMeshNode.primitives[0].material, "scissor", Chamber.vec4.{scissorLeftBoundary, 0.0, scissorLeftBoundary + UiConstants.WidthTextEntryWithoutPadding, 0.0});
    Sill.mesh_commit_nodes(*textEntry.mesh);
}

_set_text_cursor_position_from_mouse :: (textEntry : *TextEntryEntity) {
    relativePosition := Sill.ui_relative_mouse_pointer_position(*textEntry.ui);
    relativePosition.y = 0.0; // @note We don't care, as we are on one line.

    if relativePosition.std.x < -UiConstants.WidthTextEntryWithoutPadding / 2.0 {
        textEntry.textCursorByteIndex = 0;
    } else if relativePosition.std.x > UiConstants.WidthTextEntryWithoutPadding / 2.0 {
        textEntry.textCursorByteIndex = cast(u32) textEntry.text.count;
    } else {
        relativePosition.std.x -= textEntry.mesh.nodes[0].transform.translation.x;
        textEntry.textCursorByteIndex = byte_index_from_mouse_position(relativePosition, textEntry.text, *textEntry.charInfos);
    }

    _update_from_text_cursor(textEntry);
}
