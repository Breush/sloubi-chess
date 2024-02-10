ControllerEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    camera : Sill.CameraComponent;
    behaviorComponent : Sill.BehaviorComponent;

    debug : ControllerDebugEntity;

    modeStack : [..]struct {
        mode : Mode;
        dialog : *DialogEntity;
    };
    currentMode := Mode.None;

    on_cleanup :: (using this : *ControllerEntity) {
        Basic.array_reset(*modeStack);
    }
}

ControllerDebugEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage;

    behavior : Sill.BehaviorComponent;

    origin : Chamber.vec3;
    target : Chamber.vec3;

    enabled : bool;
}

Mode :: enum {
    None :: 0;
    Library;
    Game;
    GameCommentEdit;
    GameEdit;
    Dialog;
}

controller_create :: () -> *ControllerEntity {
    using controller := SillMeta.create_controller_entity(instance.engine);
    Sill.listener_on_message(*listener, _on_message);
    controls := *instance.config.controls;

    Sill.input_action_bind(*instance.engine.input, "game.ply.previous", controls.previousPly);
    Sill.input_action_bind(*instance.engine.input, "game.ply.next", controls.nextPly);
    Sill.input_action_bind(*instance.engine.input, "game.ply.first", controls.firstPly);
    Sill.input_action_bind(*instance.engine.input, "game.ply.last", controls.lastPly);
    Sill.input_action_bind(*instance.engine.input, "game.ply.comment.edit", controls.editPlyComment);
    Sill.input_action_bind(*instance.engine.input, "game.text.edit.word-modifier", .ControlLeft);
    Sill.input_action_bind(*instance.engine.input, "game.text.edit.word-modifier", .ControlRight);
    Sill.input_action_bind(*instance.engine.input, "game.variation.previous", controls.previousVariation);
    Sill.input_action_bind(*instance.engine.input, "game.variation.next", controls.nextVariation);

    Sill.behavior_on_update(*behaviorComponent, (dt : float64, using instance : *Instance) {
        if currentGame == null then return;

        if Sill.input_action_just_activated(*engine.input, "game.ply.previous", true)         then game_go_to_previous_move(currentGame);
        if Sill.input_action_just_activated(*engine.input, "game.ply.next", true)             then game_go_to_next_move(currentGame);
        if Sill.input_action_just_activated(*engine.input, "game.ply.first", true)            then game_go_to_first_ply(currentGame);
        if Sill.input_action_just_activated(*engine.input, "game.ply.last", true)             then game_go_to_last_ply(currentGame);
        if Sill.input_action_just_activated(*engine.input, "game.ply.comment.edit", true)     then game_edit_ply_comment(currentGame);
        if Sill.input_action_just_activated(*engine.input, "game.variation.previous", true)   then game_go_to_previous_variation(currentGame);
        if Sill.input_action_just_activated(*engine.input, "game.variation.next", true)       then game_go_to_next_variation(currentGame);
    }, *instance);

    // Debug 3D
    Sill.input_action_bind(*instance.engine.input, "debug.3d", .F12);

    _setup_orthographic_camera(controller);

    Sill.behavior_on_update(*debug.behavior, (dt : float64, using controller : *ControllerEntity) {
        if Sill.input_action_just_activated(*engine.input, "debug.3d", true) {
            debug.enabled = !debug.enabled;

            if debug.enabled {
                eye := Magma.renderer_get_eye(instance.engine.renderer, 0);
                debug.origin = .{0, 0, 0};
                debug.origin.z = - cast(float) instance.engine.options.windowExtent.x;
                Chamber.infinite_perspective_projection(*eye.projectionMatrix, 70.0, (cast(float) eye.extent.width) / eye.extent.height, 0.1);
                Sill.transform_origin_target(*transform, debug.origin, debug.target, referenceUp=.{0, -1, 0});

                Sill.input_axis_bind(*engine.input, "debug.3d.look-x", .MousePointerX);
                Sill.input_axis_bind(*engine.input, "debug.3d.look-y", .MousePointerY);
            } else {
                _setup_orthographic_camera(controller);

                Sill.input_axis_unbind(*engine.input, "debug.3d.look-x");
                Sill.input_axis_unbind(*engine.input, "debug.3d.look-y");
            }
        }

        lookX := Sill.input_axis_value(*engine.input, "debug.3d.look-x");
        lookY := Sill.input_axis_value(*engine.input, "debug.3d.look-y");
        if lookX != 0. || lookY != 0. {
            debug.origin.std += Chamber.rotate_around_target(debug.origin, debug.target, -lookX / 100., -lookY / 100., upAxis = .NegativeY);
            Sill.transform_origin_target(*transform, debug.origin, debug.target, referenceUp=.{0, -1, 0});
        }
    }, controller);

    return controller;
}

controller_handle_escape :: () -> bool {
    if instance.controller.modeStack.count == 0 then return false;

    dialog := Basic.peek(instance.controller.modeStack).dialog;
    if dialog != null {
        dialog_cancel(dialog);
        return true;
    }

    return false;
}

mode_push :: (mode : Mode, dialog : *DialogEntity = null) {
    oldMode := instance.controller.currentMode;
    Basic.array_add(*instance.controller.modeStack, .{mode, dialog});
    instance.controller.currentMode = mode;
    send(.ModeChanged, mode, oldMode);
}

mode_pop :: () {
    if instance.controller.modeStack.count == 0 then return;

    oldMode := Basic.peek(instance.controller.modeStack).mode;

    instance.controller.currentMode = .None;
    instance.controller.modeStack.count -= 1;
    if instance.controller.modeStack.count != 0 {
        instance.controller.currentMode = Basic.peek(instance.controller.modeStack).mode;
    }
    send(.ModeChanged, instance.controller.currentMode, oldMode);
}

#scope_file

_on_message :: (using controller : *ControllerEntity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _setup_orthographic_camera(controller);
    case .SelectTab;
        if message.entity.typeInfo == type_info(StudyView) {
            game_show((cast(*StudyView) message.entity).study.currentGame);
        } else {
            game_show(null);
        }
    }
}

_setup_orthographic_camera :: (using controller : *ControllerEntity) {
    eye := Magma.renderer_get_eye(engine.renderer, 0);

    extent : Chamber.vec2;
    extent.width = cast(float) eye.extent.width;
    extent.height = cast(float) eye.extent.height;

    eye.viewMatrix = Chamber.look_at_matrix(.{0, 0, -1}, .{0, 0, 0}, .{0, -1, 0});
    Chamber.unnear_orthographic_projection(*eye.projectionMatrix, extent, 200.0); // Orthographic camera with 1 pixel = 1 unit
    Sill.transform_origin_target(*transform, .{0, 0, -100}, .{0, 0, 0}, referenceUp=.{0, -1, 0});
}
