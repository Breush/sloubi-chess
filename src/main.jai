// #import "Basic"()(MEMORY_DEBUGGER=true);

Basic :: #import "Basic";
Magma :: #import "Magma";
Crater :: #import "Crater";
Chamber :: #import "Chamber";

Hash :: #import "Hash_Table";

#load "board.jai";
#load "position.jai";

instance : struct {
    window : *Crater.Window;
    renderEngine : *Magma.Engine;
    renderScene : *Magma.Scene;

    windowTarget : *Magma.WindowTarget;
    renderer : *Magma.Renderer;

    running := true;

    board : Board;
}

main :: () {
    Chamber.init_logger();
    context.log_level = .VERBOSE;

    instance.window = Crater.create_window(.{width=1600, height=900}, "SloubiChess");
    instance.renderEngine = Magma.create_engine();
    instance.renderScene = Magma.create_scene(instance.renderEngine);

    instance.windowTarget = Magma.create_window_target(instance.renderEngine, Crater.window_get_handle(instance.window));
    instance.renderer = Magma.create_forward_renderer(instance.renderScene, Crater.window_get_extent(instance.window));
    Magma.target_bind(instance.windowTarget, Magma.renderer_get_output(instance.renderer));

    init_board();

    while instance.running {
        Basic.reset_temporary_storage();
        handle_input_events();

        // But we draw as fast as we can.
        Magma.engine_update(instance.renderEngine);
        Magma.engine_draw(instance.renderEngine);
    }

    // cleanup();
    // Chamber.cleanup_logger();
    // Basic.report_memory_leaks();
}

#scope_file

handle_input_events :: () {
    event := Crater.window_poll_event(instance.window);

    while event.kind != Crater.Event.Kind.None {
        if event.kind == Crater.Event.Kind.WindowClosed {
            instance.running = false;
            return;
        }
        else if event.kind == Crater.Event.Kind.KeyPressed &&
                event.key.which == Crater.Key.Escape {
            instance.running = false;
            return;
        }

        board_handle_input_event(event);

        // @todo Delegate and handle.
        event = Crater.window_poll_event(instance.window);
    }
}

cleanup :: () {
    Magma.destroy_engine(instance.renderEngine);
    Crater.destroy_window(instance.window);
}

#import "Math";
