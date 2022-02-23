// #import "Basic"()(MEMORY_DEBUGGER=true);

Magma :: #import "Magma";
Crater :: #import "Crater";
Chamber :: #import "Chamber";

Basic :: #import "Basic";
Hash :: #import "Hash_Table";
Math :: #import "Math";
File :: #import "File";

#load "display/background.jai";
#load "display/board.jai";
#load "display/varianter.jai";
#load "structures/coord.jai";
#load "structures/game.jai";
#load "structures/piece.jai";
#load "structures/position.jai";
#load "readers/fen.jai";
#load "readers/pgn.jai";

instance : struct {
    window : *Crater.Window;
    renderEngine : *Magma.Engine;
    renderScene : *Magma.Scene;

    windowTarget : *Magma.WindowTarget;
    renderer : *Magma.Renderer;

    running := true;

    fonts : struct {
        light : Chamber.Font;
        bold : Chamber.Font;
    };

    background : Background;
    board : Board;
    game : Game;
    varianter : Varianter;
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

    instance.fonts.light = Chamber.font_load("./assets/fonts/Ubuntu-Light.ttf", 16);
    instance.fonts.bold = Chamber.font_load("./assets/fonts/Ubuntu-Bold.ttf", 16);

    board_init();
    background_init();
    varianter_init();

    // load_pgn("./assets/pgns/opera-game.pgn");
    // load_pgn("./assets/pgns/test-crazy-moves.pgn");
    // load_pgn("./assets/pgns/reti-bogoliouboff-new_york-1924.pgn");
    // load_pgn("./assets/pgns/test-fen-and-comments.pgn");
    load_pgn("./assets/pgns/benko-revealed-intro.pgn");
    // load_pgn("./assets/pgns/benko-revealed-intro-english.pgn");
    // load_pgn("./assets/pgns/breush-game.pgn");

    varianter_show(instance.game);
    game_update_to(*instance.game, 0);
    // game_debug_dump(instance.game);

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
        varianter_handle_input_event(event);

        // @todo Delegate and handle.
        event = Crater.window_poll_event(instance.window);
    }
}

cleanup :: () {
    Magma.destroy_engine(instance.renderEngine);
    Crater.destroy_window(instance.window);
}

#import "Math";
