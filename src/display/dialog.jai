DialogEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    content : DialogContentEntity;

    anchor : DialogAnchor;
    callback : #type (dialog : *DialogEntity, choiceIndex : u32, userData : *void);
    userData : *void;
    cancelChoiceIndex : u32;
}

DialogContentEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage
    // @todo Forgetting this annotation was a lot hard to debug.
    // There was a double free of the children because
    // 1/ DialogContentEntity was deleted through DialogEntity with destroyChildren = true
    // 2/ DialogContentEntity was deleted through SillMeta.destroy_dialog_entity because content : DialogContentEntity is inlined
    // => Have a unit test?

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    elementInfos : [..]ElementInfo;

    choiceIndexOffset : u32;

    ElementInfo :: struct {
        entities : [2]*Sill.Entity;
        kind : DialogFormElement.Kind;
        changed : bool;
        value : string;
    }

    on_cleanup :: (using this : *DialogContentEntity) {
        Basic.array_reset(*elementInfos);
    }
}

DialogFormData :: struct($T : Type = void) {
    anchor := DialogAnchor.Full;
    elements : []DialogFormElement;
    choices : []string;
    cancelChoiceIndex : u32 = 0xFFFF_FFFF;
    callback : #type (dialog : *DialogEntity, choiceIndex : u32, userData : *T);
    userData : *T;
    mode := Mode.Dialog;
}

DialogFormElement :: struct {
    kind : Kind;
    text : string;
    value : string;
    anchor : Chamber.Anchor;
    callback : #type (data : *void);
    callbackData : *void;

    Kind :: enum u8 {
        Label;      // text, anchor
        TextEntry;  // text, value
        Button;     // text, callback, callbackData
    }
}

DialogAnchor :: enum {
    Full :: 0;
    Half;
}

dialog_form_create :: (data : DialogFormData) {
    dialog := SillMeta.create_dialog_entity(instance.engine);
    Sill.listener_on_message(*dialog.listener, _on_message);
    dialog.anchor = data.anchor;
    dialog.callback = xx data.callback;
    dialog.userData = data.userData;
    dialog.cancelChoiceIndex = data.cancelChoiceIndex;

    Sill.ui_set_focused(*dialog.ui, false);

    // In front of everything else, and grab all events.
    dialog.transform.translation.z = UiConstants.DepthDialog;
    Sill.ui_on_trigger(*dialog.ui, (trigger : Sill.UiTrigger, userData : *void) {
        trigger.stopPropagation.* = true;
    });

    // Full background.
    backgroundMesh := Sill.mesh_make_primitive(*dialog.mesh);
    create_rect_mesh(depth = UiConstants.DepthDialogBackground, existingMesh = backgroundMesh);
    backgroundMesh.material = Magma.create_material(instance.shaders.translucentMonochrome);
    Magma.material_set_color(backgroundMesh.material, "color", Chamber.make_vec4(instance.config.env.backgroundColor, 0.99));

    _content_create(*dialog.content, data);
    Sill.entity_set_parent(*dialog.content, dialog);

    _reflow(dialog);
    mode_push(data.mode, dialog);
}

DialogData :: struct($T : Type = void) {
    mainText : string;
    text : string;
    choices : []string;
    cancelChoiceIndex : u32;
    callback : #type (dialog : *DialogEntity, choiceIndex : u32, userData : *T);
    userData : *T;

    UserDataType :: T;
}

dialog_create :: (using data : DialogData) {
    elements : [..]DialogFormElement;
    elements.allocator = Basic.temp;
    Basic.array_add(*elements, .{ kind = .Label, text = data.mainText, value = "mainBold" }, .{ kind = .Label, text = data.text, value = "mainLight" });

    formData : DialogFormData(data.UserDataType);
    formData.anchor = .Full;
    formData.elements = elements;
    formData.choices = data.choices;
    formData.cancelChoiceIndex = data.cancelChoiceIndex;
    formData.callback = data.callback;
    formData.userData = data.userData;

    dialog_form_create(formData);
}

dialog_close :: (dialog : *DialogEntity) {
    Basic.array_reset(*dialog.content.elementInfos);
    Sill.destroy_entity(dialog, destroyChildren = true);
    mode_pop();
}

dialog_cancel :: (dialog : *DialogEntity) {
    if dialog.cancelChoiceIndex == 0xFFFF_FFFF then return;
    dialog.callback(dialog, dialog.cancelChoiceIndex, dialog.userData);
}

#scope_file

_on_message :: (using dialog : *DialogEntity, message : *Message) {
    if message.kind == .SystemReflow {
        _reflow(dialog);
    }
}

_content_create :: (using dialogContent : *DialogContentEntity, data : DialogFormData) {
    Basic.array_resize(*dialogContent.elementInfos, data.elements.count);

    backgroundMesh, backgroundMeshNode := Sill.mesh_make_primitive(*dialogContent.mesh);
    create_rect_mesh(depth = UiConstants.DepthDialogContentBackground, anchor = .Top, existingMesh = backgroundMesh);
    backgroundMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set_color(backgroundMesh.material, "color", instance.config.env.backgroundColor);

    // Elements.
    yOffset := UiConstants.PaddingVerticalMedium;
    dialogWidth : float;
    for element, elementIndex : data.elements {
        if #complete element.kind == {
        case .Label;
            label := create_label(element.text, style = element.value, anchor = element.anchor);
            label.transform.translation.y = yOffset + label.ui.extent.height / 2.0;
            label.transform.translation.z = UiConstants.DepthDialogLabel;
            Sill.entity_set_parent(label, dialogContent);
            dialogContent.elementInfos[elementIndex].entities[0] = label;

            dialogWidth = Basic.max(dialogWidth, label.ui.extent.width);
            yOffset += label.ui.extent.height + UiConstants.PaddingVerticalMedium;
        case .TextEntry;
            textEntry := create_text_entry(element.value);
            textEntry.transform.translation.y = yOffset + textEntry.ui.extent.height / 2.0;
            textEntry.transform.translation.z = UiConstants.DepthDialogTextEntry;
            textEntry.callback = xx _on_text_entry_changed;
            textEntry.userData = *dialogContent.elementInfos[elementIndex];
            dialogContent.elementInfos[elementIndex].value = textEntry.text;
            Sill.entity_set_parent(textEntry, dialogContent);
            dialogContent.elementInfos[elementIndex].entities[0] = textEntry;

            label := create_label(element.text, style = "mainLight", anchor = .Right);
            label.transform.translation.x = -textEntry.ui.extent.width / 2.0 - UiConstants.PaddingHorizontalMedium;
            label.transform.translation.y = yOffset + label.ui.extent.height / 2.0;
            label.transform.translation.z = UiConstants.DepthDialogTextEntryLabel;
            Sill.entity_set_parent(label, dialogContent);
            dialogContent.elementInfos[elementIndex].entities[1] = label;

            dialogWidth = Basic.max(dialogWidth, 2 * (label.ui.extent.width + UiConstants.PaddingHorizontalMedium) + textEntry.ui.extent.width);
            yOffset += UiConstants.HeightLine + UiConstants.PaddingVerticalMedium;
        case .Button;
            button := SillMeta.create_ui_button_entity(instance.engine);
            Sill.entity_set_parent(button, dialogContent);
            button.ui.extent.width = UiConstants.WidthButtonDialog;
            button.ui.extent.height = UiConstants.HeightButtonDialog;
            button.transform.translation.y = yOffset + button.ui.extent.height / 2.0;
            button.transform.translation.z = UiConstants.DepthDialogButton;

            button.button.text = element.text;
            button.button.callback = element.callback;
            button_commit(*button.button);

            Magma.material_set_color(button.mesh.nodes[0].primitives[0].material, "color", instance.config.env.contrastColor);

            yOffset += button.ui.extent.height + UiConstants.PaddingVerticalMedium;
        }
    }

    for element, elementIndex : data.elements {
        if element.anchor == .Left {
            for entity : dialogContent.elementInfos[elementIndex].entities {
                if entity == null then break;
                transform := Sill.entity_get_component(entity, Sill.TransformComponent);
                transform.translation.x -= dialogWidth / 2.0;
                Chamber.round(*transform.translation);
            }
        }
    }

    dialogWidth += 2.0 * UiConstants.PaddingHorizontalMedium;
    yOffset += UiConstants.PaddingVerticalMedium;

    // Buttons.
    dialogContent.choiceIndexOffset = cast(u32) dialogContent.children.count;
    for choice, choiceIndex : data.choices {
        button := SillMeta.create_ui_button_entity(instance.engine);
        Sill.entity_set_parent(button, dialogContent);
        button.ui.extent.width = UiConstants.WidthButtonDialog;
        button.ui.extent.height = UiConstants.HeightButtonDialog;
        button.transform.translation.x = dialogWidth / 2.0 - Math.floor((0.5 + choiceIndex) * (UiConstants.WidthButtonDialog + 1) + 0.5);
        button.transform.translation.y = yOffset + UiConstants.HeightButtonDialog / 2.0;
        button.transform.translation.z = UiConstants.DepthDialogButton;

        button.button.text = choice;
        button.button.callback = xx (button : *UiButtonEntity) {
            dialogContent := cast(*DialogContentEntity) button.parent;
            dialog := cast(*DialogEntity) dialogContent.parent;
            found, choiceIndex := Basic.array_find(dialogContent.children, button);
            choiceIndex -= dialogContent.choiceIndexOffset;
            if found then dialog.callback(dialog, cast(u32) choiceIndex, dialog.userData);
        };
        button.button.callbackData = button;
        button_commit(*button.button); // @todo Unify, as Label and TextEntry don't work like that...
    }
    yOffset += UiConstants.HeightButtonDialog;

    dialogContent.ui.extent.width = dialogWidth;
    dialogContent.ui.extent.height = yOffset;

    mesh.nodes[0].transform.scaling.xy = dialogContent.ui.extent;
}

_reflow :: (using dialog : *DialogEntity) {
    extent := Crater.window_get_extent(instance.engine.window, Chamber.vec2);

    if anchor == .Half {
        // Vertical layout
        if (extent.height > extent.width) {
            extent.height = extent.height / 2;
            transform.translation.y = Math.floor(extent.height / 2.0 + 0.5);
        } else {
            extent.width = extent.width / 2;
            transform.translation.x = Math.floor(extent.width / 2.0 + 0.5);
        }
    } else {
        transform.translation.x = 0.0;
    }

    ui.extent = extent;
    mesh.nodes[0].transform.scaling.xy = ui.extent;
    content.transform.translation.y = -Math.floor(content.ui.extent.y / 2.0 + 0.5);
    Sill.transform_commit(*dialog.transform);
}

_on_text_entry_changed :: (textEntry : *TextEntryEntity, elementInfo : *DialogContentEntity.ElementInfo) {
    elementInfo.changed = true;
    elementInfo.value = textEntry.text;
}
