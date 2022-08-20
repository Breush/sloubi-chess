ButtonBar :: struct {
    backButton : *ButtonEntity;
    analysisButton : *ButtonEntity;
    saveButton : *ButtonEntity;
}

ButtonEntity :: struct {
    using #as entity : Sill.Entity;
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
}

button_bar_init :: () {
    using *instance.buttonBar;

    // Back to home button.
    backButton = _make_button(ForkAwesome.Reply);

    Sill.ui_on_trigger(*backButton.ui, (trigger : Sill.UiTrigger, backButton : *ButtonEntity) {
        // @fixme Have a "not-saved changes" dialog.
        button_bar_show(false);
        game_cleanup(*instance.game);
        file_select_show(".pgn", (selectedFile : string) {
            load_pgn(selectedFile);
        });
    }, .Click, backButton);

    // Open lichess analysis button
    analysisButton = _make_button(ForkAwesome.Laptop);

    Sill.ui_on_trigger(*analysisButton.ui, (trigger : Sill.UiTrigger, analysisButton : *ButtonEntity) {
        Basic.log("Opening analysis.");
        Chamber.os_open_browser(Basic.tprint("%1%2", instance.config.analysis.externalSite, position_to_fen(instance.game.ply.position)));
    }, .Click, analysisButton);

    // Save button
    // @fixme Have user feedback that we saved.
    saveButton = _make_button(ForkAwesome.FloppyO);

    Sill.ui_on_trigger(*saveButton.ui, (trigger : Sill.UiTrigger, saveButton : *ButtonEntity) {
        save_pgn(instance.game.pgnFileName);
    }, .Click, saveButton);

    button_bar_reflow();
}

button_bar_reflow :: () {
    using *instance.buttonBar;

    extent := Crater.window_get_extent(instance.engine.window);

    // @fixme Should UI widgets become components?
    // @fixme Missing hlayout?
    backButton.transform.translation.x = extent.width / 2 - 5 * backButton.ui.extent.width / 2 - 5;
    backButton.transform.translation.y = extent.height / 2 - backButton.ui.extent.height / 2;
    Sill.transform_commit(*backButton.transform);

    analysisButton.transform.translation.x = extent.width / 2 - 3 * analysisButton.ui.extent.width / 2;
    analysisButton.transform.translation.y = extent.height / 2 - analysisButton.ui.extent.height / 2;
    Sill.transform_commit(*analysisButton.transform);

    saveButton.transform.translation.x = extent.width / 2 - saveButton.ui.extent.width / 2;
    saveButton.transform.translation.y = extent.height / 2 - saveButton.ui.extent.height / 2;
    Sill.transform_commit(*saveButton.transform);
}

button_bar_show :: (visible := true) {
    using *instance.buttonBar;

    _button_show(backButton, visible);
    _button_show(analysisButton, visible);
    _button_show(saveButton, visible);
}

#scope_file

_make_button :: (text : string) -> *ButtonEntity {
    button := SillMeta.create_button_entity(instance.engine);
    button.ui.extent.width = 30; // @todo Completely arbitrary...
    button.ui.extent.height = UiConstants.HeightLine;

    backgroundNode := Basic.array_add(*button.mesh.nodes);
    backgroundMesh := create_rect_mesh(button.ui.extent.width, button.ui.extent.height, 1);
    backgroundMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set(backgroundMesh.material, "color", instance.config.env.secondaryBackgroundColor);
    Magma.mesh_commit_vertices(backgroundMesh);
    Basic.array_add(*backgroundNode.primitives, backgroundMesh);

    textNode := Basic.array_add(*button.mesh.nodes);
    textMesh := create_text_mesh();
    charInfos := text_mesh_update(textMesh, text, "mainLight", instance.config.env.textColor);
    defer Basic.array_free(charInfos);
    textNode.transform.translation.x = -Math.floor(Basic.peek_pointer(charInfos).effective.xEnd / 2 + 0.5);
    textNode.transform.translation.y = -8; // @todo Hardcoded offset... We should know the max glyph height instead.
    Basic.array_add(*textNode.primitives, textMesh);

    Sill.ui_on_update(*button.ui, (update : Sill.UiUpdate, userData : *void) {
        <<update.stopPropagation = true;
    }, .Hover);

    Sill.ui_on_trigger(*button.ui, (trigger : Sill.UiTrigger, button : *ButtonEntity) {
        <<trigger.stopPropagation = true;

        if trigger.flags & .Hover {
            Magma.material_set(button.mesh.nodes[0].primitives[0].material, "color", instance.config.env.selectionBackgroundColor);
            Crater.window_pointer_style(instance.engine.window, .HandPointer);
        } else if trigger.flags & .NoHover {
            Magma.material_set(button.mesh.nodes[0].primitives[0].material, "color", instance.config.env.secondaryBackgroundColor);
            Crater.window_pointer_style(instance.engine.window, .Default);
        }
    }, Sill.UiCallbackFlags.Click | .Hover | .NoHover, button);

    button.transform.translation.z = -10; // Needed to be selectable in front of things.

    _button_show(button, false);
    return button;
}

#scope_file

_button_show :: (button : *ButtonEntity, visible : bool) {
    button.ui.disabled = !visible;
    button.mesh.nodes[0].primitives[0].disabled = !visible;
    button.mesh.nodes[1].primitives[0].disabled = !visible;
}
