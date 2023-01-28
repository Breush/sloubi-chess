ButtonComponent :: struct {
    using #as component : Sill.Component;

    transform : *Sill.TransformComponent;
    mesh : *Sill.MeshComponent;
    ui : *Sill.UiComponent;

    // Editable at any time.
    interactive := true;

    // Editable before commit.
    text : string;
    tooltipText : string;
    tooltipSide : Chamber.Anchor;

    // Set by component after commit.
    meshNode : *Sill.MeshNode;
    tooltipMeshNode : *Sill.MeshNode;
    tooltipExtent : Chamber.vec2;
}

component_init :: (using iButton : *ButtonComponent) {}
component_cleanup :: (using iButton : *ButtonComponent) {}
component_update :: (using iButton : *ButtonComponent, dt : float64) {}

button_commit :: (using iButton : *ButtonComponent, noBackground := false) {
    // Background & text
    meshes, node := Sill.mesh_make_primitives(iButton.mesh, ifx noBackground then cast(u32) 1 else 2);
    if !noBackground {
        create_rect_mesh(iButton.ui.extent.width, iButton.ui.extent.height, 1, .Center, existingMesh = meshes[0]);
        meshes[0].material = Magma.create_material(instance.shaders.monochrome);
    }
    textPrimitive := ifx noBackground then meshes[0] else meshes[1];
    create_text_mesh(existingMesh = textPrimitive);
    text_mesh_update(textPrimitive, text, "mainLight", instance.config.env.textColor, anchor = .Center);

    Sill.ui_on_trigger(iButton.ui, (trigger : Sill.UiTrigger, iButton : *ButtonComponent) {
        hovered := iButton.interactive && (trigger.flags & .HoverStart);
        Crater.window_pointer_style(instance.engine.window, ifx hovered then Crater.PointerStyle.HandPointing else .Default);
        if iButton.entity.flags & .Destroyed then return;
        if iButton.tooltipText.count == 0 then return;
        _update_button_from_hover(iButton, hovered);
        if hovered then _place_tooltip(iButton);
    }, Sill.UiCallbackFlags.HoverStart | .HoverStop, iButton);

    // Tooltip background & text
    if tooltipText.count != 0 {
        tooltipMeshes, tooltipNode := Sill.mesh_make_primitives(iButton.mesh, 2);
        create_text_mesh(existingMesh = tooltipMeshes[1]);
        tooltipTextWidth := text_mesh_update(tooltipMeshes[1], tooltipText, "mainLight", instance.config.env.textColor, anchor = .Center);
        create_rect_mesh(tooltipTextWidth + 2 * UiConstants.PaddingHorizontalMedium, instance.config.env.fontSize + UiConstants.PaddingVerticalMedium, 1, .Center, existingMesh = tooltipMeshes[0]);
        tooltipMeshes[0].material = Magma.create_material(instance.shaders.monochrome);
        Magma.material_set_color(tooltipMeshes[0].material, "color", instance.config.env.hoverColor);
        tooltipNode.transform.translation.z = -10; // Needed to be visible in front of everything.

        meshNode = node;
        tooltipMeshNode = tooltipNode;
        tooltipExtent = Chamber.vec2.{tooltipTextWidth + 2 * UiConstants.PaddingHorizontalMedium, instance.config.env.fontSize + 2 * UiConstants.PaddingVerticalMedium};
        _update_button_from_hover(iButton);
    }
}

#scope_file

_update_button_from_hover :: (iButton : *ButtonComponent, hovered := false) {
    // For each tooltip node primitive.
    for primitive : iButton.tooltipMeshNode.primitives {
        if hovered then primitive.disabled &= ~.Application;
        else primitive.disabled |= .Application;
    }
}

_place_tooltip :: (using iButton : *ButtonComponent) {
    // @todo :UpdateAtEachHover We could somehow dirtify this on screen extent change and
    // transform to recompute only when necessary, but this would require additional callbacks watchers.
    // Do we really want that?

    // Basic placement.
    if tooltipSide == .Left then tooltipMeshNode.transform.translation.x = -iButton.ui.extent.width / 2 - tooltipExtent.x / 2;
    else if tooltipSide == .Right then tooltipMeshNode.transform.translation.x = iButton.ui.extent.width / 2 + tooltipExtent.x / 2;
    else if tooltipSide == .Bottom then tooltipMeshNode.transform.translation.y = iButton.ui.extent.height / 2 + tooltipExtent.y / 2;
    else tooltipMeshNode.transform.translation.y = -iButton.ui.extent.height / 2 - tooltipExtent.y / 2;

    Sill.mesh_commit_nodes(iButton.mesh, instantly = true);

    // Ensure it fits the screen.
    screenExtent := Crater.window_get_extent(instance.engine.window, Chamber.vec2);
    tooltipPosition := tooltipMeshNode.primitives[0].transform.translation.xy;
    if tooltipPosition.x + tooltipExtent.x / 2 > screenExtent.x / 2 then tooltipMeshNode.transform.translation.x -= tooltipPosition.x + tooltipExtent.x / 2 - screenExtent.x / 2;
    else if tooltipPosition.x - tooltipExtent.x / 2 < -screenExtent.x / 2 then tooltipMeshNode.transform.translation.x += -screenExtent.x / 2 - tooltipPosition.x + tooltipExtent.x / 2;
    if tooltipPosition.y + tooltipExtent.y / 2 > screenExtent.y / 2 then tooltipMeshNode.transform.translation.y -= tooltipPosition.y + tooltipExtent.y / 2 - screenExtent.y / 2;
    else if tooltipPosition.y - tooltipExtent.y / 2 < -screenExtent.y / 2 then tooltipMeshNode.transform.translation.y += -screenExtent.y / 2 - tooltipPosition.y + tooltipExtent.y / 2;

    Chamber.round(*tooltipMeshNode.transform.translation.xy);

    Sill.mesh_commit_nodes(iButton.mesh);
}
