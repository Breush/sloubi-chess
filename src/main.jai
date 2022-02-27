// #import "Basic"()(MEMORY_DEBUGGER=true);

Sill :: #import "Sill";
Magma :: Sill.Magma;
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

CommandLine :: #import "Command_Line";

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

Arguments :: struct {
    pgn : string;
}

main :: () {
    Chamber.init_logger();
    context.log_level = .VERBOSE;

    // @todo Have a better command line parser, checking required arguments and such.
    success, args, setArgs := CommandLine.parse_arguments(Arguments);
    if !success then return;

    if !setArgs.pgn {
        Basic.log("No PGN file specified. Please relaunch with -pgn <PGN_FILE>.", flags = .WARNING);
        return;
    }

    instance.engine = Sill.create_engine(SillMeta);
    instance.fonts.light = Chamber.font_load("./assets/fonts/Ubuntu-Light.ttf", 16);
    instance.fonts.bold = Chamber.font_load("./assets/fonts/Ubuntu-Bold.ttf", 16);

    controller_init();
    board_init();
    background_init();
    varianter_init();

    load_pgn(args.pgn);

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
