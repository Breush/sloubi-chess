// A tab is composed of:
// - a button, automatically added to the sidebar
// - a page, which is itself composed of:
//   - a title
//      - a menu, unfoldable, on the left side
//      - actions, buttons on the right side
//   - a scrollable content, which has the main entity as a child

TabComponent :: struct {
    using #as component : Sill.Component;

    transform : *Sill.TransformComponent;
    listener : *Sill.ListenerComponent;
    ui : *Sill.UiComponent;

    // Configuration.
    text : string;
    icon : string;
    actions : [..]Action;
    menu : struct {
        items : [..]string;
        selectedItemIndex : u32;
        onItemClick : #type (entity : *Sill.Entity, itemIndex : u32);
    };
    onReflow : #type (entity : *Sill.Entity);

    button : SidebarButtonEntity;
    page : TabPageEntity;
    linkedToSidebar : bool;

    Action :: struct {
        text : string;
        icon : string;
        callback : #type (entity : *Sill.Entity);
        place : Place;

        Place :: enum u8 {
            None :: 0;
            Left;
            Right;
        }
    }
}

TabPageEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    title : TabPageTitleEntity;
    content : InvisibleUiEntity;
}

TabPageTitleEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;

    menu : TabPageTitleMenuEntity;
    actions : [..]*TabPageTitleActionEntity;

    on_cleanup :: (using this : *TabPageTitleEntity) {
        Basic.array_free(actions);
    }
}

TabPageTitleMenuEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    items : [..]*UiEntity;
    tabComponent : *TabComponent;
    itemsScrollOffset : s32; // We show only 10 items at a time, this is the scroll offset.
    folded := true;

    on_cleanup :: (using this : *TabPageTitleMenuEntity) {
        Basic.array_free(items);
    }
}

TabPageTitleActionEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;
    button : ButtonComponent;

    tabComponent : *TabComponent;
    actionIndex : u32;
}

component_init :: (using iTab : *TabComponent) {
    Sill.listener_on_message(iTab.listener, _on_message);

    // -- Sidebar button

    SillMeta.entity_init(*button, instance.engine);
    Sill.entity_set_parent(*button, instance.sidebar);
    button.tab = iTab;

    Basic.array_add(*instance.sidebar.tabButtons, *button);
    instance.sidebar.tabButtonsDirty = true;
    button.tab.linkedToSidebar = true;

    // -- Title

    SillMeta.entity_init(*iTab.page, instance.engine);
    Sill.entity_add_child(*iTab.page, *iTab.page.title);

    titleBackgroundMesh := Sill.mesh_make_primitive(*iTab.page.title.mesh);
    create_rect_mesh(1, 1, anchor = .BottomLeft, existingMesh = titleBackgroundMesh);
    titleBackgroundMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set_color(titleBackgroundMesh.material, "color", instance.config.env.backgroundColor);

    titleBorderMesh, titleBorderMeshNode := Sill.mesh_make_primitive(*iTab.page.title.mesh);
    create_rect_mesh(1, 1, anchor = .TopLeft, existingMesh = titleBorderMesh);
    titleBorderMesh.material = Magma.create_material(instance.shaders.monochrome);
    Magma.material_set_color(titleBorderMesh.material, "color", instance.config.env.contrastColor);

    titleTextMesh, titleTextMeshNode := Sill.mesh_make_primitive(*iTab.page.title.mesh);
    titleTextMesh.material = Magma.create_material(instance.shaders.text);
    titleTextMeshNode.transform.translation.y = UiConstants.HeightTabPageTitle / 2.0 - UiConstants.HeightLine / 2.0;
    titleTextMeshNode.transform.translation.z = UiConstants.DepthTabText;

    // -- Menu

    Sill.entity_add_child(*iTab.page.title, *iTab.page.title.menu);
    iTab.page.title.menu.tabComponent = iTab;

    menuBackgroundMesh, menuBackgroundMeshNode := Sill.mesh_make_primitive(*iTab.page.title.menu.mesh);
    create_rect_mesh(1, 1, 1, anchor = .TopLeft, existingMesh = menuBackgroundMesh);
    menuBackgroundMesh.material = Magma.create_material(instance.shaders.monochrome);
    menuBackgroundMeshNode.transform.translation.y = 1 + UiConstants.SizeTabAction / 2.0;
    Magma.material_set_color(menuBackgroundMesh.material, "color", instance.config.env.contrastColor);

    menuTextMesh, menuTextMeshNode := Sill.mesh_make_primitive(*iTab.page.title.menu.mesh);
    create_text_mesh(existingMesh = menuTextMesh);
    iTab.page.title.menu.transform.translation.x = UiConstants.PaddingHorizontal / 2.0;
    iTab.page.title.menu.transform.translation.y = UiConstants.HeightTabPageTitle - UiConstants.SizeTabAction / 2.0;
    iTab.page.title.menu.transform.translation.z = UiConstants.DepthTabMenu;
    _update_action_hovered(menuTextMeshNode);

    Sill.ui_on_trigger(*iTab.page.title.menu.ui, (trigger : Sill.UiTrigger, menu : *TabPageTitleMenuEntity) {
        trigger.stopPropagation.* = true;

        if trigger.flags & .HoverStart || trigger.flags & .HoverStop {
            hovered := cast(bool) (trigger.flags & .HoverStart);
            Crater.window_pointer_style(instance.engine.window, ifx hovered then Crater.PointerStyle.HandPointing else .Default);
            if menu.flags & .Destroyed then return;
            _update_action_hovered(*menu.mesh.nodes[1], hovered);
        } else if trigger.flags & .ClickStop {
            menu.folded = !menu.folded;
            _refresh_menu(menu.tabComponent);
        }
    }, Sill.UiCallbackFlags.ClickStop | .HoverStart | .Hovering | .HoverStop, *iTab.page.title.menu);

    // -- Content

    Sill.entity_add_child(*iTab.page, *iTab.page.content);
    Sill.entity_set_parent(iTab.entity, *iTab.page.content);
    iTab.page.content.transform.translation.y = UiConstants.HeightTabPageTitle;
    iTab.transform.translation.x = UiConstants.PaddingHorizontal;
    iTab.transform.translation.y = UiConstants.PaddingVerticalMedium;

    Sill.ui_on_trigger(*iTab.page.content.ui, (trigger : Sill.UiTrigger, tab : *TabComponent) {
        if tab.entity.flags & .Disabled then return;
        tab_scroll(tab, 25 * trigger.event.mouseWheel.dy);
        trigger.stopPropagation.* = true;
    }, .Scrolling, iTab);

    _reflow(iTab.entity);
}

component_cleanup :: (iTab : *TabComponent) {
    for action : iTab.page.title.actions {
        Sill.destroy_entity(action);
    }
    for menuItem : iTab.page.title.menu.items {
        Sill.destroy_entity(menuItem);
    }

    Basic.array_free(iTab.actions);
    Basic.array_free(iTab.menu.items);
    SillMeta.entity_cleanup(*iTab.page);
    SillMeta.entity_cleanup(*iTab.button);

    if iTab.linkedToSidebar then sidebar_remove_tab_button(instance.sidebar, *iTab.button);
}

component_update :: (iTab : *TabComponent, dt : float64) {
    SillMeta.entity_update(*iTab.button, dt);
    SillMeta.entity_update(*iTab.page, dt);
}

tab_scroll :: (using iTab : *TabComponent, scrollDelta : float) {
    iTab.transform.translation.y += Math.floor(scrollDelta + 0.5);

    // Clever scrolling.
    maxY := iTab.ui.extent.height - iTab.page.content.ui.extent.height / 2;
    maxY = Basic.max(maxY, -UiConstants.PaddingVerticalMedium);

    if iTab.transform.translation.y > UiConstants.PaddingVerticalMedium {
        iTab.transform.translation.y = UiConstants.PaddingVerticalMedium;
    } else if iTab.transform.translation.y < -maxY {
        iTab.transform.translation.y = -maxY;
    }

    Sill.transform_commit(iTab.transform);
}

tab_commit_text :: (using iTab : *TabComponent) {
    _refresh_title(iTab);
}

tab_commit_actions :: (using iTab : *TabComponent) {
    _refresh_actions(iTab);
}

tab_commit_menu :: (using iTab : *TabComponent) {
    _refresh_menu(iTab);
}

#scope_file

_on_message :: (entity : *Sill.Entity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _reflow(entity);
    case .SelectTab;
        iTab := entity_get_component(entity, TabComponent);
        Sill.entity_set_disabled(*iTab.page, message.entity != entity);
    }
}

_refresh_title :: (using iTab : *TabComponent) {
    textWidth := text_mesh_update(iTab.page.title.mesh.nodes[2].primitives[0], iTab.text, "mainBold", instance.config.env.textColor);

    iTab.page.title.mesh.nodes[2].transform.translation.x = Math.floor(iTab.page.content.ui.extent.width / 2.0 - textWidth / 2.0 + 0.5);
    Sill.mesh_commit_nodes(*iTab.page.title.mesh);
}

_refresh_actions :: (using iTab : *TabComponent) {
    leftCurrentPosition : Chamber.vec3;
    leftCurrentPosition.x = UiConstants.SizeTabAction / 2.0 + UiConstants.PaddingHorizontal / 2.0;
    leftCurrentPosition.y = UiConstants.HeightTabPageTitle - UiConstants.SizeTabAction / 2.0;
    leftCurrentPosition.z = -5;

    rightCurrentPosition := leftCurrentPosition;
    rightCurrentPosition.x = iTab.page.content.ui.extent.width - UiConstants.SizeTabAction / 2.0 - UiConstants.PaddingHorizontal / 2.0;

    // @todo Should destroy old, too.
    Basic.array_resize(*iTab.page.title.actions, iTab.actions.count);

    for *action, actionIndex : actions {
        if iTab.page.title.actions[actionIndex] == null {
            actionEntity := SillMeta.create_tab_page_title_action_entity(instance.engine);
            Sill.entity_set_parent(actionEntity, *iTab.page.title);
            actionEntity.tabComponent = iTab;
            actionEntity.actionIndex = cast(u32) actionIndex;

            actionEntity.button.text = action.icon;
            actionEntity.button.tooltipText = action.text;
            actionEntity.button.tooltipSide = .Top;
            actionEntity.button.callback = xx (actionEntity : *TabPageTitleActionEntity) {
                actionEntity.tabComponent.actions[actionEntity.actionIndex].callback(actionEntity.tabComponent.entity);
            };
            actionEntity.button.callbackData = actionEntity;
            actionEntity.ui.extent.width = UiConstants.SizeTabAction;
            actionEntity.ui.extent.height = UiConstants.SizeTabAction;
            button_commit(*actionEntity.button, noBackground = true);
            _update_action_hovered(actionEntity.button.meshNode);

            Sill.ui_on_trigger(*actionEntity.ui, (trigger : Sill.UiTrigger, actionEntity : *TabPageTitleActionEntity) {
                if actionEntity.flags & .Destroyed then return;
                _update_action_hovered(actionEntity.button.meshNode, cast(bool) (trigger.flags & .HoverStart));
            }, .HoverStart | .HoverStop, actionEntity);

            iTab.page.title.actions[actionIndex] = actionEntity;
        }

        Sill.entity_set_disabled(iTab.page.title.actions[actionIndex], action.place == .None);
        if action.place == .Left {
            iTab.page.title.actions[actionIndex].transform.translation = leftCurrentPosition;
            leftCurrentPosition.x += UiConstants.SizeTabAction;
        } else if action.place == .Right {
            iTab.page.title.actions[actionIndex].transform.translation = rightCurrentPosition;
            rightCurrentPosition.x -= UiConstants.SizeTabAction;
        }
    }

    Sill.transform_commit(*iTab.page.title.transform);

    _place_menu(iTab);
}

_place_menu :: (iTab : *TabComponent) {
    menu := *iTab.page.title.menu;
    leftActionCount := 0;
    for *action : iTab.actions {
        if action.place == .Left then leftActionCount += 1;
    }
    menu.transform.translation.x = UiConstants.SizeTabAction * leftActionCount + UiConstants.PaddingHorizontal / 2.0;
    menu.mesh.nodes[0].transform.translation.x = -UiConstants.SizeTabAction * leftActionCount;
    Sill.transform_commit(*menu.transform);
}

_refresh_menu :: (iTab : *TabComponent) {
    _place_menu(iTab);

    if iTab.menu.items.count == 0 then return;

    menu := *iTab.page.title.menu;
    selectedItem := *iTab.menu.items[iTab.menu.selectedItemIndex];
    icon := ifx iTab.menu.items.count > 1 then ForkAwesome.ChevronCircleRight else "";
    textWidth := text_mesh_update(menu.mesh.nodes[1].primitives[0], Basic.tprint("%  %", icon, selectedItem.*), "mainLight", instance.config.env.textColor, anchor = .Left);
    menu.ui.extent.height = UiConstants.SizeTabAction;
    menu.ui.extent.width = textWidth;
    menu.ui.anchor = .Left;

    _refresh_menu_items(iTab);

    // @todo There will be a dedicated Jai syntax on day: menu.mesh.nodes[0].primitives[0].disabled.Application = menu.folded;
    if menu.folded then menu.mesh.nodes[0].primitives[0].disabled |= .Application;
    else menu.mesh.nodes[0].primitives[0].disabled &= ~.Application;
}

_refresh_menu_items :: (iTab : *TabComponent) {
    leftActionCount := 0;
    for *action : iTab.actions {
        if action.place == .Left then leftActionCount += 1;
    }

    // Show 10 items max at a time, but we can scroll.
    MAX_ITEM_COUNT :: 10;

    menu := *iTab.page.title.menu;
    if menu.itemsScrollOffset > iTab.menu.items.count - MAX_ITEM_COUNT then menu.itemsScrollOffset = cast(s32) iTab.menu.items.count - MAX_ITEM_COUNT;
    if menu.itemsScrollOffset < 0 then menu.itemsScrollOffset = 0;

    itemCount := Basic.min(MAX_ITEM_COUNT, iTab.menu.items.count - menu.itemsScrollOffset);
    for item, itemIndex : iTab.page.title.menu.items {
        if itemIndex >= itemCount then Sill.destroy_entity(item);
    }
    Basic.array_resize(*iTab.page.title.menu.items, itemCount);

    for item, itemIndex : iTab.menu.items {
        effectiveItemIndex := itemIndex - menu.itemsScrollOffset;
        if effectiveItemIndex < 0 then continue;
        if effectiveItemIndex >= itemCount then break;

        if iTab.page.title.menu.items[effectiveItemIndex] == null {
            itemEntity := SillMeta.create_ui_entity(instance.engine);
            Sill.entity_set_parent(itemEntity, *iTab.page.title.menu);

            itemMesh, itemMeshNode := Sill.mesh_make_primitive(*itemEntity.mesh);
            create_text_mesh(existingMesh = itemMesh);
            Magma.material_set(itemMesh.material, "translucency", 0.5);
            itemEntity.ui.extent.height = UiConstants.HeightLine;
            itemEntity.ui.anchor = .Left;
            iTab.page.title.menu.items[effectiveItemIndex] = itemEntity;
            itemMeshNode.transform.translation.x = UiConstants.PaddingHorizontalMedium - UiConstants.SizeTabAction * leftActionCount;

            Sill.ui_on_trigger(*itemEntity.ui, (trigger : Sill.UiTrigger, itemEntity : *UiEntity) {
                trigger.stopPropagation.* = true;

                if trigger.flags & .HoverStart || trigger.flags & .HoverStop {
                    hovered := cast(bool) (trigger.flags & .HoverStart);
                    Crater.window_pointer_style(instance.engine.window, ifx hovered then Crater.PointerStyle.HandPointing else .Default);
                    if itemEntity.flags & .Destroyed then return;
                    Magma.material_set(itemEntity.mesh.nodes[0].primitives[0].material, "translucency", ifx hovered then 0.0 else 0.5);
                } else if trigger.flags & .ClickStop {
                    menu := cast(*TabPageTitleMenuEntity) itemEntity.parent;
                    menu.folded = true;
                    found, itemIndex := Basic.array_find(menu.items, itemEntity);
                    if found && menu.tabComponent.menu.onItemClick != null {
                        menu.tabComponent.menu.onItemClick(menu.tabComponent.entity, cast(u32) menu.itemsScrollOffset + cast(u32) itemIndex);
                    }
                } else if trigger.flags & .Scrolling {
                    menu := cast(*TabPageTitleMenuEntity) itemEntity.parent;
                    scrollDelta := ifx trigger.event.mouseWheel.dy >= 0.0 then cast(s32) -1 else 1;
                    menu.itemsScrollOffset += scrollDelta;
                    _refresh_menu_items(menu.tabComponent);
                }
            }, Sill.UiCallbackFlags.ClickStop | .HoverStart | .Hovering | .HoverStop | .Scrolling, itemEntity);
        }

        itemEntity := iTab.page.title.menu.items[effectiveItemIndex];
        itemEntity.ui.extent.width = iTab.page.content.ui.extent.width - UiConstants.PaddingHorizontal;
        itemEntity.transform.translation.y = UiConstants.SizeTabAction + UiConstants.HeightLine * effectiveItemIndex;
        text_mesh_update(itemEntity.mesh.nodes[0].primitives[0], item, "mainLight", instance.config.env.textColor, anchor = .Left);
        Sill.transform_commit(*itemEntity.transform);
        Sill.entity_set_disabled(itemEntity, menu.folded);
    }

    menu.mesh.nodes[0].transform.scaling.x = iTab.page.content.ui.extent.width - UiConstants.PaddingHorizontal;
    menu.mesh.nodes[0].transform.scaling.y = (itemCount + 0.5) * UiConstants.HeightLine;
    Sill.mesh_commit_nodes(*menu.mesh);
}

_update_action_hovered :: (meshNode : *Sill.MeshNode, hovered := false) {
    Magma.material_set(meshNode.primitives[0].material, "translucency", ifx hovered then 0.0 else UiConstants.TranslucencyTabAction);
}

_reflow :: (entity : *Sill.Entity) {
    iTab := entity_get_component(entity, TabComponent);
    extent := Crater.window_get_extent(instance.engine.window, Chamber.vec2);

    // Vertical layout
    if extent.height > extent.width {
        iTab.page.transform.translation.x = -Math.floor(extent.width / 2.0 + 0.5);
        iTab.page.transform.translation.y = 0.0;
        iTab.page.content.ui.anchor = .TopLeft;
        iTab.page.content.ui.extent.width = extent.width - UiConstants.PaddingHorizontal;
        iTab.page.content.ui.extent.height = extent.height / 2 - UiConstants.HeightTabPageTitle;

        iTab.page.title.mesh.nodes[0].transform.scaling.x = extent.width - UiConstants.WidthSidebar;
        iTab.page.title.mesh.nodes[0].transform.scaling.y = UiConstants.HeightTabPageTitle + extent.height / 2;
        iTab.page.title.mesh.nodes[1].transform.scaling.x = extent.width - UiConstants.PaddingHorizontal - UiConstants.WidthSidebar - UiConstants.PaddingHorizontal;
    }
    // Horizontal layout
    else {
        iTab.page.transform.translation.x = 0.0;
        iTab.page.transform.translation.y = -Math.floor(extent.height / 2.0 + 0.5);
        iTab.page.content.ui.anchor = .TopLeft;
        iTab.page.content.ui.extent.width = extent.width / 2 - UiConstants.WidthSidebar;
        iTab.page.content.ui.extent.height = extent.height - UiConstants.HeightTabPageTitle;

        iTab.page.title.mesh.nodes[0].transform.scaling.x = extent.width / 2 - UiConstants.WidthSidebar;
        iTab.page.title.mesh.nodes[0].transform.scaling.y = UiConstants.HeightTabPageTitle;
        iTab.page.title.mesh.nodes[1].transform.scaling.x = extent.width / 2 - UiConstants.WidthSidebar - UiConstants.PaddingHorizontal;
    }

    iTab.page.title.transform.translation.z = UiConstants.DepthTab;
    iTab.page.title.mesh.nodes[0].transform.translation.y = UiConstants.HeightTabPageTitle;
    iTab.page.title.mesh.nodes[1].transform.translation.x = UiConstants.PaddingHorizontal / 2;
    iTab.page.title.mesh.nodes[1].transform.translation.y = UiConstants.HeightTabPageTitle;

    Sill.transform_commit(*iTab.page.transform);
    Sill.mesh_commit_nodes(*iTab.page.title.mesh);

    _refresh_title(iTab);
    _refresh_actions(iTab);

    if iTab.onReflow != null {
        iTab.onReflow(iTab.entity);
    }
}
