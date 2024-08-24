ButtonComponent :: struct {
    using #as component : Sill.Component;

    transform : *Sill.TransformComponent;
    mesh : *Sill.MeshComponent;
    ui : *Sill.UiComponent;

    // Editable at any time.
    locked := false;
    backgroundColor : Chamber.vec3;
    backgroundHoverColor : Chamber.vec3;
    backgroundLockColor : Chamber.vec3;
    callback : #type (data : *void);
    callbackData : *void;

    // Editable before commit.
    text : string;
    tooltipText : string;
    tooltipSide : Chamber.Anchor;

    // Set by component after commit.
    meshNode : *Sill.MeshNode;
    tooltipMeshNode : *Sill.MeshNode;
    tooltipExtent : Chamber.vec2;

    // Internal
    noBackground : bool;
    hovered : bool;
}

component_init :: (using iButton : *ButtonComponent) {
    backgroundColor = instance.config.env.contrastColor;
    backgroundHoverColor = instance.config.env.hoverColor;
    backgroundLockColor = instance.config.env.backgroundColor;
}

component_cleanup :: (using iButton : *ButtonComponent) {}
component_update :: (using iButton : *ButtonComponent, dt : float64) {}

button_commit :: (iButton : *ButtonComponent, noBackground := false) {
    iButton.noBackground = noBackground;

    // Background & text
    meshes, node := Sill.mesh_make_primitives(iButton.mesh, ifx noBackground then cast(u32) 1 else 2);
    if !noBackground {
        create_rect_mesh(iButton.ui.extent.width, iButton.ui.extent.height, 1, .Center, existingMesh = meshes[0]);
        meshes[0].material = Magma.create_material(instance.shaders.monochrome);
    }
    textPrimitive := ifx noBackground then meshes[0] else meshes[1];
    create_text_mesh(existingMesh = textPrimitive);
    text_mesh_update(textPrimitive, iButton.text, "mainLight", instance.config.env.textColor, anchor = .Center);

    Sill.ui_on_trigger(iButton.ui, (trigger : Sill.UiTrigger, iButton : *ButtonComponent) {
        if iButton.entity.flags & .Destroyed then return;

        << trigger.stopPropagation = true;

        if trigger.flags & .Hovering then return;
        if trigger.flags & .ClickStop {
            if iButton.callback {
                iButton.callback(iButton.callbackData);
            }
            return;
        }

        iButton.hovered = cast(bool) (trigger.flags & .HoverStart);
        button_refresh(iButton);
    }, Sill.UiCallbackFlags.HoverStart | .Hovering | .HoverStop | .ClickStop, iButton);

    // Tooltip background & text
    if iButton.tooltipText.count != 0 {
        tooltipMeshes, tooltipNode := Sill.mesh_make_primitives(iButton.mesh, 2);
        create_text_mesh(existingMesh = tooltipMeshes[1]);
        tooltipTextWidth := text_mesh_update(tooltipMeshes[1], iButton.tooltipText, "mainLight", instance.config.env.textColor, anchor = .Center);
        create_rect_mesh(tooltipTextWidth + 2 * UiConstants.PaddingHorizontalMedium, instance.config.env.fontSize + UiConstants.PaddingVerticalMedium, 1, .Center, existingMesh = tooltipMeshes[0]);
        tooltipMeshes[0].material = Magma.create_material(instance.shaders.monochrome);
        Magma.material_set_color(tooltipMeshes[0].material, "color", instance.config.env.hoverColor);
        tooltipNode.transform.translation.z = UiConstants.DepthButtonTooltip;

        iButton.meshNode = node;
        iButton.tooltipMeshNode = tooltipNode;
        iButton.tooltipExtent = Chamber.vec2.{tooltipTextWidth + 2 * UiConstants.PaddingHorizontalMedium, instance.config.env.fontSize + 2 * UiConstants.PaddingVerticalMedium};
    }

    button_refresh(iButton);
}

button_refresh :: (iButton : *ButtonComponent) {
    if iButton.mesh.nodes.count == 0 then return;

    if !iButton.noBackground {
        color := iButton.backgroundColor;
        if iButton.locked {
            color = iButton.backgroundLockColor;
            iButton.hovered = false;
        } else if iButton.hovered {
            color = iButton.backgroundHoverColor;
        }

        Magma.material_set_color(iButton.mesh.nodes[0].primitives[0].material, "color", color);
    }

    Crater.window_pointer_style(instance.engine.window, ifx iButton.hovered then Crater.PointerStyle.HandPointing else .Default);

    if iButton.tooltipText.count == 0 then return;

    // For each tooltip node primitive.
    for primitive : iButton.tooltipMeshNode.primitives {
        if iButton.hovered then primitive.disabled &= ~.Application;
        else primitive.disabled |= .Application;
    }

    if iButton.hovered then _place_tooltip(iButton);
}

#scope_file

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
