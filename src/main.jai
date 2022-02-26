// #import "Basic"()(MEMORY_DEBUGGER=true);

Sill :: #import "Sill";
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
#load "controller.jai";

instance : Instance;

Instance :: struct {
    engine : *Sill.Engine(SillMeta);

    fonts : struct {
        light : Chamber.Font;
        bold : Chamber.Font;
    };

    background : Background;
    board : *BoardEntity;
    game : Game;
    varianter : Varianter;
    controller : *ControllerEntity;
}

main :: () {
    Chamber.init_logger();
    context.log_level = .VERBOSE;

    instance.engine = Sill.create_engine(SillMeta);
    instance.fonts.light = Chamber.font_load("./assets/fonts/Ubuntu-Light.ttf", 16);
    instance.fonts.bold = Chamber.font_load("./assets/fonts/Ubuntu-Bold.ttf", 16);

    controller_init();
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

    Sill.engine_run(instance.engine);

    // cleanup();
    // Chamber.cleanup_logger();
    // Basic.report_memory_leaks();
}

#scope_file

cleanup :: () {
    Sill.destroy_engine(instance.engine);
}

#import "Math";
