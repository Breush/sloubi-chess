SidebarEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
    behavior : Sill.BehaviorComponent;

    tabButtonsDirty := false;
    tabButtons : [..]*SidebarButtonEntity;

    on_cleanup :: (using this : *SidebarEntity) {
        for tabButton : tabButtons {
            tabButton.tab.linkedToSidebar = false;
        }
        Basic.array_reset(*tabButtons);
    }
}

SidebarButtonEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
    button : ButtonComponent;

    active : bool;

    tab : *TabComponent; // Only set for a "tab" button
}

sidebar_create :: () -> *SidebarEntity {
    using sidebar := SillMeta.create_sidebar_entity(instance.engine);
    Sill.listener_on_message(*listener, _on_message);

    ui.extent.width = UiConstants.WidthSidebar;

    // Background
    backgroundMesh := Sill.mesh_make_primitive(*mesh);
    create_rect_mesh(ui.extent.width, 1, anchor = .Top, existingMesh = backgroundMesh);
    backgroundMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set_color(backgroundMesh.material, "color", instance.config.env.contrastColor);

    Sill.behavior_on_update(*behavior, (dt : float64, sidebar : *SidebarEntity) {
        _update(sidebar);
    }, sidebar);

    return sidebar;
}

sidebar_remove_tab_button :: (using sidebar : *SidebarEntity, tabButton : *SidebarButtonEntity) {
    found, index := Basic.array_find(instance.sidebar.tabButtons, tabButton);
    if !found then return;

    sidebar.tabButtonsDirty = true;
    Basic.array_unordered_remove_by_index(*instance.sidebar.tabButtons, index);

    // Select the tab below. As library cannot be removed, this is always possible.
    if index > 0 then send(.SelectTab, instance.sidebar.tabButtons[index - 1].tab.entity);
}

#scope_file

_on_message :: (using sidebar : *SidebarEntity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _reflow(sidebar);
    case .SelectTab;
        for tabButton : tabButtons {
            tabButton.active = (tabButton.tab.entity == message.entity);
            _update_button_from_hover(tabButton);
        }

    }
}

_reflow :: (using sidebar : *SidebarEntity) {
    extent := Crater.window_get_extent(instance.engine.window, Chamber.vec2);
    ui.extent.height = extent.height;

    mesh.nodes[0].transform.scaling.y = extent.height;
    Sill.mesh_commit_nodes(*mesh, instantly = true);

    transform.translation.x = extent.width / 2.0 - UiConstants.WidthSidebar / 2.0;
    transform.translation.y = -extent.height / 2.0;
    transform.translation.z = UiConstants.DepthSidebar;
    Sill.transform_commit(*transform);
}

_update :: (using sidebar : *SidebarEntity) {
    if !sidebar.tabButtonsDirty then return;
    sidebar.tabButtonsDirty = false;

    for tabButton, tabButtonIndex : tabButtons {
        // Create the button if it doesn't exist yet.
        if tabButton.mesh.nodes.count == 0 {
            _make_button(tabButton, tabButton.tab.icon, tabButton.tab.text);
            Sill.ui_on_trigger(*tabButton.ui, (trigger : Sill.UiTrigger, tabButton : *SidebarButtonEntity) {
                send(.SelectTab, tabButton.tab.entity);
            }, .ClickStop, tabButton);
        }

        // Position the button.
        tabButton.transform.translation.y = (tabButtonIndex + 0.5) * UiConstants.WidthSidebar;
    }

    Sill.transform_commit(*transform);
}

_make_button :: (button : *SidebarButtonEntity, icon : string, tooltipText : string) {
    button.ui.extent.width = UiConstants.WidthSidebar;
    button.ui.extent.height = UiConstants.WidthSidebar;

    button.button.text = icon;
    button.button.tooltipText = tooltipText;
    button.button.tooltipSide = .Left;
    button_commit(*button.button);

    Sill.ui_on_trigger(*button.ui, (trigger : Sill.UiTrigger, button : *SidebarButtonEntity) {
        trigger.stopPropagation.* = true;

        if trigger.flags & .HoverStart || trigger.flags & .HoverStop {
            hovered := cast(bool) (trigger.flags & .HoverStart);
            _update_button_from_hover(button, hovered);
            Crater.window_pointer_style(instance.engine.window, ifx !button.active && hovered then Crater.PointerStyle.HandPointing else .Default);
        }
    }, Sill.UiCallbackFlags.ClickStop | .HoverStart | .Hovering | .HoverStop, button);

    button.transform.translation.z = UiConstants.DepthSidebarButton;
    _update_button_from_hover(button);
}

_update_button_from_hover :: (button : *SidebarButtonEntity, hovered := false) {
    // @note Check needed, as buttons can be constructed with delay.
    if button.mesh.nodes.count == 0 then return;

    // For each tooltip node primitive.
    if button.button.tooltipMeshNode != null {
        for primitive : button.button.tooltipMeshNode.primitives {
            if !button.active && hovered then primitive.disabled &= ~.Application;
            else primitive.disabled |= .Application;
        }
    }

    color : *Chamber.vec3;
    if button.active then color = *instance.config.env.backgroundColor;
    else if hovered then color = *instance.config.env.hoverColor;
    else color = *instance.config.env.contrastColor;
    Magma.material_set_color(button.mesh.nodes[0].primitives[0].material, "color", << color);
}
