DialogEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
    button : ButtonComponent;

    callback : #type (dialog : *DialogEntity, choiceIndex : u32, userData : *void);
    userData : *void;
}

dialog_create :: (mainText : string, text : string, choices : []string, callback : #type (dialog : *DialogEntity, choiceIndex : u32, userData : *T), userData : *$T) {
    dialog := SillMeta.create_dialog_entity(instance.engine);
    dialog.callback = xx callback;
    dialog.userData = userData;

    Sill.ui_set_focused(*dialog.ui, false);

    // In front of everything else, and grab all events.
    dialog.transform.translation.z = -20.0;
    Sill.ui_on_trigger(*dialog.ui, (trigger : Sill.UiTrigger, userDara : *void) {
        <<trigger.stopPropagation = true;
    });

    HeightDialog :: UiConstants.HeightButtonDialog + 2 * UiConstants.HeightLine + UiConstants.PaddingVertical;

    // Background.
    fullBackgroundMesh := Sill.mesh_make_primitive(*dialog.mesh);
    create_rect_mesh(depth = 2, existingMesh = fullBackgroundMesh);
    fullBackgroundMesh.material = Magma.create_material(instance.shaders.translucentMonochrome);
    Magma.material_set_color(fullBackgroundMesh.material, "color", Chamber.vec4.{0.0, 0.0, 0.0, 0.98});

    backgroundMesh, backgroundMeshNode := Sill.mesh_make_primitive(*dialog.mesh);
    create_rect_mesh(depth = 1, existingMesh = backgroundMesh);
    backgroundMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set_color(backgroundMesh.material, "color", instance.config.env.backgroundColor);

    // Text.
    mainTextMesh, mainTextMeshNode := Sill.mesh_make_primitive(*dialog.mesh);
    create_text_mesh(existingMesh = mainTextMesh);
    mainTextWidth := text_mesh_update(mainTextMesh, mainText, "mainBold", instance.config.env.textColor, anchor = .Center);
    mainTextMeshNode.transform.translation.y = -HeightDialog / 2.0 + UiConstants.PaddingVertical / 2.0;

    textMesh, textMeshNode := Sill.mesh_make_primitive(*dialog.mesh);
    create_text_mesh(existingMesh = textMesh);
    textWidth := text_mesh_update(textMesh, text, "mainLight", instance.config.env.textColor, anchor = .Center);
    textMeshNode.transform.translation.y = -HeightDialog / 2.0 + UiConstants.PaddingVertical / 2.0 + UiConstants.HeightLine;

    maxTextWidth := Basic.max(mainTextWidth, textWidth);
    backgroundMeshNode.transform.scaling.xy = .{maxTextWidth + 2 * UiConstants.PaddingHorizontal, HeightDialog};

    // Buttons.
    for choice, choiceIndex : choices {
        button := SillMeta.create_ui_button_entity(instance.engine);
        Sill.entity_set_parent(button, dialog);
        button.ui.extent.width = UiConstants.WidthButtonDialog;
        button.ui.extent.height = UiConstants.HeightButtonDialog;
        button.transform.translation.x = Math.floor(maxTextWidth / 2.0 - choiceIndex * (UiConstants.WidthButtonDialog + 1.0) + 0.5);
        button.transform.translation.y = HeightDialog / 2.0 - UiConstants.HeightButtonDialog / 2.0;
        button.transform.translation.z = -5;

        button.button.text = choice;
        button_commit(*button.button);

        Magma.material_set_color(button.mesh.nodes[0].primitives[0].material, "color", instance.config.env.contrastColor);

        Sill.ui_on_trigger(*button.ui, (trigger : Sill.UiTrigger, button : *UiButtonEntity) {
            if trigger.flags & .HoverStart || trigger.flags & .HoverStop {
                hovered := cast(bool) (trigger.flags & .HoverStart);
                if button.flags & .Destroyed then return;
                color := ifx hovered then instance.config.env.hoverColor else instance.config.env.contrastColor;
                Magma.material_set_color(button.mesh.nodes[0].primitives[0].material, "color", color);
            } else {
                dialog := cast(*DialogEntity) button.parent;
                found, choiceIndex := Basic.array_find(dialog.children, button);
                if found then dialog.callback(dialog, cast(u32) choiceIndex, dialog.userData);
            }
        }, Sill.UiCallbackFlags.HoverStart | .HoverStop | .ClickStop, button);
    }

    Sill.transform_commit(*dialog.transform);
    _reflow(dialog);
}

dialog_close :: (dialog : *DialogEntity) {
    Sill.destroy_entity(dialog, destroyChildren = true);
}

#scope_file

_reflow :: (using dialog : *DialogEntity) {
    extent := Crater.window_get_extent(instance.engine.window, Chamber.vec2);
    ui.extent = extent;

    mesh.nodes[0].transform.scaling.xy = extent;
    Sill.mesh_commit_nodes(*mesh);
}
