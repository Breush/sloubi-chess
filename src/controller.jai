ControllerEntity :: struct {
    using entity : Sill.Entity;
    behaviorComponent : Sill.BehaviorComponent;
}

controller_init :: () {
    using *instance;

    controller = SillMeta.create_controller_entity(engine);

    // @todo Propagate the naming convention of "ply" to the rest of the software.
    Sill.input_action_bind(*engine.input, "game.ply.previous", config.controls.previousPly);
    Sill.input_action_bind(*engine.input, "game.ply.next", config.controls.nextPly);
    Sill.input_action_bind(*engine.input, "game.ply.first", config.controls.firstPly);
    Sill.input_action_bind(*engine.input, "game.ply.last", config.controls.lastPly);
    Sill.input_action_bind(*engine.input, "game.variation.previous", config.controls.previousVariation);
    Sill.input_action_bind(*engine.input, "game.variation.next", config.controls.nextVariation);

    Sill.behavior_on_update(*controller.behaviorComponent, xx (dt : float64, using instance : *Instance) {
        if Sill.input_action_just_activated(*engine.input, "game.ply.previous", true)         then game_go_to_previous_move(*game);
        if Sill.input_action_just_activated(*engine.input, "game.ply.next", true)             then game_go_to_next_move(*game);
        if Sill.input_action_just_activated(*engine.input, "game.ply.first", true)            then game_go_to_first_ply(*game);
        if Sill.input_action_just_activated(*engine.input, "game.ply.last", true)             then game_go_to_last_ply(*game);
        if Sill.input_action_just_activated(*engine.input, "game.variation.previous", true)   then game_go_to_previous_variation(*game);
        if Sill.input_action_just_activated(*engine.input, "game.variation.next", true)       then game_go_to_next_variation(*game);
    }, *instance);
}
