ControllerEntity :: struct {
    using entity : Sill.Entity;
    behaviorComponent : Sill.BehaviorComponent;
}

controller_init :: () {
    using *instance;

    controller = SillMeta.create_controller_entity(engine);

    Sill.input_action_bind(*engine.input, "game.move.previous", .Left);
    Sill.input_action_bind(*engine.input, "game.move.next", .Right);
    Sill.input_action_bind(*engine.input, "game.variation.previous", .Up);
    Sill.input_action_bind(*engine.input, "game.variation.next", .Down);

    Sill.behavior_on_update(*controller.behaviorComponent, xx (dt : float64, using instance : *Instance) {
        if Sill.input_action_just_activated(*engine.input, "game.move.previous", true)        then game_go_to_previous_move(*game);
        if Sill.input_action_just_activated(*engine.input, "game.move.next", true)            then game_go_to_next_move(*game);
        if Sill.input_action_just_activated(*engine.input, "game.variation.previous", true)   then game_go_to_previous_variation(*game);
        if Sill.input_action_just_activated(*engine.input, "game.variation.next", true)       then game_go_to_next_variation(*game);
    }, *instance);
}
