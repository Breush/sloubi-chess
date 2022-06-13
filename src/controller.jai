ControllerEntity :: struct {
    using entity : Sill.Entity;
    behaviorComponent : Sill.BehaviorComponent;

    debug : *ControllerDebugEntity;
}

ControllerDebugEntity :: struct {
    using entity : Sill.Entity;

    transform : Sill.TransformComponent;
    behavior : Sill.BehaviorComponent;
    camera : Sill.CameraComponent;

    origin : Chamber.vec3;
    target : Chamber.vec3;

    enabled : bool;
}

controller_init :: () {
    using *instance;

    controller = SillMeta.create_controller_entity(engine);

    // @todo Propagate the naming convention of "ply" to the rest of the software.
    Sill.input_action_bind(engine, "game.ply.previous", config.controls.previousPly);
    Sill.input_action_bind(engine, "game.ply.next", config.controls.nextPly);
    Sill.input_action_bind(engine, "game.ply.first", config.controls.firstPly);
    Sill.input_action_bind(engine, "game.ply.last", config.controls.lastPly);
    Sill.input_action_bind(engine, "game.variation.previous", config.controls.previousVariation);
    Sill.input_action_bind(engine, "game.variation.next", config.controls.nextVariation);

    Sill.input_axis_bind(engine, "list.scroll", .MouseWheelY);

    Sill.behavior_on_update(*controller.behaviorComponent, xx (dt : float64, using instance : *Instance) {
        if Sill.input_action_just_activated(engine, "game.ply.previous", true)         then game_go_to_previous_move(*game);
        if Sill.input_action_just_activated(engine, "game.ply.next", true)             then game_go_to_next_move(*game);
        if Sill.input_action_just_activated(engine, "game.ply.first", true)            then game_go_to_first_ply(*game);
        if Sill.input_action_just_activated(engine, "game.ply.last", true)             then game_go_to_last_ply(*game);
        if Sill.input_action_just_activated(engine, "game.variation.previous", true)   then game_go_to_previous_variation(*game);
        if Sill.input_action_just_activated(engine, "game.variation.next", true)       then game_go_to_next_variation(*game);

        // @todo This should be UI job, somehow.
        if Sill.input_axis_changed(engine, "list.scroll") {
            list_scroll(Sill.input_axis_value(engine, "list.scroll"));
        }
    }, *instance);

    // Debug 3D
    Sill.input_action_bind(engine, "debug.3d", .F12);

    controller.debug = SillMeta.create_controller_debug_entity(engine);
    _setup_orthographic_camera();

    Sill.behavior_on_update(*controller.debug.behavior, xx (dt : float64, using instance : *Instance) {
        if Sill.input_action_just_activated(engine, "debug.3d", true) {
            controller.debug.enabled = !controller.debug.enabled;

            if controller.debug.enabled {
                eye := Magma.renderer_get_eye(instance.engine.renderer, 0);
                controller.debug.origin = .{0, 0, -1600};
                Chamber.infinite_perspective_projection(*eye.projectionMatrix, 70.0, (cast(float) eye.extent.width) / eye.extent.height, 0.1);
                Sill.transform_origin_target(*controller.debug.transform, controller.debug.origin, controller.debug.target, referenceUp=.{0, -1, 0});

                Sill.input_axis_bind(engine, "debug.3d.look-x", .MousePointerX);
                Sill.input_axis_bind(engine, "debug.3d.look-y", .MousePointerY);
            } else {
                _setup_orthographic_camera();

                Sill.input_axis_unbind(engine, "debug.3d.look-x");
                Sill.input_axis_unbind(engine, "debug.3d.look-y");
            }
        }

        lookX := Sill.input_axis_value(*engine.input, "debug.3d.look-x");
        lookY := Sill.input_axis_value(*engine.input, "debug.3d.look-y");
        if lookX != 0. || lookY != 0. {
            controller.debug.origin.std += Chamber.rotate_around_target(controller.debug.origin, controller.debug.target, -lookX / 100., -lookY / 100., upAxis = .NegativeY);
            Sill.transform_origin_target(*controller.debug.transform, controller.debug.origin, controller.debug.target, referenceUp=.{0, -1, 0});
        }
    }, *instance);
}

#scope_file

_setup_orthographic_camera :: () {
    using *instance;

    eye := Magma.renderer_get_eye(engine.renderer, 0);

    extent : Chamber.vec2;
    extent.width = cast(float) eye.extent.width;
    extent.height = cast(float) eye.extent.height;

    eye.viewMatrix = Chamber.look_at_matrix(.{0, 0, -1}, .{0, 0, 0}, .{0, -1, 0});
    Chamber.unnear_orthographic_projection(*eye.projectionMatrix, extent, 100.0); // Orthographic camera with 1 pixel = 1 unit
    Sill.transform_origin_target(*controller.debug.transform, .{0, 0, -40}, .{0, 0, 0}, referenceUp=.{0, -1, 0});
}
