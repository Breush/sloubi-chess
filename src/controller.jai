ControllerEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    camera : Sill.CameraComponent;
    behaviorComponent : Sill.BehaviorComponent;

    debug : ControllerDebugEntity;
}

ControllerDebugEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage;

    behavior : Sill.BehaviorComponent;

    origin : Chamber.vec3;
    target : Chamber.vec3;

    enabled : bool;
}

controller_create :: () -> *ControllerEntity {
    using controller := SillMeta.create_controller_entity(instance.engine);
    Sill.listener_on_message(*listener, _on_message);
    controls := *instance.config.controls;

    // @todo Propagate the naming convention of "ply" to the rest of the software.
    Sill.input_action_bind(instance.engine, "game.ply.previous", controls.previousPly);
    Sill.input_action_bind(instance.engine, "game.ply.next", controls.nextPly);
    Sill.input_action_bind(instance.engine, "game.ply.first", controls.firstPly);
    Sill.input_action_bind(instance.engine, "game.ply.last", controls.lastPly);
    Sill.input_action_bind(instance.engine, "game.ply.comment.edit", controls.editPlyComment);
    Sill.input_action_bind(instance.engine, "game.variation.previous", controls.previousVariation);
    Sill.input_action_bind(instance.engine, "game.variation.next", controls.nextVariation);

    Sill.input_axis_bind(instance.engine, "list.scroll", .MouseWheelY);

    Sill.behavior_on_update(*behaviorComponent, xx (dt : float64, using instance : *Instance) {
        if game.ply == null then return;

        if Sill.input_action_just_activated(engine, "game.ply.previous", true)         then game_go_to_previous_move(*game);
        if Sill.input_action_just_activated(engine, "game.ply.next", true)             then game_go_to_next_move(*game);
        if Sill.input_action_just_activated(engine, "game.ply.first", true)            then game_go_to_first_ply(*game);
        if Sill.input_action_just_activated(engine, "game.ply.last", true)             then game_go_to_last_ply(*game);
        if Sill.input_action_just_activated(engine, "game.ply.comment.edit", true)     then game_edit_ply_comment(*game);
        if Sill.input_action_just_activated(engine, "game.variation.previous", true)   then game_go_to_previous_variation(*game);
        if Sill.input_action_just_activated(engine, "game.variation.next", true)       then game_go_to_next_variation(*game);

        // @todo This should be UI job, somehow.
        if Sill.input_axis_changed(engine, "list.scroll") {
            list_scroll(list, 25.0 * Sill.input_axis_value(engine, "list.scroll"));
        }
    }, *instance);

    // Debug 3D
    Sill.input_action_bind(instance.engine, "debug.3d", .F12);

    _setup_orthographic_camera(controller);

    Sill.behavior_on_update(*debug.behavior, xx (dt : float64, using controller : *ControllerEntity) {
        if Sill.input_action_just_activated(engine, "debug.3d", true) {
            debug.enabled = !debug.enabled;

            if debug.enabled {
                eye := Magma.renderer_get_eye(instance.engine.renderer, 0);
                debug.origin = .{0, 0, 0};
                debug.origin.z = - cast(float) instance.engine.options.windowExtent.x;
                Chamber.infinite_perspective_projection(*eye.projectionMatrix, 70.0, (cast(float) eye.extent.width) / eye.extent.height, 0.1);
                Sill.transform_origin_target(*transform, debug.origin, debug.target, referenceUp=.{0, -1, 0});

                Sill.input_axis_bind(engine, "debug.3d.look-x", .MousePointerX);
                Sill.input_axis_bind(engine, "debug.3d.look-y", .MousePointerY);
            } else {
                _setup_orthographic_camera(controller);

                Sill.input_axis_unbind(engine, "debug.3d.look-x");
                Sill.input_axis_unbind(engine, "debug.3d.look-y");
            }
        }

        lookX := Sill.input_axis_value(engine, "debug.3d.look-x");
        lookY := Sill.input_axis_value(engine, "debug.3d.look-y");
        if lookX != 0. || lookY != 0. {
            debug.origin.std += Chamber.rotate_around_target(debug.origin, debug.target, -lookX / 100., -lookY / 100., upAxis = .NegativeY);
            Sill.transform_origin_target(*transform, debug.origin, debug.target, referenceUp=.{0, -1, 0});
        }
    }, controller);

    return controller;
}

#scope_file

_on_message :: (using controller : *ControllerEntity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _setup_orthographic_camera(controller);
    }
}

_setup_orthographic_camera :: (using controller : *ControllerEntity) {
    eye := Magma.renderer_get_eye(engine.renderer, 0);

    extent : Chamber.vec2;
    extent.width = cast(float) eye.extent.width;
    extent.height = cast(float) eye.extent.height;

    eye.viewMatrix = Chamber.look_at_matrix(.{0, 0, -1}, .{0, 0, 0}, .{0, -1, 0});
    Chamber.unnear_orthographic_projection(*eye.projectionMatrix, extent, 100.0); // Orthographic camera with 1 pixel = 1 unit
    Sill.transform_origin_target(*transform, .{0, 0, -40}, .{0, 0, 0}, referenceUp=.{0, -1, 0});
}
