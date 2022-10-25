ButtonBarEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;

    backButton : ButtonEntity;
    analysisButton : ButtonEntity;
    saveButton : ButtonEntity;
}

ButtonEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
}

button_bar_create :: () -> *ButtonBarEntity {
    using buttonBar := SillMeta.create_button_bar_entity(instance.engine);
    Sill.listener_on_message(*listener, _on_message);

    // Back to home button
    _make_button(*backButton, ForkAwesome.Reply);
    Sill.entity_set_parent(*backButton, buttonBar);
    backButton.transform.translation.x = -backButton.ui.extent.width - 5;

    Sill.ui_on_trigger(*backButton.ui, (trigger : Sill.UiTrigger, backButton : *ButtonEntity) {
        // @fixme Have a "not-saved changes" dialog.
        game_cleanup(*instance.game);
        file_select_show(".pgn", (selectedFile : string) {
            if load_pgn(selectedFile) {
                game_show(*instance.game);
            }
        });
    }, .ClickStop, *backButton);

    // Open lichess analysis button
    _make_button(*analysisButton, ForkAwesome.Laptop);
    Sill.entity_set_parent(*analysisButton, buttonBar);

    Sill.ui_on_trigger(*analysisButton.ui, (trigger : Sill.UiTrigger, analysisButton : *ButtonEntity) {
        Basic.log("Opening analysis.");
        Chamber.os_open_browser(Basic.tprint("%1%2", instance.config.analysis.externalSite, position_to_fen(instance.game.ply.position)));
    }, .ClickStop, *analysisButton);

    // Save button
    // @fixme Have user feedback that we saved.
    _make_button(*saveButton, ForkAwesome.FloppyO);
    Sill.entity_set_parent(*saveButton, buttonBar);
    saveButton.transform.translation.x = saveButton.ui.extent.width;

    Sill.ui_on_trigger(*saveButton.ui, (trigger : Sill.UiTrigger, saveButton : *ButtonEntity) {
        save_pgn(instance.game.pgnFileName);
    }, .ClickStop, *saveButton);

    return buttonBar;
}

#scope_file

_on_message :: (buttonBar : *ButtonBarEntity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _reflow(buttonBar);
    case .ModeGameStarted;
        _show(true);
    case .ModeGameStopped;
        _show(false);
    }
}

_show :: (visible := true) {
    using instance.buttonBar;

    _button_show(*backButton, visible);
    _button_show(*analysisButton, visible);
    _button_show(*saveButton, visible);
}

_reflow :: (using buttonBar : *ButtonBarEntity) {
    extent := Crater.window_get_extent(instance.engine.window);

    transform.translation.x = extent.width / 2.0 - 3 * backButton.ui.extent.width / 2 - 5;
    transform.translation.y = extent.height / 2 - backButton.ui.extent.height / 2;
    Sill.transform_commit(*transform);
}

_make_button :: (button : *ButtonEntity, text : string) -> *ButtonEntity {
    button.ui.extent.width = 30; // @todo Completely arbitrary...
    button.ui.extent.height = UiConstants.HeightLine;

    backgroundNode := Basic.array_add(*button.mesh.nodes);
    backgroundMesh := create_rect_mesh(button.ui.extent.width, button.ui.extent.height, 1);
    backgroundMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set(backgroundMesh.material, "color", instance.config.env.buttonBackgroundColor);
    Magma.mesh_commit_vertices(backgroundMesh);
    Basic.array_add(*backgroundNode.primitives, backgroundMesh);

    textNode := Basic.array_add(*button.mesh.nodes);
    textMesh := create_text_mesh();
    charInfos, textWidth := text_mesh_update(textMesh, text, "mainLight", instance.config.env.textColor, computeCharInfos = false);
    textNode.transform.translation.x = -Math.floor(textWidth / 2 + 0.5);
    textNode.transform.translation.y = -8; // @todo Hardcoded offset... We should know the max glyph height instead.
    Basic.array_add(*textNode.primitives, textMesh);

    Sill.ui_on_trigger(*button.ui, (trigger : Sill.UiTrigger, button : *ButtonEntity) {
        <<trigger.stopPropagation = true;

        if trigger.flags & .HoverStart {
            Magma.material_set(button.mesh.nodes[0].primitives[0].material, "color", instance.config.env.selectedButtonBackgroundColor);
            Crater.window_pointer_style(instance.engine.window, .HandPointing);
        } else if trigger.flags & .HoverStop {
            Magma.material_set(button.mesh.nodes[0].primitives[0].material, "color", instance.config.env.buttonBackgroundColor);
            Crater.window_pointer_style(instance.engine.window, .Default);
        }
    }, Sill.UiCallbackFlags.ClickStop | .HoverStart | .Hovering | .HoverStop, button);

    button.transform.translation.z = -10; // Needed to be selectable in front of things.

    _button_show(button, false);
    return button;
}

#scope_file

_button_show :: (button : *ButtonEntity, visible : bool) {
    Sill.entity_set_disabled(button, !visible);
}
