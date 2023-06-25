VariationEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    ui : Sill.UiComponent;
    mesh : Sill.MeshComponent; // A mesh might not exists for the top variation.

    // @note plies[0].position is the initial position.
    // And it should not get any variation in it.
    plies : [..]*PlyEntity; // @note Do not flatten this, the struct might be needed for extra info about a variation.

    parentPly : *PlyEntity; // Can be null for the main variation.
    index : u16; // Index of the variation in the parent ply.

    depth : u16;
    collapsed : bool;

    decorumHeight : float; // Last decorum height, so that it is not rebuilt uselessly if it didn't changed.
}

variation_init :: (variation : *VariationEntity, game : *Game, firstOne := true) {
    Sill.listener_on_message(*variation.listener, _on_message);

    for plyIndex : 0 .. variation.plies.count - 1 {
        ply := variation.plies[plyIndex];
        ply_init(ply, game);

        for variation : ply.variations {
            variation_init(variation, game, firstOne = false);
        }
    }

    if (variation.parentPly != null) {
        _init_decorum(variation);
    }
}

variation_cleanup :: (using variation : *VariationEntity) {
    for ply : plies {
        ply_cleanup(ply);
    }
    Basic.array_free(plies);

    Sill.destroy_entity(variation);
}

variation_add_ply :: (variation : *VariationEntity) -> *PlyEntity {
    ply := SillMeta.create_ply_entity(instance.engine);
    Sill.entity_set_disabled(ply, true);
    Basic.array_add(*variation.plies, ply);

    ply.parentVariation = variation;
    ply.index = cast(u16) (variation.plies.count - 1);
    ply.first = ply.index == 0;
    return ply;
}

variation_refresh_backlinks :: (variation : *VariationEntity, game : *Game) {
    for ply : variation.plies {
        Chamber.debug("From ", ply.game, " to ", game);
        ply.game = game;
        for subVariation : ply.variations {
            variation_refresh_backlinks(subVariation, game);
        }
    }
}

variation_toggle_collapsed :: (variation : *VariationEntity) {
    variation.collapsed = !variation.collapsed;
    send(.VariationCollapsedChanged, variation);
}

variation_place_plies :: (variation : *VariationEntity, plyIndex : u16, upstream := true, hidden := false, firstOne := true) {
    // Downstream
    for i : plyIndex .. variation.plies.count - 1 {
        ply := variation.plies[i];
        ply_place(ply, hidden = hidden);

        for subVariation : ply.variations {
            variation_place_plies(subVariation, 0, upstream = false, hidden = hidden || variation.collapsed, firstOne = false);
            send(.VariationContentChanged, subVariation);
        }
    }

    // Upstream
    if upstream && variation.parentPly != null {
        for i : variation.index + 1 .. variation.parentPly.variations.count - 1 {
            variation_place_plies(variation.parentPly.variations[i], 0, upstream = false, firstOne = false);
            send(.VariationContentChanged, variation.parentPly.variations[i]);
        }

        variation_place_plies(variation.parentPly.parentVariation, variation.parentPly.index + 1, firstOne = false);
        send(.VariationContentChanged, variation.parentPly.parentVariation);
    }

    if firstOne {
        send(.VariationContentChanged, variation);
    }
}

variation_debug_dump :: (variation : *VariationEntity, depth : u8) {
    prefix := "| | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | ";
    prefix.count = depth * 2;

    for ply, plyIndex : variation.plies {
        if plyIndex == 0 {
            prefix.count -= 1;
            Basic.log("% > {%}", prefix, ply.position.comment);
            prefix.count += 1;
        } else {
            fullMoveIndex := (ply.position.moveIndex + 1) / 2;
            Basic.log("%0%0% % {%}}", prefix, fullMoveIndex, ifx ply.position.moveIndex % 2 then "." else "…", position_last_move_to_san(ply.position), ply.position.comment);
        }

        for variation : ply.variations {
            variation_debug_dump(variation, depth + 1);
        }
    }
}

#scope_file

_on_message :: (variation : *VariationEntity, message : *Message) {
    if message.kind == {
    case .SelectedPlyChanged;
        if variation.plies.count == 0 then return;
        if message.oldPly == variation.plies[0] && variation.mesh.nodes.count != 0 {
            Magma.material_set_color(variation.mesh.nodes[0].primitives[0].material, "color", instance.config.moves.mainColor);
        } else if message.newPly == variation.plies[0] && variation.mesh.nodes.count != 0 {
            Magma.material_set_color(variation.mesh.nodes[0].primitives[0].material, "color", instance.config.moves.selectedColor);
        }
    case .VariationContentChanged;
        if variation == message.variation {
            _rebuild_decorum(variation);
        }
    }
}

_init_decorum :: (variation : *VariationEntity) {
    variation.ui.anchor = .TopLeft;

    mesh := Magma.create_mesh(instance.engine.scene);
    create_rect_mesh(1, 1, 0, .TopLeft, existingMesh = mesh);

    mesh.material = Magma.create_material(instance.shaders.decorum);
    Magma.material_set_color(mesh.material, "color", instance.config.moves.mainColor);
    Magma.mesh_commit_vertices(mesh);

    Basic.array_add(*variation.mesh.nodes, .{});
    Basic.array_add(*Basic.peek_pointer(variation.mesh.nodes).primitives, mesh);

    Sill.ui_on_trigger(*variation.ui, (trigger : Sill.UiTrigger, variation : *VariationEntity) {
        if trigger.flags == .ClickStop {
            variation_toggle_collapsed(variation);
        } else {
            pointerStyle := ifx trigger.flags == .HoverStart then Crater.PointerStyle.HandPointing else .Default;
            color := ifx trigger.flags == .HoverStart then instance.config.moves.selectedColor else instance.config.moves.mainColor;
            Magma.material_set_color(variation.mesh.nodes[0].primitives[0].material, "color", color);
            Crater.window_pointer_style(instance.engine.window, pointerStyle);
        }
    }, Sill.UiCallbackFlags.HoverStart | .HoverStop | .ClickStop, variation);
}

_rebuild_decorum :: (variation : *VariationEntity) {
    if variation.mesh.nodes.count == 0 then return;

    hidden := false;
    parentVariation := variation;
    while parentVariation.parentPly != null {
        parentVariation = parentVariation.parentPly.parentVariation;
        if parentVariation.collapsed {
            hidden = true;
            break;
        }
    }

    Sill.entity_set_disabled(variation, hidden);
    if hidden then return;

    // @todo Is this the right thing to do? It just feels a bit weird to be placed based
    // a "child" conceptually.
    Sill.entity_set_parent(variation, variation.plies[0].parent);
    variation.transform.translation.xy = variation.plies[0].transform.translation.xy;
    variation.transform.translation.x -= UiConstants.PaddingHorizontalVariation / 2.0;
    Sill.transform_commit(*variation.transform);

    firstPly := variation.plies[0];
    lastPly := Basic.peek(variation.plies);

    while lastPly.variations.count != 0 {
        lastPly = Basic.peek(Basic.peek(lastPly.variations).plies);
    }

    position := firstPly.transform.translation;
    height := lastPly.transform.translation.y + lastPly.ui.extent.height - position.y;
    height = Basic.max(height, UiConstants.HeightLine);
    if variation.collapsed then height += 1; // So that the check below distinguishes between collapsed and not collapsed.

    if height == variation.decorumHeight then return;
    variation.decorumHeight = height;
    _update_decorum(variation, variation.collapsed);
}

_update_decorum :: (variation : *VariationEntity, collapsed := false) {
    mesh := variation.mesh.nodes[0].primitives[0];

    variation.ui.extent.width = UiConstants.WidthDecorumVariation + 1;
    variation.ui.extent.height = variation.decorumHeight;
    variation.ui.anchor = .TopLeft;

    mesh.vertices[0].position.x = 0.0;
    mesh.vertices[1].position.x = 0.0;
    mesh.vertices[2].position.x = UiConstants.WidthDecorumVariation;
    mesh.vertices[3].position.x = UiConstants.WidthDecorumVariation;
    mesh.vertices[0].position.y = UiConstants.PaddingVerticalDecorumVariation;
    mesh.vertices[1].position.y = variation.decorumHeight - UiConstants.PaddingVerticalDecorumVariation;
    mesh.vertices[2].position.y = variation.decorumHeight - UiConstants.PaddingVerticalDecorumVariation;
    mesh.vertices[3].position.y = UiConstants.PaddingVerticalDecorumVariation;

    Magma.material_set(mesh.material, "collapsed", collapsed);
    Magma.material_set(mesh.material, "height", variation.decorumHeight);

    Magma.mesh_commit_vertices(mesh);
}
